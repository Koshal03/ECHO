-- Echo: Wallet history + Virtual Gifts
-- Supabase Dashboard > SQL Editor > New query > paste > Run   (safe to run more than once)

-- 1) Gift catalogue (server is the source of truth for prices)
create table if not exists gift_catalog (
  gift_id       text primary key,                 -- 'heart' | 'rose' | 'golden_star' | 'diamond'
  name          text not null,
  coin_price    integer not null check (coin_price > 0),
  animation_key text not null,
  popular       boolean not null default false,
  enabled       boolean not null default true,
  sort_order    integer not null default 0
);

insert into gift_catalog (gift_id, name, coin_price, animation_key, popular, sort_order) values
  ('heart',       'Heart',       10,  'pop',     false, 1),
  ('rose',        'Rose',        20,  'petals',  false, 2),
  ('golden_star', 'Golden Star', 50,  'burst',   true,  3),
  ('diamond',     'Diamond',     100, 'sparkle', false, 4)
on conflict (gift_id) do nothing;

-- 2) One row per gift sent (no call content is stored)
create table if not exists gift_events (
  gift_event_id  text primary key,
  sender_id      text not null,
  recipient_id   text not null,
  call_id        text,
  gift_id        text not null,
  coin_price     integer not null,
  transaction_id text not null,
  request_id     text not null,                   -- client retry id => idempotency
  created_at     timestamptz not null default now(),
  unique (sender_id, request_id)
);
create index if not exists idx_gift_events_sender on gift_events(sender_id, created_at desc);
create index if not exists idx_ledger_user_time on wallet_ledger(user_id, created_at desc);

-- 3) Atomic "send gift": validates price, checks balance, debits, writes ledger + gift event.
--    A retry with the same request_id returns the first result and never charges twice.
create or replace function send_gift(
  p_sender text, p_recipient text, p_call_id text, p_gift_id text, p_price integer, p_request_id text
) returns jsonb
language plpgsql security definer as $$
declare
  v_gift gift_catalog%rowtype;
  v_existing gift_events%rowtype;
  v_balance integer;
  v_event_id text := 'gft_' || gen_random_uuid();
  v_tx_id text := 'tx_' || gen_random_uuid();
begin
  select * into v_existing from gift_events where sender_id = p_sender and request_id = p_request_id;
  if found then
    select coins into v_balance from users where user_id = p_sender;
    return jsonb_build_object('duplicate', true, 'gift_event_id', v_existing.gift_event_id,
                              'new_balance', v_balance, 'coin_price', v_existing.coin_price);
  end if;

  select * into v_gift from gift_catalog where gift_id = p_gift_id and enabled;
  if not found then raise exception 'gift_unavailable'; end if;
  if v_gift.coin_price <> p_price then raise exception 'price_mismatch'; end if;

  update users set coins = coins - v_gift.coin_price
   where user_id = p_sender and coins >= v_gift.coin_price
   returning coins into v_balance;
  if v_balance is null then raise exception 'insufficient_coins'; end if;

  insert into wallet_ledger(transaction_id, user_id, entry_type, coin_delta, source, product_id, reference)
  values (v_tx_id, p_sender, 'debit', -v_gift.coin_price, 'gift_sent', p_gift_id, v_event_id);

  insert into gift_events(gift_event_id, sender_id, recipient_id, call_id, gift_id, coin_price, transaction_id, request_id)
  values (v_event_id, p_sender, p_recipient, p_call_id, p_gift_id, v_gift.coin_price, v_tx_id, p_request_id);

  return jsonb_build_object('duplicate', false, 'gift_event_id', v_event_id,
                            'new_balance', v_balance, 'coin_price', v_gift.coin_price);
end $$;

-- SECURITY: RLS on, no policies => only your server (service_role key) can read/write.
alter table gift_catalog enable row level security;
alter table gift_events  enable row level security;
revoke execute on function send_gift from anon, authenticated;

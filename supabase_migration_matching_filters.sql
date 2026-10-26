-- Echo: Matching preferences + Premium Filters unlock
-- Supabase Dashboard > SQL Editor > New query > paste > Run   (safe to run more than once)

create table if not exists user_preferences (
  user_id             text primary key references users(user_id) on delete cascade,
  languages           text[]  not null default '{}',   -- profile: languages the person speaks
  interests           text[]  not null default '{}',
  region              text    not null default 'any',  -- 'any' or a 2-letter country code
  filters_on          boolean not null default true,   -- person can switch filtering off
  filters_unlocked    boolean not null default false,  -- paid one-time unlock
  filters_unlocked_at timestamptz,
  updated_at          timestamptz not null default now()
);

-- Atomic unlock: checks balance, debits, flips the flag, writes the ledger row.
-- Already unlocked => returns already=true and charges nothing (safe to retry).
create or replace function unlock_filters(p_user text, p_price integer) returns jsonb
language plpgsql security definer as $$
declare
  v_unlocked boolean;
  v_balance integer;
begin
  insert into user_preferences(user_id) values (p_user) on conflict (user_id) do nothing;
  select filters_unlocked into v_unlocked from user_preferences where user_id = p_user for update;
  if v_unlocked then
    select coins into v_balance from users where user_id = p_user;
    return jsonb_build_object('already', true, 'new_balance', v_balance);
  end if;

  update users set coins = coins - p_price
   where user_id = p_user and coins >= p_price
   returning coins into v_balance;
  if v_balance is null then raise exception 'insufficient_coins'; end if;

  update user_preferences set filters_unlocked = true, filters_unlocked_at = now(), updated_at = now()
   where user_id = p_user;

  insert into wallet_ledger(transaction_id, user_id, entry_type, coin_delta, source, product_id, reference)
  values ('tx_' || gen_random_uuid(), p_user, 'debit', -p_price, 'filter_unlock', 'advanced_filters', null);

  return jsonb_build_object('already', false, 'new_balance', v_balance);
end $$;

-- SECURITY: RLS on, no policies => only your server (service_role key) can read/write.
alter table user_preferences enable row level security;
revoke execute on function unlock_filters from anon, authenticated;

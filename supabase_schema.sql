-- Echo: Supabase (Postgres) schema
-- Supabase Dashboard > SQL Editor > New query > paste > Run

create table if not exists users (
  user_id          text primary key,              -- 'usr_xxxxxxxx'
  username         text not null,
  username_norm    text not null unique,          -- lowercase, unique check
  display_name     text not null,
  email            text default '',
  google_sub       text unique,                   -- Google account id
  phone            text unique,                   -- verified phone (E.164), set by SMS sign-in
  email_verified   boolean not null default false, -- true only when the email was proven (Google / OTP)
  avatar_url       text,
  coins            integer not null default 50 check (coins >= 0),
  status           text not null default 'active',  -- active | suspended
  terms_version    text,                            -- Terms and Conditions version the user accepted
  terms_accepted_at timestamptz,
  created_at       timestamptz not null default now()
);

create table if not exists guest_sessions (
  session_id    text primary key,                 -- 'guest_xxxx'
  device_id     text not null unique,             -- 1 free allowance per device
  display_name  text not null,
  created_at    timestamptz not null default now(),
  expires_at    timestamptz not null
);

create table if not exists blocks (
  blocker_id  text not null,
  blocked_id  text not null,
  created_at  timestamptz not null default now(),
  primary key (blocker_id, blocked_id)
);

create table if not exists reports (
  report_id        text primary key,
  reporter_id      text not null,
  reported_user_id text not null,
  category         text not null,
  description      text,
  call_id          text,
  status           text not null default 'pending_review',
  created_at       timestamptz not null default now()
);

-- Every coin change is recorded here (audit trail)
create table if not exists wallet_ledger (
  transaction_id text primary key,
  user_id        text not null,   -- no foreign key: records stay (without personal data) after account deletion
  entry_type     text not null,                   -- credit | debit
  coin_delta     integer not null,
  source         text not null,                   -- welcome_bonus | google_play | rewarded_ad | admin_gift | call
  product_id     text,
  reference      text,
  created_at     timestamptz not null default now()
);
create index if not exists idx_ledger_user on wallet_ledger(user_id);

-- Google Play purchase tokens (stops double-crediting)
create table if not exists purchases (
  purchase_token text primary key,
  user_id        text not null,   -- no foreign key: records stay (without personal data) after account deletion
  product_id     text not null,
  state          text not null default 'pending', -- pending | credited
  created_at     timestamptz not null default now()
);

-- AdMob rewarded-ad transactions (stops replay)
create table if not exists ad_rewards (
  transaction_id text primary key,
  user_id        text not null,
  created_at     timestamptz not null default now()
);

-- Atomic coin update: race condition se bachne ke liye
create or replace function add_coins(
  p_user_id text, p_delta integer, p_source text,
  p_product_id text default null, p_reference text default null
) returns integer
language plpgsql security definer as $$
declare new_balance integer;
begin
  update users set coins = coins + p_delta
   where user_id = p_user_id
   returning coins into new_balance;
  if new_balance is null then raise exception 'user not found'; end if;

  insert into wallet_ledger(transaction_id, user_id, entry_type, coin_delta, source, product_id, reference)
  values ('tx_' || gen_random_uuid(), p_user_id,
          case when p_delta >= 0 then 'credit' else 'debit' end,
          p_delta, p_source, p_product_id, p_reference);
  return new_balance;
end $$;

-- SECURITY: RLS ON, koi policy nahi => anon key se koi data nahi padh/likh sakta.
-- Sirf aapka server (service_role key) access karega.
alter table users          enable row level security;
alter table guest_sessions enable row level security;
alter table blocks         enable row level security;
alter table reports        enable row level security;
alter table wallet_ledger  enable row level security;
alter table purchases      enable row level security;
alter table ad_rewards     enable row level security;

revoke execute on function add_coins from anon, authenticated;

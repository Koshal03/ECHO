-- Run ONCE in Supabase > SQL Editor (you already ran supabase_schema.sql earlier).
alter table users add column if not exists phone text unique;
alter table users add column if not exists email_verified boolean not null default false;
-- Existing Google accounts have verified emails:
update users set email_verified = true where google_sub is not null and email <> '';

-- Account deletion: keep purchase + coin records (they contain only an opaque id once the
-- users row is deleted) so an old Google Play purchase token can never be replayed.
-- Safe to run more than once.
alter table wallet_ledger drop constraint if exists wallet_ledger_user_id_fkey;
alter table purchases     drop constraint if exists purchases_user_id_fkey;

-- Terms and Conditions: remember which version each member accepted (and when).
alter table users add column if not exists terms_version text;
alter table users add column if not exists terms_accepted_at timestamptz;

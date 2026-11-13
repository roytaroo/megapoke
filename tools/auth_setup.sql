-- メガポケ ログイン導入用(SupabaseのSQL Editorで1回だけ実行)
-- 注意: 2. で今までのカード・デッキ・戦績・特典コードの記録・対戦部屋をすべて消す(引き継がない方針)

-- 1. アカウントとプレイヤー名の対応表
create table if not exists public.megapoke_profiles (
  user_id uuid primary key default auth.uid() references auth.users(id) on delete cascade,
  name text not null unique check (char_length(name) between 1 and 10),
  created_at timestamptz default now()
);
alter table public.megapoke_profiles enable row level security;
drop policy if exists "profiles read" on public.megapoke_profiles;
drop policy if exists "profiles insert own" on public.megapoke_profiles;
create policy "profiles read" on public.megapoke_profiles for select using (true);
create policy "profiles insert own" on public.megapoke_profiles for insert to authenticated with check (user_id = auth.uid());

-- ログイン中の人のプレイヤー名
create or replace function public.megapoke_my_name() returns text
language sql stable security definer set search_path = public as
$$ select name from public.megapoke_profiles where user_id = auth.uid() $$;

-- 2. 今までのデータを消す
delete from public.megapoke_collections;
delete from public.megapoke_decks;
delete from public.megapoke_match_history;
delete from public.megapoke_redeemed_codes;
delete from public.megapoke_rooms;

-- 3. 今のアクセス設定を外して、ログインした本人だけが自分のデータを書けるようにする
do $$ declare r record; begin
  for r in select policyname, tablename from pg_policies
    where schemaname = 'public' and tablename in ('megapoke_collections','megapoke_decks','megapoke_match_history','megapoke_redeemed_codes','megapoke_rooms')
  loop execute format('drop policy %I on public.%I', r.policyname, r.tablename); end loop;
end $$;

alter table public.megapoke_collections enable row level security;
alter table public.megapoke_decks enable row level security;
alter table public.megapoke_match_history enable row level security;
alter table public.megapoke_redeemed_codes enable row level security;
alter table public.megapoke_rooms enable row level security;

create policy "read" on public.megapoke_collections for select using (true);
create policy "write own" on public.megapoke_collections for all to authenticated
  using (player_name = public.megapoke_my_name()) with check (player_name = public.megapoke_my_name());

create policy "read" on public.megapoke_decks for select using (true);
create policy "write own" on public.megapoke_decks for all to authenticated
  using (split_part(player_name, '#', 1) = public.megapoke_my_name()) with check (split_part(player_name, '#', 1) = public.megapoke_my_name());

create policy "read" on public.megapoke_match_history for select using (true);
create policy "insert own" on public.megapoke_match_history for insert to authenticated
  with check (public.megapoke_my_name() in (player1_name, player2_name));

create policy "read own" on public.megapoke_redeemed_codes for select to authenticated using (player_name = public.megapoke_my_name());
create policy "insert own" on public.megapoke_redeemed_codes for insert to authenticated with check (player_name = public.megapoke_my_name());

create policy "play" on public.megapoke_rooms for all to authenticated using (true) with check (true);

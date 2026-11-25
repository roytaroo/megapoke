-- メガポケ ズル対策(SupabaseのSQL Editorで1回だけ実行)
-- ・パックの抽選、特典コード、デバッグのカード操作をサーバー側の関数でやる。所持カードは画面から直接書き換えられなくなる
-- ・対戦部屋は、その部屋の2人しか書き換えられなくなる
-- ・ランダム対戦用の列を追加

-- 0. 日付は文字で持つ
alter table public.megapoke_collections alter column last_pack_date type text using last_pack_date::text;

-- 1. 封入データ(だいきのアカウントでゲームを開くと自動で更新される)
create table if not exists public.megapoke_config (key text primary key, value jsonb not null, updated_at timestamptz default now());
alter table public.megapoke_config enable row level security;
drop policy if exists "read" on public.megapoke_config;
drop policy if exists "admin write" on public.megapoke_config;
create policy "read" on public.megapoke_config for select using (true);
create policy "admin write" on public.megapoke_config for all to authenticated
  using (auth.uid() = '773a6b5e-1f84-4aad-a3a7-3a13c9eb0739'::uuid) with check (auth.uid() = '773a6b5e-1f84-4aad-a3a7-3a13c9eb0739'::uuid);

-- 2. 所持カードは読むだけ(書き込みは下の関数だけ)
drop policy if exists "write own" on public.megapoke_collections;
drop policy if exists "insert own" on public.megapoke_redeemed_codes;

create or replace function public.megapoke_pick(arr jsonb) returns text language sql volatile as
$$ select arr->>(floor(random() * jsonb_array_length(arr))::int) $$;

-- パックを開ける。引いたカードの配列を返す
create or replace function public.megapoke_open_pack(p_pack text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_name text := megapoke_my_name();
  v_cfg jsonb; v_pack jsonb; v_row megapoke_collections%rowtype;
  v_today text := to_char((now() at time zone 'Asia/Tokyo')::date, 'YYYY-MM-DD');
  v_bonus int; v_opened int; v_mode text;
  v_d1 jsonb; v_drawn text[] := '{}'; v_tier text; v_cards jsonb;
  i int; v_w jsonb; v_tot numeric; v_r numeric; k text; w numeric;
begin
  if v_name is null then raise exception 'NOT_LOGGED_IN'; end if;
  select value into v_cfg from megapoke_config where key = 'pool';
  v_pack := v_cfg->'packs'->p_pack;
  if v_pack is null then raise exception 'NO_POOL'; end if;
  insert into megapoke_collections(player_name, cards) values (v_name, '{}'::jsonb) on conflict (player_name) do nothing;
  select * into v_row from megapoke_collections where player_name = v_name for update;
  v_bonus := coalesce(v_row.bonus_packs, 0); v_opened := coalesce(v_row.packs_opened_total, 0);
  if v_bonus > 0 then v_mode := 'bonus';
  elsif v_opened < coalesce((v_cfg->>'freePacks')::int, 3) then v_mode := 'free';
  elsif coalesce(v_row.last_pack_date, '') <> v_today then v_mode := 'daily';
  else raise exception 'NO_PACKS'; end if;
  v_d1 := v_pack->'byRarity'->'diamond1';
  if v_d1 is null or jsonb_array_length(v_d1) = 0 then v_d1 := v_cfg->'diamond1All'; end if;
  for i in 1..3 loop v_drawn := v_drawn || megapoke_pick(v_d1); end loop;
  for i in 4..5 loop
    v_w := v_cfg->'weights'->(i::text);
    v_tot := 0;
    for k, w in select key, value::numeric from jsonb_each_text(v_w) loop
      if w > 0 and (v_pack->'byRarity') ? k then v_tot := v_tot + w; end if;
    end loop;
    v_tier := null;
    if v_tot > 0 then
      v_r := random() * v_tot;
      for k, w in select key, value::numeric from jsonb_each_text(v_w) loop
        if w > 0 and (v_pack->'byRarity') ? k then
          v_tier := k;
          exit when v_r < w;
          v_r := v_r - w;
        end if;
      end loop;
    end if;
    v_drawn := v_drawn || megapoke_pick(case when v_tier is null then v_d1 else v_pack->'byRarity'->v_tier end);
  end loop;
  v_cards := coalesce(v_row.cards, '{}'::jsonb);
  foreach k in array v_drawn loop
    v_cards := jsonb_set(v_cards, array[k], to_jsonb(coalesce((v_cards->>k)::int, 0) + 1));
  end loop;
  update megapoke_collections set cards = v_cards, updated_at = now(),
    bonus_packs = case when v_mode = 'bonus' then v_bonus - 1 else bonus_packs end,
    packs_opened_total = case when v_mode <> 'bonus' then v_opened + 1 else packs_opened_total end,
    last_pack_date = case when v_mode <> 'bonus' then v_today else last_pack_date end
  where player_name = v_name;
  return to_jsonb(v_drawn);
end $$;

-- 特典コード
create or replace function public.megapoke_redeem(p_code text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_name text := megapoke_my_name(); v_code text := upper(trim(p_code)); v_def jsonb; v_cards jsonb; v_promo text;
begin
  if v_name is null then raise exception 'NOT_LOGGED_IN'; end if;
  select value->'codes'->v_code into v_def from megapoke_config where key = 'pool';
  if v_def is null then raise exception 'NO_CODE'; end if;
  if exists (select 1 from megapoke_redeemed_codes where player_name = v_name and code = v_code) then raise exception 'USED'; end if;
  insert into megapoke_collections(player_name, cards) values (v_name, '{}'::jsonb) on conflict (player_name) do nothing;
  select coalesce(cards, '{}'::jsonb) into v_cards from megapoke_collections where player_name = v_name for update;
  v_promo := v_def->>'promo';
  if v_promo is not null then v_cards := jsonb_set(v_cards, array[v_promo], to_jsonb(coalesce((v_cards->>v_promo)::int, 0) + 1)); end if;
  update megapoke_collections set cards = v_cards, bonus_packs = coalesce(bonus_packs, 0) + coalesce((v_def->>'packs')::int, 0), updated_at = now()
    where player_name = v_name;
  insert into megapoke_redeemed_codes(player_name, code) values (v_name, v_code);
  return v_def;
end $$;

-- デバッグ(だいきだけ)
create or replace function public.megapoke_admin(p_op text, p_n int default 0) returns void
language plpgsql security definer set search_path = public as $$
declare v_name text := megapoke_my_name(); v_cards jsonb; k text;
begin
  if auth.uid() is distinct from '773a6b5e-1f84-4aad-a3a7-3a13c9eb0739'::uuid then raise exception 'FORBIDDEN'; end if;
  insert into megapoke_collections(player_name, cards) values (v_name, '{}'::jsonb) on conflict (player_name) do nothing;
  if p_op = 'bonus' then update megapoke_collections set bonus_packs = coalesce(bonus_packs, 0) + p_n where player_name = v_name;
  elsif p_op = 'today' then update megapoke_collections set last_pack_date = null where player_name = v_name;
  elsif p_op = 'clear' then update megapoke_collections set cards = '{}'::jsonb where player_name = v_name;
  elsif p_op = 'all' then
    select coalesce(cards, '{}'::jsonb) into v_cards from megapoke_collections where player_name = v_name;
    for k in select jsonb_array_elements_text(value->'allArt') from megapoke_config where key = 'pool' loop
      v_cards := jsonb_set(v_cards, array[k], to_jsonb(coalesce((v_cards->>k)::int, 0) + 1));
    end loop;
    update megapoke_collections set cards = v_cards where player_name = v_name;
  end if;
end $$;

grant execute on function public.megapoke_open_pack(text), public.megapoke_redeem(text), public.megapoke_admin(text, int) to authenticated;

-- 3. 対戦部屋は、その部屋の2人だけが書き換えられる
alter table public.megapoke_rooms add column if not exists is_public boolean default false;
drop policy if exists "play" on public.megapoke_rooms;
drop policy if exists "read" on public.megapoke_rooms;
drop policy if exists "create own" on public.megapoke_rooms;
drop policy if exists "update players" on public.megapoke_rooms;
create policy "read" on public.megapoke_rooms for select to authenticated using (true);
create policy "create own" on public.megapoke_rooms for insert to authenticated with check (player1_name = public.megapoke_my_name());
create policy "update players" on public.megapoke_rooms for update to authenticated
  using (public.megapoke_my_name() in (player1_name, player2_name) or player2_name is null)
  with check (public.megapoke_my_name() in (player1_name, player2_name));

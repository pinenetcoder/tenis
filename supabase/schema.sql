create extension if not exists pgcrypto;

-- Idempotent enum creation (safe to re-run whole schema; plain CREATE TYPE fails if type exists)
do $$ begin
  create type tournament_category as enum ('singles', 'doubles');
exception
  when duplicate_object then null;
end $$;

do $$ begin
  create type bracket_format as enum ('single_elimination');
exception
  when duplicate_object then null;
end $$;

do $$ begin
  create type registration_status as enum ('pending', 'approved', 'rejected');
exception
  when duplicate_object then null;
end $$;

do $$ begin
  create type tournament_status as enum ('draft', 'registration_open', 'registration_closed', 'in_progress', 'completed');
exception
  when duplicate_object then null;
end $$;

do $$ begin
  create type set_format as enum ('best_of_3', 'best_of_5');
exception
  when duplicate_object then null;
end $$;

do $$ begin
  create type draw_mode as enum ('auto-random', 'manual');
exception
  when duplicate_object then null;
end $$;

do $$ begin
  create type match_status as enum ('pending', 'ready', 'finished');
exception
  when duplicate_object then null;
end $$;

do $$ begin
  create type doubles_pairing_mode as enum ('pre_agreed', 'pick_random');
exception
  when duplicate_object then null;
end $$;

do $$ begin
  create type org_type as enum ('club', 'coach');
exception
  when duplicate_object then null;
end $$;

do $$ begin
  create type membership_role as enum ('member', 'student', 'admin', 'external');
exception
  when duplicate_object then null;
end $$;

do $$ begin
  create type membership_status as enum ('pending', 'active', 'inactive', 'banned', 'rejected', 'expired', 'pending_payment');
exception
  when duplicate_object then null;
end $$;

do $$ begin
  create type membership_visibility as enum ('full', 'stats_only', 'hidden');
exception
  when duplicate_object then null;
end $$;

do $$ begin
  create type organization_status as enum ('pending', 'active', 'rejected');
exception
  when duplicate_object then null;
end $$;

create table if not exists organizations (
  id uuid primary key default gen_random_uuid(),
  slug text unique,
  type org_type not null,
  name text not null,
  description text,
  logo_url text,
  city text,
  country text,
  address text,
  contact_email text,
  contact_phone text,
  owner_user_id uuid references auth.users (id) on delete restrict,
  plan text default 'free',
  auto_approve_members boolean not null default true,
  status organization_status not null default 'active',
  is_active boolean not null default true,
  rejection_reason text,
  reviewed_by uuid references auth.users (id),
  reviewed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists players (
  id uuid primary key default gen_random_uuid(),
  user_id uuid unique references auth.users (id) on delete set null,
  display_name text not null,
  avatar_url text,
  contact_hash text,
  birth_year integer,
  gender text check (gender in ('male', 'female', 'other')),
  country text,
  merged_into uuid references players (id) on delete set null,
  is_deleted boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index if not exists idx_players_contact
  on players (contact_hash)
  where contact_hash is not null and is_deleted = false;

create table if not exists org_memberships (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references organizations (id) on delete cascade,
  player_id uuid not null references players (id) on delete cascade,
  role membership_role not null default 'member',
  status membership_status not null default 'pending',
  visibility membership_visibility not null default 'full',
  is_primary boolean not null default false,
  invited_by uuid references auth.users (id),
  review_note text,
  joined_at timestamptz,
  expires_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (org_id, player_id)
);

create table if not exists org_invites (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references organizations (id) on delete cascade,
  token text unique not null
    default replace(translate(encode(gen_random_bytes(24), 'base64'), '+/', '-_'), '=', ''),
  contact_email text,
  contact_phone text,
  contact_hash text not null,
  player_id uuid references players (id),
  role membership_role not null default 'member',
  message text,
  invited_by uuid not null references auth.users (id),
  status text not null default 'pending'
    check (status in ('pending', 'accepted', 'rejected', 'expired', 'revoked')),
  expires_at timestamptz not null default (now() + interval '30 days'),
  accepted_at timestamptz,
  created_at timestamptz not null default now()
);

create table if not exists tournaments (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  slug text not null unique,
  description text,
  category tournament_category not null,
  bracket_format bracket_format not null default 'single_elimination',
  set_format set_format not null default 'best_of_3',
  status tournament_status not null default 'draft',
  is_public boolean not null default true,
  doubles_pairing_mode doubles_pairing_mode,
  org_id uuid references organizations (id) on delete restrict,
  created_by uuid not null references auth.users (id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists tournament_admins (
  id uuid primary key default gen_random_uuid(),
  tournament_id uuid not null references tournaments (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  role text not null check (role in ('owner', 'editor')),
  created_at timestamptz not null default now(),
  unique (tournament_id, user_id)
);

create table if not exists entries (
  id uuid primary key default gen_random_uuid(),
  tournament_id uuid not null references tournaments (id) on delete cascade,
  entry_type tournament_category not null,
  display_name text not null,
  phone_or_email text not null,
  status registration_status not null default 'pending',
  seed_order integer,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index if not exists idx_entries_active_contact
  on entries (tournament_id, phone_or_email)
  where status in ('pending', 'approved');

create table if not exists entry_members (
  id uuid primary key default gen_random_uuid(),
  entry_id uuid not null references entries (id) on delete cascade,
  member_name text not null,
  member_order integer not null check (member_order in (1, 2)),
  player_id uuid references players (id) on delete set null,
  created_at timestamptz not null default now(),
  unique (entry_id, member_order)
);

do $$
begin
  if not exists (
    select 1 from information_schema.columns
    where table_name = 'tournaments' and column_name = 'org_id'
  ) then
    alter table tournaments add column org_id uuid references organizations(id) on delete restrict;
  end if;
end $$;

do $$
begin
  if not exists (
    select 1 from information_schema.columns
    where table_name = 'entry_members' and column_name = 'player_id'
  ) then
    alter table entry_members add column player_id uuid references players(id) on delete set null;
  end if;
end $$;

create table if not exists matches (
  id uuid primary key default gen_random_uuid(),
  tournament_id uuid not null references tournaments (id) on delete cascade,
  round_number integer not null check (round_number > 0),
  match_number integer not null check (match_number > 0),
  side_a_entry_id uuid references entries (id) on delete set null,
  side_b_entry_id uuid references entries (id) on delete set null,
  winner_entry_id uuid references entries (id) on delete set null,
  status match_status not null default 'pending',
  next_match_id uuid references matches (id) on delete set null,
  next_slot text check (next_slot in ('A', 'B')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (tournament_id, round_number, match_number)
);

create table if not exists match_sets (
  id uuid primary key default gen_random_uuid(),
  match_id uuid not null references matches (id) on delete cascade,
  set_index integer not null check (set_index >= 1 and set_index <= 5),
  side_a_games integer not null check (side_a_games >= 0 and side_a_games <= 7),
  side_b_games integer not null check (side_b_games >= 0 and side_b_games <= 7),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (match_id, set_index)
);

create table if not exists bracket_versions (
  id uuid primary key default gen_random_uuid(),
  tournament_id uuid not null references tournaments (id) on delete cascade,
  snapshot jsonb not null,
  created_at timestamptz not null default now()
);

create index if not exists idx_bracket_versions_tournament on bracket_versions (tournament_id);
create index if not exists idx_org_owner on organizations (owner_user_id);
create index if not exists idx_org_type on organizations (type);
create index if not exists idx_organizations_status on organizations (status);
create index if not exists idx_players_user on players (user_id);
create index if not exists idx_memberships_org on org_memberships (org_id);
create index if not exists idx_memberships_player on org_memberships (player_id);
create index if not exists idx_memberships_status on org_memberships (status);
create unique index if not exists idx_memberships_primary
  on org_memberships (player_id) where is_primary = true;
create index if not exists idx_invites_token on org_invites (token);
create index if not exists idx_invites_org on org_invites (org_id);
create index if not exists idx_invites_contact on org_invites (contact_hash);
create index if not exists idx_tournaments_org on tournaments (org_id);
create index if not exists idx_entry_members_player on entry_members (player_id);
create index if not exists idx_tournament_admins_user on tournament_admins (user_id);
create index if not exists idx_entries_tournament on entries (tournament_id, status);
create index if not exists idx_matches_tournament on matches (tournament_id, round_number, match_number);
create index if not exists idx_match_sets_match on match_sets (match_id);

create or replace function set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists trg_tournaments_updated_at on tournaments;
create trigger trg_tournaments_updated_at
before update on tournaments
for each row
execute function set_updated_at();

drop trigger if exists trg_organizations_updated_at on organizations;
create trigger trg_organizations_updated_at
before update on organizations
for each row
execute function set_updated_at();

drop trigger if exists trg_players_updated_at on players;
create trigger trg_players_updated_at
before update on players
for each row
execute function set_updated_at();

drop trigger if exists trg_memberships_updated_at on org_memberships;
create trigger trg_memberships_updated_at
before update on org_memberships
for each row
execute function set_updated_at();

drop trigger if exists trg_entries_updated_at on entries;
create trigger trg_entries_updated_at
before update on entries
for each row
execute function set_updated_at();

drop trigger if exists trg_matches_updated_at on matches;
create trigger trg_matches_updated_at
before update on matches
for each row
execute function set_updated_at();

drop trigger if exists trg_match_sets_updated_at on match_sets;
create trigger trg_match_sets_updated_at
before update on match_sets
for each row
execute function set_updated_at();

create or replace function is_tournament_admin(p_tournament_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from tournament_admins ta
    where ta.tournament_id = p_tournament_id
      and ta.user_id = auth.uid()
  );
$$;

create or replace function normalize_contact(p_contact text)
returns text
language sql
immutable
as $$
  select regexp_replace(lower(coalesce(trim(p_contact), '')), '\s|-|\+|\(|\)', '', 'g');
$$;

create or replace function hash_contact(p_contact text)
returns text
language sql
immutable
set search_path = public, extensions
as $$
  select case
    when p_contact is null or btrim(p_contact) = '' then null
    else encode(extensions.digest(normalize_contact(p_contact), 'sha256'), 'hex')
  end;
$$;

create or replace function is_org_admin(p_org_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from organizations o
    where o.id = p_org_id
      and o.owner_user_id = auth.uid()
  ) or exists (
    select 1
    from org_memberships m
    join players p on p.id = m.player_id
    where m.org_id = p_org_id
      and m.role = 'admin'
      and m.status = 'active'
      and p.user_id = auth.uid()
  );
$$;

create or replace function propagate_winner(p_match_id uuid, p_winner_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_next_match_id uuid;
  v_next_slot text;
  v_side_a uuid;
  v_side_b uuid;
begin
  if p_winner_id is null then
    return;
  end if;

  select next_match_id, next_slot
    into v_next_match_id, v_next_slot
  from matches
  where id = p_match_id;

  if v_next_match_id is null then
    return;
  end if;

  if v_next_slot = 'A' then
    update matches
      set side_a_entry_id = p_winner_id
    where id = v_next_match_id;
  else
    update matches
      set side_b_entry_id = p_winner_id
    where id = v_next_match_id;
  end if;

  select side_a_entry_id, side_b_entry_id
    into v_side_a, v_side_b
  from matches
  where id = v_next_match_id;

  update matches
    set status = case
      when v_side_a is not null and v_side_b is not null then 'ready'::match_status
      else 'pending'::match_status
    end
  where id = v_next_match_id
    and status <> 'finished'::match_status;
end;
$$;

create or replace function clear_downstream(p_match_id uuid, p_stale_winner uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_next_match_id uuid;
  v_next_slot text;
  v_next_winner uuid;
begin
  if p_stale_winner is null then
    return;
  end if;

  select next_match_id, next_slot
    into v_next_match_id, v_next_slot
  from matches
  where id = p_match_id;

  if v_next_match_id is null then
    return;
  end if;

  if v_next_slot = 'A' then
    update matches
    set side_a_entry_id = null
    where id = v_next_match_id
      and side_a_entry_id = p_stale_winner;
  else
    update matches
    set side_b_entry_id = null
    where id = v_next_match_id
      and side_b_entry_id = p_stale_winner;
  end if;

  select winner_entry_id
    into v_next_winner
  from matches
  where id = v_next_match_id;

  if v_next_winner is not null then
    delete from match_sets where match_id = v_next_match_id;
    perform clear_downstream(v_next_match_id, v_next_winner);
  end if;

  update matches
  set winner_entry_id = null,
      status = case
        when side_a_entry_id is not null and side_b_entry_id is not null then 'ready'::match_status
        else 'pending'::match_status
      end
  where id = v_next_match_id
    and status = 'finished'::match_status;
end;
$$;

create or replace function register_entry(
  p_slug text,
  p_entry_type tournament_category,
  p_phone_or_email text,
  p_member_one text,
  p_member_two text default null,
  p_display_name text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_tournament tournaments;
  v_entry_id uuid;
  v_display_name text;
begin
  select *
    into v_tournament
  from tournaments
  where slug = p_slug
  limit 1;

  if v_tournament.id is null then
    raise exception 'Tournament not found';
  end if;

  if v_tournament.is_public is false then
    raise exception 'Tournament is private';
  end if;

  if v_tournament.status <> 'registration_open' then
    raise exception 'Registration is closed';
  end if;

  if v_tournament.category <> p_entry_type then
    raise exception 'Invalid category for tournament';
  end if;

  if p_entry_type = 'singles' and (p_member_one is null or btrim(p_member_one) = '') then
    raise exception 'Single entry requires one participant';
  end if;

  if p_entry_type = 'doubles' then
    if p_member_one is null or btrim(p_member_one) = '' then
      raise exception 'Double entry requires at least one participant';
    end if;
    if v_tournament.doubles_pairing_mode <> 'pick_random'
       and (p_member_two is null or btrim(p_member_two) = '') then
      raise exception 'Double entry requires two participants';
    end if;
  end if;

  if p_phone_or_email is null or btrim(p_phone_or_email) = '' then
    raise exception 'Contact info is required';
  end if;

  if btrim(p_phone_or_email) !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$'
     and btrim(p_phone_or_email) !~ '^\+?[0-9\s\-\(\)]{7,20}$' then
    raise exception 'Invalid phone number or email';
  end if;

  if exists (
    select 1
    from entries e
    where e.tournament_id = v_tournament.id
      and e.phone_or_email = p_phone_or_email
      and e.status in ('pending', 'approved')
  ) then
    raise exception 'Registration already exists for this contact';
  end if;

  if p_display_name is not null and btrim(p_display_name) <> '' then
    v_display_name := p_display_name;
  elsif p_entry_type = 'singles' then
    v_display_name := p_member_one;
  elsif p_member_two is not null and btrim(p_member_two) <> '' then
    v_display_name := p_member_one || ' / ' || p_member_two;
  else
    v_display_name := p_member_one;
  end if;

  insert into entries (
    tournament_id,
    entry_type,
    display_name,
    phone_or_email,
    status
  ) values (
    v_tournament.id,
    p_entry_type,
    v_display_name,
    p_phone_or_email,
    'pending'
  )
  returning id into v_entry_id;

  insert into entry_members (entry_id, member_name, member_order)
  values (v_entry_id, p_member_one, 1);

  if p_entry_type = 'doubles' and p_member_two is not null and btrim(p_member_two) <> '' then
    insert into entry_members (entry_id, member_name, member_order)
    values (v_entry_id, p_member_two, 2);
  end if;

  return v_entry_id;
end;
$$;

drop function if exists create_tournament(
  text,
  text,
  text,
  tournament_category,
  set_format,
  boolean,
  doubles_pairing_mode
);

create or replace function create_tournament(
  p_name text,
  p_slug text,
  p_description text default null,
  p_category tournament_category default 'singles',
  p_set_format set_format default 'best_of_3',
  p_is_public boolean default true,
  p_doubles_pairing_mode doubles_pairing_mode default null,
  p_org_id uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
  v_uid uuid := auth.uid();
  v_org_id uuid := p_org_id;
  v_profile_name text;
begin
  if v_uid is null then
    raise exception 'Authentication required';
  end if;

  if v_org_id is null then
    select id into v_org_id
    from organizations
    where owner_user_id = v_uid
    order by created_at asc
    limit 1;
  else
    if not is_org_admin(v_org_id) then
      raise exception 'Forbidden for this organization';
    end if;
  end if;

  if v_org_id is null then
    select nullif(btrim(concat_ws(' ', first_name, last_name)), '')
      into v_profile_name
    from user_profiles
    where id = v_uid;

    insert into organizations (slug, type, name, owner_user_id)
    values (
      'coach-' || substring(v_uid::text, 1, 8),
      'coach',
      coalesce(v_profile_name, 'Coach') || ' (coach)',
      v_uid
    )
    on conflict (slug) do update
      set name = excluded.name
    returning id into v_org_id;
  end if;

  insert into tournaments (name, slug, description, category, set_format, status, is_public, doubles_pairing_mode, created_by, org_id)
  values (
    p_name,
    p_slug,
    p_description,
    p_category,
    p_set_format,
    'registration_open',
    p_is_public,
    case when p_category = 'doubles' then coalesce(p_doubles_pairing_mode, 'pre_agreed') else null end,
    v_uid,
    v_org_id
  )
  returning id into v_id;

  insert into tournament_admins (tournament_id, user_id, role)
  values (v_id, v_uid, 'owner');

  return v_id;
end;
$$;

create or replace function generate_bracket(
  p_tournament_id uuid,
  p_mode draw_mode default 'auto-random',
  p_manual_order uuid[] default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_entry_ids uuid[];
  v_ordered_ids uuid[];
  v_count integer;
  v_bracket_size integer := 1;
  v_rounds integer := 0;
  v_round integer;
  v_match integer;
  v_matches_in_round integer;
  v_match_id uuid;
  v_next_match_id uuid;
  v_side_a uuid;
  v_side_b uuid;
  v_winner uuid;
begin
  if not is_tournament_admin(p_tournament_id) then
    raise exception 'Not allowed';
  end if;

  select array_agg(e.id)
    into v_entry_ids
  from entries e
  where e.tournament_id = p_tournament_id
    and e.status = 'approved';

  v_count := coalesce(array_length(v_entry_ids, 1), 0);

  if v_count < 2 then
    raise exception 'At least 2 approved entries required';
  end if;

  if p_mode = 'manual' and p_manual_order is not null then
    select array_agg(x.entry_id)
      into v_ordered_ids
    from (
      select distinct unnest(p_manual_order) as entry_id
    ) x
    where x.entry_id = any(v_entry_ids);

    select coalesce(v_ordered_ids, '{}') || coalesce(array_agg(e.id order by e.created_at), '{}')
      into v_ordered_ids
    from entries e
    where e.tournament_id = p_tournament_id
      and e.status = 'approved'
      and not (e.id = any(coalesce(v_ordered_ids, '{}')));
  else
    select array_agg(e.id order by random())
      into v_ordered_ids
    from entries e
    where e.tournament_id = p_tournament_id
      and e.status = 'approved';
  end if;

  while v_bracket_size < v_count loop
    v_bracket_size := v_bracket_size * 2;
  end loop;

  v_matches_in_round := v_bracket_size / 2;
  while v_matches_in_round >= 1 loop
    v_rounds := v_rounds + 1;
    v_matches_in_round := v_matches_in_round / 2;
  end loop;

  delete from match_sets
  where match_id in (
    select m.id
    from matches m
    where m.tournament_id = p_tournament_id
  );

  delete from matches
  where tournament_id = p_tournament_id;

  create temporary table tmp_match_ids (
    round_number integer,
    match_number integer,
    match_id uuid
  ) on commit drop;

  for v_round in 1..v_rounds loop
    v_matches_in_round := v_bracket_size / (2 ^ v_round);

    for v_match in 1..v_matches_in_round loop
      insert into matches (
        tournament_id,
        round_number,
        match_number,
        status
      ) values (
        p_tournament_id,
        v_round,
        v_match,
        'pending'::match_status
      )
      returning id into v_match_id;

      insert into tmp_match_ids (round_number, match_number, match_id)
      values (v_round, v_match, v_match_id);
    end loop;
  end loop;

  for v_round in 1..(v_rounds - 1) loop
    v_matches_in_round := v_bracket_size / (2 ^ v_round);

    for v_match in 1..v_matches_in_round loop
      select tmi.match_id
        into v_match_id
      from tmp_match_ids tmi
      where tmi.round_number = v_round
        and tmi.match_number = v_match;

      select tmi.match_id
        into v_next_match_id
      from tmp_match_ids tmi
      where tmi.round_number = v_round + 1
        and tmi.match_number = ((v_match + 1) / 2)::integer;

      update matches
      set next_match_id = v_next_match_id,
          next_slot = case when mod(v_match, 2) = 1 then 'A' else 'B' end
      where id = v_match_id;
    end loop;
  end loop;

  v_matches_in_round := v_bracket_size / 2;
  for v_match in 1..v_matches_in_round loop
    v_side_a := null;
    v_side_b := null;

    if (2 * v_match - 1) <= v_count then
      v_side_a := v_ordered_ids[2 * v_match - 1];
    end if;

    if (2 * v_match) <= v_count then
      v_side_b := v_ordered_ids[2 * v_match];
    end if;

    select tmi.match_id
      into v_match_id
    from tmp_match_ids tmi
    where tmi.round_number = 1
      and tmi.match_number = v_match;

    v_winner := case
      when v_side_a is null then v_side_b
      when v_side_b is null then v_side_a
      else null
    end;

    update matches
    set side_a_entry_id = v_side_a,
        side_b_entry_id = v_side_b,
        winner_entry_id = v_winner,
        status = case
          when v_winner is not null then 'finished'::match_status
          when v_side_a is not null and v_side_b is not null then 'ready'::match_status
          else 'pending'::match_status
        end
    where id = v_match_id;

    if v_winner is not null then
      perform propagate_winner(v_match_id, v_winner);
    end if;
  end loop;
end;
$$;

create or replace function rebuild_bracket(
  p_tournament_id uuid,
  p_mode draw_mode default 'auto-random',
  p_manual_order uuid[] default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_snapshot jsonb;
begin
  select jsonb_build_object(
    'matches', coalesce((
      select jsonb_agg(row_to_json(m))
      from matches m
      where m.tournament_id = p_tournament_id
    ), '[]'::jsonb),
    'match_sets', coalesce((
      select jsonb_agg(row_to_json(ms))
      from match_sets ms
      join matches m on m.id = ms.match_id
      where m.tournament_id = p_tournament_id
    ), '[]'::jsonb)
  ) into v_snapshot;

  if v_snapshot->'matches' <> '[]'::jsonb then
    insert into bracket_versions (tournament_id, snapshot)
    values (p_tournament_id, v_snapshot);
  end if;

  perform generate_bracket(p_tournament_id, p_mode, p_manual_order);
end;
$$;

create or replace function form_random_pairs(p_tournament_id uuid)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_unpaired_ids uuid[];
  v_count integer;
  v_i integer;
  v_entry_a uuid;
  v_entry_b uuid;
  v_name_a text;
  v_name_b text;
  v_pairs_formed integer := 0;
begin
  if not is_tournament_admin(p_tournament_id) then
    raise exception 'Not allowed';
  end if;

  if not exists (
    select 1 from tournaments
    where id = p_tournament_id
      and category = 'doubles'
      and doubles_pairing_mode = 'pick_random'
  ) then
    raise exception 'Tournament is not configured for random pairing';
  end if;

  select array_agg(e.id order by random())
    into v_unpaired_ids
  from entries e
  where e.tournament_id = p_tournament_id
    and e.status = 'approved'
    and e.entry_type = 'doubles'
    and not exists (
      select 1 from entry_members em
      where em.entry_id = e.id and em.member_order = 2
    );

  v_count := coalesce(array_length(v_unpaired_ids, 1), 0);

  if v_count = 0 then
    return 0;
  end if;

  if v_count % 2 <> 0 then
    raise exception 'Odd number of unpaired players (%). Remove or add one before forming pairs.', v_count;
  end if;

  v_i := 1;
  while v_i <= v_count - 1 loop
    v_entry_a := v_unpaired_ids[v_i];
    v_entry_b := v_unpaired_ids[v_i + 1];

    select em.member_name into v_name_a
    from entry_members em
    where em.entry_id = v_entry_a and em.member_order = 1;

    select em.member_name into v_name_b
    from entry_members em
    where em.entry_id = v_entry_b and em.member_order = 1;

    insert into entry_members (entry_id, member_name, member_order)
    values (v_entry_a, v_name_b, 2);

    update entries
    set display_name = v_name_a || ' / ' || v_name_b
    where id = v_entry_a;

    delete from entry_members where entry_id = v_entry_b;
    delete from entries where id = v_entry_b;

    v_pairs_formed := v_pairs_formed + 1;
    v_i := v_i + 2;
  end loop;

  return v_pairs_formed;
end;
$$;

create or replace function form_manual_pairs(
  p_tournament_id uuid,
  p_pairs jsonb
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_pair jsonb;
  v_entry_a uuid;
  v_entry_b uuid;
  v_name_a text;
  v_name_b text;
  v_pairs_formed integer := 0;
begin
  if not is_tournament_admin(p_tournament_id) then
    raise exception 'Not allowed';
  end if;

  if not exists (
    select 1 from tournaments
    where id = p_tournament_id
      and category = 'doubles'
      and doubles_pairing_mode = 'pick_random'
  ) then
    raise exception 'Tournament is not configured for random pairing';
  end if;

  for v_pair in select * from jsonb_array_elements(p_pairs)
  loop
    v_entry_a := (v_pair->>0)::uuid;
    v_entry_b := (v_pair->>1)::uuid;

    if not exists (
      select 1 from entries
      where id = v_entry_a
        and tournament_id = p_tournament_id
        and status = 'approved'
        and not exists (
          select 1 from entry_members em where em.entry_id = v_entry_a and em.member_order = 2
        )
    ) then
      raise exception 'Entry % is not a valid unpaired entry', v_entry_a;
    end if;

    if not exists (
      select 1 from entries
      where id = v_entry_b
        and tournament_id = p_tournament_id
        and status = 'approved'
        and not exists (
          select 1 from entry_members em where em.entry_id = v_entry_b and em.member_order = 2
        )
    ) then
      raise exception 'Entry % is not a valid unpaired entry', v_entry_b;
    end if;

    select em.member_name into v_name_a
    from entry_members em
    where em.entry_id = v_entry_a and em.member_order = 1;

    select em.member_name into v_name_b
    from entry_members em
    where em.entry_id = v_entry_b and em.member_order = 1;

    insert into entry_members (entry_id, member_name, member_order)
    values (v_entry_a, v_name_b, 2);

    update entries
    set display_name = v_name_a || ' / ' || v_name_b
    where id = v_entry_a;

    delete from entry_members where entry_id = v_entry_b;
    delete from entries where id = v_entry_b;

    v_pairs_formed := v_pairs_formed + 1;
  end loop;

  return v_pairs_formed;
end;
$$;

create or replace function split_pairs(
  p_tournament_id uuid
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_entry record;
  v_member2_name text;
  v_new_entry_id uuid;
  v_split_count integer := 0;
begin
  if not is_tournament_admin(p_tournament_id) then
    raise exception 'Not allowed';
  end if;

  if not exists (
    select 1 from tournaments
    where id = p_tournament_id
      and category = 'doubles'
      and doubles_pairing_mode = 'pick_random'
  ) then
    raise exception 'Tournament is not configured for random pairing';
  end if;

  if exists (
    select 1 from tournaments
    where id = p_tournament_id
      and status in ('in_progress', 'completed')
  ) then
    raise exception 'Cannot edit pairs while tournament is in progress or completed';
  end if;

  delete from match_sets where match_id in (
    select id from matches where tournament_id = p_tournament_id
  );
  delete from matches where tournament_id = p_tournament_id;

  for v_entry in
    select e.id, e.phone_or_email
    from entries e
    where e.tournament_id = p_tournament_id
      and e.status = 'approved'
      and exists (
        select 1 from entry_members em
        where em.entry_id = e.id and em.member_order = 2
      )
  loop
    select em.member_name into v_member2_name
    from entry_members em
    where em.entry_id = v_entry.id and em.member_order = 2;

    delete from entry_members
    where entry_id = v_entry.id and member_order = 2;

    update entries
    set display_name = (
      select em.member_name from entry_members em
      where em.entry_id = v_entry.id and em.member_order = 1
    )
    where id = v_entry.id;

    insert into entries (tournament_id, entry_type, display_name, phone_or_email, status)
    values (p_tournament_id, 'doubles', v_member2_name, 'split-' || gen_random_uuid(), 'approved')
    returning id into v_new_entry_id;

    insert into entry_members (entry_id, member_name, member_order)
    values (v_new_entry_id, v_member2_name, 1);

    v_split_count := v_split_count + 1;
  end loop;

  return v_split_count;
end;
$$;

create or replace function update_match_sets(
  p_match_id uuid,
  p_sets jsonb
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_tournament_id uuid;
  v_tournament_status tournament_status;
  v_set_format set_format;
  v_required_wins integer;
  v_side_a_id uuid;
  v_side_b_id uuid;
  v_previous_winner uuid;
  v_new_winner uuid;
  v_a_wins integer := 0;
  v_b_wins integer := 0;
  v_item jsonb;
  v_set_index integer;
  v_a_games integer;
  v_b_games integer;
begin
  select m.tournament_id,
         m.side_a_entry_id,
         m.side_b_entry_id,
         m.winner_entry_id,
         t.set_format,
         t.status
    into v_tournament_id,
         v_side_a_id,
         v_side_b_id,
         v_previous_winner,
         v_set_format,
         v_tournament_status
  from matches m
  join tournaments t on t.id = m.tournament_id
  where m.id = p_match_id;

  if v_tournament_id is null then
    raise exception 'Match not found';
  end if;

  if not is_tournament_admin(v_tournament_id) then
    raise exception 'Not allowed';
  end if;

  if v_tournament_status <> 'in_progress'::tournament_status then
    raise exception 'Scores can be entered only after the tournament starts';
  end if;

  if v_side_a_id is null or v_side_b_id is null then
    raise exception 'Both sides must be assigned before scoring';
  end if;

  v_required_wins := case
    when v_set_format = 'best_of_5' then 3
    else 2
  end;

  delete from match_sets where match_id = p_match_id;

  for v_item in
    select value
    from jsonb_array_elements(p_sets)
  loop
    v_set_index := (v_item->>'set_index')::integer;
    v_a_games := (v_item->>'side_a_games')::integer;
    v_b_games := (v_item->>'side_b_games')::integer;

    insert into match_sets (
      match_id,
      set_index,
      side_a_games,
      side_b_games
    ) values (
      p_match_id,
      v_set_index,
      v_a_games,
      v_b_games
    );

    if v_a_games > v_b_games then
      v_a_wins := v_a_wins + 1;
    elsif v_b_games > v_a_games then
      v_b_wins := v_b_wins + 1;
    end if;
  end loop;

  v_new_winner := case
    when v_a_wins >= v_required_wins then v_side_a_id
    when v_b_wins >= v_required_wins then v_side_b_id
    else null
  end;

  update matches
  set winner_entry_id = v_new_winner,
      status = case
        when v_new_winner is null then 'ready'::match_status
        else 'finished'::match_status
      end
  where id = p_match_id;

  if v_previous_winner is not null and v_previous_winner is distinct from v_new_winner then
    perform clear_downstream(p_match_id, v_previous_winner);
  end if;

  if v_new_winner is not null then
    perform propagate_winner(p_match_id, v_new_winner);
  end if;

  -- status transitions are managed explicitly via the admin UI

  return v_new_winner;
end;
$$;

create or replace function swap_bracket_slots(
  p_tournament_id uuid,
  p_from_match_id uuid,
  p_from_slot text,
  p_to_match_id uuid,
  p_to_slot text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_fs text := upper(trim(p_from_slot));
  v_ts text := upper(trim(p_to_slot));
  m_from matches%rowtype;
  m_to matches%rowtype;
  v1 uuid;
  v2 uuid;
  nf_a uuid;
  nf_b uuid;
  nt_a uuid;
  nt_b uuid;
begin
  if v_fs not in ('A', 'B') or v_ts not in ('A', 'B') then
    raise exception 'Invalid slot (use A or B)';
  end if;

  if not is_tournament_admin(p_tournament_id) then
    raise exception 'Not allowed';
  end if;

  select * into m_from from matches where id = p_from_match_id for update;
  select * into m_to from matches where id = p_to_match_id for update;

  if m_from.id is null or m_to.id is null then
    raise exception 'Match not found';
  end if;

  if m_from.tournament_id <> p_tournament_id or m_to.tournament_id <> p_tournament_id then
    raise exception 'Match does not belong to this tournament';
  end if;

  if m_from.status = 'finished'::match_status or m_to.status = 'finished'::match_status then
    raise exception 'Cannot move players in finished matches';
  end if;

  if exists (
    select 1
    from match_sets ms
    where ms.match_id in (p_from_match_id, p_to_match_id)
  ) then
    raise exception 'Cannot move players when match scores exist';
  end if;

  if p_from_match_id = p_to_match_id then
    if v_fs = v_ts then
      return;
    end if;
    update matches
    set
      side_a_entry_id = m_from.side_b_entry_id,
      side_b_entry_id = m_from.side_a_entry_id,
      winner_entry_id = null,
      status = case
        when m_from.side_b_entry_id is not null and m_from.side_a_entry_id is not null then 'ready'::match_status
        else 'pending'::match_status
      end
    where id = p_from_match_id;
    return;
  end if;

  v1 := case v_fs when 'A' then m_from.side_a_entry_id else m_from.side_b_entry_id end;
  v2 := case v_ts when 'A' then m_to.side_a_entry_id else m_to.side_b_entry_id end;

  nf_a := m_from.side_a_entry_id;
  nf_b := m_from.side_b_entry_id;
  nt_a := m_to.side_a_entry_id;
  nt_b := m_to.side_b_entry_id;

  if v_fs = 'A' then
    nf_a := v2;
  else
    nf_b := v2;
  end if;

  if v_ts = 'A' then
    nt_a := v1;
  else
    nt_b := v1;
  end if;

  update matches
  set
    side_a_entry_id = nf_a,
    side_b_entry_id = nf_b,
    winner_entry_id = null,
    status = case
      when nf_a is not null and nf_b is not null then 'ready'::match_status
      else 'pending'::match_status
    end
  where id = p_from_match_id;

  update matches
  set
    side_a_entry_id = nt_a,
    side_b_entry_id = nt_b,
    winner_entry_id = null,
    status = case
      when nt_a is not null and nt_b is not null then 'ready'::match_status
      else 'pending'::match_status
    end
  where id = p_to_match_id;
end;
$$;

create or replace function apply_bracket_layout(
  p_tournament_id uuid,
  p_layout jsonb
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_item jsonb;
  v_match_id uuid;
  v_side_a uuid;
  v_side_b uuid;
  v_match matches%rowtype;
begin
  if not is_tournament_admin(p_tournament_id) then
    raise exception 'Not allowed';
  end if;

  for v_item in select * from jsonb_array_elements(p_layout)
  loop
    v_match_id := (v_item->>'match_id')::uuid;
    v_side_a := nullif(v_item->>'side_a_entry_id', '')::uuid;
    v_side_b := nullif(v_item->>'side_b_entry_id', '')::uuid;

    select * into v_match from matches where id = v_match_id;
    if v_match.id is null then
      raise exception 'Match % not found', v_match_id;
    end if;
    if v_match.tournament_id <> p_tournament_id then
      raise exception 'Match does not belong to this tournament';
    end if;
    if v_match.status = 'finished'::match_status then
      raise exception 'Cannot modify finished match';
    end if;

    update matches
    set
      side_a_entry_id = v_side_a,
      side_b_entry_id = v_side_b,
      winner_entry_id = null,
      status = case
        when v_side_a is not null and v_side_b is not null then 'ready'::match_status
        else 'pending'::match_status
      end
    where id = v_match_id;
  end loop;
end;
$$;

create or replace function add_tournament_admin_by_email(
  p_tournament_id uuid,
  p_email text,
  p_role text default 'editor'
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid;
begin
  if not is_tournament_admin(p_tournament_id) then
    raise exception 'Not authorized';
  end if;

  select id into v_user_id
  from auth.users
  where email = lower(trim(p_email));

  if v_user_id is null then
    raise exception 'User with email % not found', p_email;
  end if;

  insert into tournament_admins (tournament_id, user_id, role)
  values (p_tournament_id, v_user_id, p_role)
  on conflict (tournament_id, user_id)
  do update set role = excluded.role;
end;
$$;

create or replace function remove_tournament_admin(
  p_tournament_id uuid,
  p_admin_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not is_tournament_admin(p_tournament_id) then
    raise exception 'Not authorized';
  end if;

  delete from tournament_admins
  where id = p_admin_id
    and tournament_id = p_tournament_id;
end;
$$;

create or replace function get_tournament_admins_with_email(p_tournament_id uuid)
returns table (
  id uuid,
  user_id uuid,
  email text,
  role text,
  created_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
begin
  if not is_tournament_admin(p_tournament_id) then
    raise exception 'Not authorized';
  end if;

  return query
    select ta.id, ta.user_id, u.email::text, ta.role, ta.created_at
    from tournament_admins ta
    join auth.users u on u.id = ta.user_id
    where ta.tournament_id = p_tournament_id
    order by ta.created_at asc;
end;
$$;

alter table tournaments enable row level security;
alter table tournament_admins enable row level security;
alter table entries enable row level security;
alter table entry_members enable row level security;
alter table matches enable row level security;
alter table match_sets enable row level security;
alter table bracket_versions enable row level security;

drop policy if exists bracket_versions_select_admin on bracket_versions;
create policy bracket_versions_select_admin on bracket_versions
for select
to authenticated
using (is_tournament_admin(tournament_id));

drop policy if exists bracket_versions_insert_admin on bracket_versions;
create policy bracket_versions_insert_admin on bracket_versions
for insert
to authenticated
with check (is_tournament_admin(tournament_id));

drop policy if exists tournaments_public_or_admin_select on tournaments;
create policy tournaments_public_or_admin_select on tournaments
for select
using (
  is_public = true or is_tournament_admin(id)
);

drop policy if exists tournaments_insert_authenticated on tournaments;
create policy tournaments_insert_authenticated on tournaments
for insert
to authenticated
with check (
  created_by = auth.uid()
);

drop policy if exists tournaments_update_admin on tournaments;
create policy tournaments_update_admin on tournaments
for update
to authenticated
using (is_tournament_admin(id))
with check (is_tournament_admin(id));

drop policy if exists tournaments_delete_admin on tournaments;
create policy tournaments_delete_admin on tournaments
for delete
to authenticated
using (is_tournament_admin(id));

drop policy if exists tournament_admins_select_admin on tournament_admins;
create policy tournament_admins_select_admin on tournament_admins
for select
to authenticated
using (is_tournament_admin(tournament_id));

drop policy if exists tournament_admins_insert_owner_or_admin on tournament_admins;
create policy tournament_admins_insert_owner_or_admin on tournament_admins
for insert
to authenticated
with check (
  (
    user_id = auth.uid()
    and exists (
      select 1
      from tournaments t
      where t.id = tournament_id
        and t.created_by = auth.uid()
    )
  )
  or is_tournament_admin(tournament_id)
);

drop policy if exists tournament_admins_delete_admin on tournament_admins;
create policy tournament_admins_delete_admin on tournament_admins
for delete
to authenticated
using (is_tournament_admin(tournament_id));

drop policy if exists entries_public_or_admin_select on entries;
create policy entries_public_or_admin_select on entries
for select
using (
  exists (
    select 1
    from tournaments t
    where t.id = entries.tournament_id
      and (t.is_public = true or is_tournament_admin(t.id))
  )
);

drop policy if exists entries_insert_admin on entries;
create policy entries_insert_admin on entries
for insert
to authenticated
with check (is_tournament_admin(tournament_id));

drop policy if exists entries_update_admin on entries;
create policy entries_update_admin on entries
for update
to authenticated
using (is_tournament_admin(tournament_id))
with check (is_tournament_admin(tournament_id));

drop policy if exists entries_delete_admin on entries;
create policy entries_delete_admin on entries
for delete
to authenticated
using (is_tournament_admin(tournament_id));

drop policy if exists entry_members_public_or_admin_select on entry_members;
create policy entry_members_public_or_admin_select on entry_members
for select
using (
  exists (
    select 1
    from entries e
    join tournaments t on t.id = e.tournament_id
    where e.id = entry_members.entry_id
      and (t.is_public = true or is_tournament_admin(t.id))
  )
);

drop policy if exists entry_members_insert_admin on entry_members;
create policy entry_members_insert_admin on entry_members
for insert
to authenticated
with check (
  exists (
    select 1
    from entries e
    where e.id = entry_members.entry_id
      and is_tournament_admin(e.tournament_id)
  )
);

drop policy if exists entry_members_update_admin on entry_members;
create policy entry_members_update_admin on entry_members
for update
to authenticated
using (
  exists (
    select 1
    from entries e
    where e.id = entry_members.entry_id
      and is_tournament_admin(e.tournament_id)
  )
)
with check (
  exists (
    select 1
    from entries e
    where e.id = entry_members.entry_id
      and is_tournament_admin(e.tournament_id)
  )
);

drop policy if exists entry_members_delete_admin on entry_members;
create policy entry_members_delete_admin on entry_members
for delete
to authenticated
using (
  exists (
    select 1
    from entries e
    where e.id = entry_members.entry_id
      and is_tournament_admin(e.tournament_id)
  )
);

drop policy if exists matches_public_or_admin_select on matches;
create policy matches_public_or_admin_select on matches
for select
using (
  exists (
    select 1
    from tournaments t
    where t.id = matches.tournament_id
      and (t.is_public = true or is_tournament_admin(t.id))
  )
);

drop policy if exists matches_insert_admin on matches;
create policy matches_insert_admin on matches
for insert
to authenticated
with check (is_tournament_admin(tournament_id));

drop policy if exists matches_update_admin on matches;
create policy matches_update_admin on matches
for update
to authenticated
using (is_tournament_admin(tournament_id))
with check (is_tournament_admin(tournament_id));

drop policy if exists matches_delete_admin on matches;
create policy matches_delete_admin on matches
for delete
to authenticated
using (is_tournament_admin(tournament_id));

drop policy if exists match_sets_public_or_admin_select on match_sets;
create policy match_sets_public_or_admin_select on match_sets
for select
using (
  exists (
    select 1
    from matches m
    join tournaments t on t.id = m.tournament_id
    where m.id = match_sets.match_id
      and (t.is_public = true or is_tournament_admin(t.id))
  )
);

drop policy if exists match_sets_insert_admin on match_sets;
create policy match_sets_insert_admin on match_sets
for insert
to authenticated
with check (
  exists (
    select 1
    from matches m
    where m.id = match_sets.match_id
      and is_tournament_admin(m.tournament_id)
  )
);

drop policy if exists match_sets_update_admin on match_sets;
create policy match_sets_update_admin on match_sets
for update
to authenticated
using (
  exists (
    select 1
    from matches m
    where m.id = match_sets.match_id
      and is_tournament_admin(m.tournament_id)
  )
)
with check (
  exists (
    select 1
    from matches m
    where m.id = match_sets.match_id
      and is_tournament_admin(m.tournament_id)
  )
);

drop policy if exists match_sets_delete_admin on match_sets;
create policy match_sets_delete_admin on match_sets
for delete
to authenticated
using (
  exists (
    select 1
    from matches m
    where m.id = match_sets.match_id
      and is_tournament_admin(m.tournament_id)
  )
);

grant execute on function create_tournament(text, text, text, tournament_category, set_format, boolean, doubles_pairing_mode, uuid) to authenticated;
grant execute on function register_entry(text, tournament_category, text, text, text, text) to anon, authenticated;
grant execute on function normalize_contact(text) to authenticated;
grant execute on function hash_contact(text) to authenticated;
grant execute on function is_org_admin(uuid) to authenticated;
grant execute on function generate_bracket(uuid, draw_mode, uuid[]) to authenticated;
grant execute on function rebuild_bracket(uuid, draw_mode, uuid[]) to authenticated;
grant execute on function update_match_sets(uuid, jsonb) to authenticated;
grant execute on function swap_bracket_slots(uuid, uuid, text, uuid, text) to authenticated;
grant execute on function form_random_pairs(uuid) to authenticated;
grant execute on function form_manual_pairs(uuid, jsonb) to authenticated;
grant execute on function split_pairs(uuid) to authenticated;
grant execute on function apply_bracket_layout(uuid, jsonb) to authenticated;
grant execute on function add_tournament_admin_by_email(uuid, text, text) to authenticated;
grant execute on function remove_tournament_admin(uuid, uuid) to authenticated;
grant execute on function get_tournament_admins_with_email(uuid) to authenticated;

-- Idempotent: skip if table is already in supabase_realtime publication
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'tournaments'
  ) then
    alter publication supabase_realtime add table tournaments;
  end if;
end $$;

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'entries'
  ) then
    alter publication supabase_realtime add table entries;
  end if;
end $$;

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'matches'
  ) then
    alter publication supabase_realtime add table matches;
  end if;
end $$;

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'match_sets'
  ) then
    alter publication supabase_realtime add table match_sets;
  end if;
end $$;

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'tournament_admins'
  ) then
    alter publication supabase_realtime add table tournament_admins;
  end if;
end $$;

-- =============================================
-- CLUB REGISTRATION & PLATFORM ADMIN
-- =============================================

-- Enum: club status
do $$ begin
  create type club_status as enum ('pending', 'approved', 'rejected', 'active');
exception
  when duplicate_object then null;
end $$;

-- User profiles (extends auth.users)
create table if not exists user_profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  first_name text not null,
  last_name text not null,
  phone text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

drop trigger if exists trg_user_profiles_updated_at on user_profiles;
create trigger trg_user_profiles_updated_at
before update on user_profiles for each row execute function set_updated_at();

-- Clubs
create table if not exists clubs (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  city text not null,
  address text,
  contact_email text,
  contact_phone text,
  status club_status not null default 'pending',
  owner_id uuid not null references auth.users(id) on delete restrict,
  rejection_reason text,
  reviewed_by uuid references auth.users(id),
  reviewed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

drop trigger if exists trg_clubs_updated_at on clubs;
create trigger trg_clubs_updated_at
before update on clubs for each row execute function set_updated_at();

-- Platform super admins
create table if not exists platform_admins (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade unique,
  created_at timestamptz not null default now()
);

-- Add nullable club_id to tournaments
do $$
begin
  if not exists (
    select 1 from information_schema.columns
    where table_name = 'tournaments' and column_name = 'club_id'
  ) then
    alter table tournaments add column club_id uuid references clubs(id) on delete set null;
  end if;
end $$;

create index if not exists idx_tournaments_club on tournaments(club_id);

-- Helper: check if current user is platform admin
create or replace function is_platform_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from platform_admins where user_id = auth.uid()
  );
$$;

-- RLS: user_profiles
alter table user_profiles enable row level security;

do $$ begin
  drop policy if exists user_profiles_select_own on user_profiles;
  drop policy if exists user_profiles_insert_own on user_profiles;
  drop policy if exists user_profiles_update_own on user_profiles;
  drop policy if exists user_profiles_select_superadmin on user_profiles;
end $$;

create policy user_profiles_select_own on user_profiles
  for select to authenticated using (id = auth.uid());

create policy user_profiles_insert_own on user_profiles
  for insert to authenticated with check (id = auth.uid());

create policy user_profiles_update_own on user_profiles
  for update to authenticated using (id = auth.uid()) with check (id = auth.uid());

create policy user_profiles_select_superadmin on user_profiles
  for select to authenticated using (is_platform_admin());

-- RLS: clubs
alter table clubs enable row level security;

do $$ begin
  drop policy if exists clubs_select_own on clubs;
  drop policy if exists clubs_select_superadmin on clubs;
  drop policy if exists clubs_insert_authenticated on clubs;
  drop policy if exists clubs_update_superadmin on clubs;
end $$;

create policy clubs_select_own on clubs
  for select to authenticated using (owner_id = auth.uid());

create policy clubs_select_superadmin on clubs
  for select to authenticated using (is_platform_admin());

-- RLS: platform_admins
alter table platform_admins enable row level security;

do $$ begin
  drop policy if exists platform_admins_select_self on platform_admins;
end $$;

create policy platform_admins_select_self on platform_admins
  for select to authenticated using (user_id = auth.uid());

-- RLS: organizations
alter table organizations enable row level security;

drop policy if exists organizations_public_read on organizations;
drop policy if exists organizations_owner_write on organizations;
drop policy if exists organizations_platform_write on organizations;

create policy organizations_public_read on organizations
  for select using (
    (is_active = true and status = 'active')
    or auth.uid() = owner_user_id
    or is_platform_admin()
  );

create policy organizations_platform_write on organizations
  for all using (is_platform_admin())
  with check (is_platform_admin());

-- RPC: register organization-backed club (profile + pending organization)
create or replace function register_organization(
  p_first_name text,
  p_last_name text,
  p_phone text,
  p_org_name text,
  p_org_city text,
  p_org_address text default null,
  p_contact_email text default null,
  p_contact_phone text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_org_id uuid;
  v_slug text;
begin
  if v_uid is null then
    raise exception 'Authentication required';
  end if;

  insert into user_profiles (id, first_name, last_name, phone)
  values (v_uid, p_first_name, p_last_name, p_phone)
  on conflict (id) do update
  set first_name = excluded.first_name,
      last_name = excluded.last_name,
      phone = excluded.phone;

  if exists (
    select 1 from organizations
    where type = 'club'
      and lower(name) = lower(p_org_name)
      and lower(coalesce(city, '')) = lower(coalesce(p_org_city, ''))
      and status in ('pending', 'active')
  ) then
    raise exception 'CLUB_DUPLICATE';
  end if;

  if exists (
    select 1 from organizations
    where owner_user_id = v_uid
      and type = 'club'
      and status in ('pending', 'active')
  ) then
    raise exception 'CLUB_ALREADY_EXISTS';
  end if;

  v_slug := 'club-' || substring(replace(gen_random_uuid()::text, '-', ''), 1, 10);

  insert into organizations (
    slug, type, name, city, address, contact_email, contact_phone,
    owner_user_id, status, is_active
  )
  values (
    v_slug,
    'club',
    p_org_name,
    p_org_city,
    p_org_address,
    coalesce(p_contact_email, (select email from auth.users where id = v_uid)),
    p_contact_phone,
    v_uid,
    'pending',
    false
  )
  returning id into v_org_id;

  return v_org_id;
end;
$$;

-- RPC: approve organization-backed club (super admin only)
create or replace function approve_organization(p_org_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not is_platform_admin() then
    raise exception 'Not allowed';
  end if;

  update organizations
  set status = 'active',
      is_active = true,
      reviewed_by = auth.uid(),
      reviewed_at = now(),
      rejection_reason = null
  where id = p_org_id
    and type = 'club'
    and status = 'pending';
end;
$$;

-- RPC: reject organization-backed club (super admin only)
create or replace function reject_organization(p_org_id uuid, p_reason text default null)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not is_platform_admin() then
    raise exception 'Not allowed';
  end if;

  update organizations
  set status = 'rejected',
      is_active = false,
      reviewed_by = auth.uid(),
      reviewed_at = now(),
      rejection_reason = p_reason
  where id = p_org_id
    and type = 'club'
    and status = 'pending';
end;
$$;

-- RPC: list organization-backed club registrations with owner info.
create or replace function list_organizations_for_review()
returns table (
  id uuid,
  name text,
  city text,
  address text,
  contact_email text,
  contact_phone text,
  status organization_status,
  rejection_reason text,
  created_at timestamptz,
  reviewed_at timestamptz,
  owner_first_name text,
  owner_last_name text,
  owner_email text,
  owner_phone text,
  duplicate_count bigint
)
language plpgsql
security definer
set search_path = public
as $$
begin
  if not is_platform_admin() then
    raise exception 'Not allowed';
  end if;

  return query
  select
    o.id,
    o.name,
    o.city,
    o.address,
    o.contact_email,
    o.contact_phone,
    o.status,
    o.rejection_reason,
    o.created_at,
    o.reviewed_at,
    up.first_name::text as owner_first_name,
    up.last_name::text as owner_last_name,
    u.email::text as owner_email,
    up.phone::text as owner_phone,
    (
      select count(*) from organizations o2
      where o2.type = 'club'
        and lower(o2.name) = lower(o.name)
        and lower(coalesce(o2.city, '')) = lower(coalesce(o.city, ''))
        and o2.id <> o.id
        and o2.status in ('active', 'pending')
    ) as duplicate_count
  from organizations o
  join auth.users u on u.id = o.owner_user_id
  left join user_profiles up on up.id = o.owner_user_id
  where o.type = 'club'
  order by
    case o.status when 'pending' then 0 when 'active' then 1 when 'rejected' then 2 else 3 end,
    o.created_at desc;
end;
$$;

create or replace function my_club_registration()
returns table (
  id uuid,
  name text,
  city text,
  address text,
  contact_email text,
  contact_phone text,
  status organization_status,
  rejection_reason text,
  created_at timestamptz,
  reviewed_at timestamptz,
  slug text
)
language sql
stable
security definer
set search_path = public
as $$
  select
    o.id,
    o.name,
    o.city,
    o.address,
    o.contact_email,
    o.contact_phone,
    o.status,
    o.rejection_reason,
    o.created_at,
    o.reviewed_at,
    o.slug
  from organizations o
  where o.owner_user_id = auth.uid()
    and o.type = 'club'
  order by o.created_at desc
  limit 1;
$$;

create or replace function club_page_data(p_slug text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_org organizations%rowtype;
  v_tournaments jsonb;
  v_members jsonb;
  v_member_count int;
  v_my_membership jsonb;
begin
  select * into v_org
  from organizations
  where slug = p_slug
    and is_active = true
    and status = 'active';

  if not found then
    return null;
  end if;

  select coalesce(jsonb_agg(t order by t.created_at desc), '[]'::jsonb)
  into v_tournaments
  from (
    select id, slug, name, category, status, created_at
    from tournaments
    where org_id = v_org.id
      and is_public = true
    order by created_at desc
    limit 50
  ) t;

  select coalesce(jsonb_agg(m), '[]'::jsonb)
  into v_members
  from (
    select p.id, p.display_name, p.avatar_url, m.role, m.joined_at
    from org_memberships m
    join players p on p.id = m.player_id
    where m.org_id = v_org.id
      and m.status = 'active'
      and p.is_deleted = false
    order by m.joined_at desc nulls last
    limit 12
  ) m;

  select count(*) into v_member_count
  from org_memberships m
  join players p on p.id = m.player_id
  where m.org_id = v_org.id
    and m.status = 'active'
    and p.is_deleted = false;

  if auth.uid() is not null then
    select to_jsonb(m) into v_my_membership
    from org_memberships m
    join players p on p.id = m.player_id
    where m.org_id = v_org.id
      and p.user_id = auth.uid()
      and p.is_deleted = false
    limit 1;
  end if;

  return jsonb_build_object(
    'org', to_jsonb(v_org),
    'tournaments', v_tournaments,
    'members_preview', v_members,
    'members_count', v_member_count,
    'my_membership', coalesce(v_my_membership, 'null'::jsonb),
    'is_owner', v_org.owner_user_id = auth.uid()
  );
end;
$$;

-- Backwards-compatible RPC wrappers. New writes stay in organizations.
create or replace function register_club(
  p_first_name text,
  p_last_name text,
  p_phone text,
  p_club_name text,
  p_club_city text,
  p_club_address text default null,
  p_contact_email text default null,
  p_contact_phone text default null
)
returns uuid
language sql
security definer
set search_path = public
as $$
  select register_organization(
    p_first_name,
    p_last_name,
    p_phone,
    p_club_name,
    p_club_city,
    p_club_address,
    p_contact_email,
    p_contact_phone
  );
$$;

create or replace function approve_club(p_club_id uuid)
returns void
language sql
security definer
set search_path = public
as $$
  select approve_organization(p_club_id);
$$;

create or replace function reject_club(p_club_id uuid, p_reason text default null)
returns void
language sql
security definer
set search_path = public
as $$
  select reject_organization(p_club_id, p_reason);
$$;

drop function if exists get_pending_clubs();
create or replace function get_pending_clubs()
returns table (
  id uuid,
  name text,
  city text,
  address text,
  contact_email text,
  contact_phone text,
  status organization_status,
  rejection_reason text,
  created_at timestamptz,
  reviewed_at timestamptz,
  owner_first_name text,
  owner_last_name text,
  owner_email text,
  owner_phone text,
  duplicate_count bigint
)
language sql
security definer
set search_path = public
as $$
  select
    id,
    name,
    city,
    address,
    contact_email,
    contact_phone,
    status,
    rejection_reason,
    created_at,
    reviewed_at,
    owner_first_name,
    owner_last_name,
    owner_email,
    owner_phone,
    duplicate_count
  from list_organizations_for_review();
$$;

-- Grant execute on new functions
grant execute on function register_organization(text, text, text, text, text, text, text, text) to authenticated;
grant execute on function approve_organization(uuid) to authenticated;
grant execute on function reject_organization(uuid, text) to authenticated;
grant execute on function list_organizations_for_review() to authenticated;
grant execute on function my_club_registration() to authenticated;
grant execute on function club_page_data(text) to anon, authenticated;
grant execute on function register_club(text, text, text, text, text, text, text, text) to authenticated;
grant execute on function approve_club(uuid) to authenticated;
grant execute on function reject_club(uuid, text) to authenticated;
grant execute on function get_pending_clubs() to authenticated;
grant execute on function is_platform_admin() to authenticated;

-- Realtime for clubs
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'clubs'
  ) then
    alter publication supabase_realtime add table clubs;
  end if;
end $$;

-- =============================================
-- LIVE SCORING & COUNTER ROLE
-- =============================================


alter table tournament_admins drop constraint if exists tournament_admins_role_check;
alter table tournament_admins
  add constraint tournament_admins_role_check check (role in ('owner', 'editor', 'counter'));

create or replace function is_tournament_admin(p_tournament_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from tournament_admins ta
    where ta.tournament_id = p_tournament_id
      and ta.user_id = auth.uid()
      and ta.role in ('owner', 'editor')
  );
$$;

create or replace function can_live_score(p_tournament_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from tournament_admins ta
    where ta.tournament_id = p_tournament_id
      and ta.user_id = auth.uid()
      and ta.role in ('owner', 'editor', 'counter')
  );
$$;

create or replace function get_my_tournament_role(p_tournament_id uuid)
returns text
language sql
stable
security definer
set search_path = public
as $$
  select ta.role
  from tournament_admins ta
  where ta.tournament_id = p_tournament_id
    and ta.user_id = auth.uid()
  limit 1;
$$;

create table if not exists live_scores (
  id uuid primary key default gen_random_uuid()
);

alter table live_scores add column if not exists match_id uuid;
alter table live_scores add column if not exists tournament_id uuid;
alter table live_scores add column if not exists counter_user_id uuid references auth.users (id) on delete set null;
alter table live_scores add column if not exists status text default 'active';
alter table live_scores add column if not exists state jsonb;
alter table live_scores add column if not exists history jsonb default '[]'::jsonb;
alter table live_scores add column if not exists revision integer default 0;
alter table live_scores add column if not exists created_at timestamptz default now();
alter table live_scores add column if not exists updated_at timestamptz default now();

update live_scores ls
set tournament_id = m.tournament_id
from matches m
where ls.match_id = m.id
  and ls.tournament_id is null;

update live_scores
set status = 'active'
where status is null or status not in ('active', 'stopped', 'finished');

update live_scores
set history = '[]'::jsonb
where history is null;

update live_scores
set revision = 0
where revision is null;

update live_scores
set created_at = now()
where created_at is null;

update live_scores
set updated_at = now()
where updated_at is null;

update live_scores ls
set state = jsonb_build_object(
  'points', jsonb_build_object('a', 0, 'b', 0),
  'games', jsonb_build_object('a', 0, 'b', 0),
  'setsWon', jsonb_build_object('a', 0, 'b', 0),
  'sets', '[]'::jsonb,
  'currentSet', 1,
  'isTiebreak', false,
  'tiebreakPoints', jsonb_build_object('a', 0, 'b', 0),
  'requiredSets', case when t.set_format = 'best_of_5' then 3 else 2 end,
  'winner', null
)
from matches m
join tournaments t on t.id = m.tournament_id
where ls.match_id = m.id
  and ls.state is null;

update live_scores
set state = jsonb_build_object(
  'points', jsonb_build_object('a', 0, 'b', 0),
  'games', jsonb_build_object('a', 0, 'b', 0),
  'setsWon', jsonb_build_object('a', 0, 'b', 0),
  'sets', '[]'::jsonb,
  'currentSet', 1,
  'isTiebreak', false,
  'tiebreakPoints', jsonb_build_object('a', 0, 'b', 0),
  'requiredSets', 2,
  'winner', null
)
where state is null;

alter table live_scores alter column id set default gen_random_uuid();
update live_scores set id = gen_random_uuid() where id is null;
alter table live_scores alter column id set not null;
alter table live_scores alter column status set default 'active';
alter table live_scores alter column status set not null;
alter table live_scores alter column state set not null;
alter table live_scores alter column history set default '[]'::jsonb;
alter table live_scores alter column history set not null;
alter table live_scores alter column revision set default 0;
alter table live_scores alter column revision set not null;
alter table live_scores alter column created_at set default now();
alter table live_scores alter column created_at set not null;
alter table live_scores alter column updated_at set default now();
alter table live_scores alter column updated_at set not null;

alter table live_scores drop constraint if exists live_scores_status_check;
alter table live_scores
  add constraint live_scores_status_check check (status in ('active', 'stopped', 'finished'));

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conrelid = 'public.live_scores'::regclass
      and contype = 'p'
  ) then
    alter table live_scores add constraint live_scores_pkey primary key (id);
  end if;
end $$;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.live_scores'::regclass
      and conname = 'live_scores_match_id_fkey'
  ) then
    alter table live_scores
      add constraint live_scores_match_id_fkey
      foreign key (match_id) references matches(id) on delete cascade;
  end if;
end $$;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.live_scores'::regclass
      and conname = 'live_scores_tournament_id_fkey'
  ) then
    alter table live_scores
      add constraint live_scores_tournament_id_fkey
      foreign key (tournament_id) references tournaments(id) on delete cascade;
  end if;
end $$;

create index if not exists idx_live_scores_tournament on live_scores (tournament_id);
create index if not exists idx_live_scores_match on live_scores (match_id);
create unique index if not exists idx_live_scores_match_unique
  on live_scores (match_id)
  where match_id is not null;

drop trigger if exists trg_live_scores_updated_at on live_scores;
create trigger trg_live_scores_updated_at
before update on live_scores
for each row
execute function set_updated_at();

create or replace function live_score_initial_state(p_required_sets integer)
returns jsonb
language sql
immutable
as $$
  select jsonb_build_object(
    'points', jsonb_build_object('a', 0, 'b', 0),
    'games', jsonb_build_object('a', 0, 'b', 0),
    'setsWon', jsonb_build_object('a', 0, 'b', 0),
    'sets', '[]'::jsonb,
    'currentSet', 1,
    'isTiebreak', false,
    'tiebreakPoints', jsonb_build_object('a', 0, 'b', 0),
    'requiredSets', p_required_sets,
    'winner', null
  );
$$;

create or replace function tennis_apply_point(p_state jsonb, p_side text)
returns jsonb
language plpgsql
immutable
as $$
declare
  v_side text := lower(trim(p_side));
  v_other text;
  v_points_a integer := coalesce((p_state #>> '{points,a}')::integer, 0);
  v_points_b integer := coalesce((p_state #>> '{points,b}')::integer, 0);
  v_games_a integer := coalesce((p_state #>> '{games,a}')::integer, 0);
  v_games_b integer := coalesce((p_state #>> '{games,b}')::integer, 0);
  v_sets_a integer := coalesce((p_state #>> '{setsWon,a}')::integer, 0);
  v_sets_b integer := coalesce((p_state #>> '{setsWon,b}')::integer, 0);
  v_tb_a integer := coalesce((p_state #>> '{tiebreakPoints,a}')::integer, 0);
  v_tb_b integer := coalesce((p_state #>> '{tiebreakPoints,b}')::integer, 0);
  v_required_sets integer := coalesce((p_state->>'requiredSets')::integer, 2);
  v_current_set integer := coalesce((p_state->>'currentSet')::integer, 1);
  v_is_tiebreak boolean := coalesce((p_state->>'isTiebreak')::boolean, false);
  v_winner text := nullif(p_state->>'winner', '');
  v_sets jsonb := coalesce(p_state->'sets', '[]'::jsonb);
  v_side_points integer;
  v_other_points integer;
  v_set_winner text := null;
begin
  if v_side not in ('a', 'b') then
    raise exception 'Invalid side';
  end if;

  if v_winner in ('a', 'b') then
    return p_state;
  end if;

  v_other := case when v_side = 'a' then 'b' else 'a' end;

  if v_is_tiebreak then
    if v_side = 'a' then
      v_tb_a := v_tb_a + 1;
      if v_tb_a >= 7 and v_tb_a - v_tb_b >= 2 then
        v_games_a := v_games_a + 1;
        v_set_winner := 'a';
      end if;
    else
      v_tb_b := v_tb_b + 1;
      if v_tb_b >= 7 and v_tb_b - v_tb_a >= 2 then
        v_games_b := v_games_b + 1;
        v_set_winner := 'b';
      end if;
    end if;
  else
    if v_side = 'a' then
      v_points_a := v_points_a + 1;
    else
      v_points_b := v_points_b + 1;
    end if;

    v_side_points := case when v_side = 'a' then v_points_a else v_points_b end;
    v_other_points := case when v_other = 'a' then v_points_a else v_points_b end;

    if v_side_points >= 4 and v_side_points - v_other_points >= 2 then
      if v_side = 'a' then
        v_games_a := v_games_a + 1;
      else
        v_games_b := v_games_b + 1;
      end if;
      v_points_a := 0;
      v_points_b := 0;

      if v_games_a = 6 and v_games_b = 6 then
        v_is_tiebreak := true;
      elsif (v_games_a >= 6 or v_games_b >= 6) and abs(v_games_a - v_games_b) >= 2 then
        v_set_winner := case when v_games_a > v_games_b then 'a' else 'b' end;
      end if;
    end if;
  end if;

  if v_set_winner in ('a', 'b') then
    v_sets := v_sets || jsonb_build_array(jsonb_build_object(
      'set_index', v_current_set,
      'side_a_games', v_games_a,
      'side_b_games', v_games_b
    ));

    if v_set_winner = 'a' then
      v_sets_a := v_sets_a + 1;
      if v_sets_a >= v_required_sets then
        v_winner := 'a';
      end if;
    else
      v_sets_b := v_sets_b + 1;
      if v_sets_b >= v_required_sets then
        v_winner := 'b';
      end if;
    end if;

    v_points_a := 0;
    v_points_b := 0;
    v_tb_a := 0;
    v_tb_b := 0;
    v_is_tiebreak := false;

    if v_winner is null then
      v_current_set := v_current_set + 1;
      v_games_a := 0;
      v_games_b := 0;
    end if;
  end if;

  return jsonb_build_object(
    'points', jsonb_build_object('a', v_points_a, 'b', v_points_b),
    'games', jsonb_build_object('a', v_games_a, 'b', v_games_b),
    'setsWon', jsonb_build_object('a', v_sets_a, 'b', v_sets_b),
    'sets', v_sets,
    'currentSet', v_current_set,
    'isTiebreak', v_is_tiebreak,
    'tiebreakPoints', jsonb_build_object('a', v_tb_a, 'b', v_tb_b),
    'requiredSets', v_required_sets,
    'winner', v_winner
  );
end;
$$;

drop function if exists start_live_match(uuid);
drop function if exists record_point(uuid, text);
drop function if exists record_point(uuid, text, integer);
drop function if exists stop_live_match(uuid);

create or replace function start_live_match(p_match_id uuid)
returns live_scores
language plpgsql
security definer
set search_path = public
as $$
declare
  v_match matches%rowtype;
  v_set_format set_format;
  v_tournament_status tournament_status;
  v_required_sets integer;
  v_live live_scores%rowtype;
begin
  select *
    into v_match
  from matches
  where id = p_match_id;

  if v_match.id is null then
    raise exception 'Match not found';
  end if;

  select t.set_format, t.status
    into v_set_format, v_tournament_status
  from tournaments t
  where t.id = v_match.tournament_id;

  if not can_live_score(v_match.tournament_id) then
    raise exception 'Not allowed';
  end if;

  if v_tournament_status <> 'in_progress'::tournament_status then
    raise exception 'Live scoring can start only after the tournament starts';
  end if;

  if v_match.side_a_entry_id is null or v_match.side_b_entry_id is null then
    raise exception 'Both sides must be assigned before scoring';
  end if;

  if v_match.status = 'finished'::match_status then
    raise exception 'Match already finished';
  end if;

  v_required_sets := case when v_set_format = 'best_of_5' then 3 else 2 end;

  select * into v_live
  from live_scores
  where match_id = p_match_id;

  if v_live.id is null then
    insert into live_scores (match_id, tournament_id, counter_user_id, status, state)
    values (p_match_id, v_match.tournament_id, auth.uid(), 'active', live_score_initial_state(v_required_sets))
    returning * into v_live;
  elsif v_live.status <> 'finished' then
    update live_scores
    set status = 'active',
        counter_user_id = coalesce(counter_user_id, auth.uid())
    where id = v_live.id
    returning * into v_live;
  end if;

  return v_live;
end;
$$;

create or replace function record_point(
  p_match_id uuid,
  p_side text,
  p_expected_revision integer default null
)
returns live_scores
language plpgsql
security definer
set search_path = public
as $$
declare
  v_live live_scores%rowtype;
  v_match matches%rowtype;
  v_tournament_status tournament_status;
  v_history_len integer;
  v_new_state jsonb;
  v_new_history jsonb;
  v_winner_side text;
  v_winner_id uuid;
  v_previous_winner uuid;
  v_set jsonb;
begin
  select *
    into v_match
  from matches
  where id = p_match_id;

  if v_match.id is null then
    raise exception 'Match not found';
  end if;

  select t.status
    into v_tournament_status
  from tournaments t
  where t.id = v_match.tournament_id;

  if not can_live_score(v_match.tournament_id) then
    raise exception 'Not allowed';
  end if;

  if v_tournament_status <> 'in_progress'::tournament_status then
    raise exception 'Live scoring is available only while the tournament is in progress';
  end if;

  select * into v_live
  from live_scores
  where match_id = p_match_id
  for update;

  if v_live.id is null then
    v_live := start_live_match(p_match_id);
    select * into v_live
    from live_scores
    where match_id = p_match_id
    for update;
  end if;

  if p_expected_revision is not null and v_live.revision <> p_expected_revision then
    raise exception 'Live score changed. Refresh and try again.';
  end if;

  if lower(trim(p_side)) = 'undo' then
    if v_live.status = 'finished' then
      raise exception 'Cannot undo a finished live match';
    end if;

    v_history_len := jsonb_array_length(v_live.history);
    if v_history_len = 0 then
      raise exception 'Nothing to undo';
    end if;

    update live_scores
    set state = v_live.history -> (v_history_len - 1),
        history = v_live.history - (v_history_len - 1),
        status = 'active',
        revision = revision + 1
    where id = v_live.id
    returning * into v_live;

    return v_live;
  end if;

  if v_live.status = 'finished' then
    raise exception 'Match already finished';
  end if;

  v_new_history := v_live.history || jsonb_build_array(v_live.state);
  v_new_state := tennis_apply_point(v_live.state, p_side);
  v_winner_side := v_new_state->>'winner';

  update live_scores
  set state = v_new_state,
      history = v_new_history,
      status = case when v_winner_side in ('a', 'b') then 'finished' else 'active' end,
      revision = revision + 1
  where id = v_live.id
  returning * into v_live;

  if v_winner_side in ('a', 'b') then
    v_previous_winner := v_match.winner_entry_id;
    v_winner_id := case
      when v_winner_side = 'a' then v_match.side_a_entry_id
      else v_match.side_b_entry_id
    end;

    delete from match_sets where match_id = p_match_id;

    for v_set in
      select value
      from jsonb_array_elements(v_new_state->'sets')
    loop
      insert into match_sets (match_id, set_index, side_a_games, side_b_games)
      values (
        p_match_id,
        (v_set->>'set_index')::integer,
        (v_set->>'side_a_games')::integer,
        (v_set->>'side_b_games')::integer
      );
    end loop;

    update matches
    set winner_entry_id = v_winner_id,
        status = 'finished'::match_status
    where id = p_match_id;

    if v_previous_winner is not null and v_previous_winner is distinct from v_winner_id then
      perform clear_downstream(p_match_id, v_previous_winner);
    end if;

    perform propagate_winner(p_match_id, v_winner_id);
  end if;

  return v_live;
end;
$$;

create or replace function stop_live_match(p_match_id uuid)
returns live_scores
language plpgsql
security definer
set search_path = public
as $$
declare
  v_live live_scores%rowtype;
  v_tournament_id uuid;
begin
  select m.tournament_id into v_tournament_id
  from matches m
  where m.id = p_match_id;

  if v_tournament_id is null then
    raise exception 'Match not found';
  end if;

  if not can_live_score(v_tournament_id) then
    raise exception 'Not allowed';
  end if;

  select * into v_live
  from live_scores
  where match_id = p_match_id;

  if v_live.id is null then
    raise exception 'Live match not found';
  end if;

  if v_live.status <> 'finished' then
    update live_scores
    set status = 'stopped',
        revision = revision + 1
    where id = v_live.id
    returning * into v_live;
  end if;

  return v_live;
end;
$$;

alter table live_scores enable row level security;

drop policy if exists live_scores_public_or_scorer_select on live_scores;
create policy live_scores_public_or_scorer_select on live_scores
for select
using (
  exists (
    select 1
    from tournaments t
    where t.id = live_scores.tournament_id
      and (t.is_public = true or can_live_score(t.id))
  )
);

drop policy if exists tournaments_public_or_admin_select on tournaments;
create policy tournaments_public_or_admin_select on tournaments
for select
using (
  is_public = true or is_tournament_admin(id) or can_live_score(id)
);

drop policy if exists entries_public_or_admin_select on entries;
create policy entries_public_or_admin_select on entries
for select
using (
  exists (
    select 1
    from tournaments t
    where t.id = entries.tournament_id
      and (t.is_public = true or is_tournament_admin(t.id) or can_live_score(t.id))
  )
);

drop policy if exists entry_members_public_or_admin_select on entry_members;
create policy entry_members_public_or_admin_select on entry_members
for select
using (
  exists (
    select 1
    from entries e
    join tournaments t on t.id = e.tournament_id
    where e.id = entry_members.entry_id
      and (t.is_public = true or is_tournament_admin(t.id) or can_live_score(t.id))
  )
);

drop policy if exists matches_public_or_admin_select on matches;
create policy matches_public_or_admin_select on matches
for select
using (
  exists (
    select 1
    from tournaments t
    where t.id = matches.tournament_id
      and (t.is_public = true or is_tournament_admin(t.id) or can_live_score(t.id))
  )
);

drop policy if exists match_sets_public_or_admin_select on match_sets;
create policy match_sets_public_or_admin_select on match_sets
for select
using (
  exists (
    select 1
    from matches m
    join tournaments t on t.id = m.tournament_id
    where m.id = match_sets.match_id
      and (t.is_public = true or is_tournament_admin(t.id) or can_live_score(t.id))
  )
);

grant select on live_scores to anon, authenticated;
grant execute on function can_live_score(uuid) to authenticated;
grant execute on function get_my_tournament_role(uuid) to authenticated;
grant execute on function start_live_match(uuid) to authenticated;
grant execute on function record_point(uuid, text, integer) to authenticated;
grant execute on function stop_live_match(uuid) to authenticated;

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'live_scores'
  ) then
    alter publication supabase_realtime add table live_scores;
  end if;
end $$;

-- =============================================
-- COUNTER TOURNAMENT LIST ACCESS
-- =============================================

drop policy if exists tournament_admins_select_admin on tournament_admins;
create policy tournament_admins_select_admin on tournament_admins
for select
to authenticated
using (
  user_id = auth.uid()
  or is_tournament_admin(tournament_id)
);

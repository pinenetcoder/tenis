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
  created_at timestamptz not null default now(),
  unique (entry_id, member_order)
);

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

create or replace function create_tournament(
  p_name text,
  p_slug text,
  p_description text default null,
  p_category tournament_category default 'singles',
  p_set_format set_format default 'best_of_3',
  p_is_public boolean default true,
  p_doubles_pairing_mode doubles_pairing_mode default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'Authentication required';
  end if;

  insert into tournaments (name, slug, description, category, set_format, status, is_public, doubles_pairing_mode, created_by)
  values (p_name, p_slug, p_description, p_category, p_set_format, 'registration_open', p_is_public,
          case when p_category = 'doubles' then coalesce(p_doubles_pairing_mode, 'pre_agreed') else null end,
          v_uid)
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
         t.set_format
    into v_tournament_id,
         v_side_a_id,
         v_side_b_id,
         v_previous_winner,
         v_set_format
  from matches m
  join tournaments t on t.id = m.tournament_id
  where m.id = p_match_id;

  if v_tournament_id is null then
    raise exception 'Match not found';
  end if;

  if not is_tournament_admin(v_tournament_id) then
    raise exception 'Not allowed';
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

grant execute on function create_tournament(text, text, text, tournament_category, set_format, boolean, doubles_pairing_mode) to authenticated;
grant execute on function register_entry(text, tournament_category, text, text, text, text) to anon, authenticated;
grant execute on function generate_bracket(uuid, draw_mode, uuid[]) to authenticated;
grant execute on function rebuild_bracket(uuid, draw_mode, uuid[]) to authenticated;
grant execute on function update_match_sets(uuid, jsonb) to authenticated;
grant execute on function swap_bracket_slots(uuid, uuid, text, uuid, text) to authenticated;
grant execute on function form_random_pairs(uuid) to authenticated;
grant execute on function form_manual_pairs(uuid, jsonb) to authenticated;
grant execute on function split_pairs(uuid) to authenticated;
grant execute on function apply_bracket_layout(uuid, jsonb) to authenticated;

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

-- =====================================================================
-- Pin It — Supabase schema
-- Paste this whole file into Supabase → SQL Editor → New query → Run.
-- =====================================================================

create extension if not exists pgcrypto;

-- ---------- Tables ----------------------------------------------------

-- One row of game settings
create table public.settings (
  id          int primary key default 1 check (id = 1),
  title       text not null default 'Pin It',
  rounds      int  not null default 5   check (rounds between 1 and 20),
  strict      text not null default 'normal' check (strict in ('easy','normal','hard')),
  timer       int  not null default 30  check (timer between 0 and 600),
  flash_ms    int  not null default 750 check (flash_ms between 100 and 950),
  scale_width double precision not null default 0,
  scale_unit  text not null default '',
  map_path    text,
  map_w       int,
  map_h       int
);
insert into public.settings (id) values (1);

-- Who can manage the game
create table public.admins (
  user_id uuid primary key references auth.users(id) on delete cascade
);

-- Screenshots and their correct spot (x, y are 0–1 across the map)
create table public.locations (
  id         uuid primary key default gen_random_uuid(),
  shot_path  text not null,
  x          double precision not null check (x between 0 and 1),
  y          double precision not null check (y between 0 and 1),
  created_at timestamptz not null default now()
);

-- Leaderboard: one row per player
create table public.players (
  id           uuid primary key references auth.users(id) on delete cascade,
  name         text not null check (char_length(name) between 1 and 24),
  best         int  not null default 0,
  last         int  not null default 0,
  games_played int  not null default 0,
  updated_at   timestamptz not null default now()
);

-- Games in progress / finished (never readable by players directly)
create table public.games (
  id               uuid primary key default gen_random_uuid(),
  player_id        uuid not null references auth.users(id) on delete cascade,
  location_ids     uuid[] not null,
  round            int  not null default 0,
  round_started_at timestamptz,
  total            int  not null default 0,
  finished         boolean not null default false,
  created_at       timestamptz not null default now()
);

create table public.guesses (
  game_id     uuid references public.games(id) on delete cascade,
  round       int,
  location_id uuid references public.locations(id) on delete set null,
  x           double precision,
  y           double precision,
  points      int not null,
  created_at  timestamptz not null default now(),
  primary key (game_id, round)
);

create index on public.players (best desc);
create index on public.games (player_id, created_at);

-- ---------- Security --------------------------------------------------

create or replace function public.is_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from admins where user_id = auth.uid());
$$;

alter table public.settings  enable row level security;
alter table public.admins    enable row level security;
alter table public.locations enable row level security;
alter table public.players   enable row level security;
alter table public.games     enable row level security;
alter table public.guesses   enable row level security;

create policy "settings are public"  on public.settings  for select using (true);
create policy "admins edit settings" on public.settings  for update using (public.is_admin()) with check (public.is_admin());
create policy "admins see self"      on public.admins    for select using (user_id = auth.uid());
create policy "admins manage locations" on public.locations for all using (public.is_admin()) with check (public.is_admin());
create policy "leaderboard is public" on public.players  for select using (true);
-- games / guesses: no policies on purpose → only the functions below touch them.
-- players: no insert/update policy → scores can only be written by submit_guess.

-- ---------- Game functions (run on the server) ------------------------

create or replace function public.location_count() returns int
language sql stable security definer set search_path = public as $$
  select count(*)::int from locations;
$$;

create or replace function public.set_player_name(p_name text) returns void
language plpgsql security definer set search_path = public as $$
declare n text := btrim(p_name);
begin
  if auth.uid() is null then raise exception 'Not signed in'; end if;
  if n is null or char_length(n) < 1 or char_length(n) > 24 then
    raise exception 'Name must be 1 to 24 characters';
  end if;
  insert into players (id, name) values (auth.uid(), n)
  on conflict (id) do update set name = excluded.name, updated_at = now();
end $$;

create or replace function public.start_game() returns json
language plpgsql security definer set search_path = public as $$
declare s settings; ids uuid[]; gid uuid;
begin
  if auth.uid() is null then raise exception 'Not signed in'; end if;
  if not exists (select 1 from players where id = auth.uid()) then
    raise exception 'Enter a name first';
  end if;
  if (select count(*) from games
      where player_id = auth.uid() and created_at > now() - interval '1 hour') >= 40 then
    raise exception 'Too many games this hour. Try again later.';
  end if;
  select * into s from settings where id = 1;
  if s.map_path is null then raise exception 'The game isn''t ready yet'; end if;
  select array_agg(id) into ids
    from (select id from locations order by random() limit s.rounds) t;
  if ids is null then raise exception 'The game isn''t ready yet'; end if;
  insert into games (player_id, location_ids) values (auth.uid(), ids) returning id into gid;
  return json_build_object('game_id', gid, 'total_rounds', array_length(ids, 1));
end $$;

-- Returns only the current round's screenshot, never the answer.
create or replace function public.begin_round(p_game uuid) returns json
language plpgsql security definer set search_path = public as $$
declare g games; loc locations;
begin
  select * into g from games where id = p_game and player_id = auth.uid() for update;
  if not found then raise exception 'Game not found'; end if;
  if g.finished then raise exception 'This game is over'; end if;
  select * into loc from locations where id = g.location_ids[g.round + 1];
  if not found then raise exception 'This location was removed. Start a new game.'; end if;
  -- coalesce: calling again can't restart the clock
  update games set round_started_at = coalesce(round_started_at, now()) where id = g.id;
  return json_build_object('round', g.round + 1, 'shot_path', loc.shot_path);
end $$;

-- Scores the guess on the server, enforces the timer, updates the leaderboard.
create or replace function public.submit_guess(p_game uuid, p_x double precision, p_y double precision)
returns json
language plpgsql security definer set search_path = public as $$
declare
  g games; s settings; loc locations;
  d double precision := null; pts int := 0; late boolean := false; done boolean; new_total int;
begin
  select * into g from games where id = p_game and player_id = auth.uid() for update;
  if not found then raise exception 'Game not found'; end if;
  if g.finished then raise exception 'This game is over'; end if;
  if g.round_started_at is null then raise exception 'Round not started'; end if;

  select * into s from settings where id = 1;
  select * into loc from locations where id = g.location_ids[g.round + 1];

  -- timer + countdown + flash + grace for slow connections
  if s.timer > 0 then
    late := extract(epoch from now() - g.round_started_at) > s.timer + 2 + s.flash_ms / 1000.0 + 8;
  end if;

  if loc.id is not null and not late and p_x between 0 and 1 and p_y between 0 and 1 then
    d := sqrt(power((p_x - loc.x) * s.map_w, 2) + power((p_y - loc.y) * s.map_h, 2))
         / sqrt(power(s.map_w, 2) + power(s.map_h, 2));
    pts := case when d < 0.003 then 5000
                else round(5000 * exp(-d / case s.strict when 'easy' then 0.16
                                                         when 'hard' then 0.045
                                                         else 0.09 end))::int end;
  end if;

  insert into guesses (game_id, round, location_id, x, y, points)
  values (g.id, g.round + 1, loc.id, p_x, p_y, pts);

  done := g.round + 1 >= array_length(g.location_ids, 1);
  new_total := g.total + pts;
  update games set round = round + 1, total = new_total, round_started_at = null, finished = done
  where id = g.id;

  if done then
    update players set best = greatest(best, new_total), last = new_total,
           games_played = games_played + 1, updated_at = now()
    where id = auth.uid();
  end if;

  return json_build_object('points', pts, 'd', d, 'late', late,
    'actual_x', loc.x, 'actual_y', loc.y, 'total', new_total, 'finished', done);
end $$;

create or replace function public.admin_remove_player(p_id uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'Admins only'; end if;
  delete from players where id = p_id;
end $$;

revoke all on function public.admin_remove_player(uuid) from public, anon;
revoke all on function public.location_count()  from public, anon;
revoke all on function public.set_player_name(text) from public, anon;
revoke all on function public.start_game()       from public, anon;
revoke all on function public.begin_round(uuid)  from public, anon;
revoke all on function public.submit_guess(uuid, double precision, double precision) from public, anon;
grant execute on function public.is_admin(), public.admin_remove_player(uuid), public.location_count(), public.set_player_name(text),
  public.start_game(), public.begin_round(uuid),
  public.submit_guess(uuid, double precision, double precision) to authenticated;

-- ---------- Live leaderboard -----------------------------------------
alter publication supabase_realtime add table public.players;

-- ---------- Image storage --------------------------------------------
insert into storage.buckets (id, name, public) values ('pinit', 'pinit', true);

create policy "admins upload images" on storage.objects for insert to authenticated
  with check (bucket_id = 'pinit' and public.is_admin());
create policy "admins update images" on storage.objects for update to authenticated
  using (bucket_id = 'pinit' and public.is_admin());
create policy "admins delete images" on storage.objects for delete to authenticated
  using (bucket_id = 'pinit' and public.is_admin());
create policy "admins list images" on storage.objects for select to authenticated
  using (bucket_id = 'pinit' and public.is_admin());
-- Players get no select policy: images load by their (random) public URL, but players can't list the bucket.

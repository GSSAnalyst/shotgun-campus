-- Shotgun: campus ride board
-- Run this whole file once in Supabase: Dashboard > SQL Editor > New query > paste > Run.
-- Before running, change ucsc.edu below if your campus uses a different email domain.

create extension if not exists pgcrypto;

-- Only people signed in with a campus email pass this check.
create or replace function public.is_campus()
returns boolean
language sql stable
as $$
  select coalesce(lower(auth.jwt() ->> 'email') like '%@ucsc.edu', false)
$$;

-- Profiles ------------------------------------------------------------
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null check (char_length(display_name) between 1 and 40),
  college text check (college is null or char_length(college) <= 60),
  created_at timestamptz not null default now()
);

-- Rides ---------------------------------------------------------------
create table if not exists public.rides (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null default auth.uid() references public.profiles(id) on delete cascade,
  kind text not null check (kind in ('offer','want')),
  category text not null default 'trip' check (category in ('trip','airport','home','errand','event')),
  origin text not null check (char_length(origin) between 1 and 60),
  destination text not null check (char_length(destination) between 1 and 60),
  depart_at timestamptz not null,
  seats int not null default 1 check (seats between 1 and 7),
  miles numeric check (miles is null or (miles > 0 and miles < 5000)),
  mpg numeric check (mpg is null or (mpg > 0 and mpg < 200)),
  gas_price numeric check (gas_price is null or (gas_price >= 0 and gas_price < 30)),
  note text check (note is null or char_length(note) <= 280),
  created_at timestamptz not null default now()
);
create index if not exists rides_depart_idx on public.rides (depart_at);

-- Contact details live in their own table so they can be locked down
-- separately: only the ride's owner and riders they approved can read them.
create table if not exists public.ride_contacts (
  ride_id uuid primary key references public.rides(id) on delete cascade,
  contact text not null check (char_length(contact) between 1 and 80)
);

-- Seat requests -------------------------------------------------------
create table if not exists public.seat_requests (
  id uuid primary key default gen_random_uuid(),
  ride_id uuid not null references public.rides(id) on delete cascade,
  rider_id uuid not null default auth.uid() references public.profiles(id) on delete cascade,
  status text not null default 'pending' check (status in ('pending','approved','declined')),
  message text check (message is null or char_length(message) <= 200),
  created_at timestamptz not null default now(),
  unique (ride_id, rider_id)
);

-- Helpers -------------------------------------------------------------
create or replace function public.owns_ride(r uuid)
returns boolean language sql stable security definer set search_path = public
as $$ select exists (select 1 from rides where id = r and owner_id = auth.uid()) $$;

create or replace function public.approved_on(r uuid)
returns boolean language sql stable security definer set search_path = public
as $$ select exists (select 1 from seat_requests where ride_id = r and rider_id = auth.uid() and status = 'approved') $$;

-- Everyone on campus can see how many seats are taken, without seeing who took them.
create or replace function public.seat_counts()
returns table (ride_id uuid, taken bigint)
language sql stable security definer set search_path = public
as $$
  select ride_id, count(*) from seat_requests
  where status = 'approved' and public.is_campus()
  group by ride_id
$$;

-- Row level security --------------------------------------------------
alter table public.profiles      enable row level security;
alter table public.rides         enable row level security;
alter table public.ride_contacts enable row level security;
alter table public.seat_requests enable row level security;

drop policy if exists "campus reads profiles" on public.profiles;
create policy "campus reads profiles" on public.profiles for select using (public.is_campus());
drop policy if exists "own profile insert" on public.profiles;
create policy "own profile insert" on public.profiles for insert with check (id = auth.uid() and public.is_campus());
drop policy if exists "own profile update" on public.profiles;
create policy "own profile update" on public.profiles for update using (id = auth.uid()) with check (id = auth.uid());

drop policy if exists "campus reads rides" on public.rides;
create policy "campus reads rides" on public.rides for select using (public.is_campus());
drop policy if exists "post own rides" on public.rides;
create policy "post own rides" on public.rides for insert with check (owner_id = auth.uid() and public.is_campus());
drop policy if exists "edit own rides" on public.rides;
create policy "edit own rides" on public.rides for update using (owner_id = auth.uid()) with check (owner_id = auth.uid());
drop policy if exists "delete own rides" on public.rides;
create policy "delete own rides" on public.rides for delete using (owner_id = auth.uid());

drop policy if exists "owner or approved reads contact" on public.ride_contacts;
create policy "owner or approved reads contact" on public.ride_contacts for select
  using (public.owns_ride(ride_id) or public.approved_on(ride_id));
drop policy if exists "owner writes contact" on public.ride_contacts;
create policy "owner writes contact" on public.ride_contacts for all
  using (public.owns_ride(ride_id)) with check (public.owns_ride(ride_id));

drop policy if exists "rider or owner reads requests" on public.seat_requests;
create policy "rider or owner reads requests" on public.seat_requests for select
  using (rider_id = auth.uid() or public.owns_ride(ride_id));
drop policy if exists "rider requests seat" on public.seat_requests;
create policy "rider requests seat" on public.seat_requests for insert
  with check (rider_id = auth.uid() and status = 'pending' and public.is_campus() and not public.owns_ride(ride_id));
drop policy if exists "owner decides" on public.seat_requests;
create policy "owner decides" on public.seat_requests for update
  using (public.owns_ride(ride_id)) with check (public.owns_ride(ride_id));
drop policy if exists "rider cancels" on public.seat_requests;
create policy "rider cancels" on public.seat_requests for delete using (rider_id = auth.uid());

-- Live updates --------------------------------------------------------
do $$ begin
  alter publication supabase_realtime add table public.rides, public.seat_requests;
exception when duplicate_object then null; end $$;

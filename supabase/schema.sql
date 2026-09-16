create extension if not exists pgcrypto;
create schema if not exists private;
revoke all on schema private from public, anon;
grant usage on schema private to authenticated;

create table if not exists public.events (
  id text primary key,
  slug text unique not null,
  title text not null,
  description text not null default '',
  status text not null default 'open' check (status in ('open','closed')),
  leaderboard_visible boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists public.questions (
  id uuid primary key default gen_random_uuid(),
  event_id text not null references public.events(id) on delete cascade,
  position integer not null,
  type text not null check (type in ('multiple_choice','fill_blank')),
  prompt text not null,
  choices text[] not null default '{}',
  answers text[] not null default '{}',
  points integer not null default 10 check (points between 0 and 100),
  unique(event_id, position)
);

create table if not exists public.teams (
  id uuid primary key default gen_random_uuid(),
  event_id text not null references public.events(id) on delete cascade,
  name text not null check (char_length(name) between 1 and 60),
  token_hash bytea not null,
  photo_path text,
  completed_at timestamptz,
  score integer not null default 0,
  created_at timestamptz not null default now()
);

create table if not exists public.responses (
  id uuid primary key default gen_random_uuid(),
  team_id uuid not null references public.teams(id) on delete cascade,
  question_id uuid not null references public.questions(id) on delete cascade,
  answer text not null,
  correct boolean not null,
  points_awarded integer not null default 0,
  submitted_at timestamptz not null default now(),
  unique(team_id, question_id)
);

create table if not exists public.photos (
  id uuid primary key default gen_random_uuid(),
  event_id text not null references public.events(id) on delete cascade,
  team_id uuid references public.teams(id) on delete set null,
  kind text not null default 'bonus',
  object_path text not null,
  caption text not null default '',
  created_at timestamptz not null default now()
);

create table if not exists public.admins (
  user_id uuid primary key references auth.users(id) on delete cascade,
  email text not null,
  created_at timestamptz not null default now()
);

create index if not exists idx_teams_event_completed_score on public.teams(event_id, completed_at, score desc);
create index if not exists idx_photos_event_created on public.photos(event_id, created_at desc);
create index if not exists idx_photos_team_created on public.photos(team_id, created_at desc);
create index if not exists idx_responses_question on public.responses(question_id);

create or replace function public.normalize_answer(value text) returns text
language sql immutable parallel safe set search_path = pg_catalog as $$
  select regexp_replace(regexp_replace(lower(trim(coalesce(value,''))), '[^a-z0-9[:space:]]', '', 'g'), '[[:space:]]+', ' ', 'g')
$$;

create or replace function private.is_admin() returns boolean
language sql stable security definer set search_path = pg_catalog, public as $$
  select exists(select 1 from public.admins where user_id = auth.uid())
$$;

create or replace function public.admin_status() returns table(admin boolean, can_claim boolean)
language sql stable security definer set search_path = pg_catalog, public, private as $$
  select private.is_admin(), not exists(select 1 from public.admins)
$$;

create or replace function public.claim_admin() returns boolean
language plpgsql security definer set search_path = pg_catalog, public, private as $$
begin
  if auth.uid() is null then raise exception 'Sign in first'; end if;
  if exists(select 1 from public.admins) and not private.is_admin() then raise exception 'Administrator already claimed'; end if;
  insert into public.admins(user_id, email) values (auth.uid(), coalesce(auth.jwt()->>'email','')) on conflict do nothing;
  return true;
end;
$$;

create or replace function public.join_team(p_event_id text, p_name text)
returns table(team_id uuid, team_token text, team_name text)
language plpgsql security definer set search_path = pg_catalog, public, extensions as $$
declare new_id uuid := gen_random_uuid(); new_token text := encode(gen_random_bytes(32), 'hex'); clean_name text := left(trim(p_name), 60);
begin
  if clean_name = '' then raise exception 'Enter a team name'; end if;
  if not exists(select 1 from public.events where id = p_event_id and status = 'open') then raise exception 'Registration is closed'; end if;
  insert into public.teams(id,event_id,name,token_hash) values(new_id,p_event_id,clean_name,digest(new_token,'sha256'));
  return query select new_id,new_token,clean_name;
end;
$$;

create or replace function public.set_team_photo(p_team_id uuid, p_token text, p_photo_path text) returns boolean
language plpgsql security definer set search_path = pg_catalog, public, extensions as $$
declare team_event text;
begin
  select event_id into team_event from public.teams where id = p_team_id and token_hash = digest(p_token,'sha256');
  if team_event is null then raise exception 'Invalid team session'; end if;
  if p_photo_path not like 'events/' || team_event || '/teams/' || p_team_id::text || '/%' then raise exception 'Invalid photo path'; end if;
  update public.teams set photo_path = left(p_photo_path,500) where id = p_team_id;
  if not found then raise exception 'Invalid team session'; end if;
  return true;
end;
$$;

create or replace function public.submit_quiz(p_team_id uuid, p_token text, p_answers jsonb)
returns table(score integer, possible integer, rank bigint)
language plpgsql security definer set search_path = pg_catalog, public, extensions as $$
declare q record; supplied text; awarded integer; total integer := 0; maximum integer := 0; team_event text; team_completed_at timestamptz; saved_score integer;
begin
  select event_id, completed_at, score into team_event, team_completed_at, saved_score
  from public.teams
  where id = p_team_id and token_hash = digest(p_token,'sha256')
  for update;
  if team_event is null then raise exception 'Invalid team session'; end if;
  select coalesce(sum(points),0)::integer into maximum from public.questions where event_id = team_event;
  if team_completed_at is not null then
    return query select saved_score, maximum, (select count(*)+1 from public.teams where event_id=team_event and completed_at is not null and teams.score>saved_score);
    return;
  end if;
  for q in select * from public.questions where event_id = team_event order by position loop
    supplied := coalesce(p_answers->>q.id::text,'');
    awarded := case when exists(select 1 from unnest(q.answers) accepted where public.normalize_answer(accepted)=public.normalize_answer(supplied)) then q.points else 0 end;
    total := total + awarded;
    insert into public.responses(team_id,question_id,answer,correct,points_awarded) values(p_team_id,q.id,supplied,awarded>0,awarded)
      on conflict(team_id,question_id) do update set answer=excluded.answer, correct=excluded.correct, points_awarded=excluded.points_awarded, submitted_at=now();
  end loop;
  update public.teams set score=total,completed_at=now() where id=p_team_id;
  return query select total,maximum,(select count(*)+1 from public.teams where event_id=team_event and completed_at is not null and teams.score>total);
end;
$$;

create or replace function public.get_team_state(p_team_id uuid, p_token text)
returns table(completed boolean, score integer, possible integer, rank bigint)
language plpgsql stable security definer set search_path = pg_catalog, public, extensions as $$
declare team_event text; team_completed_at timestamptz; team_score integer; maximum integer;
begin
  select event_id, completed_at, teams.score into team_event, team_completed_at, team_score
  from public.teams
  where id = p_team_id and token_hash = digest(p_token,'sha256');
  if team_event is null then raise exception 'Invalid team session'; end if;
  select coalesce(sum(points),0)::integer into maximum from public.questions where event_id = team_event;
  return query select
    team_completed_at is not null,
    team_score,
    maximum,
    case when team_completed_at is null then null::bigint else (select count(*)+1 from public.teams where event_id=team_event and completed_at is not null and teams.score>team_score) end;
end;
$$;

create or replace function public.add_bonus_photo(p_team_id uuid, p_token text, p_object_path text, p_caption text) returns uuid
language plpgsql security definer set search_path = pg_catalog, public, extensions as $$
declare event_value text; photo_id uuid := gen_random_uuid();
begin
  select event_id into event_value from public.teams where id=p_team_id and token_hash=digest(p_token,'sha256');
  if event_value is null then raise exception 'Invalid team session'; end if;
  if p_object_path not like 'events/' || event_value || '/bonus/' || p_team_id::text || '/%' then raise exception 'Invalid photo path'; end if;
  insert into public.photos(id,event_id,team_id,object_path,caption) values(photo_id,event_value,p_team_id,left(p_object_path,500),left(trim(coalesce(p_caption,'')),140));
  return photo_id;
end;
$$;

create or replace function public.get_my_photos(p_team_id uuid, p_token text)
returns table(id uuid, object_path text, caption text, created_at timestamptz)
language plpgsql stable security definer set search_path = pg_catalog, public, extensions as $$
begin
  if not exists(select 1 from public.teams where teams.id=p_team_id and token_hash=digest(p_token,'sha256')) then raise exception 'Invalid team session'; end if;
  return query select photos.id,photos.object_path,photos.caption,photos.created_at from public.photos where team_id=p_team_id order by photos.created_at desc limit 20;
end;
$$;

create or replace function public.get_leaderboard(p_event_id text)
returns table(id uuid, name text, score integer, rank bigint, photo_path text)
language sql stable security definer set search_path = pg_catalog, public as $$
  select t.id, t.name, t.score,
    row_number() over(order by t.score desc,t.completed_at asc) as rank,
    t.photo_path
  from public.teams t
  join public.events e on e.id=t.event_id
  where t.event_id=p_event_id and t.completed_at is not null and e.leaderboard_visible
  order by rank
$$;

alter table public.events enable row level security;
alter table public.questions enable row level security;
alter table public.teams enable row level security;
alter table public.responses enable row level security;
alter table public.photos enable row level security;
alter table public.admins enable row level security;

create policy "public reads events" on public.events for select to anon,authenticated using (true);
create policy "public reads questions" on public.questions for select to anon,authenticated using (true);
create policy "admins manage events" on public.events for all to authenticated using (private.is_admin()) with check (private.is_admin());
create policy "admins manage questions" on public.questions for all to authenticated using (private.is_admin()) with check (private.is_admin());
create policy "admins manage teams" on public.teams for all to authenticated using (private.is_admin()) with check (private.is_admin());
create policy "admins manage responses" on public.responses for all to authenticated using (private.is_admin()) with check (private.is_admin());
create policy "admins manage photos" on public.photos for all to authenticated using (private.is_admin()) with check (private.is_admin());
create policy "admins read own admin row" on public.admins for select to authenticated using (user_id=(select auth.uid()));

grant select on public.events,public.questions to anon,authenticated;
grant select,insert,update,delete on public.events,public.questions,public.teams,public.responses,public.photos to authenticated;
revoke all on function private.is_admin() from public;
revoke all on function public.admin_status(),public.claim_admin(),public.join_team(text,text),public.set_team_photo(uuid,text,text),public.submit_quiz(uuid,text,jsonb),public.get_team_state(uuid,text),public.add_bonus_photo(uuid,text,text,text),public.get_my_photos(uuid,text),public.get_leaderboard(text) from public;
revoke all on function public.admin_status(),public.claim_admin() from anon;
grant execute on function private.is_admin() to authenticated;
grant execute on function public.join_team(text,text),public.set_team_photo(uuid,text,text),public.submit_quiz(uuid,text,jsonb),public.get_team_state(uuid,text),public.add_bonus_photo(uuid,text,text,text),public.get_my_photos(uuid,text),public.get_leaderboard(text) to anon,authenticated;
grant execute on function public.admin_status(),public.claim_admin() to authenticated;

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('party-photos','party-photos',true,12582912,array['image/jpeg','image/png','image/webp','image/heic','image/heif'])
on conflict(id) do update set public=true,file_size_limit=excluded.file_size_limit,allowed_mime_types=excluded.allowed_mime_types;
create policy "guests upload party photos" on storage.objects for insert to anon,authenticated with check(bucket_id='party-photos' and (storage.foldername(name))[1]='events');
create policy "admins manage party photos" on storage.objects for all to authenticated using(bucket_id='party-photos' and private.is_admin()) with check(bucket_id='party-photos' and private.is_admin());

insert into public.events(id,slug,title,description,status,leaderboard_visible) values
('birthday-main','claire','How Well Do You Know Claire?','A birthday quiz made by the people who know Claire best.','open',true)
on conflict(id) do nothing;
insert into public.questions(event_id,position,type,prompt,choices,answers,points) values
('birthday-main',1,'multiple_choice','Which decade did Claire graduate from high school?',array['1950s','1960s','1970s','1980s'],array['1960s'],10),
('birthday-main',2,'fill_blank','What was the name of Claire''s first pet?',array[]::text[],array['replace me'],10),
('birthday-main',3,'multiple_choice','Which treat would Claire choose first?',array['Chocolate cake','Apple pie','Ice cream','Cheesecake'],array['Chocolate cake'],10)
on conflict(event_id,position) do nothing;

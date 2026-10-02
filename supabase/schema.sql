-- Nuestro Presupuesto: shared snapshots for one household of at most two users.
-- Run once (or rerun safely) in the Supabase SQL editor as the project owner.
-- Enable Confirm Email in Auth. Only the publishable key belongs in the browser.
-- finance_private MUST NOT be added to the API's exposed schemas.
-- All changes and privilege revocations become visible together.
begin;

create schema if not exists finance_private;
revoke all on schema finance_private from public, anon, authenticated;
grant usage on schema finance_private to authenticated;

create table if not exists finance_private.households (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(name) between 1 and 100),
  state jsonb not null check (jsonb_typeof(state) = 'object'),
  revision bigint not null default 1 check (revision between 1 and 9007199254740991),
  updated_at timestamptz not null default clock_timestamp()
);
create table if not exists finance_private.members (
  user_id uuid primary key references auth.users(id) on delete cascade,
  household_id uuid not null references finance_private.households(id) on delete cascade,
  role text not null check (role in ('owner', 'member')),
  joined_at timestamptz not null default clock_timestamp()
);
create index if not exists finance_members_household on finance_private.members(household_id);
create unique index if not exists finance_one_owner on finance_private.members(household_id) where role = 'owner';
create table if not exists finance_private.invitations (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references finance_private.households(id) on delete cascade,
  email text not null,
  token_hash bytea not null unique,
  expires_at timestamptz not null,
  used_at timestamptz,
  used_by uuid references auth.users(id) on delete set null,
  revoked_at timestamptz,
  created_at timestamptz not null default clock_timestamp()
);
create index if not exists finance_invitations_household on finance_private.invitations(household_id);
alter table finance_private.invitations add column if not exists source_household_id uuid
  references finance_private.households(id) on delete restrict;
alter table finance_private.invitations add column if not exists source_revision bigint
  check (source_revision between 1 and 9007199254740991);
create table if not exists finance_private.mutations (
  household_id uuid not null references finance_private.households(id) on delete cascade,
  actor_id uuid not null references auth.users(id) on delete cascade,
  mutation_id uuid not null,
  base_revision bigint not null,
  state_hash bytea not null,
  saved_revision bigint not null,
  created_at timestamptz not null default clock_timestamp(),
  primary key (household_id, actor_id, mutation_id)
);
-- A sole owner's previous household stays private and recoverable after moving.
-- It has no active members, and its pending invitations are revoked on archive.
create table if not exists finance_private.household_archives (
  user_id uuid not null references auth.users(id) on delete cascade,
  household_id uuid not null references finance_private.households(id) on delete restrict,
  archived_at timestamptz not null default clock_timestamp(),
  primary key (user_id, household_id)
);

-- No direct client table access. RLS has no permissive policies: default deny.
alter table finance_private.households enable row level security;
alter table finance_private.members enable row level security;
alter table finance_private.invitations enable row level security;
alter table finance_private.mutations enable row level security;
alter table finance_private.household_archives enable row level security;
revoke all on all tables in schema finance_private from public, anon, authenticated;
revoke all on all sequences in schema finance_private from public, anon, authenticated;
alter default privileges in schema finance_private revoke execute on functions from public;
alter default privileges in schema finance_private revoke all on tables from public, anon, authenticated;

create or replace function finance_private.require_user()
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_uid uuid := auth.uid();
begin
  if v_uid is null or not exists (
    select 1 from auth.users u where u.id = v_uid and u.email is not null
      and u.email <> '' and u.email_confirmed_at is not null
      and coalesce(u.is_anonymous, false) = false
  ) then
    raise exception using errcode = '42501', message = 'Inicia sesión con un correo confirmado.';
  end if;
  return v_uid;
end;
$$;

create or replace function finance_private.validate_snapshot(p_state jsonb)
returns void language plpgsql security invoker set search_path = '' as $$
begin
  if p_state is null or pg_catalog.jsonb_typeof(p_state) is distinct from 'object'
    or p_state -> 'version' is distinct from '3'::jsonb
    or pg_catalog.jsonb_typeof(p_state -> 'settings') is distinct from 'object'
    or pg_catalog.jsonb_typeof(p_state -> 'months') is distinct from 'object'
    or pg_catalog.jsonb_typeof(p_state -> 'initialFunds') is distinct from 'object'
    or pg_catalog.jsonb_typeof(p_state -> 'transactions') is distinct from 'array'
    or pg_catalog.jsonb_typeof(p_state -> 'goals') is distinct from 'array'
    or pg_catalog.jsonb_typeof(p_state -> 'equipment') is distinct from 'array'
    or pg_catalog.jsonb_typeof(p_state -> 'selectedMonth') is distinct from 'string'
    or pg_catalog.jsonb_typeof(p_state -> 'cashStartMonth') is distinct from 'string'
  then
    raise exception using errcode = '22023', message = 'La copia financiera no tiene un formato compatible.';
  end if;
  if pg_catalog.octet_length(p_state::text) > 8000000
    or pg_catalog.jsonb_array_length(p_state -> 'transactions') > 50000
    or pg_catalog.jsonb_array_length(p_state -> 'goals') > 500
    or pg_catalog.jsonb_array_length(p_state -> 'equipment') > 100
    or (select pg_catalog.count(*) from pg_catalog.jsonb_object_keys(p_state -> 'months')) not between 1 and 2400
  then
    raise exception using errcode = '22023', message = 'La copia supera el tamaño admitido.';
  end if;
end;
$$;

create or replace function finance_private.household_json(p_household uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_uid uuid := finance_private.require_user(); v_result jsonb;
begin
  select pg_catalog.jsonb_build_object('id', h.id, 'name', h.name, 'state', h.state,
      'revision', h.revision, 'updated_at', h.updated_at)
    into v_result from finance_private.households h
    where h.id = p_household and exists (
      select 1 from finance_private.members m where m.household_id = h.id and m.user_id = v_uid
    );
  if v_result is null then
    raise exception using errcode = '42501', message = 'No tienes acceso a este hogar.';
  end if;
  return v_result;
end;
$$;

create or replace function finance_private.bootstrap()
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_uid uuid := finance_private.require_user(); v_id uuid; v_members jsonb;
begin
  select m.household_id into v_id from finance_private.members m where m.user_id = v_uid;
  if v_id is null then return pg_catalog.jsonb_build_object('household', null); end if;
  select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object('email', u.email, 'role', m.role)
      order by m.role desc, m.joined_at, m.user_id)
    into v_members from finance_private.members m join auth.users u on u.id = m.user_id
    where m.household_id = v_id;
  return pg_catalog.jsonb_build_object('household', finance_private.household_json(v_id), 'members', v_members);
end;
$$;

create or replace function finance_private.create_household(p_name text, p_state jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_uid uuid := finance_private.require_user(); v_id uuid; v_name text := pg_catalog.btrim(p_name);
begin
  perform finance_private.validate_snapshot(p_state);
  if v_name is null or pg_catalog.char_length(v_name) not between 1 and 100 then
    raise exception using errcode = '22023', message = 'Escribe un nombre de hogar de 1 a 100 caracteres.';
  end if;
  -- Serialize create/join for a user. The PK also enforces one household per user.
  perform 1 from auth.users u where u.id = v_uid for update;
  if exists (select 1 from finance_private.members m where m.user_id = v_uid) then
    return finance_private.bootstrap();
  end if;
  insert into finance_private.households(name, state) values (v_name, p_state) returning id into v_id;
  insert into finance_private.members(user_id, household_id, role) values (v_uid, v_id, 'owner');
  return finance_private.bootstrap();
end;
$$;

create or replace function finance_private.save(p_household uuid, p_expected_revision bigint, p_state jsonb, p_mutation uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := finance_private.require_user();
  v_house finance_private.households%rowtype;
  v_mutation finance_private.mutations%rowtype;
  v_hash bytea;
begin
  if p_household is null or p_mutation is null or p_expected_revision is null
    or p_expected_revision not between 1 and 9007199254740991 then
    raise exception using errcode = '22023', message = 'La revisión y el identificador del guardado son obligatorios.';
  end if;
  perform finance_private.validate_snapshot(p_state);
  select h.* into v_house from finance_private.households h
    where h.id = p_household and exists (
      select 1 from finance_private.members m where m.household_id = h.id and m.user_id = v_uid
    ) for update of h;
  if not found then raise exception using errcode = '42501', message = 'No tienes acceso a este hogar.'; end if;
  -- The EXISTS above may have used a snapshot from before waiting for the lock.
  -- Moving households revokes membership under this same lock; check it afresh.
  if not exists (select 1 from finance_private.members m where m.household_id = p_household and m.user_id = v_uid) then
    raise exception using errcode = '42501', message = 'Ya no tienes acceso a este hogar.';
  end if;
  v_hash := pg_catalog.sha256(pg_catalog.convert_to(p_state::text, 'UTF8'));
  select * into v_mutation from finance_private.mutations x
    where x.household_id = p_household and x.actor_id = v_uid and x.mutation_id = p_mutation;
  if found then
    if v_mutation.state_hash <> v_hash or v_mutation.base_revision <> p_expected_revision then
      raise exception using errcode = '22023', message = 'Ese identificador ya se utilizó para otro guardado.';
    end if;
    -- Always return the current head, including when another member saved later.
    return pg_catalog.jsonb_build_object('status', 'replayed', 'household', finance_private.household_json(p_household));
  end if;
  if v_house.revision <> p_expected_revision then
    return pg_catalog.jsonb_build_object('status', 'conflict', 'household', finance_private.household_json(p_household));
  end if;
  if v_house.revision = 9007199254740991 then
    raise exception using errcode = '22003', message = 'Se alcanzó el límite de revisiones.';
  end if;
  update finance_private.households set state = p_state, revision = revision + 1,
    updated_at = pg_catalog.clock_timestamp() where id = p_household;
  insert into finance_private.mutations(household_id, actor_id, mutation_id, base_revision, state_hash, saved_revision)
    values (p_household, v_uid, p_mutation, p_expected_revision, v_hash, v_house.revision + 1);
  return pg_catalog.jsonb_build_object('status', 'saved', 'household', finance_private.household_json(p_household));
end;
$$;

create or replace function finance_private.invite(p_household uuid, p_email text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := finance_private.require_user();
  v_email text := pg_catalog.lower(pg_catalog.btrim(p_email));
  v_token text; v_expires timestamptz; v_now timestamptz;
begin
  if v_email is null or pg_catalog.char_length(v_email) > 254
    or v_email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' then
    raise exception using errcode = '22023', message = 'Escribe el correo de la persona que quieres invitar.';
  end if;
  perform 1 from finance_private.households h where h.id = p_household and exists (
    select 1 from finance_private.members m where m.household_id = h.id and m.user_id = v_uid and m.role = 'owner'
  ) for update of h;
  if not found then raise exception using errcode = '42501', message = 'Solo quien creó el hogar puede generar la invitación.'; end if;
  if not exists (select 1 from finance_private.members m where m.household_id = p_household and m.user_id = v_uid and m.role = 'owner') then
    raise exception using errcode = '42501', message = 'Ya no administras este hogar.';
  end if;
  if (select pg_catalog.count(*) from finance_private.members m where m.household_id = p_household) >= 2 then
    raise exception using errcode = '23514', message = 'Este hogar ya tiene sus dos integrantes.';
  end if;
  if exists (select 1 from finance_private.members m join auth.users u on u.id = m.user_id
    where m.household_id = p_household and pg_catalog.lower(u.email) = v_email) then
    raise exception using errcode = '22023', message = 'Ese correo ya pertenece al hogar.';
  end if;
  -- Regenerating for the same email must not invalidate a code already copied.
  -- Changing the intended recipient does revoke previous recipients' codes.
  update finance_private.invitations set revoked_at = pg_catalog.clock_timestamp()
    where household_id = p_household and email <> v_email and used_at is null and revoked_at is null;
  v_token := pg_catalog.replace(pg_catalog.gen_random_uuid()::text || pg_catalog.gen_random_uuid()::text, '-', '');
  v_now := pg_catalog.clock_timestamp();
  v_expires := v_now + interval '10 minutes';
  insert into finance_private.invitations(household_id, email, token_hash, expires_at, created_at)
    values (p_household, v_email, pg_catalog.sha256(pg_catalog.convert_to(v_token, 'UTF8')), v_expires, v_now);
  return pg_catalog.jsonb_build_object('token', v_token, 'expires_at', v_expires, 'server_now', v_now);
end;
$$;

create or replace function finance_private.join_invite(p_token text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := finance_private.require_user(); v_email text; v_household uuid;
  v_existing uuid; v_hash bytea; v_invite finance_private.invitations%rowtype;
begin
  if p_token is null or p_token !~ '^[0-9a-f]{64}$' then
    raise exception using errcode = '22023', message = 'La invitación no es válida o ya no está disponible.';
  end if;
  -- Match the verified CURRENT Auth email, never user metadata or a client claim.
  select pg_catalog.lower(u.email) into v_email from auth.users u where u.id = v_uid for update;
  perform finance_private.require_user();
  v_hash := pg_catalog.sha256(pg_catalog.convert_to(p_token, 'UTF8'));
  select i.household_id into v_household from finance_private.invitations i where i.token_hash = v_hash;
  if v_household is null then
    raise exception using errcode = '22023', message = 'La invitación no es válida o ya no está disponible.';
  end if;
  -- All capacity checks use the same household lock as invitation creation.
  perform 1 from finance_private.households h where h.id = v_household for update;
  select i.* into v_invite from finance_private.invitations i where i.token_hash = v_hash for update;
  if not found or v_invite.email <> v_email then
    raise exception using errcode = '22023', message = 'La invitación no es válida para esta cuenta o ya venció.';
  end if;
  select m.household_id into v_existing from finance_private.members m where m.user_id = v_uid;
  -- Retrying a successfully accepted invitation is safe, but not reusable by anyone else.
  if v_invite.used_at is not null then
    if v_invite.used_by = v_uid and v_existing = v_household then return finance_private.bootstrap(); end if;
    raise exception using errcode = '22023', message = 'La invitación ya fue utilizada.';
  end if;
  if v_invite.revoked_at is not null or v_invite.expires_at <= pg_catalog.clock_timestamp() then
    raise exception using errcode = '22023', message = 'La invitación venció o fue reemplazada. Pide un código nuevo.';
  end if;
  if v_existing is not null then
    raise exception using errcode = '23505', message = 'Tu cuenta ya pertenece a un hogar.';
  end if;
  if (select pg_catalog.count(*) from finance_private.members m where m.household_id = v_household) >= 2 then
    raise exception using errcode = '23514', message = 'Este hogar ya tiene sus dos integrantes.';
  end if;
  insert into finance_private.members(user_id, household_id, role) values (v_uid, v_household, 'member');
  update finance_private.invitations set used_at = pg_catalog.clock_timestamp(), used_by = v_uid where id = v_invite.id;
  return finance_private.bootstrap();
end;
$$;

create or replace function finance_private.join_existing(p_token text, p_current_household uuid, p_expected_revision bigint)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := finance_private.require_user(); v_email text; v_destination uuid;
  v_existing uuid; v_role text; v_hash bytea; v_revision bigint;
  v_invite finance_private.invitations%rowtype;
begin
  if p_token is null or p_token !~ '^[0-9a-f]{64}$' or p_current_household is null
    or p_expected_revision is null or p_expected_revision not between 1 and 9007199254740991 then
    raise exception using errcode = '22023', message = 'Falta una invitación válida o la revisión del hogar que vas a conservar.';
  end if;
  -- Same lock order as create/join: current Auth user, ordered households, token.
  select pg_catalog.lower(u.email) into v_email from auth.users u where u.id = v_uid for update;
  perform finance_private.require_user();
  v_hash := pg_catalog.sha256(pg_catalog.convert_to(p_token, 'UTF8'));
  select i.household_id into v_destination from finance_private.invitations i where i.token_hash = v_hash;
  if v_destination is null or v_destination = p_current_household then
    raise exception using errcode = '22023', message = 'La invitación no es válida para cambiar de hogar.';
  end if;
  perform h.id from finance_private.households h
    where h.id in (p_current_household, v_destination) order by h.id for update;
  select i.* into v_invite from finance_private.invitations i where i.token_hash = v_hash for update;
  if not found or v_invite.email <> v_email then
    raise exception using errcode = '22023', message = 'La invitación no es válida para esta cuenta.';
  end if;
  select m.household_id, m.role into v_existing, v_role from finance_private.members m where m.user_id = v_uid;
  select h.revision into v_revision from finance_private.households h where h.id = p_current_household;
  -- A lost acknowledgement can be retried even after expiry. It must refer to
  -- this exact completed switch, not to another consumed invitation or archive.
  if v_invite.used_at is not null then
    if v_invite.used_by = v_uid and v_existing = v_destination
      and v_invite.source_household_id = p_current_household
      and v_invite.source_revision = p_expected_revision
      and v_revision = p_expected_revision and exists (
        select 1 from finance_private.household_archives a
        where a.user_id = v_uid and a.household_id = p_current_household
      ) then return finance_private.bootstrap(); end if;
    raise exception using errcode = '22023', message = 'La invitación ya fue utilizada.';
  end if;
  if v_invite.revoked_at is not null or v_invite.expires_at <= pg_catalog.clock_timestamp() then
    raise exception using errcode = '22023', message = 'La invitación venció o fue reemplazada. Pide un código nuevo.';
  end if;
  if v_existing is distinct from p_current_household or v_role is distinct from 'owner' then
    raise exception using errcode = '42501', message = 'Solo puedes conservar y dejar un hogar que tú administras.';
  end if;
  if (select pg_catalog.count(*) from finance_private.members m where m.household_id = p_current_household) <> 1 then
    raise exception using errcode = '23514', message = 'Tu hogar actual tiene otro integrante. No se puede archivar con este cambio.';
  end if;
  if v_revision is distinct from p_expected_revision then
    raise exception using errcode = '40001', message = 'Tu hogar cambió desde que lo revisaste. Actualiza y vuelve a confirmar antes de unirte.';
  end if;
  if (select pg_catalog.count(*) from finance_private.members m where m.household_id = v_destination) >= 2
    or not exists (select 1 from finance_private.members m where m.household_id = v_destination and m.role = 'owner') then
    raise exception using errcode = '23514', message = 'El hogar de destino ya está completo o no está disponible.';
  end if;
  insert into finance_private.household_archives(user_id, household_id) values (v_uid, p_current_household);
  update finance_private.invitations set revoked_at = pg_catalog.clock_timestamp()
    where household_id = p_current_household and used_at is null and revoked_at is null;
  update finance_private.members set household_id = v_destination, role = 'member', joined_at = pg_catalog.clock_timestamp()
    where user_id = v_uid;
  update finance_private.invitations set used_at = pg_catalog.clock_timestamp(), used_by = v_uid,
    source_household_id = p_current_household, source_revision = p_expected_revision where id = v_invite.id;
  return finance_private.bootstrap();
end;
$$;

create or replace function finance_private.archives()
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_uid uuid := finance_private.require_user(); v_archives jsonb;
begin
  select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object('id', h.id, 'name', h.name,
      'state', h.state, 'revision', h.revision, 'archived_at', a.archived_at)
      order by a.archived_at desc, h.id)
    into v_archives from finance_private.household_archives a
    join finance_private.households h on h.id = a.household_id where a.user_id = v_uid;
  return pg_catalog.jsonb_build_object('archives', coalesce(v_archives, '[]'::jsonb));
end;
$$;

-- Only these wrappers are exposed through PostgREST. No admin key is needed.
create or replace function public.finance_bootstrap()
returns jsonb language sql security invoker set search_path = '' as $$ select finance_private.bootstrap(); $$;
create or replace function public.finance_create_household(p_name text, p_state jsonb)
returns jsonb language sql security invoker set search_path = '' as $$ select finance_private.create_household(p_name, p_state); $$;
create or replace function public.finance_save(p_household uuid, p_expected_revision bigint, p_state jsonb, p_mutation uuid)
returns jsonb language sql security invoker set search_path = '' as $$ select finance_private.save(p_household, p_expected_revision, p_state, p_mutation); $$;
create or replace function public.finance_invite(p_household uuid, p_email text)
returns jsonb language sql security invoker set search_path = '' as $$ select finance_private.invite(p_household, p_email); $$;
create or replace function public.finance_join(p_token text)
returns jsonb language sql security invoker set search_path = '' as $$ select finance_private.join_invite(p_token); $$;
create or replace function public.finance_join_existing(p_token text, p_current_household uuid, p_expected_revision bigint)
returns jsonb language sql security invoker set search_path = '' as $$ select finance_private.join_existing(p_token, p_current_household, p_expected_revision); $$;
create or replace function public.finance_archives()
returns jsonb language sql security invoker set search_path = '' as $$ select finance_private.archives(); $$;

revoke all on all functions in schema finance_private from public, anon, authenticated;
grant execute on function finance_private.bootstrap(), finance_private.create_household(text, jsonb),
  finance_private.save(uuid, bigint, jsonb, uuid), finance_private.invite(uuid, text), finance_private.join_invite(text),
  finance_private.join_existing(text, uuid, bigint), finance_private.archives()
  to authenticated;
revoke all on function public.finance_bootstrap(), public.finance_create_household(text, jsonb),
  public.finance_save(uuid, bigint, jsonb, uuid), public.finance_invite(uuid, text), public.finance_join(text),
  public.finance_join_existing(text, uuid, bigint), public.finance_archives()
  from public, anon, authenticated;
grant execute on function public.finance_bootstrap(), public.finance_create_household(text, jsonb),
  public.finance_save(uuid, bigint, jsonb, uuid), public.finance_invite(uuid, text), public.finance_join(text),
  public.finance_join_existing(text, uuid, bigint), public.finance_archives()
  to authenticated;
commit;

-- Optional Web Push backend. Run AFTER schema.sql as the project owner.
-- Re-run this file after re-running schema.sql (which resets private grants).
-- finance_private and net must stay outside the API's exposed schemas.
-- No VAPID private key or service-role key belongs in this file or the browser.
begin;

create extension if not exists pg_net with schema extensions;
create extension if not exists pg_cron with schema pg_catalog;

create table if not exists finance_private.push_settings (
  singleton boolean primary key default true check (singleton),
  dispatch_url text not null,
  dispatch_secret text not null,
  public_key text not null
);
-- Public legacy anon JWT, used only to pass the platform gateway. The worker
-- additionally requires dispatch_secret; no service-role credential is sent by net.
alter table finance_private.push_settings add column if not exists gateway_anon_key text;
create table if not exists finance_private.push_subscriptions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  household_id uuid not null references finance_private.households(id) on delete cascade,
  endpoint text not null unique check (octet_length(endpoint) between 1 and 2048),
  auth_key text not null,
  p256dh_key text not null,
  created_at timestamptz not null default clock_timestamp()
);
create index if not exists finance_push_subscriptions_user on finance_private.push_subscriptions(user_id);
create table if not exists finance_private.push_events (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references finance_private.households(id) on delete cascade,
  revision bigint not null,
  actor_id uuid references auth.users(id) on delete set null,
  kind text not null check (kind in ('created','updated','deleted','batch')),
  tx_type text check (tx_type in ('income','expense','transfer','saving')),
  change_count integer not null check (change_count between 1 and 100000),
  created_at timestamptz not null default clock_timestamp(),
  unique (household_id, revision)
);
-- Old events intentionally keep NULL: no backfill or historical notification.
alter table finance_private.push_events add column if not exists details jsonb;
create table if not exists finance_private.push_deliveries (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references finance_private.push_events(id) on delete cascade,
  subscription_id uuid not null references finance_private.push_subscriptions(id) on delete cascade,
  recipient_id uuid not null references auth.users(id) on delete cascade,
  status text not null default 'pending' check (status in ('pending','processing','sent','expired')),
  attempts integer not null default 0 check (attempts between 0 and 5),
  lease uuid,
  lease_until timestamptz,
  next_attempt_at timestamptz not null default clock_timestamp(),
  finished_at timestamptz,
  unique (event_id, subscription_id)
);
create index if not exists finance_push_deliveries_due on finance_private.push_deliveries(next_attempt_at)
  where status in ('pending','processing');

alter table finance_private.push_settings enable row level security;
alter table finance_private.push_subscriptions enable row level security;
alter table finance_private.push_events enable row level security;
alter table finance_private.push_deliveries enable row level security;
revoke all on finance_private.push_settings, finance_private.push_subscriptions,
  finance_private.push_events, finance_private.push_deliveries from public, anon, authenticated, service_role;
grant usage on schema finance_private to service_role;

create or replace function finance_private.valid_push_endpoint(p_endpoint text)
returns boolean language plpgsql immutable set search_path = '' as $$
declare v_match text[]; v_host text;
begin
  if p_endpoint is null or pg_catalog.octet_length(p_endpoint) > 2048
    or p_endpoint ~ '[[:space:][:cntrl:]]' or pg_catalog.strpos(p_endpoint, pg_catalog.chr(92)) > 0
    or pg_catalog.strpos(p_endpoint, '#') > 0 then return false; end if;
  v_match := pg_catalog.regexp_match(p_endpoint, '^https://([a-z0-9.-]+)(/[^#]*)$');
  if v_match is null then return false; end if;
  v_host := v_match[1];
  if pg_catalog.length(v_host) > 253
    or v_host !~ '^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?(\.[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?)*$' then return false; end if;
  return v_host = 'fcm.googleapis.com' or v_host like '%.fcm.googleapis.com'
    or v_host = 'updates.push.services.mozilla.com' or v_host like '%.updates.push.services.mozilla.com'
    or v_host = 'web.push.apple.com' or v_host like '%.push.apple.com'
    or v_host like '%.notify.windows.com';
end;
$$;

create or replace function finance_private.valid_push_key(p_key text, p_bytes integer)
returns boolean language plpgsql immutable set search_path = '' as $$
declare v_decoded bytea;
begin
  if p_key is null or p_bytes not in (16,65)
    or pg_catalog.length(p_key) <> (case when p_bytes = 16 then 22 else 87 end)
    or p_key !~ '^[A-Za-z0-9_-]+$' then return false; end if;
  v_decoded := pg_catalog.decode(pg_catalog.translate(p_key, '-_', '+/') ||
    pg_catalog.repeat('=', (4 - pg_catalog.length(p_key) % 4) % 4), 'base64');
  return pg_catalog.octet_length(v_decoded) = p_bytes
    and (p_bytes = 16 or pg_catalog.get_byte(v_decoded, 0) = 4);
exception when others then return false;
end;
$$;

-- Admin-only. The dispatch secret merely wakes the worker; it is not a DB key.
create or replace function finance_private.configure_push(p_url text, p_secret text, p_public_key text)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if p_url is null or p_url !~ '^https://[a-z0-9.-]+/functions/v1/finance-push$'
    or pg_catalog.length(p_url) > 512 or p_secret is null
    or pg_catalog.length(p_secret) not between 32 and 256 or p_secret !~ '^[A-Za-z0-9_-]+$'
    or not finance_private.valid_push_key(p_public_key, 65) then
    raise exception using errcode = '22023', message = 'La configuración Push no es válida.';
  end if;
  insert into finance_private.push_settings(singleton, dispatch_url, dispatch_secret, public_key)
    values (true, p_url, p_secret, p_public_key)
    on conflict (singleton) do update set dispatch_url = excluded.dispatch_url,
      dispatch_secret = excluded.dispatch_secret, public_key = excluded.public_key;
end;
$$;

create or replace function finance_private.push_config()
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_key text;
begin
  perform finance_private.require_user();
  select s.public_key into v_key from finance_private.push_settings s where s.singleton;
  return pg_catalog.jsonb_build_object('publicKey', v_key, 'configured', v_key is not null);
end;
$$;

create or replace function finance_private.configure_push_gateway(p_key text)
returns void language plpgsql security definer set search_path = '' as $$
declare v_payload text; v_claims jsonb;
begin
  if p_key is null or pg_catalog.length(p_key) > 4096 or p_key !~ '^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$' then
    raise exception 'Usa la clave pública anon heredada (JWT), no una clave de servicio.';
  end if;
  v_payload := pg_catalog.split_part(p_key, '.', 2);
  v_claims := pg_catalog.convert_from(pg_catalog.decode(pg_catalog.translate(v_payload, '-_', '+/') ||
    pg_catalog.repeat('=', (4 - pg_catalog.length(v_payload) % 4) % 4), 'base64'), 'UTF8')::jsonb;
  if v_claims ->> 'role' is distinct from 'anon' then raise exception 'Se requiere la clave pública anon.'; end if;
  update finance_private.push_settings set gateway_anon_key = p_key where singleton;
  if not found then raise exception 'Configura primero los datos de Push.'; end if;
end;
$$;
revoke all on function finance_private.configure_push_gateway(text) from public, anon, authenticated, service_role;

create or replace function finance_private.push_status(p_endpoint text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_uid uuid := finance_private.require_user();
begin
  return pg_catalog.jsonb_build_object('enabled', exists (
    select 1 from finance_private.push_subscriptions s join finance_private.members m
      on m.user_id = s.user_id and m.household_id = s.household_id
      where s.user_id = v_uid and s.endpoint = p_endpoint
  ));
end;
$$;

create or replace function finance_private.push_subscribe(p_subscription jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := finance_private.require_user(); v_household uuid;
  v_endpoint text; v_auth text; v_p256dh text; v_old finance_private.push_subscriptions%rowtype;
begin
  if p_subscription is null or pg_catalog.jsonb_typeof(p_subscription) <> 'object'
    or pg_catalog.jsonb_typeof(p_subscription -> 'endpoint') is distinct from 'string'
    or pg_catalog.jsonb_typeof(p_subscription -> 'keys') is distinct from 'object'
    or pg_catalog.jsonb_typeof(p_subscription #> '{keys,auth}') is distinct from 'string'
    or pg_catalog.jsonb_typeof(p_subscription #> '{keys,p256dh}') is distinct from 'string'
    or pg_catalog.octet_length(p_subscription::text) > 4096 then
    raise exception using errcode = '22023', message = 'La suscripción Push no es válida.';
  end if;
  v_endpoint := p_subscription ->> 'endpoint';
  v_auth := p_subscription #>> '{keys,auth}'; v_p256dh := p_subscription #>> '{keys,p256dh}';
  if not finance_private.valid_push_endpoint(v_endpoint)
    or not finance_private.valid_push_key(v_auth, 16) or not finance_private.valid_push_key(v_p256dh, 65) then
    raise exception using errcode = '22023', message = 'El destino o las claves Push no son válidos.';
  end if;
  if not exists (select 1 from finance_private.push_settings) then
    raise exception using errcode = '55000', message = 'Primero configura las notificaciones en el servidor.';
  end if;
  -- Same auth-user -> household ordering as joining a household. This also
  -- serializes the per-account device limit and opt-in against a concurrent save.
  perform 1 from auth.users u where u.id = v_uid for no key update;
  select m.household_id into v_household from finance_private.members m where m.user_id = v_uid;
  if v_household is null then raise exception using errcode = '42501', message = 'Abre tu hogar antes de activar avisos.'; end if;
  perform 1 from finance_private.households h where h.id = v_household for update;
  if not exists (select 1 from finance_private.members m where m.user_id = v_uid and m.household_id = v_household) then
    raise exception using errcode = '42501', message = 'Tu hogar cambió. Vuelve a abrirlo.';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_endpoint, 736951));
  select s.* into v_old from finance_private.push_subscriptions s where s.endpoint = v_endpoint for update;
  if found and v_old.user_id = v_uid and v_old.household_id = v_household
    and v_old.auth_key = v_auth and v_old.p256dh_key = v_p256dh then
    return pg_catalog.jsonb_build_object('enabled', true);
  end if;
  -- A device explicitly enabling another account gets a fresh binding. Its old
  -- pending deliveries cascade away, including leases held by an old worker.
  delete from finance_private.push_subscriptions s
    where s.endpoint = v_endpoint or (s.user_id = v_uid and s.household_id <> v_household);
  if (select pg_catalog.count(*) from finance_private.push_subscriptions s where s.user_id = v_uid) >= 5 then
    raise exception using errcode = '23514', message = 'Esta cuenta ya tiene cinco dispositivos. Desactiva uno antes de agregar otro.';
  end if;
  insert into finance_private.push_subscriptions(user_id, household_id, endpoint, auth_key, p256dh_key)
    values (v_uid, v_household, v_endpoint, v_auth, v_p256dh);
  return pg_catalog.jsonb_build_object('enabled', true);
end;
$$;

create or replace function finance_private.push_unsubscribe(p_endpoint text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_uid uuid := finance_private.require_user();
begin
  perform 1 from auth.users u where u.id = v_uid for no key update;
  delete from finance_private.push_subscriptions s where s.endpoint = p_endpoint and s.user_id = v_uid;
  return pg_catalog.jsonb_build_object('enabled', false);
end;
$$;

-- Only the fields needed by the notification diff are inspected here. The app
-- remains responsible for its complete financial validation. Details below are
-- an allowlisted snapshot, never a copy of the full transaction or household.
create or replace function finance_private.validate_push_transactions(p_transactions jsonb)
returns void language plpgsql set search_path = '' as $$
begin
  if pg_catalog.jsonb_typeof(p_transactions) is distinct from 'array'
    or pg_catalog.jsonb_array_length(p_transactions) > 50000 then
    raise exception using errcode = '22023', message = 'La lista de movimientos no es válida para notificar.';
  end if;
  if exists (select 1 from pg_catalog.jsonb_array_elements(p_transactions) t(value)
    where pg_catalog.jsonb_typeof(t.value) is distinct from 'object'
      or pg_catalog.jsonb_typeof(t.value -> 'id') is distinct from 'string'
      or pg_catalog.length(t.value ->> 'id') not between 1 and 150
      or pg_catalog.btrim(t.value ->> 'id') = ''
      or coalesce(t.value ->> 'source', '') not in ('manual','close')
      or coalesce(t.value ->> 'type', '') not in ('income','expense','transfer','saving'))
    or exists (select 1 from pg_catalog.jsonb_array_elements(p_transactions) t(value)
      group by t.value ->> 'id' having pg_catalog.count(*) > 1) then
    raise exception using errcode = '22023', message = 'Hay movimientos inválidos o con identificadores repetidos.';
  end if;
end;
$$;

create or replace function finance_private.push_safe_label(p_label text, p_fallback text default 'Caja')
returns text language sql immutable set search_path = '' as $$
  select pg_catalog.left(coalesce(nullif(pg_catalog.btrim(pg_catalog.regexp_replace(
    pg_catalog.regexp_replace(coalesce(p_label, ''), '[[:cntrl:]]', ' ', 'g'),
    U&'[\007F-\009F\200B-\200F\202A-\202E\2060-\206F\FEFF]', '', 'g')), ''), p_fallback), 80);
$$;

create or replace function finance_private.push_fund_label(p_fund text, p_state jsonb)
returns text language plpgsql immutable set search_path = '' as $$
declare v_label text;
begin
  if p_fund in ('cash:personal1','cash:personal2','personal1','personal2') then
    if pg_catalog.jsonb_typeof(p_state #> array['settings','names',case when pg_catalog.right(p_fund,1) = '1' then '0' else '1' end]) = 'string' then
      v_label := p_state #>> array['settings','names',case when pg_catalog.right(p_fund,1) = '1' then '0' else '1' end];
    end if;
    return finance_private.push_safe_label(v_label, 'Integrante ' || pg_catalog.right(p_fund,1));
  elsif pg_catalog.left(p_fund,5) = 'goal:' then
    if pg_catalog.jsonb_typeof(p_state -> 'goals') = 'array' then
      select g.value ->> 'name' into v_label from pg_catalog.jsonb_array_elements(p_state -> 'goals') g(value)
        where g.value ->> 'id' = pg_catalog.substr(p_fund,6)
          and pg_catalog.jsonb_typeof(g.value -> 'name') = 'string' limit 1;
    end if;
    return finance_private.push_safe_label(v_label);
  end if;
  return case p_fund
    when 'maintenance' then 'Moto' when 'cash:home' then 'Hogar'
    when 'cash:iess' then 'IESS' when 'cash:saving' then 'Ahorro · por repartir'
    when 'cash:goals' then 'Metas · por repartir' when 'cash:unassigned' then 'Sin asignar'
    when 'rent' then 'Renta que no pagamos' when 'emergency' then 'Fondo de emergencia'
    when 'investment' then 'Metas / inversión' else 'Caja' end;
end;
$$;

create or replace function finance_private.push_movement_details(p_tx jsonb, p_state jsonb)
returns jsonb language plpgsql immutable set search_path = '' as $$
declare
  v_amount numeric; v_cash boolean; v_account text; v_fund text;
  v_label text; v_from text; v_to text; v_format text; v_result jsonb;
begin
  if pg_catalog.jsonb_typeof(p_tx) is distinct from 'object'
    or pg_catalog.jsonb_typeof(p_tx -> 'amount') is distinct from 'number' then return null; end if;
  v_amount := (p_tx ->> 'amount')::numeric;
  if v_amount < 0 or v_amount > 100000000000 or v_amount <> pg_catalog.trunc(v_amount) then return null; end if;
  v_cash := coalesce(p_state ->> 'version' = '3'
    and p_state ->> 'cashStartMonth' ~ '^(20[0-9]{2}|21[0-9]{2}|2200)-(0[1-9]|1[0-2])$'
    and pg_catalog.left(p_tx ->> 'date',7) >= p_state ->> 'cashStartMonth', false);
  v_account := p_tx ->> 'account';
  v_format := case when p_state #>> '{settings,format}' = 'us' then 'us' else 'es' end;
  case p_tx ->> 'type'
    when 'income' then
      if v_account in ('personal1','personal2') then
        v_label := 'Personal · ' || finance_private.push_fund_label(v_account,p_state);
      elsif v_account = 'home' then
        v_label := case when v_cash then 'Cajas del hogar (repartido)' else 'Hogar' end;
      else v_label := 'Caja'; end if;
    when 'expense' then
      if v_cash then
        v_fund := nullif(p_tx ->> 'from','');
        if v_fund is null then
          v_fund := case p_tx ->> 'category'
            when 'gas' then 'maintenance' when 'maintenance' then 'maintenance'
            when 'iess1' then 'cash:iess' when 'iess2' then 'cash:iess'
            when 'personal1' then 'cash:personal1' when 'personal2' then 'cash:personal2'
            when 'groceries' then 'cash:home' when 'dining' then 'cash:home' when 'services' then 'cash:home' when 'other' then 'cash:home'
            else p_tx ->> 'category' end;
        end if;
        v_label := finance_private.push_fund_label(v_fund,p_state);
      elsif v_account = 'home' then v_label := 'Hogar';
      elsif v_account in ('personal1','personal2') then v_label := 'Personal · ' || finance_private.push_fund_label(v_account,p_state);
      elsif v_account = 'savings' then v_label := finance_private.push_fund_label(p_tx ->> 'from',p_state);
      else v_label := 'Caja'; end if;
    when 'transfer' then
      v_label := 'Entre cajas';
      v_from := finance_private.push_fund_label(p_tx ->> 'from',p_state);
      v_to := finance_private.push_fund_label(p_tx ->> 'to',p_state);
    when 'saving' then v_label := finance_private.push_fund_label(p_tx ->> 'to',p_state);
    else return null;
  end case;
  v_result := pg_catalog.jsonb_build_object('amountCents',v_amount::bigint,
    'accountLabel',finance_private.push_safe_label(v_label),'format',v_format);
  if v_from is not null then v_result := v_result || pg_catalog.jsonb_build_object('fromLabel',v_from,'toLabel',v_to); end if;
  return v_result;
exception when others then
  -- Notification formatting must never prevent an otherwise accepted save.
  return null;
end;
$$;

-- Wakeup is best effort. The durable outbox, not pg_net's transient queue, is
-- the source of truth. In particular an HTTP/extension failure cannot roll back
-- a financial movement. Cron will retry when the worker is available again.
create or replace function finance_private.dispatch_push()
returns boolean language plpgsql security definer set search_path = '' as $$
declare v_settings finance_private.push_settings%rowtype;
begin
  select s.* into v_settings from finance_private.push_settings s where s.singleton;
  if not found or not exists (
    select 1 from finance_private.push_deliveries d
      join finance_private.push_events e on e.id = d.event_id
      join finance_private.push_subscriptions s on s.id = d.subscription_id and s.user_id = d.recipient_id
      join finance_private.members m on m.user_id = s.user_id and m.household_id = s.household_id
    where e.household_id = s.household_id and e.created_at > pg_catalog.clock_timestamp() - interval '24 hours'
      and d.status in ('pending','processing') and d.attempts < 5
      and d.next_attempt_at <= pg_catalog.clock_timestamp()
      and (d.lease_until is null or d.lease_until <= pg_catalog.clock_timestamp())
  ) then return false; end if;
  perform net.http_post(url := v_settings.dispatch_url, body := '{}'::jsonb,
    headers := pg_catalog.jsonb_build_object('Content-Type', 'application/json', 'x-finance-dispatch-secret', v_settings.dispatch_secret) ||
      case when v_settings.gateway_anon_key is not null then pg_catalog.jsonb_build_object('Authorization', 'Bearer ' || v_settings.gateway_anon_key) else '{}'::jsonb end,
    timeout_milliseconds := 5000);
  return true;
exception when others then return false;
end;
$$;

create or replace function finance_private.queue_push_changes()
returns trigger language plpgsql security definer set search_path = '' as $$
declare v_count integer; v_kind text; v_type text; v_event uuid; v_tx_id text; v_tx jsonb; v_snapshot jsonb; v_details jsonb;
begin
  if coalesce(pg_catalog.current_setting('finance.push_notify', true), '') <> 'on'
    or old.state -> 'transactions' = new.state -> 'transactions' then return new; end if;
  perform finance_private.validate_push_transactions(old.state -> 'transactions');
  perform finance_private.validate_push_transactions(new.state -> 'transactions');
  with old_tx as (
    select t.value ->> 'id' as id, t.value as value from pg_catalog.jsonb_array_elements(old.state -> 'transactions') t(value)
      where t.value ->> 'source' = 'manual'
  ), new_tx as (
    select t.value ->> 'id' as id, t.value as value from pg_catalog.jsonb_array_elements(new.state -> 'transactions') t(value)
      where t.value ->> 'source' = 'manual'
  ), changes as (
    select case when o.id is null then 'created' when n.id is null then 'deleted' else 'updated' end as kind,
      coalesce(n.value ->> 'type', o.value ->> 'type') as tx_type, coalesce(n.id,o.id) as tx_id
    from old_tx o full join new_tx n on n.id = o.id where o.value is distinct from n.value
  ) select pg_catalog.count(*)::integer, pg_catalog.min(c.kind), pg_catalog.min(c.tx_type), pg_catalog.min(c.tx_id)
      into v_count, v_kind, v_type, v_tx_id from changes c;
  if v_count = 0 then return new; end if;
  if v_count = 1 then
    v_snapshot := case when v_kind = 'deleted' then old.state else new.state end;
    select t.value into v_tx from pg_catalog.jsonb_array_elements(v_snapshot -> 'transactions') t(value)
      where t.value ->> 'id' = v_tx_id;
    v_details := finance_private.push_movement_details(v_tx,v_snapshot);
  end if;
  insert into finance_private.push_events(household_id, revision, actor_id, kind, tx_type, change_count, details)
    values (new.id, new.revision, auth.uid(), case when v_count = 1 then v_kind else 'batch' end,
      case when v_count = 1 then v_type else null end, v_count, v_details) returning id into v_event;
  -- Recipients are the opted-in bindings present now, including the author.
  -- Later opt-ins do not receive previous events.
  insert into finance_private.push_deliveries(event_id, subscription_id, recipient_id)
    select v_event, s.id, s.user_id from finance_private.push_subscriptions s
      join finance_private.members m on m.user_id = s.user_id and m.household_id = s.household_id
      where s.household_id = new.id;
  perform finance_private.dispatch_push();
  return new;
end;
$$;
drop trigger if exists finance_queue_push_changes on finance_private.households;
create trigger finance_queue_push_changes after update of state on finance_private.households
  for each row execute function finance_private.queue_push_changes();

create or replace function finance_private.save_notifying(p_household uuid, p_expected_revision bigint, p_state jsonb, p_mutation uuid, p_notify boolean)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_previous text := pg_catalog.current_setting('finance.push_notify', true); v_result jsonb;
begin
  if p_notify is null then raise exception using errcode = '22023', message = 'Indica si este guardado genera un aviso.'; end if;
  perform pg_catalog.set_config('finance.push_notify', case when p_notify then 'on' else 'off' end, true);
  begin
    v_result := finance_private.save(p_household, p_expected_revision, p_state, p_mutation);
  exception when others then
    perform pg_catalog.set_config('finance.push_notify', coalesce(v_previous, 'off'), true); raise;
  end;
  perform pg_catalog.set_config('finance.push_notify', coalesce(v_previous, 'off'), true);
  return v_result;
end;
$$;

create or replace function finance_private.push_claim(p_limit integer default 20)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_result jsonb; v_now timestamptz := pg_catalog.clock_timestamp();
begin
  if p_limit is null or p_limit not between 1 and 100 then
    raise exception using errcode = '22023', message = 'El tamaño de lote debe estar entre 1 y 100.';
  end if;
  -- Do not wait for rows held by finish/unsubscribe. They may be cascading
  -- through another delivery of the same subscription in this transaction.
  with invalid as (
    select d.id from finance_private.push_deliveries d
    join finance_private.push_events e on e.id = d.event_id where d.status in ('pending','processing')
      and (e.created_at <= v_now - interval '24 hours'
        or (d.attempts >= 5 and (d.lease_until is null or d.lease_until <= v_now))
        or not exists (select 1 from finance_private.push_subscriptions s join finance_private.members m
          on m.user_id = s.user_id and m.household_id = s.household_id
          where s.id = d.subscription_id and s.user_id = d.recipient_id and s.household_id = e.household_id))
    for update of d skip locked
  ) update finance_private.push_deliveries d set status = 'expired', lease = null, lease_until = null, finished_at = v_now
    from invalid where d.id = invalid.id;
  with due as (
    select d.id from finance_private.push_deliveries d
      join finance_private.push_events e on e.id = d.event_id
      join finance_private.push_subscriptions s on s.id = d.subscription_id and s.user_id = d.recipient_id
      join finance_private.members m on m.user_id = s.user_id and m.household_id = s.household_id
    where e.household_id = s.household_id and e.created_at > v_now - interval '24 hours'
      and d.status in ('pending','processing') and d.attempts < 5 and d.next_attempt_at <= v_now
      and (d.lease_until is null or d.lease_until <= v_now)
    order by d.next_attempt_at, d.id limit p_limit for update of d skip locked
  ), leased as (
    update finance_private.push_deliveries d set status = 'processing', attempts = attempts + 1,
      lease = gen_random_uuid(), lease_until = v_now + interval '2 minutes'
    from due where d.id = due.id returning d.*
  ) select coalesce(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
      'id', d.id, 'lease', d.lease, 'event_id', e.id, 'kind', e.kind, 'tx_type', e.tx_type,
      'count', e.change_count, 'created_at', e.created_at, 'details', e.details,
      'subscription', pg_catalog.jsonb_build_object('endpoint', s.endpoint,
        'keys', pg_catalog.jsonb_build_object('auth', s.auth_key, 'p256dh', s.p256dh_key))
    ) order by d.next_attempt_at, d.id), '[]'::jsonb) into v_result
      from leased d join finance_private.push_events e on e.id = d.event_id
        join finance_private.push_subscriptions s on s.id = d.subscription_id;
  return v_result;
end;
$$;

create or replace function finance_private.push_finish(p_id uuid, p_lease uuid, p_outcome text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_subscription uuid; v_delivery finance_private.push_deliveries%rowtype; v_now timestamptz := pg_catalog.clock_timestamp();
begin
  if p_outcome is null or p_outcome not in ('sent','retry','gone') then
    raise exception using errcode = '22023', message = 'Resultado Push inválido.';
  end if;
  -- Subscription -> delivery lock order matches unsubscribe/cascade deletion.
  select d.subscription_id into v_subscription from finance_private.push_deliveries d where d.id = p_id;
  if v_subscription is null then return pg_catalog.jsonb_build_object('finished', false); end if;
  perform 1 from finance_private.push_subscriptions s where s.id = v_subscription for update;
  select d.* into v_delivery from finance_private.push_deliveries d where d.id = p_id for update;
  -- Waiting for a subscription lock must not extend a lease's validity.
  v_now := pg_catalog.clock_timestamp();
  if not found or v_delivery.status <> 'processing' or v_delivery.lease is distinct from p_lease
    or v_delivery.lease_until <= v_now then return pg_catalog.jsonb_build_object('finished', false); end if;
  if p_outcome = 'gone' then
    delete from finance_private.push_subscriptions s where s.id = v_subscription;
  else
    update finance_private.push_deliveries d set status = case when p_outcome = 'sent' then 'sent' else 'pending' end,
      finished_at = case when p_outcome = 'sent' then v_now else null end,
      next_attempt_at = v_now + pg_catalog.make_interval(secs => least(900, 30 * (2 ^ v_delivery.attempts))::double precision),
      lease = null, lease_until = null where d.id = p_id;
  end if;
  return pg_catalog.jsonb_build_object('finished', true);
end;
$$;

create or replace function public.finance_save_notifying(p_household uuid, p_expected_revision bigint, p_state jsonb, p_mutation uuid, p_notify boolean)
returns jsonb language sql security invoker set search_path = '' as $$ select finance_private.save_notifying(p_household, p_expected_revision, p_state, p_mutation, p_notify); $$;
create or replace function public.finance_push_config()
returns jsonb language sql security invoker set search_path = '' as $$ select finance_private.push_config(); $$;
create or replace function public.finance_push_status(p_endpoint text)
returns jsonb language sql security invoker set search_path = '' as $$ select finance_private.push_status(p_endpoint); $$;
create or replace function public.finance_push_subscribe(p_subscription jsonb)
returns jsonb language sql security invoker set search_path = '' as $$ select finance_private.push_subscribe(p_subscription); $$;
create or replace function public.finance_push_unsubscribe(p_endpoint text)
returns jsonb language sql security invoker set search_path = '' as $$ select finance_private.push_unsubscribe(p_endpoint); $$;
create or replace function public.finance_push_claim(p_limit integer default 20)
returns jsonb language sql security invoker set search_path = '' as $$ select finance_private.push_claim(p_limit); $$;
create or replace function public.finance_push_finish(p_id uuid, p_lease uuid, p_outcome text)
returns jsonb language sql security invoker set search_path = '' as $$ select finance_private.push_finish(p_id, p_lease, p_outcome); $$;

revoke all on function finance_private.valid_push_endpoint(text), finance_private.valid_push_key(text, integer),
  finance_private.push_safe_label(text,text), finance_private.push_fund_label(text,jsonb), finance_private.push_movement_details(jsonb,jsonb),
  finance_private.configure_push(text, text, text), finance_private.validate_push_transactions(jsonb),
  finance_private.dispatch_push(), finance_private.queue_push_changes(),
  finance_private.save_notifying(uuid, bigint, jsonb, uuid, boolean), finance_private.push_config(),
  finance_private.push_status(text), finance_private.push_subscribe(jsonb), finance_private.push_unsubscribe(text),
  finance_private.push_claim(integer), finance_private.push_finish(uuid, uuid, text)
  from public, anon, authenticated, service_role;
grant execute on function finance_private.save_notifying(uuid, bigint, jsonb, uuid, boolean),
  finance_private.push_config(), finance_private.push_status(text), finance_private.push_subscribe(jsonb), finance_private.push_unsubscribe(text)
  to authenticated;
grant execute on function finance_private.push_claim(integer), finance_private.push_finish(uuid, uuid, text) to service_role;
revoke all on function public.finance_save_notifying(uuid, bigint, jsonb, uuid, boolean),
  public.finance_push_config(), public.finance_push_status(text), public.finance_push_subscribe(jsonb),
  public.finance_push_unsubscribe(text), public.finance_push_claim(integer), public.finance_push_finish(uuid, uuid, text)
  from public, anon, authenticated, service_role;
grant execute on function public.finance_save_notifying(uuid, bigint, jsonb, uuid, boolean),
  public.finance_push_config(), public.finance_push_status(text), public.finance_push_subscribe(jsonb), public.finance_push_unsubscribe(text)
  to authenticated;
grant execute on function public.finance_push_claim(integer), public.finance_push_finish(uuid, uuid, text) to service_role;

-- A named cron job is updated, not duplicated, when this migration is re-run.
-- Only the owner can configure or manually invoke dispatch_push().
select cron.schedule('finance-push-dispatch', '* * * * *', 'select finance_private.dispatch_push();');
commit;

-- Analíticas de la página de links (jch-links.vercel.app) · Jardines Club Hípico
--
-- Vive en el proyecto de Supabase "Mis proyectos", en un esquema aparte (jch_links) que la API REST
-- NO expone. Lo único que se puede llamar desde fuera es public.jch_links_rpc(), una sola puerta:
--   evento → guarda una visita o un clic (abierta, validada y con topes)
--   login  → PIN de 4 dígitos (bcrypt) con tope de intentos; devuelve un token de sesión de 12 h
--   stats  → datos del panel (exige un token de sesión válido)
--   salir  → cierra la sesión
--
-- Después de crear todo se da de alta el PIN (una sola vez; el PIN real nunca va en el repo):
--   insert into jch_links.config (clave, valor)
--   values ('pin_hash', extensions.crypt('<PIN>', extensions.gen_salt('bf', 10)))
--   on conflict (clave) do update set valor = excluded.valor;
--   update jch_links.sesiones set expira = now() where expira > now();   -- al cambiar el PIN se cierran las sesiones
--
-- Para arrancar el conteo desde cero (por ejemplo, después de las pruebas) sin borrar nada:
--   insert into jch_links.config (clave, valor) values ('conteo_desde', now()::text)
--   on conflict (clave) do update set valor = excluded.valor;
--
-- Las tablas intentos y sesiones crecen solo unas filas por día o por inicio de sesión: no necesitan limpieza.
-- Este archivo se puede volver a ejecutar sin romper nada (todo es "if not exists" / "create or replace").

create schema if not exists jch_links;
revoke all on schema jch_links from public, anon, authenticated;

-- ── Tablas ────────────────────────────────────────────────────────────────────────────────────

create table if not exists jch_links.config (
  clave text primary key,
  valor text not null
);
comment on table jch_links.config is
  'pin_hash = bcrypt del PIN del panel; pepper = sal aleatoria para guardar las IP solo como hash; conteo_desde = el panel ignora los eventos anteriores a esta fecha.';

create table if not exists jch_links.eventos (
  id     bigint generated always as identity primary key,
  ts     timestamptz not null default now(),
  tipo   text not null check (tipo in ('visita', 'clic')),
  boton  text check (boton ~ '^[a-z0-9_]{1,24}$'),
  fuente text check (fuente ~ '^[a-z0-9._-]{1,40}$'),
  vid    text not null check (vid ~ '^[a-z0-9]{8,32}$'),
  constraint eventos_boton_solo_en_clic check ((tipo = 'clic') = (boton is not null))
);
comment on table jch_links.eventos is
  'Una fila por visita a la página o por clic en un botón. Sin IP ni datos personales: vid es un id aleatorio guardado en el dispositivo; fuente es ?s= de la URL o el sitio de origen (null = directo, como el QR).';

create index if not exists eventos_ts_idx     on jch_links.eventos (ts desc);
create index if not exists eventos_vid_ts_idx on jch_links.eventos (vid, ts desc);

create table if not exists jch_links.intentos (
  bucket         text        not null,
  clave_hash     text        not null,
  ventana_inicio timestamptz not null,
  n              integer     not null default 0,
  primary key (bucket, clave_hash, ventana_inicio)
);
comment on table jch_links.intentos is
  'Contadores por ventana fija: intentos de PIN (por IP hasheada y globales) y tope diario de eventos.';

create table if not exists jch_links.sesiones (
  token_hash text primary key,
  creada     timestamptz not null default now(),
  expira     timestamptz not null
);
comment on table jch_links.sesiones is
  'Sesiones abiertas del panel. Solo se guarda el hash del token; la cookie lleva el token.';

insert into jch_links.config (clave, valor)
values ('pepper', encode(extensions.gen_random_bytes(32), 'hex'))
on conflict (clave) do nothing;

-- RLS activado y sin políticas: ningún rol de la API puede leer ni escribir directo.
alter table jch_links.config   enable row level security;
alter table jch_links.eventos  enable row level security;
alter table jch_links.intentos enable row level security;
alter table jch_links.sesiones enable row level security;
revoke all on all tables in schema jch_links from public, anon, authenticated;

-- ── Funciones internas (esquema no expuesto) ──────────────────────────────────────────────────

-- Cuenta un uso en una ventana fija y devuelve cuántos van en esa ventana.
create or replace function jch_links.consumir(p_bucket text, p_clave text, p_ventana interval)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_ini timestamptz := date_bin(p_ventana, now(), timestamptz '2000-01-01 00:00:00+00');
  v_n   integer;
begin
  insert into jch_links.intentos (bucket, clave_hash, ventana_inicio, n)
  values (p_bucket, p_clave, v_ini, 1)
  on conflict (bucket, clave_hash, ventana_inicio)
  do update set n = jch_links.intentos.n + 1
  returning n into v_n;

  return v_n;
end $$;

-- PIN: cada intento se cuenta ANTES de comparar (así no se puede probar en paralelo).
-- Máximo 5 por IP cada 15 minutos y 25 en total por hora (contra ataques repartidos en muchas IP).
create or replace function jch_links.login(p_pin text, p_ip text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  c_max_ip    constant integer     := 5;
  c_vent_ip   constant interval    := interval '15 minutes';
  c_max_glob  constant integer     := 25;
  c_vent_glob constant interval    := interval '1 hour';
  c_origen    constant timestamptz := timestamptz '2000-01-01 00:00:00+00';
  v_pin_hash text;
  v_pepper   text;
  v_clave    text;
  v_n        integer;
  v_token    text;
begin
  select valor into v_pin_hash from jch_links.config where clave = 'pin_hash';
  select valor into v_pepper   from jch_links.config where clave = 'pepper';
  v_clave := encode(sha256(convert_to(left(coalesce(p_ip, ''), 64) || ':' || coalesce(v_pepper, ''), 'utf8')), 'hex');

  v_n := jch_links.consumir('pin_ip', v_clave, c_vent_ip);
  if v_n > c_max_ip then
    return jsonb_build_object('ok', false, 'quedan', 0,
      'espera', ceil(extract(epoch from (date_bin(c_vent_ip, now(), c_origen) + c_vent_ip - now())))::integer);
  end if;
  if jch_links.consumir('pin_global', 'global', c_vent_glob) > c_max_glob then
    return jsonb_build_object('ok', false, 'quedan', 0,
      'espera', ceil(extract(epoch from (date_bin(c_vent_glob, now(), c_origen) + c_vent_glob - now())))::integer);
  end if;

  if v_pin_hash is null or p_pin is null or p_pin !~ '^[0-9]{4}$'
     or extensions.crypt(p_pin, v_pin_hash) <> v_pin_hash then
    return jsonb_build_object('ok', false, 'quedan', greatest(c_max_ip - v_n, 0));
  end if;

  v_token := encode(extensions.gen_random_bytes(32), 'hex');
  insert into jch_links.sesiones (token_hash, expira)
  values (encode(sha256(convert_to(v_token, 'utf8')), 'hex'), now() + interval '12 hours');

  return jsonb_build_object('ok', true, 'token', v_token, 'segundos', 43200);
end $$;

create or replace function jch_links.sesion_valida(p_token text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from jch_links.sesiones
     where token_hash = encode(sha256(convert_to(coalesce(p_token, ''), 'utf8')), 'hex')
       and expira > now());
$$;

-- Guarda una visita o un clic. Valida todo y pone topes: 60 por minuto por dispositivo,
-- 600 por minuto en total y 20 000 al día.
create or replace function jch_links.registrar(p jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tipo   text := case p ->> 'k' when 'v' then 'visita' when 'c' then 'clic' end;
  v_boton  text := nullif(lower(btrim(coalesce(p ->> 't', ''))), '');
  v_fuente text := nullif(lower(btrim(coalesce(p ->> 's', ''))), '');
  v_vid    text := lower(coalesce(p ->> 'v', ''));
begin
  if v_tipo is null or v_vid !~ '^[a-z0-9]{8,32}$' then
    return jsonb_build_object('ok', false, 'motivo', 'datos');
  end if;
  if v_tipo = 'visita' then
    v_boton := null;
  elsif v_boton is null or v_boton !~ '^[a-z0-9_]{1,24}$' then
    return jsonb_build_object('ok', false, 'motivo', 'boton');
  end if;
  if v_fuente is not null and v_fuente !~ '^[a-z0-9._-]{1,40}$' then
    v_fuente := null;
  end if;

  if (select count(*) from jch_links.eventos where vid = v_vid and ts > now() - interval '1 minute') >= 60
     or (select count(*) from jch_links.eventos where ts > now() - interval '1 minute') >= 600 then
    return jsonb_build_object('ok', false, 'motivo', 'tope');
  end if;
  if jch_links.consumir('ev_dia', 'global', interval '1 day') > 20000 then
    return jsonb_build_object('ok', false, 'motivo', 'tope_dia');
  end if;

  insert into jch_links.eventos (tipo, boton, fuente, vid) values (v_tipo, v_boton, v_fuente, v_vid);
  return jsonb_build_object('ok', true);
end $$;

-- Todo lo que muestra el panel, ya agregado. Los días se cuentan en hora de la Ciudad de México.
--   p_rango: 'hoy' | '7d' | '30d' | 'todo'
--   greatest() ignora los nulos: sin conteo_desde y sin inicio ('todo') el límite queda nulo = sin límite.
--   'todo' arranca el día del primer evento contado (máximo 90 días atrás).
create or replace function jch_links.estadisticas(p_rango text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  c_tz     constant text := 'America/Mexico_City';
  v_ahora  timestamp := now() at time zone c_tz;
  v_hoy    timestamp := date_trunc('day', now() at time zone c_tz);
  v_rango  text := case when p_rango in ('hoy', '7d', '30d', 'todo') then p_rango else 'hoy' end;
  v_conteo timestamptz;
  v_ini    timestamp;
  v_desde  timestamptz;
  v_totales jsonb;
  v_botones jsonb;
  v_fuentes jsonb;
  v_serie   jsonb;
  v_ultima  timestamptz;
begin
  select valor::timestamptz into v_conteo from jch_links.config where clave = 'conteo_desde';

  v_ini := case v_rango
    when 'hoy' then v_hoy
    when '7d'  then v_hoy - interval '6 days'
    when '30d' then v_hoy - interval '29 days'
    else null
  end;
  v_desde := greatest(case when v_ini is null then null else v_ini at time zone c_tz end, v_conteo);

  select jsonb_build_object(
           'visitas',       count(*) filter (where tipo = 'visita'),
           'personas',      count(distinct vid) filter (where tipo = 'visita'),
           'clics',         count(*) filter (where tipo = 'clic'),
           'personas_clic', count(distinct vid) filter (where tipo = 'clic')),
         max(ts) filter (where tipo = 'visita')
    into v_totales, v_ultima
    from jch_links.eventos
   where v_desde is null or ts >= v_desde;

  select coalesce(jsonb_agg(jsonb_build_object('id', boton, 'clics', clics, 'personas', personas)
                            order by clics desc, boton), '[]'::jsonb)
    into v_botones
    from (select boton, count(*) as clics, count(distinct vid) as personas
            from jch_links.eventos
           where tipo = 'clic' and (v_desde is null or ts >= v_desde)
           group by boton) b;

  select coalesce(jsonb_agg(jsonb_build_object('fuente', fuente, 'visitas', visitas, 'personas', personas)
                            order by visitas desc, fuente), '[]'::jsonb)
    into v_fuentes
    from (select coalesce(fuente, 'directo') as fuente, count(*) as visitas, count(distinct vid) as personas
            from jch_links.eventos
           where tipo = 'visita' and (v_desde is null or ts >= v_desde)
           group by 1
           order by 2 desc, 1
           limit 8) f;

  if v_rango = 'hoy' then
    select coalesce(jsonb_agg(jsonb_build_object('t', to_char(g, 'HH24:MI'),
                                                 'visitas', coalesce(a.visitas, 0),
                                                 'clics', coalesce(a.clics, 0)) order by g), '[]'::jsonb)
      into v_serie
      from generate_series(v_hoy, v_hoy + interval '23 hours', interval '1 hour') as g
      left join (select date_trunc('hour', ts at time zone c_tz) as h,
                        count(*) filter (where tipo = 'visita') as visitas,
                        count(*) filter (where tipo = 'clic')   as clics
                   from jch_links.eventos
                  where ts >= v_desde
                  group by 1) a on a.h = g;
  else
    v_ini := coalesce(v_ini, greatest(
      coalesce(date_trunc('day', (select min(e.ts) from jch_links.eventos e
                                   where v_conteo is null or e.ts >= v_conteo) at time zone c_tz), v_hoy),
      v_hoy - interval '89 days'));
    select coalesce(jsonb_agg(jsonb_build_object('t', to_char(g, 'YYYY-MM-DD'),
                                                 'visitas', coalesce(a.visitas, 0),
                                                 'clics', coalesce(a.clics, 0)) order by g), '[]'::jsonb)
      into v_serie
      from generate_series(v_ini, v_hoy, interval '1 day') as g
      left join (select date_trunc('day', ts at time zone c_tz) as d,
                        count(*) filter (where tipo = 'visita') as visitas,
                        count(*) filter (where tipo = 'clic')   as clics
                   from jch_links.eventos
                  where ts >= greatest(v_ini at time zone c_tz, v_conteo)
                  group by 1) a on a.d = g;
  end if;

  return jsonb_build_object(
    'rango',         v_rango,
    'por',           case when v_rango = 'hoy' then 'hora' else 'dia' end,
    'ahora',         to_char(v_ahora, 'YYYY-MM-DD"T"HH24:MI:SS'),
    'ultima_visita', v_ultima,
    'totales',       v_totales,
    'botones',       v_botones,
    'fuentes',       v_fuentes,
    'serie',         v_serie);
end $$;

revoke all on all functions in schema jch_links from public, anon, authenticated;

-- ── Única puerta de entrada ───────────────────────────────────────────────────────────────────
-- anon puede ejecutarla; cada operación se protege sola (PIN con tope de intentos, o token de sesión).

create or replace function public.jch_links_rpc(p_op text, p_args jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
begin
  p_args := coalesce(p_args, '{}'::jsonb);

  if p_op = 'evento' then
    return jch_links.registrar(p_args);

  elsif p_op = 'login' then
    return jch_links.login(p_args ->> 'pin', p_args ->> 'ip');

  elsif p_op = 'stats' then
    if not jch_links.sesion_valida(p_args ->> 'token') then
      return jsonb_build_object('ok', false, 'motivo', 'sesion');
    end if;
    return jsonb_build_object('ok', true) || jch_links.estadisticas(p_args ->> 'rango');

  elsif p_op = 'salir' then
    update jch_links.sesiones set expira = now()
     where token_hash = encode(sha256(convert_to(coalesce(p_args ->> 'token', ''), 'utf8')), 'hex');
    return jsonb_build_object('ok', true);
  end if;

  raise exception 'operación desconocida' using errcode = '22023';
end $$;

revoke all on function public.jch_links_rpc(text, jsonb) from public, anon, authenticated;
grant execute on function public.jch_links_rpc(text, jsonb) to anon;

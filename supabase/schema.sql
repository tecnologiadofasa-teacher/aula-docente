-- Aula Docente: esquema para Supabase (versión 2: horario + aula virtual).
-- Ejecuta este archivo completo en Supabase → SQL Editor → New query → Run.
-- Puede ejecutarse de nuevo sin perder datos.
--
-- Docentes: inician sesión con Google o correo. Cada docente solo ve y modifica sus registros.
-- Estudiantes: entran con una sesión anónima + código de clase + eligiendo su nombre de la lista.
--   Solo pueden leer las publicaciones dirigidas a su clase o a ellos, y los archivos adjuntos de esas publicaciones.

-- ¿La sesión es de un docente (no anónima)?
create or replace function public.es_docente() returns boolean
language sql stable as $$
  select coalesce((auth.jwt() ->> 'is_anonymous')::boolean, false) = false
$$;

------------------------------------------------------------------
-- 1. Registros del docente (estudiantes, notas, asistencia, etc.)
------------------------------------------------------------------
create table if not exists public.docs (
  user_id    uuid        not null default auth.uid() references auth.users (id) on delete cascade,
  col        text        not null,
  id         text        not null,
  data       jsonb       not null default '{}'::jsonb,
  updated_at timestamptz not null default now(),
  primary key (user_id, col, id)
);
alter table public.docs enable row level security;
alter table public.docs drop constraint if exists docs_tamano;
alter table public.docs add constraint docs_tamano check (pg_column_size(data) < 400000);

drop policy if exists "docs_select_propios" on public.docs;
drop policy if exists "docs_insert_propios" on public.docs;
drop policy if exists "docs_update_propios" on public.docs;
drop policy if exists "docs_delete_propios" on public.docs;
create policy "docs_select_propios" on public.docs for select to authenticated using ((select auth.uid()) = user_id and public.es_docente());
create policy "docs_insert_propios" on public.docs for insert to authenticated with check ((select auth.uid()) = user_id and public.es_docente());
create policy "docs_update_propios" on public.docs for update to authenticated using ((select auth.uid()) = user_id and public.es_docente()) with check ((select auth.uid()) = user_id);
create policy "docs_delete_propios" on public.docs for delete to authenticated using ((select auth.uid()) = user_id and public.es_docente());

------------------------------------------------------------------
-- 2. Códigos de clase (uno por curso y asignatura)
------------------------------------------------------------------
create table if not exists public.codigos (
  id         uuid primary key default gen_random_uuid(),
  teacher_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  codigo     text not null unique check (codigo ~ '^[A-Z0-9]{6,10}$'),
  curso_id   text not null,
  asig_id    text not null,
  nombre     text not null default '',
  grado      text not null default '',
  docente    text not null default '',
  activo     boolean not null default true,
  created_at timestamptz not null default now(),
  unique (teacher_id, curso_id, asig_id)
);
alter table public.codigos enable row level security;
drop policy if exists "codigos_docente" on public.codigos;
create policy "codigos_docente" on public.codigos for all to authenticated
  using ((select auth.uid()) = teacher_id and public.es_docente())
  with check ((select auth.uid()) = teacher_id and public.es_docente());

------------------------------------------------------------------
-- 3. Matrículas: qué estudiante (sesión) pertenece a qué clase
--    Se crean solo mediante la función unirse_clase.
------------------------------------------------------------------
create table if not exists public.matriculas (
  id         uuid primary key default gen_random_uuid(),
  auth_uid   uuid not null references auth.users (id) on delete cascade,
  teacher_id uuid not null references auth.users (id) on delete cascade,
  codigo_id  uuid not null references public.codigos (id) on delete cascade,
  est_id     text not null,
  curso_id   text not null,
  asig_id    text not null,
  nombre     text not null default '',
  clase      text not null default '',
  docente    text not null default '',
  created_at timestamptz not null default now(),
  unique (auth_uid, codigo_id)
);
create index if not exists matriculas_teacher on public.matriculas (teacher_id);
alter table public.matriculas enable row level security;
drop policy if exists "matriculas_leer" on public.matriculas;
drop policy if exists "matriculas_borrar" on public.matriculas;
create policy "matriculas_leer" on public.matriculas for select to authenticated
  using ((select auth.uid()) = auth_uid or (select auth.uid()) = teacher_id);
create policy "matriculas_borrar" on public.matriculas for delete to authenticated
  using ((select auth.uid()) = auth_uid or (select auth.uid()) = teacher_id);

------------------------------------------------------------------
-- 4. Publicaciones del aula virtual
------------------------------------------------------------------
create table if not exists public.publicaciones (
  id         uuid primary key default gen_random_uuid(),
  teacher_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  titulo     text not null,
  cuerpo     text not null default '',
  clases     text[] not null default '{}',   -- 'cursoId|asignaturaId'
  est_ids    text[] not null default '{}',   -- vacío = todos los estudiantes de esas clases
  archivos   jsonb not null default '[]'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists publicaciones_teacher on public.publicaciones (teacher_id, created_at desc);
alter table public.publicaciones enable row level security;
drop policy if exists "pub_docente" on public.publicaciones;
drop policy if exists "pub_estudiante" on public.publicaciones;
create policy "pub_docente" on public.publicaciones for all to authenticated
  using ((select auth.uid()) = teacher_id and public.es_docente())
  with check ((select auth.uid()) = teacher_id and public.es_docente());
-- Clases activas del estudiante que consulta (lee códigos sin exponerlos al estudiante).
create or replace function public.mis_clases()
returns table (teacher_id uuid, clave text, est_id text)
language sql stable security definer set search_path = public as $$
  select m.teacher_id, m.curso_id || '|' || m.asig_id, m.est_id
  from matriculas m join codigos c on c.id = m.codigo_id
  where m.auth_uid = auth.uid() and c.activo
$$;
revoke all on function public.mis_clases() from public, anon;
grant execute on function public.mis_clases() to authenticated;

create policy "pub_estudiante" on public.publicaciones for select to authenticated
  using (exists (
    select 1 from public.mis_clases() x
    where x.teacher_id = publicaciones.teacher_id
      and x.clave = any (publicaciones.clases)
      and (cardinality(publicaciones.est_ids) = 0 or x.est_id = any (publicaciones.est_ids))
  ));

------------------------------------------------------------------
-- 5. Ingreso del estudiante: código de clase + elegir su nombre de la lista
--    Cada nombre solo puede estar vinculado a una sesión por clase.
--    El docente lo libera con "Quitar acceso".
------------------------------------------------------------------
delete from public.matriculas a using public.matriculas b
 where a.codigo_id = b.codigo_id and a.est_id = b.est_id and a.created_at > b.created_at;
create unique index if not exists matriculas_est_unico on public.matriculas (codigo_id, est_id);

drop function if exists public.unirse_clase(text, text);
drop function if exists public.alumnos_de_clase(text);

-- Lista de nombres de la clase (solo nombres; ningún otro dato del estudiante).
create function public.alumnos_de_clase(p_codigo text)
returns json language plpgsql stable security definer set search_path = public as $$
declare c record;
begin
  if auth.uid() is null then return json_build_object('ok', false, 'error', 'sesion'); end if;
  select * into c from codigos where codigo = upper(trim(p_codigo)) and activo;
  if not found then return json_build_object('ok', false, 'error', 'codigo'); end if;
  return json_build_object('ok', true, 'clase', c.nombre, 'docente', c.docente, 'alumnos', coalesce((
    select json_agg(json_build_object(
             'id', d.id,
             'nombre', trim(coalesce(d.data ->> 'apellidos', '') || ' ' || coalesce(d.data ->> 'nombres', '')),
             'ocupado', exists (select 1 from matriculas m where m.codigo_id = c.id and m.est_id = d.id and m.auth_uid <> auth.uid()),
             'mio', exists (select 1 from matriculas m where m.codigo_id = c.id and m.est_id = d.id and m.auth_uid = auth.uid()))
           order by lower(coalesce(d.data ->> 'apellidos', '')), lower(coalesce(d.data ->> 'nombres', '')))
    from docs d
    where d.user_id = c.teacher_id and d.col = 'ests'
      and d.data ->> 'cursoId' = c.curso_id
      and coalesce((d.data ->> 'activo')::boolean, true)), '[]'::json));
end $$;

create function public.unirse_clase(p_codigo text, p_est_id text)
returns json language plpgsql security definer set search_path = public as $$
declare c record; e record;
begin
  if auth.uid() is null then return json_build_object('ok', false, 'error', 'sesion'); end if;
  select * into c from codigos where codigo = upper(trim(p_codigo)) and activo;
  if not found then return json_build_object('ok', false, 'error', 'codigo'); end if;
  select d.id, d.data into e from docs d
   where d.user_id = c.teacher_id and d.col = 'ests' and d.id = p_est_id
     and d.data ->> 'cursoId' = c.curso_id
     and coalesce((d.data ->> 'activo')::boolean, true);
  if not found then return json_build_object('ok', false, 'error', 'alumno'); end if;
  if exists (select 1 from matriculas m where m.codigo_id = c.id and m.est_id = e.id and m.auth_uid <> auth.uid()) then
    return json_build_object('ok', false, 'error', 'ocupado');
  end if;
  insert into matriculas (auth_uid, teacher_id, codigo_id, est_id, curso_id, asig_id, nombre, clase, docente)
  values (auth.uid(), c.teacher_id, c.id, e.id, c.curso_id, c.asig_id,
          trim(coalesce(e.data ->> 'nombres', '') || ' ' || coalesce(e.data ->> 'apellidos', '')), c.nombre, c.docente)
  on conflict (auth_uid, codigo_id) do update set est_id = excluded.est_id, nombre = excluded.nombre, clase = excluded.clase, docente = excluded.docente;
  return json_build_object('ok', true, 'clase', c.nombre);
exception when unique_violation then
  return json_build_object('ok', false, 'error', 'ocupado');
end $$;

revoke all on function public.alumnos_de_clase(text) from public, anon;
revoke all on function public.unirse_clase(text, text) from public, anon;
grant execute on function public.alumnos_de_clase(text) to authenticated;
grant execute on function public.unirse_clase(text, text) to authenticated;

------------------------------------------------------------------
-- 6. Permisos de tablas
------------------------------------------------------------------
revoke all on public.docs, public.codigos, public.matriculas, public.publicaciones from anon;
grant select, insert, update, delete on public.docs, public.codigos, public.publicaciones to authenticated;
grant select, delete on public.matriculas to authenticated;

------------------------------------------------------------------
-- 7. Archivos del aula virtual (Supabase Storage, depósito privado)
--    Ruta: <id del docente>/<id de la publicación>/<archivo>
------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit)
values ('materiales', 'materiales', false, 10485760)
on conflict (id) do update set public = false, file_size_limit = 10485760;

drop policy if exists "materiales_subir" on storage.objects;
drop policy if exists "materiales_borrar" on storage.objects;
drop policy if exists "materiales_leer" on storage.objects;
create policy "materiales_subir" on storage.objects for insert to authenticated
  with check (bucket_id = 'materiales' and (storage.foldername(name))[1] = (select auth.uid())::text and public.es_docente());
create policy "materiales_borrar" on storage.objects for delete to authenticated
  using (bucket_id = 'materiales' and (storage.foldername(name))[1] = (select auth.uid())::text and public.es_docente());
create policy "materiales_leer" on storage.objects for select to authenticated
  using (bucket_id = 'materiales' and (
    (storage.foldername(name))[1] = (select auth.uid())::text
    or exists (select 1 from public.publicaciones p where p.id::text = (storage.foldername(name))[2])
  ));

------------------------------------------------------------------
-- 8. Institución y coordinación
--    La coordinación solo puede LEER estudiantes, cursos, nombres de
--    asignaturas y asistencia de los docentes de su institución.
--    Nunca calificaciones, actividades ni evidencias.
------------------------------------------------------------------
create or replace function public.gen_codigo() returns text language sql volatile as $$
  select string_agg(substr('ABCDEFGHJKMNPQRSTUVWXYZ23456789', 1 + floor(random() * 31)::int, 1), '')
  from generate_series(1, 7)
$$;

create table if not exists public.instituciones (
  id              uuid primary key default gen_random_uuid(),
  nombre          text not null,
  codigo_docentes text not null unique default public.gen_codigo(),
  codigo_coord    text not null unique default public.gen_codigo(),
  params          jsonb not null default '{"limite":25,"alerta":15,"consecutivos":3}'::jsonb,
  creada_por      uuid references auth.users (id) on delete set null,
  created_at      timestamptz not null default now()
);
create table if not exists public.miembros (
  inst_id    uuid not null references public.instituciones (id) on delete cascade,
  user_id    uuid not null references auth.users (id) on delete cascade,
  rol        text not null check (rol in ('coordinador', 'docente')),
  nombre     text not null default '',
  email      text not null default '',
  created_at timestamptz not null default now(),
  primary key (inst_id, user_id)
);
create unique index if not exists miembros_una_inst on public.miembros (user_id);

create or replace function public.es_coord_de(p_inst uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from miembros where inst_id = p_inst and user_id = auth.uid() and rol = 'coordinador')
$$;
create or replace function public.coord_ve_docente(p_user uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from miembros c join miembros d on d.inst_id = c.inst_id
                 where c.user_id = auth.uid() and c.rol = 'coordinador' and d.user_id = p_user)
$$;
create or replace function public.mi_institucion() returns uuid
language sql stable security definer set search_path = public as $$
  select inst_id from miembros where user_id = auth.uid() limit 1
$$;

alter table public.instituciones enable row level security;
alter table public.miembros enable row level security;
drop policy if exists "inst_leer" on public.instituciones;
drop policy if exists "inst_editar" on public.instituciones;
create policy "inst_leer" on public.instituciones for select to authenticated using (id = public.mi_institucion());
create policy "inst_editar" on public.instituciones for update to authenticated using (public.es_coord_de(id)) with check (public.es_coord_de(id));
drop policy if exists "miembros_leer" on public.miembros;
drop policy if exists "miembros_borrar" on public.miembros;
create policy "miembros_leer" on public.miembros for select to authenticated using (user_id = (select auth.uid()) or public.es_coord_de(inst_id));
create policy "miembros_borrar" on public.miembros for delete to authenticated using (user_id = (select auth.uid()) or public.es_coord_de(inst_id));

-- Lectura de asistencia de los docentes de la institución (solo estas colecciones).
drop policy if exists "docs_coordinacion" on public.docs;
create policy "docs_coordinacion" on public.docs for select to authenticated
  using (col in ('asis', 'ests', 'cursos', 'asigs', 'meta') and public.es_docente() and public.coord_ve_docente(user_id));

create or replace function public.crear_institucion(p_nombre text, p_minombre text, p_email text)
returns json language plpgsql security definer set search_path = public as $$
declare v uuid;
begin
  if auth.uid() is null or not public.es_docente() then return json_build_object('ok', false, 'error', 'sesion'); end if;
  if exists (select 1 from miembros where user_id = auth.uid()) then return json_build_object('ok', false, 'error', 'ya_miembro'); end if;
  if length(trim(coalesce(p_nombre, ''))) < 3 then return json_build_object('ok', false, 'error', 'nombre'); end if;
  insert into instituciones (nombre, creada_por) values (trim(p_nombre), auth.uid()) returning id into v;
  insert into miembros (inst_id, user_id, rol, nombre, email) values (v, auth.uid(), 'coordinador', coalesce(p_minombre, ''), coalesce(p_email, ''));
  return json_build_object('ok', true, 'id', v);
end $$;

create or replace function public.unirse_institucion(p_codigo text, p_nombre text, p_email text)
returns json language plpgsql security definer set search_path = public as $$
declare i record; v_rol text;
begin
  if auth.uid() is null or not public.es_docente() then return json_build_object('ok', false, 'error', 'sesion'); end if;
  if exists (select 1 from miembros where user_id = auth.uid()) then return json_build_object('ok', false, 'error', 'ya_miembro'); end if;
  select * into i from instituciones where codigo_docentes = upper(trim(p_codigo)) or codigo_coord = upper(trim(p_codigo));
  if not found then return json_build_object('ok', false, 'error', 'codigo'); end if;
  v_rol := case when i.codigo_coord = upper(trim(p_codigo)) then 'coordinador' else 'docente' end;
  insert into miembros (inst_id, user_id, rol, nombre, email) values (i.id, auth.uid(), v_rol, coalesce(p_nombre, ''), coalesce(p_email, ''));
  return json_build_object('ok', true, 'nombre', i.nombre, 'rol', v_rol);
end $$;

create table if not exists public.excusas (
  id             uuid primary key default gen_random_uuid(),
  inst_id        uuid not null references public.instituciones (id) on delete cascade,
  curso          text not null,             -- nombre del curso normalizado
  est_key        text not null,             -- nombre del estudiante normalizado
  est_doc        text not null default '',
  est_nombre     text not null default '',
  desde          date not null,
  hasta          date not null,
  motivo         text not null default '',
  soporte        text not null default '',
  estado         text not null default 'pendiente' check (estado in ('pendiente', 'aprobada', 'rechazada')),
  registrada_por uuid default auth.uid(),
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  check (hasta >= desde)
);
-- El observador y convivencia se retiraron de la aplicación (12-nov-2026).
drop table if exists public.convivencia;
create index if not exists excusas_inst on public.excusas (inst_id, desde);
alter table public.excusas enable row level security;
drop policy if exists "excusas_coord" on public.excusas;
create policy "excusas_coord" on public.excusas for all to authenticated using (public.es_coord_de(inst_id)) with check (public.es_coord_de(inst_id));

-- Los docentes solo reciben las fechas de las excusas aprobadas (no el motivo).
alter table public.excusas add column if not exists est_id text not null default '';
drop function if exists public.excusas_aprobadas();
create function public.excusas_aprobadas()
returns table (curso text, est_key text, est_doc text, est_id text, desde date, hasta date)
language sql stable security definer set search_path = public as $$
  select e.curso, e.est_key, e.est_doc, e.est_id, e.desde, e.hasta
  from excusas e join miembros m on m.inst_id = e.inst_id and m.user_id = auth.uid()
  where e.estado = 'aprobada'
$$;

revoke all on function public.crear_institucion(text, text, text), public.unirse_institucion(text, text, text), public.excusas_aprobadas() from public, anon;
grant execute on function public.crear_institucion(text, text, text), public.unirse_institucion(text, text, text), public.excusas_aprobadas() to authenticated;
revoke all on public.instituciones, public.miembros, public.excusas from anon;
grant select, update on public.instituciones to authenticated;
grant select, delete on public.miembros to authenticated;
grant select, insert, update, delete on public.excusas to authenticated;

------------------------------------------------------------------
-- 9. Sincronización eficiente: la fecha de modificación la pone el servidor,
--    para que la aplicación descargue solo lo que cambió.
------------------------------------------------------------------
create or replace function public.marcar_actualizacion() returns trigger language plpgsql as $$
begin new.updated_at := now(); return new; end $$;
drop trigger if exists docs_actualizacion on public.docs;
create trigger docs_actualizacion before insert or update on public.docs
  for each row execute function public.marcar_actualizacion();
create index if not exists docs_usuario_fecha on public.docs (user_id, updated_at);
create index if not exists docs_col_fecha on public.docs (col, updated_at);

------------------------------------------------------------------
-- 10. Listas oficiales (las administra coordinación) y carga académica
--     Coordinación crea cursos, asignaturas y estudiantes; los docentes
--     de la institución solo los leen para armar su carga académica.
------------------------------------------------------------------
create table if not exists public.inst_cursos (
  id         text primary key default replace(gen_random_uuid()::text, '-', ''),
  inst_id    uuid not null references public.instituciones (id) on delete cascade,
  nombre     text not null,
  grado      text not null default '',
  jornada    text not null default '',
  director   text not null default '',
  updated_at timestamptz not null default now(),
  unique (inst_id, nombre)
);
create table if not exists public.inst_asignaturas (
  id         text primary key default replace(gen_random_uuid()::text, '-', ''),
  inst_id    uuid not null references public.instituciones (id) on delete cascade,
  nombre     text not null,
  area       text not null default '',
  updated_at timestamptz not null default now(),
  unique (inst_id, nombre)
);
create table if not exists public.inst_estudiantes (
  id         text primary key default replace(gen_random_uuid()::text, '-', ''),
  inst_id    uuid not null references public.instituciones (id) on delete cascade,
  curso_id   text not null references public.inst_cursos (id) on delete restrict,
  apellidos  text not null default '',
  nombres    text not null default '',
  tipo_doc   text not null default 'TI',
  documento  text not null default '',
  acudiente  text not null default '',
  telefono   text not null default '',
  correo     text not null default '',
  activo     boolean not null default true,
  updated_at timestamptz not null default now()
);
create index if not exists inst_estudiantes_curso on public.inst_estudiantes (inst_id, curso_id);
drop trigger if exists inst_cursos_act on public.inst_cursos;
drop trigger if exists inst_asig_act on public.inst_asignaturas;
drop trigger if exists inst_est_act on public.inst_estudiantes;
create trigger inst_cursos_act before insert or update on public.inst_cursos for each row execute function public.marcar_actualizacion();
create trigger inst_asig_act before insert or update on public.inst_asignaturas for each row execute function public.marcar_actualizacion();
create trigger inst_est_act before insert or update on public.inst_estudiantes for each row execute function public.marcar_actualizacion();

alter table public.inst_cursos enable row level security;
alter table public.inst_asignaturas enable row level security;
alter table public.inst_estudiantes enable row level security;
drop policy if exists "icur_leer" on public.inst_cursos;
drop policy if exists "icur_coord" on public.inst_cursos;
drop policy if exists "iasi_leer" on public.inst_asignaturas;
drop policy if exists "iasi_coord" on public.inst_asignaturas;
drop policy if exists "iest_leer" on public.inst_estudiantes;
drop policy if exists "iest_coord" on public.inst_estudiantes;
create policy "icur_leer" on public.inst_cursos for select to authenticated using (inst_id = public.mi_institucion() and public.es_docente());
create policy "icur_coord" on public.inst_cursos for all to authenticated using (public.es_coord_de(inst_id)) with check (public.es_coord_de(inst_id));
create policy "iasi_leer" on public.inst_asignaturas for select to authenticated using (inst_id = public.mi_institucion() and public.es_docente());
create policy "iasi_coord" on public.inst_asignaturas for all to authenticated using (public.es_coord_de(inst_id)) with check (public.es_coord_de(inst_id));
create policy "iest_leer" on public.inst_estudiantes for select to authenticated using (inst_id = public.mi_institucion() and public.es_docente());
create policy "iest_coord" on public.inst_estudiantes for all to authenticated using (public.es_coord_de(inst_id)) with check (public.es_coord_de(inst_id));
revoke all on public.inst_cursos, public.inst_asignaturas, public.inst_estudiantes from anon;
grant select, insert, update, delete on public.inst_cursos, public.inst_asignaturas, public.inst_estudiantes to authenticated;


-- Aula Docente: esquema para Supabase (versión 2: horario + aula virtual).
-- Ejecuta este archivo completo en Supabase → SQL Editor → New query → Run.
-- Puede ejecutarse de nuevo sin perder datos.
--
-- Docentes: inician sesión con Google o correo. Cada docente solo ve y modifica sus registros.
-- Estudiantes: entran con una sesión anónima + código de clase + número de documento.
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
-- 5. Ingreso del estudiante con código + documento
------------------------------------------------------------------
create or replace function public.unirse_clase(p_codigo text, p_documento text)
returns json language plpgsql security definer set search_path = public as $$
declare
  c record; e record; v_doc text;
begin
  if auth.uid() is null then return json_build_object('ok', false, 'error', 'sesion'); end if;
  v_doc := regexp_replace(lower(coalesce(p_documento, '')), '[^a-z0-9]', '', 'g');
  if length(v_doc) < 4 then return json_build_object('ok', false, 'error', 'documento'); end if;
  select * into c from codigos where codigo = upper(trim(p_codigo)) and activo;
  if not found then return json_build_object('ok', false, 'error', 'codigo'); end if;
  select d.id, d.data into e from docs d
   where d.user_id = c.teacher_id and d.col = 'ests'
     and d.data ->> 'cursoId' = c.curso_id
     and coalesce((d.data ->> 'activo')::boolean, true)
     and regexp_replace(lower(coalesce(d.data ->> 'documento', '')), '[^a-z0-9]', '', 'g') = v_doc
   limit 1;
  if not found then return json_build_object('ok', false, 'error', 'documento'); end if;
  insert into matriculas (auth_uid, teacher_id, codigo_id, est_id, curso_id, asig_id, nombre, clase, docente)
  values (auth.uid(), c.teacher_id, c.id, e.id, c.curso_id, c.asig_id,
          trim(coalesce(e.data ->> 'nombres', '') || ' ' || coalesce(e.data ->> 'apellidos', '')), c.nombre, c.docente)
  on conflict (auth_uid, codigo_id) do update set est_id = excluded.est_id, nombre = excluded.nombre, clase = excluded.clase, docente = excluded.docente;
  return json_build_object('ok', true, 'clase', c.nombre);
end $$;
revoke all on function public.unirse_clase(text, text) from public, anon;
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
values ('materiales', 'materiales', false, 52428800)
on conflict (id) do update set public = false, file_size_limit = 52428800;

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

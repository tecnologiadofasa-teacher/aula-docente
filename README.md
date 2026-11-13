# Aula Docente

Aplicación web para docentes: horario semanal con acceso directo a cada clase, registro de estudiantes con fotografía, cursos, asignaturas, calificaciones con componentes y pesos personalizables, asistencia con códigos propios, observaciones de clase, periodos académicos configurables, evidencias por actividad guardadas en Google Drive y un aula virtual donde los estudiantes, con un código de clase, reciben mensajes, instrucciones y archivos.

Funciona como sitio estático en **GitHub Pages**, con **Supabase** para el inicio de sesión y la base de datos. Cada docente crea su propia cuenta y solo ve sus registros (seguridad por filas, RLS). Se instala en el teléfono como aplicación (PWA) con su propio ícono.

## Estructura

| Archivo | Función |
|---|---|
| `index.html` | Aplicación completa (interfaz y lógica) |
| `config.js` | URL y clave pública de Supabase; ID de cliente de Google (opcional) |
| `supabase/schema.sql` | Tabla y políticas de seguridad |
| `manifest.webmanifest`, `sw.js`, `icons/` | Instalación como aplicación |

## Puesta en marcha

### 1. Supabase

1. Crea un proyecto gratuito en https://supabase.com.
2. En **SQL Editor → New query**, pega el contenido de `supabase/schema.sql` y pulsa **Run**. Crea las tablas, las reglas de seguridad y el depósito privado de archivos `materiales`. Puedes ejecutarlo otra vez cuando se actualice la aplicación; no borra datos.
3. En **Authentication → Sign In / Providers**, activa **Allow anonymous sign-ins**. Es la forma en que entran los estudiantes (sin correo ni contraseña, con el código de clase y eligiendo su nombre). Se recomienda activar también la protección CAPTCHA de Supabase si la dirección se difunde ampliamente.
4. En **Project Settings → API** copia la *Project URL* y la clave **anon** (o *publishable*). No uses nunca la clave `service_role` ni `secret` en el navegador.
5. En **Authentication → URL Configuration**:
   - *Site URL*: `https://TU_USUARIO.github.io/aula-docente/`
   - *Redirect URLs*: agrega la misma dirección.

### 2. Inicio de sesión con Google (recomendado)

1. En https://console.cloud.google.com crea un proyecto y configura la **pantalla de consentimiento OAuth** (tipo *Externo*). Mientras esté en modo *Prueba*, agrega como usuarios de prueba los correos de los docentes; para uso abierto, publícala.
2. En **Credenciales → Crear credenciales → ID de cliente de OAuth → Aplicación web**:
   - *Orígenes de JavaScript autorizados*: `https://TU_USUARIO.github.io`
   - *URI de redireccionamiento autorizados*: `https://TU_PROYECTO.supabase.co/auth/v1/callback`
3. En Supabase, **Authentication → Providers → Google**: activa el proveedor y pega el *Client ID* y el *Client secret*.

El ingreso con correo y contraseña funciona sin este paso (Supabase envía un correo de confirmación al crear la cuenta).

### 3. Evidencias en Google Drive (opcional)

1. En el mismo proyecto de Google Cloud, **APIs y servicios → Biblioteca**: habilita **Google Drive API**.
2. Copia el *Client ID* del paso anterior en `GOOGLE_CLIENT_ID` de `config.js`.

La aplicación solicita el permiso `drive.file`, que solo da acceso a los archivos que ella misma crea. Las evidencias quedan en la carpeta *Aula Docente - Evidencias <año>* del Drive de cada docente, con una subcarpeta por curso y asignatura. Sin este paso, las evidencias se registran con enlaces.

### 4. Configurar y publicar

1. Edita `config.js` con tus valores.
2. Sube todos los archivos a un repositorio público de GitHub llamado `aula-docente`.
3. En el repositorio: **Settings → Pages → Build and deployment → Deploy from a branch**, rama `main`, carpeta `/ (root)`.
4. En uno o dos minutos la aplicación queda en `https://TU_USUARIO.github.io/aula-docente/`.

## Horario y clases

En **Ajustes → Horario de clases** se registran los bloques de la semana (día, hora, curso, asignatura y aula). La vista **Semana** los muestra como calendario; al tocar una clase se abre su panel con acceso directo a la asistencia de ese día, las calificaciones, las evidencias, el aula virtual y las observaciones de la clase (tema y novedades).

## Calificaciones

- **Ajustes → Estructura de la nota** define los ítems y porcentajes por defecto (Actividades 70 %, Evaluación trimestral 20 %, Autoevaluación 10 %). Se pueden agregar otros ítems y aplicar la estructura a todas las asignaturas; cada asignatura puede ajustarse aparte.
- En la planilla, los ítems sin casillas muestran **+ Agregar** para crear su columna con un toque (por ejemplo, la evaluación trimestral).
- **Ajustes → Escala de valoración** define los niveles de desempeño, sus rangos y su color; las notas se colorean según el nivel.
- **Estadísticas** (en Calificaciones) muestra un gráfico circular por nivel de desempeño, promedio, mediana, nota más alta y más baja y porcentaje de aprobación, del periodo o del acumulado anual, para un curso o todos los cursos de la asignatura. Se descarga como imagen.
- **Ajustes → Periodos académicos** incluye accesos rápidos para 3 trimestres o 4 periodos.

## Aula virtual y acceso de estudiantes

1. En **Aula virtual**, genera un código para cada clase (curso + asignatura) y usa **Copiar invitación** para enviarlo por WhatsApp o correo.
2. El estudiante abre la dirección de la aplicación, elige **Soy estudiante**, escribe el código y toca su nombre en la lista del curso. Cada nombre queda vinculado a un solo dispositivo: si alguien ya lo eligió aparece como “Ya ingresó”. Si un estudiante eligió un nombre equivocado o cambió de teléfono, usa **Quitar acceso** para liberar el nombre.
3. Las publicaciones (mensaje, instrucciones, archivos de hasta 50 MB y enlaces) se dirigen a una o varias clases, a todo un grado o solo a algunos estudiantes.
4. El estudiante solo ve las publicaciones dirigidas a su clase o a él; no ve notas, asistencia ni datos de compañeros.
5. **Cambiar** el código impide nuevos ingresos con el anterior; **Desactivar** bloquea a toda la clase; **Quitar acceso** desconecta a un estudiante. Al eliminar o retirar un estudiante también se le quita el acceso.

## Instalar en el teléfono

- **Android**: abre la dirección en Chrome, inicia sesión y toca **Instalar** (aviso en Inicio o en Ajustes), o ⋮ → **Instalar aplicación**.
- **iPhone**: en Safari, **Compartir → Agregar a inicio**.

Para generar un APK a partir de la aplicación publicada se puede usar https://www.pwabuilder.com con la dirección de GitHub Pages.

## Compartir con otros docentes

Comparte la dirección de GitHub Pages. Cada docente crea su cuenta y empieza con un espacio vacío; nadie ve los datos de otro. Si prefieres que cada institución tenga su propia base de datos, se repite la puesta en marcha con otro proyecto de Supabase.

## Seguridad y datos personales

- La clave de `config.js` es pública por diseño; la protección la dan las políticas RLS de `schema.sql`.
- Las sesiones de estudiante (anónimas) no pueden leer ni escribir los registros del docente; solo leen sus publicaciones y los archivos adjuntos de estas, mediante enlaces firmados que vencen en una hora.
- El acceso de estudiantes depende del código de clase. Quien tenga el código ve la lista de nombres del curso (solo nombres). Revisa en **Estudiantes conectados** que cada nombre corresponda a quien es, y si un código circula fuera de la clase, cámbialo.
- Las fotografías se guardan como miniaturas dentro de la base de datos.
- Los datos de menores requieren la autorización de los acudientes (Ley 1581 de 2012). La ficha del estudiante incluye un campo para registrarla.
- **Ajustes → Copia de seguridad** descarga todos los registros en un archivo `.json` que puede restaurarse.

## Límites del plan gratuito de Supabase

500 MB de base de datos y 1 GB de archivos (adjuntos del aula virtual). Con miniaturas de unos 20 KB por estudiante, alcanza para varios miles de estudiantes con sus notas y asistencias. Los proyectos gratuitos se pausan tras una semana sin actividad y se reactivan desde el panel de Supabase.

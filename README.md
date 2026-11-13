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
- **Ajustes → Periodos académicos** incluye accesos rápidos para 3 trimestres o 4 periodos; al agregar o quitar un periodo los porcentajes se reparten de nuevo para sumar 100 %.

## Informes de asistencia

En **Asistencia**:
- **Consolidado**: asistencia y marcas de uniforme por estudiante, por curso o todos los cursos, por asignatura o todas, por periodo o entre fechas (por ejemplo, del inicio del trimestre a hoy). Se descarga en CSV o se copia como resumen.
- **Inasistencias del día**: estudiantes con falta en la fecha elegida, por curso, con mensaje listo para el grupo de WhatsApp del curso y botón para escribir a cada acudiente (si su teléfono está en la ficha). Opcionalmente incluye faltas con excusa, tardanzas y uniforme. Las plantillas de mensaje se editan ahí mismo.
- Los informes incluyen las clases en las que el docente tomó asistencia.

## Listas oficiales y carga académica

Cuando el colegio usa el módulo de coordinación, los docentes **no** registran estudiantes:

1. Coordinación, en **Coordinación → Listas oficiales**, importa los estudiantes (copiando desde Excel las columnas Curso · Apellidos · Nombres · Documento · Acudiente · Teléfono; los cursos se crean solos) y registra el catálogo de asignaturas. Puede volver a importar la lista: los estudiantes existentes se actualizan, no se duplican.
2. Cada docente, en **Ajustes → Mi carga académica**, marca sus asignaturas y los cursos de cada una (con atajo "todo el grado"). Sus estudiantes aparecen automáticamente.
3. El docente puede tomar la foto, escribir observaciones y registrar la autorización de datos, pero no cambia nombres ni crea o borra estudiantes. Los cambios de coordinación (nuevos estudiantes, retiros, cambios de curso) llegan a cada docente al abrir la aplicación.
4. Como todos usan los mismos identificadores, coordinación reconoce a cada estudiante sin depender de cómo se escriba su nombre.

## Módulo de coordinación

1. En la pantalla de ingreso, la coordinadora elige la pestaña **Coordinación**, crea su cuenta e ingresa. La aplicación le muestra directamente **Crear la institución** (o unirse con el código de coordinación). Recibe dos códigos: uno para docentes y otro para otras personas de coordinación.
   - En **Listas oficiales**: **Elegir cursos** (cuadrícula de primaria y bachillerato, por ejemplo 1001 a 1004), **Asignaturas sugeridas** (áreas obligatorias de la Ley 115 de 1994, arts. 23 y 31, más las que agregue el colegio) e **Importar estudiantes**. Para cambiar estudiantes de curso, se marcan en la lista y se elige el curso de destino.
   - La coordinación no ve opciones propias del docente (forma de calificar, horario, Google Drive).
2. Cada docente escribe el código en **Ajustes → Institución**.
3. En **Coordinación** aparecen:
   - **Hoy**: inasistencias del día de todos los cursos, sin importar qué docente tomó la lista; se actualiza cada minuto. Mensaje para el grupo del curso y WhatsApp al acudiente.
   - **Consolidado**: asistencia y uniforme por rango de fechas o por trimestre, con CSV.
   - **Alertas**: estudiantes que superan el porcentaje de inasistencia definido en el SIEE (crítico y preventivo) o que llevan varios días seguidos sin asistir.
   - **Excusas**: al aprobarlas, las faltas de esas fechas cuentan como justificadas en todas las asignaturas. Los docentes ven que la falta está excusada, pero no el motivo.
   - **Institución**: códigos, miembros y parámetros de alertas.

La coordinación **no** tiene acceso a calificaciones, actividades, evidencias ni al aula virtual de los docentes; la base de datos lo impide. Los estudiantes de un mismo curso registrados por distintos docentes se reconocen por el nombre del curso y el nombre completo (o el documento), así que conviene que todos usen el mismo nombre de curso y la misma lista.

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

## Capacidad y límites (colegio de unos 600 estudiantes)

Estimación para un año con 25 docentes, 20 cursos y registro diario de asistencia:

| Concepto | Estimación anual | Plan gratuito |
|---|---|---|
| Base de datos (estudiantes con foto en la lista de cada docente, asistencia, notas) | 150 a 300 MB | 500 MB |
| Archivos del aula virtual (Supabase Storage) | depende del uso | 1 GB |
| Transferencia mensual (egress) | 1 a 3 GB con la caché local | 5 GB |
| Usuarios activos (docentes + estudiantes) | unos 650 | 50.000 |

Medidas incluidas: la aplicación guarda una copia local en el dispositivo y solo descarga lo que cambió; la coordinación no descarga fotos; las fotos se reducen a miniaturas de unos 8 KB; los adjuntos del aula virtual tienen un máximo de 10 MB (lo más pesado se comparte como enlace de Drive).

Puntos a tener en cuenta:
- **Pausa por inactividad**: el plan gratuito pausa el proyecto tras 7 días sin uso (vacaciones). Los datos no se pierden; se reactiva desde el panel de Supabase.
- **Sin copias automáticas** en el plan gratuito: descarga periódicamente la copia de seguridad (.json) desde Ajustes.
- **Correos de registro**: el servicio de correo incluido en Supabase envía muy pocos correos por hora. Para registrar a muchos docentes con correo y contraseña, configura un SMTP propio (Authentication → Emails → SMTP) o usa el ingreso con Google.
- **Ingreso de estudiantes desde la misma red**: Supabase limita los ingresos anónimos a 30 por hora por dirección IP. Si un salón entero entra desde el wifi del colegio, sube ese límite en Authentication → Rate Limits.
- **Crecimiento**: al terminar el año, descarga la copia y elimina los cursos antiguos; si la base supera unos 400 MB, el plan Pro (25 USD al mes) da 8 GB, 250 GB de transferencia y copias diarias.
- **Datos personales**: la base de datos queda en servidores de Supabase fuera de Colombia; la institución debe contar con su política de tratamiento de datos y la autorización de las familias (Ley 1581 de 2012).

/* Configuración de Aula Docente.
   1. SUPABASE_URL y SUPABASE_KEY: en Supabase → Project Settings → API (URL del proyecto y clave
      "anon" o "publishable"). Esta clave es pública por diseño; la seguridad la dan las políticas RLS
      de supabase/schema.sql. NUNCA pongas aquí la clave "service_role" o "secret".
   2. GOOGLE_CLIENT_ID (opcional): ID de cliente OAuth web de Google Cloud, para subir evidencias a
      Google Drive. Si lo dejas vacío, las evidencias se registran con enlaces. */
window.AULA_CONFIG = {
  SUPABASE_URL: "https://kxjizqrbcyfqzdwmufzg.supabase.co",
  SUPABASE_KEY: "sb_publishable_Rc6g76ZZMmdIV509jkpmWQ__N7M0HfR",
  GOOGLE_CLIENT_ID: ""
};

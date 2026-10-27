# Notificaciones de FINANCE

La actualización añade **Configuración → Notificaciones en este dispositivo → Activar**.
Cada integrante debe activarlas desde su propio celular, dentro del mismo hogar.
En iPhone, abre FINANCE desde el icono añadido a la pantalla de inicio (iOS 16.4 o posterior).

Los avisos se generan al guardar, editar o eliminar ingresos, gastos, aportes y transferencias.
Llegan a los dispositivos activados de ambos integrantes, incluido quien hizo el cambio.
Muestran el tipo de movimiento, el monto y la caja correspondiente, incluido el nombre de
la caja personal o de la meta. Por ejemplo: “Gasto de $12,50 desde Moto.” Los ingresos
compartidos indican “Cajas del hogar (repartido)” porque financian varias cajas. En una
transferencia aparecen la caja de origen y la de destino. Los avisos de edición y eliminación
indican esa acción y el valor del movimiento; no son nuevos ingresos ni gastos.
No incluyen la descripción del movimiento. Tocarlos abre Movimientos después de iniciar
sesión, si corresponde. Un formulario abierto se conserva hasta guardarlo o cerrarlo.

Cada aviso conserva el monto y la cuenta del momento del cambio. Los avisos antiguos o
los guardados con varios movimientos a la vez pueden conservar el mensaje general.
Para recibir el nuevo formato, publica también `sw.js` y vuelve a abrir FINANCE en ambos
celulares con conexión para que actualicen su componente de notificaciones.

El cierre automático por inactividad conserva los avisos. **Cerrar sesión** manualmente
intenta desactivarlos en ese dispositivo. También puedes desactivarlos en Configuración.
Sin conexión, el aviso espera al guardado en Supabase. La entrega puede demorarse por la red,
los modos de concentración o el sistema operativo; no se garantiza entrega instantánea.

## Activación del servidor (una vez)

El código está preparado, pero necesita estos pasos en Supabase antes de enviar avisos:

1. Ejecutar `supabase/notifications.sql` después de `supabase/schema.sql`.
2. Generar una pareja VAPID una sola vez con `web-push.generateVAPIDKeys()` y conservarla privada.
3. Guardar en Edge Functions → Secrets:
   - `FINANCE_VAPID_PUBLIC_KEY`
   - `FINANCE_VAPID_PRIVATE_KEY`
   - `FINANCE_VAPID_SUBJECT=https://andresrsr.github.io/finanzas/`
   - `FINANCE_PUSH_SECRET` (32 bytes aleatorios o más, codificados base64url).
4. Desplegar `supabase/functions/finance-push`, usando `supabase/config.toml`.
   Mantén **Verify JWT with legacy secret activado** (`verify_jwt = true`). Además,
   la función verifica `x-finance-dispatch-secret`; las llamadas de usuarios continúan
   requiriendo sesión. No publicar ninguna clave privada en `config.js` o GitHub.
5. Ejecutar como administrador, sustituyendo los valores privados:

   ```sql
   select finance_private.configure_push(
     'https://ggrmlmzdtwvxfptarhsx.supabase.co/functions/v1/finance-push',
     'EL_MISMO_FINANCE_PUSH_SECRET',
     'FINANCE_VAPID_PUBLIC_KEY'
   );
   select finance_private.configure_push_gateway('CLAVE_PUBLICA_ANON_HEREDADA_JWT');
   ```

   La clave `anon` heredada está en Project Settings → API Keys → Legacy.
   Es pública; no uses `service_role`. Permite pasar la comprobación JWT de la plataforma,
   pero no puede enviar avisos sin el secreto privado del servidor.

Hay un asistente local en `Activar-notificaciones.ps1` que realiza estos pasos con el
CLI oficial de Supabase. Pide iniciar sesión en Supabase y la contraseña de la base de
datos, conserva las claves en `.qa/.finance-push.env` y verifica TLS con el certificado
oficial. No cambia contraseñas ni registra movimientos de prueba. Reutiliza las claves
existentes al volver a ejecutarlo.

## Publicación y comprobación

Publica juntos `index.html`, `sw.js` y los iconos existentes de `assets/` en GitHub Pages.
Después de publicar, abre la app, recarga e ingresa a Configuración. Activa los avisos en
los dos celulares. El siguiente movimiento que realmente necesites registrar sirve para
comprobar la recepción; no hace falta alterar saldos con registros ficticios.

Si reejecutas `schema.sql`, ejecuta después `notifications.sql` porque el primero
restablece permisos privados. No expongas `finance_private` ni `net` en Data API.
Los reintentos de guardado se deduplican por revisión. Los envíos se reintentan hasta cinco
veces durante 24 horas; un envío cuya respuesta se pierde puede repetirse con la misma
etiqueta, para reemplazar el aviso anterior. Las suscripciones inválidas se retiran.

Referencias: [Web Push en iOS](https://webkit.org/blog/13878/web-push-for-web-apps-on-ios-and-ipados/),
[Edge Functions](https://supabase.com/docs/guides/functions/deploy),
[cifrado Web Push](https://github.com/web-push-libs/web-push).

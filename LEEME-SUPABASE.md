# FINANCE: usarlo juntos con Supabase

GitHub Pages publicará la aplicación. Supabase guardará el historial compartido y comprobará el acceso de cada integrante. Cada persona entrará con su propio correo y contraseña; ambas verán el mismo hogar.

## 1. Guarda tu historial actual

Antes de configurar la nube, abre la aplicación original en el navegador donde están tus datos. En **Configuración**, pulsa **Exportar datos JSON** y guarda el archivo fuera de la carpeta que publicarás.

Si abres la aplicación original con una dirección `file://`, sus datos del navegador no aparecerán automáticamente en GitHub Pages. Usarás ese JSON para crear el hogar compartido. Conserva el archivo original y el respaldo hasta comprobar la migración en ambos dispositivos.

## 2. Crea el proyecto y prepara la base de datos

Si ya tienes el proyecto de FINANCE en Supabase, utiliza ese mismo proyecto y sigue la actualización indicada al final de esta sección. No necesitas crear otro.

1. Entra en el [panel de Supabase](https://supabase.com/dashboard) y crea un proyecto nuevo para esta aplicación.
2. Elige un nombre, una región y una contraseña de base de datos. Guarda esa contraseña en privado; no se escribe en la aplicación.
3. Cuando el proyecto esté listo, abre **SQL Editor** y una consulta nueva.
4. Abre el archivo `supabase/schema.sql` de esta entrega, copia todo su contenido, pégalo en el editor y pulsa **Run**.
5. Comprueba que la ejecución termine sin errores antes de seguir. El archivo prepara las tablas, funciones y permisos que necesita la aplicación. No crees ni edites los movimientos financieros desde el editor SQL.

Supabase documenta el uso de su [editor SQL y base de datos](https://supabase.com/docs/guides/database/overview).

### Actualizar un proyecto que ya tiene datos

1. Exporta una copia JSON de los datos actuales de cada hogar que vayan a conservar.
2. En el mismo proyecto de Supabase, abre **SQL Editor** y una consulta nueva.
3. Copia **todo el contenido de la versión actual de `supabase/schema.sql`**, pégalo y ejecútalo de nuevo con **Run**.
4. Comprueba que termine sin errores. Después publica la versión actual de la aplicación y recarga la página en ambos dispositivos.

El script está preparado para volver a ejecutarse sin eliminar los hogares ni sus movimientos existentes. Actualiza las funciones y permisos necesarios para cambiar de hogar, consultar los respaldos privados y usar las invitaciones de 10 minutos. No borres tablas ni reinicies la base de datos para actualizar. Publicar el HTML por sí solo no actualiza estas funciones de Supabase.

## 3. Crea las dos cuentas de acceso

Hazlo desde el panel del proyecto, una vez por cada persona:

1. Abre **Authentication → Users**.
2. Pulsa **Add user → Create new user**.
3. Introduce el correo real de esa persona y una contraseña propia para su cuenta.
4. Marca **Auto Confirm User** y crea el usuario.
5. Repite los pasos para el segundo integrante. Comprueba que ambos usuarios estén confirmados.

Después abre **Authentication → Sign In / Providers**. Mantén habilitado el acceso por correo y contraseña, desactiva **Allow new users to sign up** y guarda el cambio. Así pueden entrar las cuentas que acabas de crear, sin habilitar registros públicos. La [configuración oficial de Auth](https://supabase.com/docs/guides/auth/general-configuration) explica esta opción; las cuentas se gestionan en [Authentication → Users](https://supabase.com/docs/guides/auth/users).

Este procedimiento no necesita enviar correos de confirmación. El servicio de correo predeterminado de Supabase solo entrega mensajes a direcciones autorizadas del equipo del proyecto; para enviar confirmaciones, invitaciones de Auth o recuperación de contraseñas a otras direcciones hace falta configurar [SMTP propio](https://supabase.com/docs/guides/auth/auth-smtp). El código para unirse al hogar que se explica más abajo lo genera nuestra aplicación y se comparte directamente con la pareja.

## 4. Completa `config.js`

En Supabase, abre **Connect** para encontrar la URL del proyecto. La clave pública se obtiene en **Settings → API Keys**, en la sección de claves publicables.

Edita `config.js` y coloca esos dos valores entre comillas:

```js
window.FINANZAS_CLOUD = {
  url: 'https://TU-PROYECTO.supabase.co',
  publishableKey: 'sb_publishable_TU_CLAVE_PUBLICA'
};
```

La URL debe ser la del proyecto, no la dirección del panel de Supabase. Utiliza la **publishable key**. Nunca pongas una clave `secret`, `sb_secret_…`, `service_role`, la contraseña de la base de datos ni las contraseñas de los usuarios en este archivo.

La clave publicable está diseñada para aparecer en una página web; el acceso a los datos depende de la sesión y de los permisos preparados por `schema.sql`. Las claves secretas tienen privilegios elevados y no deben publicarse. Consulta la [guía oficial de claves API](https://supabase.com/docs/guides/getting-started/api-keys).

## 5. Publica en GitHub Pages

El repositorio ya existe: [AndresRsR/finanzas](https://github.com/AndresRsR/finanzas). Su carpeta local es `C:\Users\LENOVO\OneDrive\Documents\finanzas`. Los archivos de la web se publican directamente desde su raíz; no hace falta crear otro repositorio ni una carpeta de publicación adicional.

1. Comprueba que el `config.js` de esa carpeta contiene los valores del paso anterior. Si también utilizas otra copia local de la aplicación, actualiza el `config.js` que está junto a su `index.html`.
2. Sube los archivos actualizados a la raíz del repositorio, conservando la carpeta `vendor`. Deben quedar allí `index.html`, `config.js`, `manifest.webmanifest`, `.nojekyll` y los archivos de `assets/` y `vendor/`.
3. En el repositorio abre **Settings → Pages**. En **Build and deployment**, selecciona **Deploy from a branch**, la rama `main` y la carpeta `/(root)`. Guarda.
4. Espera a que GitHub publique el sitio y abre el enlace que aparece en Pages. Para este repositorio, la dirección habitual es `https://andresrsr.github.io/finanzas/`; utiliza la que confirme el panel.
5. Activa **Enforce HTTPS** cuando esté disponible. Guarda ese enlace como favorito en ambos dispositivos.

GitHub explica cómo [elegir la fuente de publicación](https://docs.github.com/en/pages/getting-started-with-github-pages/configuring-a-publishing-source-for-your-github-pages-site) y [activar HTTPS](https://docs.github.com/en/pages/getting-started-with-github-pages/securing-your-github-pages-site-with-https). El archivo de entrada debe estar en la carpeta publicada; consulta también [crear un sitio de GitHub Pages](https://docs.github.com/en/pages/getting-started-with-github-pages/creating-a-github-pages-site).

La aplicación usa rutas relativas para `config.js` y `vendor/`, por lo que funciona dentro de `/finanzas/` u otro nombre de repositorio. Conserva esas rutas: una ruta que empiece por `/config.js` buscaría el archivo fuera de la subcarpeta del proyecto.

En Supabase puedes establecer la dirección HTTPS completa, incluida la subcarpeta, en **Authentication → URL Configuration → Site URL**. Si habilitas en el futuro flujos de correo que redirigen a la aplicación, configura también sus direcciones de retorno según la [documentación de Redirect URLs](https://supabase.com/docs/guides/auth/redirect-urls).

### Qué se puede publicar

| Archivo o contenido | Dónde conservarlo |
| --- | --- |
| `index.html`, `config.js` con URL y clave publicable, `manifest.webmanifest`, `assets/`, `vendor/`, `.nojekyll` | En el repositorio y GitHub Pages. |
| Esta guía y `supabase/schema.sql` sin datos personales | Pueden estar en un repositorio de código; no son necesarios para servir la página. El SQL se ejecuta en Supabase. |
| Respaldos JSON reales, exportaciones CSV/PDF, capturas con tus cifras o correos | En una ubicación privada, fuera de la carpeta de publicación. |
| Contraseñas, claves secretas, sesiones y tokens de acceso | En privado; nunca en GitHub ni en archivos de la web. |

Sube únicamente los archivos de la web indicados arriba. No copies toda la carpeta de desarrollo al repositorio: puede contener respaldos y capturas. La pantalla de acceso protege la información que guarda Supabase; no convierte los archivos publicados en GitHub Pages en privados.

## 6. Crea el hogar e invita a tu pareja

La primera persona hace estos pasos:

1. Abre la página HTTPS e inicia sesión con su cuenta del paso 3.
2. Elige crear el hogar. Selecciona el JSON exportado en el paso 1. Si la aplicación ofrece datos originales guardados en ese mismo navegador, puedes elegirlos explícitamente después de comprobar que son los correctos.
3. Pulsa **Crear hogar con esta copia**. Espera la confirmación del guardado y revisa los meses, movimientos y saldos. Crear el hogar es el momento de copiar el historial a Supabase; iniciar sesión por sí solo no migra datos.
4. Abre **Mi hogar → Invitar a mi pareja**, introduce exactamente el correo con el que creaste la segunda cuenta y genera el código.
5. Pulsa **Copiar código** y compártelo directamente con tu pareja. Si el navegador no permite copiar automáticamente, selecciona el texto del código y cópialo manualmente. No es necesario darle acceso al panel de administración de Supabase.

La segunda persona abre la misma página, inicia sesión con su propia cuenta y pulsa **Unirme al hogar**. Introduce el código recibido. Debe unirse al hogar existente para compartir el historial; crear otro hogar produciría un espacio separado.

Cada código nuevo vence **10 minutos después de generarse**. La cuenta atrás muestra lo que queda. Puedes volver a abrir y copiar el código vigente desde **Invitar a mi pareja** en el mismo navegador, incluso después de cerrar e iniciar sesión; esto no reinicia su plazo. Generar otro código para el mismo correo no cancela los anteriores que aún estén vigentes. Si ya venció, genera uno nuevo y comparte ese código.

Comprueba un ingreso o gasto existente desde ambos dispositivos. El mes seleccionado y la apariencia clara u oscura son preferencias de cada navegador y pueden ser diferentes.

### Si ambos ya crearon un hogar

Elijan cuál será el hogar que compartirán. Los movimientos de ambos hogares no se suman automáticamente.

1. La persona que conservará su hogar entra en **Mi hogar → Invitar a mi pareja** y genera un código para el correo de la otra persona.
2. La otra persona inicia sesión en su hogar actual y abre **Mi hogar → Unirme al hogar de mi pareja**. No necesita volver a la pantalla inicial ni crear otra cuenta.
3. Introduce el código, revisa la confirmación y pulsa **Guardar copia y unirme**. Ese botón descarga automáticamente un respaldo JSON del hogar actual antes de solicitar el cambio. Conserva el archivo descargado en una ubicación privada.
4. Tras confirmar, ambos verán el historial del hogar elegido. Revisa las cifras antes de registrar nuevos movimientos.

Este cambio solo está permitido si quien se une es el propietario y **único integrante de su hogar actual**. Si ya hay otra persona en ese hogar, la aplicación no permite abandonarlo mediante esta opción. El hogar de destino debe tener espacio para el segundo integrante y el código debe corresponder al correo con el que se inició sesión.

El historial del hogar que dejas se conserva como un respaldo privado. Desde **Mi hogar → Respaldos de hogares anteriores** puedes descargar su copia JSON. Solo su propietario puede consultar esos respaldos; no se incorporan al hogar nuevo ni se comparten automáticamente con la pareja.

Si cambiaste de hogar desde otro dispositivo y aquí había un cambio pendiente, la aplicación conserva esa copia sin enviarla al hogar nuevo. Verás un aviso; descárgala desde **Mi hogar → Respaldos de hogares anteriores → Descargar cambio pendiente** en el dispositivo donde la registraste. Revisa qué falta antes de registrar movimientos en el hogar compartido.

Conserva también la copia descargada en una ubicación privada. Si necesitas trasladar algún movimiento del hogar anterior, revísalo y registra únicamente lo que falte. Importar todo su JSON reemplazaría el historial compartido actual; no fusiona los dos hogares.

## 7. Cómo se guardan los cambios

La aplicación consulta cambios compartidos aproximadamente cada **5 segundos** mientras está activa. Los navegadores pueden espaciar las consultas en segundo plano. Un formulario en edición queda protegido para que una actualización no borre lo que estás escribiendo.

Cuando ambos guardan sobre la misma versión, uno puede recibir un conflicto. El cambio pendiente se conserva y no se impone sobre el de la otra persona. Usa **Descargar cambio pendiente** para guardar una copia y **Revisar datos compartidos** para comparar con el historial actualizado. Revisa qué falta y vuelve a registrarlo sobre la versión actual; restaurar un JSON completo reemplaza datos, no combina automáticamente los movimientos.

Si se pierde la conexión al guardar, puede quedar **un cambio pendiente**. La aplicación bloquea nuevos cambios financieros hasta resolverlo; no acumula una lista de movimientos sin conexión. Recupera la conexión y sigue las opciones del aviso. Si se cierra la sesión, vuelve a entrar con la misma cuenta en el mismo navegador para recuperar ese cambio. Conserva el respaldo pendiente antes de borrar datos del navegador o cambiar de dispositivo.

Importar una copia o reiniciar los datos dentro de un hogar compartido afecta al historial de ambos integrantes. Exporta primero el estado actual y comprueba que el guardado compartido haya terminado. Conserva periódicamente una copia JSON privada aunque uses sincronización.

## 8. Cierre de sesión y uso en el celular

La sesión se cierra después de **5 minutos sin actividad**. La aplicación avisa **30 segundos antes** para que puedas continuar usándola. El tiempo también cuenta cuando cambias a otra aplicación o dejas FINANCE en segundo plano; al volver, tendrás que iniciar sesión si ya transcurrió el plazo.

El cierre por inactividad no elimina el historial compartido. Un cambio que ya enviaste con Guardar y quedó pendiente de sincronización se conserva localmente, asociado a tu cuenta y hogar. Para retomarlo, entra de nuevo con la misma cuenta en ese navegador. Antes de alejarte, guarda los formularios que quieras conservar; escribir en un campo no equivale a confirmar un cambio.

En pantallas pequeñas, los botones y controles tienen áreas táctiles más amplias y los campos usan texto de 16 píxeles para evitar el zoom automático de iPhone. El contenido respeta las zonas del notch y del indicador inferior. En los diálogos, el cuerpo del formulario se puede desplazar y los botones de acción quedan separados de esa zona; con el teclado abierto, desplaza el formulario hasta el campo que necesites.

Las mejoras móviles van incorporadas en el `index.html` compilado. No hace falta añadir un enlace a `mobile.css` en la página publicada.

## Si algo no funciona

- **No aparece la conexión:** comprueba el `config.js` publicado y que `vendor/` esté junto al HTML. Recarga después de terminar la publicación.
- **No permite iniciar sesión:** comprueba correo, contraseña, proyecto y que el usuario esté confirmado en Authentication. La contraseña de la cuenta no es la contraseña de la base de datos.
- **Error de funciones o permisos:** vuelve a ejecutar completo el `supabase/schema.sql` actualizado en el mismo proyecto indicado en `config.js`. Comprueba que termine sin errores; no borres las tablas.
- **No aparecen los datos antiguos:** vuelve al navegador y archivo originales, exporta el JSON y selecciónalo al crear el hogar. GitHub Pages no puede leer el almacenamiento de `file://`.
- **La pareja ya tiene su propio hogar:** usa **Mi hogar → Unirme al hogar de mi pareja**. Debe ser propietaria y única integrante del hogar que deja. **Guardar copia y unirme** descarga automáticamente el respaldo antes de solicitar el cambio.
- **La pareja no puede unirse:** comprueba el correo, la cuenta atrás de 10 minutos y que ambos estén usando la misma página y proyecto. Si el código venció, genera otro. Si falta la nueva opción o función, actualiza tanto el HTML publicado como el SQL de Supabase.
- **Necesitas los datos del hogar anterior:** entra en **Mi hogar → Respaldos de hogares anteriores** y descarga el JSON. Es una copia privada del propietario, no una combinación con el hogar actual.
- **La sesión se cerró al volver al celular:** el plazo de 5 minutos continúa en segundo plano. Inicia sesión otra vez con la misma cuenta; los cambios pendientes guardados localmente se conservan en ese navegador.
- **Cambio pendiente o conflicto:** descarga el cambio, recupera la conexión y revisa los datos compartidos antes de continuar. No borres el almacenamiento del navegador para intentar resolverlo.


## Nombre e icono en el celular

La página, la pantalla de acceso y el nombre al instalarla están configurados como **FINANCE**. Publica también `manifest.webmanifest` y todos los PNG de `assets/`: el navegador utiliza esa configuración para presentar el nombre y el icono de la app ([documentación de instalación](https://developer.mozilla.org/en-US/docs/Web/Progressive_web_apps/Guides/Making_PWAs_installable)).

Si un acceso anterior sigue mostrando la N o el nombre viejo, espera a que termine la publicación en GitHub Pages. Quita ese acceso directo de la pantalla de inicio y vuelve a abrir la dirección HTTPS en el navegador. En el menú, elige **Añadir a la pantalla de inicio** o **Instalar aplicación** y comprueba que indique FINANCE antes de confirmar. El texto exacto del menú depende del navegador. No borres el almacenamiento ni los datos del sitio para cambiar un icono.

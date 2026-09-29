# Nuestro Presupuesto: usarlo juntos con Supabase

GitHub Pages publicará la aplicación. Supabase guardará el historial compartido y comprobará el acceso de cada integrante. Cada persona entrará con su propio correo y contraseña; ambas verán el mismo hogar.

## 1. Guarda tu historial actual

Antes de configurar la nube, abre la aplicación original en el navegador donde están tus datos. En **Configuración**, pulsa **Exportar datos JSON** y guarda el archivo fuera de la carpeta que publicarás.

Si abres la aplicación original con una dirección `file://`, sus datos del navegador no aparecerán automáticamente en GitHub Pages. Usarás ese JSON para crear el hogar compartido. Conserva el archivo original y el respaldo hasta comprobar la migración en ambos dispositivos.

## 2. Crea el proyecto y prepara la base de datos

1. Entra en el [panel de Supabase](https://supabase.com/dashboard) y crea un proyecto nuevo para esta aplicación.
2. Elige un nombre, una región y una contraseña de base de datos. Guarda esa contraseña en privado; no se escribe en la aplicación.
3. Cuando el proyecto esté listo, abre **SQL Editor** y una consulta nueva.
4. Abre el archivo `supabase/schema.sql` de esta entrega, copia todo su contenido, pégalo en el editor y pulsa **Run**.
5. Comprueba que la ejecución termine sin errores antes de seguir. El archivo prepara las tablas, funciones y permisos que necesita la aplicación. No crees ni edites los movimientos financieros desde el editor SQL.

Supabase documenta el uso de su [editor SQL y base de datos](https://supabase.com/docs/guides/database/overview).

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
2. Sube los archivos actualizados a la raíz del repositorio, conservando la carpeta `vendor`. Deben quedar allí `index.html`, `config.js`, `.nojekyll` y los archivos de `vendor/`.
3. En el repositorio abre **Settings → Pages**. En **Build and deployment**, selecciona **Deploy from a branch**, la rama `main` y la carpeta `/(root)`. Guarda.
4. Espera a que GitHub publique el sitio y abre el enlace que aparece en Pages. Para este repositorio, la dirección habitual es `https://andresrsr.github.io/finanzas/`; utiliza la que confirme el panel.
5. Activa **Enforce HTTPS** cuando esté disponible. Guarda ese enlace como favorito en ambos dispositivos.

GitHub explica cómo [elegir la fuente de publicación](https://docs.github.com/en/pages/getting-started-with-github-pages/configuring-a-publishing-source-for-your-github-pages-site) y [activar HTTPS](https://docs.github.com/en/pages/getting-started-with-github-pages/securing-your-github-pages-site-with-https). El archivo de entrada debe estar en la carpeta publicada; consulta también [crear un sitio de GitHub Pages](https://docs.github.com/en/pages/getting-started-with-github-pages/creating-a-github-pages-site).

La aplicación usa rutas relativas para `config.js` y `vendor/`, por lo que funciona dentro de `/finanzas/` u otro nombre de repositorio. Conserva esas rutas: una ruta que empiece por `/config.js` buscaría el archivo fuera de la subcarpeta del proyecto.

En Supabase puedes establecer la dirección HTTPS completa, incluida la subcarpeta, en **Authentication → URL Configuration → Site URL**. Si habilitas en el futuro flujos de correo que redirigen a la aplicación, configura también sus direcciones de retorno según la [documentación de Redirect URLs](https://supabase.com/docs/guides/auth/redirect-urls).

### Qué se puede publicar

| Archivo o contenido | Dónde conservarlo |
| --- | --- |
| `index.html`, `config.js` con URL y clave publicable, `vendor/`, `.nojekyll` | En el repositorio y GitHub Pages. |
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
5. Comparte ese código directamente con tu pareja. No es necesario darle acceso al panel de administración de Supabase.

La segunda persona abre la misma página, inicia sesión con su propia cuenta y pulsa **Unirme al hogar**. Introduce el código recibido. Debe unirse al hogar existente para compartir el historial; crear otro hogar produciría un espacio separado.

Comprueba un ingreso o gasto existente desde ambos dispositivos. El mes seleccionado y la apariencia clara u oscura son preferencias de cada navegador y pueden ser diferentes.

## 7. Cómo se guardan los cambios

La aplicación consulta cambios compartidos aproximadamente cada **5 segundos** mientras está activa. Los navegadores pueden espaciar las consultas en segundo plano. Un formulario en edición queda protegido para que una actualización no borre lo que estás escribiendo.

Cuando ambos guardan sobre la misma versión, uno puede recibir un conflicto. El cambio pendiente se conserva y no se impone sobre el de la otra persona. Usa **Descargar cambio pendiente** para guardar una copia y **Revisar datos compartidos** para comparar con el historial actualizado. Revisa qué falta y vuelve a registrarlo sobre la versión actual; restaurar un JSON completo reemplaza datos, no combina automáticamente los movimientos.

Si se pierde la conexión al guardar, puede quedar **un cambio pendiente**. La aplicación bloquea nuevos cambios financieros hasta resolverlo; no acumula una lista de movimientos sin conexión. Recupera la conexión y sigue las opciones del aviso. Mantén abierto el navegador y conserva el respaldo pendiente antes de borrar sus datos o cambiar de dispositivo.

Importar una copia o reiniciar los datos dentro de un hogar compartido afecta al historial de ambos integrantes. Exporta primero el estado actual y comprueba que el guardado compartido haya terminado. Conserva periódicamente una copia JSON privada aunque uses sincronización.

## Si algo no funciona

- **No aparece la conexión:** comprueba el `config.js` publicado y que `vendor/` esté junto al HTML. Recarga después de terminar la publicación.
- **No permite iniciar sesión:** comprueba correo, contraseña, proyecto y que el usuario esté confirmado en Authentication. La contraseña de la cuenta no es la contraseña de la base de datos.
- **Error de funciones o permisos:** revisa que `supabase/schema.sql` terminara sin errores en el mismo proyecto indicado en `config.js`.
- **No aparecen los datos antiguos:** vuelve al navegador y archivo originales, exporta el JSON y selecciónalo al crear el hogar. GitHub Pages no puede leer el almacenamiento de `file://`.
- **La pareja no puede unirse:** comprueba que inició sesión con el correo al que dirigiste el código y que está usando la misma página y proyecto. Si el código ya no sirve, genera otro desde el hogar.
- **Cambio pendiente o conflicto:** descarga el cambio, recupera la conexión y revisa los datos compartidos antes de continuar. No borres el almacenamiento del navegador para intentar resolverlo.

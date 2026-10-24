# Jardines Club Hípico · página de enlaces

Una sola página: `index.html` (HTML + CSS + JS, sin dependencias ni build), más el panel de analíticas
`/admin` (`admin.html`) y las funciones de `api/` que lo alimentan.

## Publicación
Sitio: https://jch-links.vercel.app

El repositorio está conectado a Vercel (proyecto `jch-links`, framework: Other, sin comando de build):
cada cambio que se sube a la rama `main` se publica solo, en un minuto aproximadamente.
Las funciones de `api/` también se publican solas.

## Qué se puede cambiar
- **Botones y textos:** bloque `<ul class="links">` de `index.html` (5 enlaces). Cada botón lleva `data-b="nombre"`
  para contar sus clics; si agregas un botón nuevo, ponle un `data-b` y agrégalo también a `BOTONES` en `api/_lib.js`.
- **Dirección:** en el botón «Cómo llegar», el texto y el parámetro `query=` del enlace de Google Maps.
- **Fotos de fondo:** `assets/bg/NN.webp` (horizontal) y `NN-m.webp` (vertical, 9:16). Son 8 pares.
- **Tiempo de cada foto:** `INTERVALO` (ms) al inicio del primer `<script>`.
- **Vista previa al compartir (WhatsApp, Facebook):** `og.jpg` (1200×630) y las etiquetas `og:` del `<head>`.
  Usan la URL completa del sitio; si cambia el dominio hay que cambiarlas.
- **Logo:** el sello del encabezado es un SVG dentro de `index.html`: el emblema (`assets/logo.webp`) con el
  nombre en arco, letra Cinzel convertida a trazos. El tamaño se ajusta solo a la altura de la pantalla
  (variables `--mark`, `--pt`, `--gap`… al inicio del CSS).
- **Pie de página:** «Made by Morphiq» al final de `index.html`.

## Analíticas (visitas y clics)
Cada vez que se abre la página cuenta **una visita** y cada toque a un botón cuenta **un clic**. No usa cookies ni
guarda la IP ni datos personales: solo un id aleatorio guardado en el dispositivo (para contar personas distintas).

**Panel:** https://jch-links.vercel.app/admin — pide un PIN de 4 dígitos. Muestra visitas, personas, clics por botón
(con cuántas personas), una gráfica por hora o por día y de dónde llegan, en Hoy, 7 días, 30 días o Todo
(los días se cuentan en hora de la Ciudad de México). Se actualiza solo.

**De dónde llegan:** sin nada especial entra como «Directo / QR» (así entran los QR ya impresos). Para separar un QR
o un anuncio, agrega `?s=nombre` al final del enlace, por ejemplo `https://jch-links.vercel.app/?s=boda-garcia`.
Facebook, Instagram, WhatsApp, Google, etc. se reconocen solos por el sitio desde el que llegan.

**No contar tus propias visitas:** en `/admin`, interruptor «No contar mis visitas ni clics en este dispositivo».

### Cómo está hecho
- `index.html` (segundo `<script>`) manda cada visita y clic a `/api/evento`.
- `api/` son funciones de Vercel: `evento` (guarda), `acceso` (PIN), `stats` (datos del panel) y `salir`.
  Todas hablan con **una sola función** de la base de datos.
- Los datos viven en Supabase (proyecto «Mis proyectos»), en el esquema privado `jch_links`, que la API no expone.
  `db/analiticas.sql` crea todo y se puede volver a ejecutar sin romper nada.
- Seguridad: el PIN está cifrado (bcrypt) en la base; máximo 5 intentos por IP cada 15 minutos y 25 por hora en total;
  la sesión dura 12 horas en una cookie HttpOnly. No hay variables de entorno ni secretos en Vercel: la URL y la llave
  de Supabase que están en `api/_lib.js` son las *publicables* y solo pueden llamar a esa función.
- Topes contra abuso: 60 eventos por minuto por dispositivo, 600 por minuto y 20 000 al día en total.

### Mantenimiento (Supabase › SQL Editor)
Cambiar el PIN (el PIN nunca se guarda en el repositorio):
```sql
insert into jch_links.config (clave, valor)
values ('pin_hash', extensions.crypt('NUEVO_PIN', extensions.gen_salt('bf', 10)))
on conflict (clave) do update set valor = excluded.valor;
update jch_links.sesiones set expira = now() where expira > now();
```
Empezar el conteo desde cero sin borrar nada (por ejemplo, después de pruebas):
```sql
insert into jch_links.config (clave, valor) values ('conteo_desde', now()::text)
on conflict (clave) do update set valor = excluded.valor;
```

## Datos usados
- Teléfono (llamada y WhatsApp): +52 55 2311 8153
- Sitio: https://jardines-club-hipico.vercel.app
- Facebook: https://www.facebook.com/JardinesClubHipico/
- Dirección (visitas): Olivos 23, Sta. Inés, Xochimilco, 16810 CDMX

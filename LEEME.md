# Jardines Club Hípico · página de enlaces

Una sola página: `index.html` (HTML + CSS + JS, sin dependencias ni build).

## Publicación
Sitio: https://jch-links.vercel.app

El repositorio está conectado a Vercel (proyecto `jch-links`, framework: Other, sin comando de build):
cada cambio que se sube a la rama `main` se publica solo, en un minuto aproximadamente.

## Qué se puede cambiar
- **Botones y textos:** bloque `<ul class="links">` de `index.html` (5 enlaces).
- **Dirección:** en el botón «Cómo llegar», el texto y el parámetro `query=` del enlace de Google Maps.
- **Fotos de fondo:** `assets/bg/NN.webp` (horizontal) y `NN-m.webp` (vertical, 9:16). Son 8 pares.
- **Tiempo de cada foto:** `INTERVALO` (ms) al inicio del `<script>`.
- **Vista previa al compartir (WhatsApp, Facebook):** `og.jpg` (1200×630) y las etiquetas `og:` del `<head>`.
  Usan la URL completa del sitio; si cambia el dominio hay que cambiarlas.
- **Logo:** el sello del encabezado es un SVG dentro de `index.html`: el emblema (`assets/logo.webp`) con el
  nombre en arco, letra Cinzel convertida a trazos. El tamaño se ajusta solo a la altura de la pantalla
  (variables `--mark`, `--pt`, `--gap`… al inicio del CSS).
- **Pie de página:** «Made by Morphiq» al final de `index.html`.

## Datos usados
- Teléfono (llamada y WhatsApp): +52 55 2311 8153
- Sitio: https://jardines-club-hipico.vercel.app
- Facebook: https://www.facebook.com/JardinesClubHipico/
- Dirección (visitas): Olivos 23, Sta. Inés, Xochimilco, 16810 CDMX

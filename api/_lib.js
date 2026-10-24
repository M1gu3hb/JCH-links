'use strict';

/*  Utilidades de /api. El guion bajo evita que Vercel publique este archivo como endpoint.

    Todo habla con UNA sola función de la base de datos: public.jch_links_rpc (ver db/analiticas.sql).
    La URL y la llave *publicable* de Supabase son públicas por diseño: esa llave solo puede llamar a esa
    función, y cada operación se protege sola (PIN con tope de intentos, o token de sesión).
    Si algún día se quieren sacar del código, se pueden definir JCH_SUPABASE_URL y JCH_SUPABASE_KEY en Vercel. */

const SUPABASE_URL = (process.env.JCH_SUPABASE_URL || 'https://vuzyhbiwnnngeohysxcw.supabase.co').replace(/\/+$/, '');
const SUPABASE_KEY = process.env.JCH_SUPABASE_KEY || 'sb_publishable_26WQI_ceor1wl2Nk43BR1A_NH1zJYDK';

const COOKIE = 'jch_admin';
const SESION_SEGUNDOS = 43200; // 12 h, igual que en la base

/* Botones de la página (data-b en index.html), en el orden en que aparecen. */
const BOTONES = [
  { id: 'sitio', etiqueta: 'Sitio web' },
  { id: 'whatsapp', etiqueta: 'WhatsApp' },
  { id: 'llamar', etiqueta: 'Llamar' },
  { id: 'facebook', etiqueta: 'Facebook' },
  { id: 'mapa', etiqueta: 'Cómo llegar' },
];
const IDS_BOTON = new Set(BOTONES.map((b) => b.id));

const ETIQUETA_FUENTE = {
  directo: 'Directo / QR',
  facebook: 'Facebook',
  instagram: 'Instagram',
  whatsapp: 'WhatsApp',
  google: 'Google',
  x: 'X',
  tiktok: 'TikTok',
  youtube: 'YouTube',
  correo: 'Correo',
};

/* Sitios de origen conocidos → nombre corto. El orden importa (correo antes que google). */
const FUENTES = [
  [/^(?:[a-z0-9-]+\.)*(?:facebook\.com|fb\.com|fb\.me|fb\.watch)$/, 'facebook'],
  [/^(?:[a-z0-9-]+\.)*(?:instagram\.com|ig\.me)$/, 'instagram'],
  [/^(?:[a-z0-9-]+\.)*(?:whatsapp\.com|wa\.me)$/, 'whatsapp'],
  [/^(?:[a-z0-9-]+\.)*tiktok\.com$/, 'tiktok'],
  [/^(?:[a-z0-9-]+\.)*(?:youtube\.com|youtu\.be)$/, 'youtube'],
  [/^(?:[a-z0-9-]+\.)*(?:twitter\.com|x\.com|t\.co)$/, 'x'],
  [/^(?:mail\.google\.com|outlook\.live\.com|outlook\.office\.com|mail\.yahoo\.com|mail\.proton\.me)$/, 'correo'],
  [/^(?:[a-z0-9-]+\.)*(?:google\.[a-z.]+|goo\.gl|g\.co)$/, 'google'],
];

/* Rastreadores y robots conocidos (el contador solo lo dispara un navegador real, esto es un extra). */
const ROBOTS = /googlebot|bingbot|yandexbot|baiduspider|duckduckbot|applebot|semrushbot|ahrefsbot|mj12bot|petalbot|facebookexternalhit|facebot|twitterbot|slackbot|telegrambot|linkedinbot|discordbot|whatsapp\/|crawler|spider|headlesschrome|lighthouse|pagespeed|gtmetrix|pingdom|uptimerobot|python-requests|curl\/|wget\/|node-fetch|axios\/|go-http-client/i;

function esRobot(ua) {
  return !ua || ROBOTS.test(ua);
}

/* "https://www.Facebook.com/x?y" → "facebook"; "qr-boda" → "qr-boda"; lo raro → "" */
function normalizarFuente(s) {
  s = String(s || '')
    .toLowerCase()
    .trim()
    .replace(/^[a-z][a-z0-9+.-]*:\/\//, '')
    .replace(/^www\./, '')
    .split(/[/?#]/)[0]
    .replace(/[^a-z0-9._-]/g, '')
    .slice(0, 40);
  if (!s) return '';
  for (const [re, nombre] of FUENTES) if (re.test(s)) return nombre;
  return s;
}

/* Una IPv6 se reduce a su /64 (los primeros 4 grupos): cambiar de dirección dentro de la misma red
   no sirve para esquivar el tope de intentos. La IP nunca se guarda: la base solo guarda un hash. */
function normalizarIp(ip) {
  ip = String(ip || '').trim().replace(/^\[|\]$/g, '').split('%')[0];
  const v4 = ip.match(/^::ffff:(\d{1,3}(?:\.\d{1,3}){3})$/i);
  if (v4) return v4[1];
  if (!ip.includes(':')) return ip.slice(0, 45);
  if (ip.includes('.')) return ip.slice(0, 45);
  const [izq, der] = ip.split('::');
  const a = izq ? izq.split(':') : [];
  const b = der ? der.split(':') : [];
  const grupos = der === undefined ? a : a.concat(new Array(Math.max(0, 8 - a.length - b.length)).fill('0'), b);
  if (grupos.length !== 8 || grupos.some((g) => !/^[0-9a-f]{1,4}$/i.test(g))) return ip.slice(0, 45);
  return grupos.slice(0, 4).map((g) => parseInt(g, 16).toString(16)).join(':') + '::/64';
}

function ipCliente(req) {
  const h = req.headers || {};
  const crudo =
    h['x-vercel-forwarded-for'] ||
    String(h['x-forwarded-for'] || '').split(',')[0] ||
    (req.socket && req.socket.remoteAddress) ||
    '';
  return normalizarIp(crudo);
}

/* Cuerpo JSON de la petición (Vercel ya lo trae en req.body; si no, se lee el flujo). Máximo 4 KB. */
async function leerJson(req, max = 4096) {
  let b = req.body;
  if (b === undefined || b === null) {
    b = await new Promise((ok, no) => {
      let n = 0;
      const partes = [];
      req.on('data', (c) => {
        n += c.length;
        if (n > max) {
          no(new Error('cuerpo muy grande'));
          return;
        }
        partes.push(c);
      });
      req.on('end', () => ok(Buffer.concat(partes).toString('utf8')));
      req.on('error', no);
    });
  }
  if (Buffer.isBuffer(b)) b = b.toString('utf8');
  if (typeof b === 'string') {
    if (b.length > max) throw new Error('cuerpo muy grande');
    b = b ? JSON.parse(b) : {};
  }
  return b && typeof b === 'object' && !Array.isArray(b) ? b : {};
}

function leerCookie(req, nombre) {
  const h = (req.headers && req.headers.cookie) || '';
  for (const parte of h.split(';')) {
    const i = parte.indexOf('=');
    if (i > 0 && parte.slice(0, i).trim() === nombre) {
      try {
        return decodeURIComponent(parte.slice(i + 1).trim());
      } catch (e) {
        return '';
      }
    }
  }
  return '';
}

function esLocal(req) {
  return /^(localhost|127\.0\.0\.1)(:\d+)?$/.test((req.headers && req.headers.host) || '');
}

/* Cookie de sesión: solo para el servidor (HttpOnly), solo por HTTPS y nunca en peticiones de otros sitios. */
function ponerCookie(req, res, token) {
  const partes = [`${COOKIE}=${token}`, 'Path=/', `Max-Age=${SESION_SEGUNDOS}`, 'HttpOnly', 'SameSite=Strict'];
  if (!esLocal(req)) partes.push('Secure');
  res.setHeader('Set-Cookie', partes.join('; '));
}

function quitarCookie(req, res) {
  const partes = [`${COOKIE}=`, 'Path=/', 'Max-Age=0', 'HttpOnly', 'SameSite=Strict'];
  if (!esLocal(req)) partes.push('Secure');
  res.setHeader('Set-Cookie', partes.join('; '));
}

function tokenDeCookie(req) {
  const t = leerCookie(req, COOKIE);
  return /^[a-f0-9]{64}$/.test(t) ? t : '';
}

function responder(res, status, cuerpo) {
  res.statusCode = status;
  res.setHeader('Content-Type', 'application/json; charset=utf-8');
  res.setHeader('Cache-Control', 'no-store');
  res.end(JSON.stringify(cuerpo));
}

/* Llama a la única función de la base. Un reintento si hay un fallo de red o un error 5xx. */
async function rpc(op, args, reintentos = 1) {
  const cabeceras = { 'Content-Type': 'application/json', apikey: SUPABASE_KEY };
  if (SUPABASE_KEY.startsWith('eyJ')) cabeceras.Authorization = 'Bearer ' + SUPABASE_KEY;
  let ultimo;
  for (let i = 0; i <= reintentos; i++) {
    try {
      const r = await fetch(`${SUPABASE_URL}/rest/v1/rpc/jch_links_rpc`, {
        method: 'POST',
        headers: cabeceras,
        body: JSON.stringify({ p_op: op, p_args: args || {} }),
        signal: AbortSignal.timeout(7000),
      });
      if (r.ok) return await r.json();
      ultimo = new Error('base de datos: HTTP ' + r.status);
      if (r.status < 500) break;
    } catch (e) {
      ultimo = e;
    }
    if (i < reintentos) await new Promise((ok) => setTimeout(ok, 250));
  }
  throw ultimo;
}

module.exports = {
  BOTONES,
  IDS_BOTON,
  ETIQUETA_FUENTE,
  esRobot,
  normalizarFuente,
  normalizarIp,
  ipCliente,
  leerJson,
  tokenDeCookie,
  ponerCookie,
  quitarCookie,
  responder,
  rpc,
};

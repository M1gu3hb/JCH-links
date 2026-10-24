'use strict';

/*  GET /api/stats?r=hoy|7d|30d|todo — datos del panel (exige la cookie de sesión).
    401 si no hay sesión o ya venció. */

const { BOTONES, ETIQUETA_FUENTE, tokenDeCookie, quitarCookie, responder, rpc } = require('./_lib');

const RANGOS = ['hoy', '7d', '30d', 'todo'];

module.exports = async function stats(req, res) {
  if (req.method !== 'GET') {
    res.setHeader('Allow', 'GET');
    return responder(res, 405, { ok: false });
  }
  const token = tokenDeCookie(req);
  if (!token) return responder(res, 401, { ok: false });

  let rango = 'hoy';
  try {
    const q = new URL(req.url, 'http://x').searchParams.get('r');
    if (RANGOS.includes(q)) rango = q;
  } catch (e) {
    /* se queda en 'hoy' */
  }

  let d;
  try {
    d = await rpc('stats', { token, rango });
  } catch (e) {
    return responder(res, 503, { ok: false, error: 'servicio' });
  }
  if (!d || !d.ok) {
    quitarCookie(req, res);
    return responder(res, 401, { ok: false });
  }

  /* Todos los botones aparecen aunque tengan 0 clics, con su nombre, en el orden de la página. */
  const porId = new Map((d.botones || []).map((b) => [b.id, b]));
  const botones = BOTONES.map((b) => {
    const x = porId.get(b.id);
    return { id: b.id, etiqueta: b.etiqueta, clics: x ? x.clics : 0, personas: x ? x.personas : 0 };
  });
  for (const [id, x] of porId) {
    if (!BOTONES.some((b) => b.id === id)) botones.push({ id, etiqueta: id, clics: x.clics, personas: x.personas });
  }

  const fuentes = (d.fuentes || []).map((f) => ({
    id: f.fuente,
    etiqueta: ETIQUETA_FUENTE[f.fuente] || f.fuente,
    visitas: f.visitas,
    personas: f.personas,
  }));

  responder(res, 200, {
    ok: true,
    rango: d.rango,
    por: d.por,
    ahora: d.ahora,
    ultima_visita: d.ultima_visita,
    totales: d.totales,
    botones,
    fuentes,
    serie: d.serie,
  });
};

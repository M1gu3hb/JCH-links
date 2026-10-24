'use strict';

/*  POST /api/acceso — { pin } → inicia sesión en el panel.
    200 { ok:true } y cookie de sesión (12 h) · 401 { ok:false, quedan } · 429 { ok:false, espera } (segundos)
    El PIN se compara en la base (bcrypt) y cada intento cuenta ANTES de compararse. */

const { leerJson, ipCliente, ponerCookie, responder, rpc } = require('./_lib');

module.exports = async function acceso(req, res) {
  if (req.method !== 'POST') {
    res.setHeader('Allow', 'POST');
    return responder(res, 405, { ok: false });
  }
  let pin = '';
  try {
    const b = await leerJson(req);
    pin = typeof b.pin === 'string' ? b.pin : '';
  } catch (e) {
    return responder(res, 400, { ok: false });
  }
  if (!/^[0-9]{4}$/.test(pin)) return responder(res, 400, { ok: false });

  let r;
  try {
    r = await rpc('login', { pin, ip: ipCliente(req) });
  } catch (e) {
    return responder(res, 503, { ok: false, error: 'servicio' });
  }
  if (r && r.ok && typeof r.token === 'string') {
    ponerCookie(req, res, r.token);
    return responder(res, 200, { ok: true });
  }
  if (r && r.espera > 0) return responder(res, 429, { ok: false, espera: r.espera });
  return responder(res, 401, { ok: false, quedan: r && Number.isInteger(r.quedan) ? r.quedan : 0 });
};

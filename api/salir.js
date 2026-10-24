'use strict';

/*  POST /api/salir — cierra la sesión del panel (en la base y en la cookie). */

const { tokenDeCookie, quitarCookie, responder, rpc } = require('./_lib');

module.exports = async function salir(req, res) {
  if (req.method !== 'POST') {
    res.setHeader('Allow', 'POST');
    return responder(res, 405, { ok: false });
  }
  const token = tokenDeCookie(req);
  if (token) {
    try {
      await rpc('salir', { token });
    } catch (e) {
      /* igual se borra la cookie; la sesión vence sola a las 12 h */
    }
  }
  quitarCookie(req, res);
  responder(res, 200, { ok: true });
};

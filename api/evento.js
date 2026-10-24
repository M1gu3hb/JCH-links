'use strict';

/*  POST /api/evento — guarda una visita ({k:'v'}) o un clic ({k:'c', t:'<botón>'}).
    Cuerpo: { k, t?, v: id del dispositivo, s?: origen }.
    Siempre responde 204 y nunca falla hacia la página: las analíticas no pueden romper nada. */

const { IDS_BOTON, esRobot, normalizarFuente, leerJson, rpc } = require('./_lib');

module.exports = async function evento(req, res) {
  res.setHeader('Cache-Control', 'no-store');
  if (req.method !== 'POST') {
    res.statusCode = 405;
    res.setHeader('Allow', 'POST');
    res.end();
    return;
  }
  try {
    if (!esRobot(String(req.headers['user-agent'] || ''))) {
      const b = await leerJson(req);
      const k = b.k === 'v' || b.k === 'c' ? b.k : '';
      const v = typeof b.v === 'string' ? b.v.toLowerCase() : '';
      const t = k === 'c' && typeof b.t === 'string' ? b.t : '';
      if (k && /^[a-z0-9]{8,32}$/.test(v) && (k === 'v' || IDS_BOTON.has(t))) {
        await rpc('evento', { k, t, v, s: normalizarFuente(b.s) }, 0);
      }
    }
  } catch (e) {
    /* se ignora a propósito */
  }
  res.statusCode = 204;
  res.end();
};

/**
 * Pont perquè l'app Guasti de l'iPhone pugui fer servir el Publicador de l'Auditori.
 *
 * Va com a fitxer a part dins del projecte d'Apps Script del publicador: no cal tocar
 * Codi.gs. Fa servir les mateixes funcions que la web (totes comproven la clau d'accés),
 * però per POST amb JSON:
 *   { "action": "pujarFitxer", "k": "<clau>", "args": [...] }  ->  { "ok": true, "r": ... }
 *
 * Després d'afegir-lo: Implementa -> Gestiona les implementacions -> llapis -> Versió nova.
 * Així l'enllaç no canvia.
 */

const ACCIONS_GUASTI = [
  'estatGuasti',
  'pujarFitxer', 'prepararFoto', 'crearElementInstagram', 'estatElementInstagram',
  'publicarInstagram', 'publicarFacebook', 'programar', 'cancellar', 'registrar',
  'llistarHistorial', 'llistarFragments', 'desarFragment', 'esborrarFragment'
];

function doPost(e) {
  let sortida;
  try {
    const peticio = JSON.parse(e.postData.contents);
    const accio = peticio.action === 'estat' ? 'estatGuasti' : peticio.action;
    if (ACCIONS_GUASTI.indexOf(accio) < 0) throw new Error('Acció desconeguda: ' + peticio.action);
    const r = globalThis[accio].apply(null, [peticio.k].concat(peticio.args || []));
    sortida = { ok: true, r: r === undefined ? null : r };
  } catch (err) {
    sortida = { ok: false, error: err && err.message ? err.message : String(err) };
  }
  return ContentService.createTextOutput(JSON.stringify(sortida)).setMimeType(ContentService.MimeType.JSON);
}

/** Per comprovar la connexió des de l'app: diu si Facebook i Instagram estan connectats. */
function estatGuasti(clau) {
  comprovarClau_(clau);
  return estatConfiguracio_();
}

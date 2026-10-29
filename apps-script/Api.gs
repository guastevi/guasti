/**
 * Guasti API: el pont entre l'app iOS "Guasti" i els teus fulls de Google.
 *
 * No toca l'app web actual: llegeix i escriu als mateixos fulls i a la mateixa
 * carpeta de fotos, així que tot el que facis des de l'iPhone es veu a la web i al revés.
 *
 * Instal·lació (un sol cop):
 *  1. script.new  →  enganxa aquest fitxer sencer.
 *  2. Configuració del projecte (engranatge)  →  Propietats de l'script  →
 *     afegeix API_KEY amb una clau llarga inventada (p. ex. 30 lletres i números a l'atzar).
 *  3. Implementa  →  Implementació nova  →  Aplicació web.
 *     Executa com: Jo.   Qui hi té accés: Qualsevol usuari.
 *  4. Autoritza els permisos i copia l'URL que acaba en /exec.
 *  5. A l'app Guasti, Configuració: enganxa l'URL i la clau.
 *
 * Sense la clau, ningú pot llegir ni escriure res encara que conegui l'URL.
 */

const ARMARI = {
  pecesSheetId: '1P3LJ9pCNz01JyPV6JMbxS-V_RaxIBRMWBfu9hgCOrkM',
  pecesTab: 'Peces',
  fotosSheetId: '1N6VQcSqTs_k8qwNxb1_PAt9bu70eoUkWOqj5V1G9tTs',
  photoPrefix: 'fotos_Images/',
};

const THUMB_SIZES = { thumb: 400, medium: 1100 };

// ---------------------------------------------------------------- entrada

function doGet(e) {
  return handle_((e && e.parameter) || {});
}

function doPost(e) {
  let body = {};
  try {
    body = JSON.parse((e && e.postData && e.postData.contents) || '{}');
  } catch (err) {}
  return handle_(Object.assign({}, (e && e.parameter) || {}, body));
}

function handle_(p) {
  const key = PropertiesService.getScriptProperties().getProperty('API_KEY');
  if (!key || p.k !== key) return json_({ ok: false, error: 'Clau incorrecta' });

  const actions = {
    'ping': () => ({}),
    'armari.list': () => armariList_(),
    'armari.photo': () => armariPhoto_(p.path, p.size),
    'armari.save': () => withLock_(() => armariSave_(p.piece)),
    'armari.delete': () => withLock_(() => armariDelete_(p.id)),
    'armari.addPhoto': () => withLock_(() => armariAddPhoto_(p.pieceId, p.base64)),
    'armari.deletePhoto': () => withLock_(() => armariDeletePhoto_(p.photoId)),
    'armari.setCover': () => withLock_(() => armariSetCover_(p.pieceId, p.path)),
    'armari.reorder': () => withLock_(() => armariReorder_(p.pieceId, p.ids)),
  };

  const fn = actions[p.action];
  if (!fn) return json_({ ok: false, error: 'Acció desconeguda: ' + p.action });
  try {
    return json_(Object.assign({ ok: true }, fn()));
  } catch (err) {
    return json_({ ok: false, error: String((err && err.message) || err) });
  }
}

// ---------------------------------------------------------------- armari

function pecesSheet_() {
  const ss = SpreadsheetApp.openById(ARMARI.pecesSheetId);
  return ss.getSheetByName(ARMARI.pecesTab) || ss.getSheets()[0];
}

function fotosSheet_() {
  return SpreadsheetApp.openById(ARMARI.fotosSheetId).getSheets()[0];
}

function armariList_() {
  return {
    peces: readObjects_(pecesSheet_()),
    fotos: readObjects_(fotosSheet_()),
  };
}

function armariSave_(piece) {
  if (!piece) throw new Error('Falta la peça');
  const sheet = pecesSheet_();
  if (!piece.ID) piece.ID = newId_();
  const t = readTable_(sheet);
  const idx = t.rows.findIndex(r => String(r[t.col.ID]) === String(piece.ID));
  if (idx >= 0) {
    writeRow_(sheet, t, idx + 2, piece);
  } else {
    appendRow_(sheet, t, piece);
  }
  return { piece: readObjects_(sheet).find(o => o.ID === String(piece.ID)) };
}

function armariDelete_(id) {
  const peces = pecesSheet_();
  const t = readTable_(peces);
  const idx = t.rows.findIndex(r => String(r[t.col.ID]) === String(id));
  if (idx < 0) throw new Error('No trobo la peça ' + id);

  const fotos = fotosSheet_();
  const f = readTable_(fotos);
  for (let i = f.rows.length - 1; i >= 0; i--) {
    if (String(f.rows[i][f.col['Peça']]) === String(id)) {
      trashPhoto_(String(f.rows[i][f.col.Foto]));
      fotos.deleteRow(i + 2);
    }
  }
  peces.deleteRow(idx + 2);
  return {};
}

function armariAddPhoto_(pieceId, base64) {
  if (!pieceId || !base64) throw new Error('Falten dades de la foto');
  const folder = photoFolder_();
  const name = pieceId + '.Foto.' + Date.now() + '.jpg';
  const blob = Utilities.newBlob(Utilities.base64Decode(base64), 'image/jpeg', name);
  const file = folder.createFile(blob);
  const path = ARMARI.photoPrefix + name;
  CacheService.getScriptCache().put('p:' + path, file.getId(), 21600);

  const fotos = fotosSheet_();
  const f = readTable_(fotos);
  const ordres = f.rows
    .filter(r => String(r[f.col['Peça']]) === String(pieceId))
    .map(r => Number(r[f.col.Ordre]) || 0);
  const foto = { ID: newId_(), 'Peça': pieceId, Foto: path, Ordre: String(Math.max(0, ...ordres) + 1) };
  appendRow_(fotos, f, foto);

  let portada = coverOf_(pieceId);
  if (!portada) {
    armariSetCover_(pieceId, path);
    portada = path;
  }
  return { foto: foto, portada: portada };
}

function armariDeletePhoto_(photoId) {
  const fotos = fotosSheet_();
  const f = readTable_(fotos);
  const idx = f.rows.findIndex(r => String(r[f.col.ID]) === String(photoId));
  if (idx < 0) throw new Error('No trobo la foto');
  const pieceId = String(f.rows[idx][f.col['Peça']]);
  const path = String(f.rows[idx][f.col.Foto]);
  fotos.deleteRow(idx + 2);
  trashPhoto_(path);

  let portada = coverOf_(pieceId);
  if (portada === path) {
    const next = f.rows.find((r, i) => i !== idx && String(r[f.col['Peça']]) === pieceId);
    portada = next ? String(next[f.col.Foto]) : '';
    armariSetCover_(pieceId, portada);
  }
  return { portada: portada };
}

function armariSetCover_(pieceId, path) {
  const sheet = pecesSheet_();
  const t = readTable_(sheet);
  const idx = t.rows.findIndex(r => String(r[t.col.ID]) === String(pieceId));
  if (idx < 0) throw new Error('No trobo la peça');
  sheet.getRange(idx + 2, t.col.Portada + 1).setValue(path || '');
  return { portada: path || '' };
}

/** Desa l'ordre de les fotos d'una peça (com l'app web). La primera passa a ser la portada. */
function armariReorder_(pieceId, ids) {
  if (!pieceId || !ids || !ids.length) throw new Error("Falta l'ordre de les fotos");
  const sheet = fotosSheet_();
  const f = readTable_(sheet);
  let firstPath = '';
  f.rows.forEach((r, i) => {
    if (String(r[f.col['Peça']]) !== String(pieceId)) return;
    const k = ids.indexOf(String(r[f.col.ID]));
    if (k < 0) return;
    sheet.getRange(i + 2, f.col.Ordre + 1).setValue(k + 1);
    if (k === 0) firstPath = String(r[f.col.Foto]);
  });
  if (firstPath) armariSetCover_(pieceId, firstPath);
  return { portada: firstPath };
}

function coverOf_(pieceId) {
  const t = readTable_(pecesSheet_());
  const row = t.rows.find(r => String(r[t.col.ID]) === String(pieceId));
  return row ? String(row[t.col.Portada] || '') : '';
}

// ---------------------------------------------------------------- fotos

/** Retorna la foto en base64. size: thumb | medium | full */
function armariPhoto_(path, size) {
  const fileId = resolvePhoto_(path);
  if (!fileId) throw new Error('No trobo la foto ' + path);
  let blob = null;
  if (size !== 'full') {
    try {
      blob = driveThumbnail_(fileId, THUMB_SIZES[size] || THUMB_SIZES.thumb);
    } catch (err) {}
  }
  if (!blob) blob = DriveApp.getFileById(fileId).getBlob();
  return { mime: blob.getContentType(), base64: Utilities.base64Encode(blob.getBytes()) };
}

function driveThumbnail_(fileId, width) {
  const headers = { Authorization: 'Bearer ' + ScriptApp.getOAuthToken() };
  const meta = UrlFetchApp.fetch(
    'https://www.googleapis.com/drive/v3/files/' + fileId + '?fields=thumbnailLink',
    { headers: headers, muteHttpExceptions: true });
  if (meta.getResponseCode() !== 200) return null;
  const link = JSON.parse(meta.getContentText()).thumbnailLink;
  if (!link) return null;
  const resp = UrlFetchApp.fetch(link.replace(/=s\d+$/, '=s' + width),
    { headers: headers, muteHttpExceptions: true });
  return resp.getResponseCode() === 200 ? resp.getBlob() : null;
}

/** Converteix "fotos_Images/xxx.jpg" en l'ID del fitxer de Drive. */
function resolvePhoto_(path) {
  path = String(path || '').trim();
  if (!path) return null;
  const cache = CacheService.getScriptCache();
  const hit = cache.get('p:' + path);
  if (hit) return hit;
  const name = String(path).split('/').pop();
  const files = DriveApp.getFilesByName(name);
  while (files.hasNext()) {
    const file = files.next();
    if (!file.isTrashed()) {
      cache.put('p:' + path, file.getId(), 21600);
      return file.getId();
    }
  }
  const m = path.match(/[-\w]{25,}/); // URL o ID de Drive, com fa l'app web
  return m ? m[0] : null;
}

/** La carpeta on hi ha les fotos existents; les noves hi van a parar també. */
function photoFolder_() {
  const props = PropertiesService.getScriptProperties();
  const saved = props.getProperty('PHOTO_FOLDER_ID');
  if (saved) {
    try { return DriveApp.getFolderById(saved); } catch (err) {}
  }
  const f = readTable_(fotosSheet_());
  for (const row of f.rows) {
    const id = resolvePhoto_(String(row[f.col.Foto]));
    if (!id) continue;
    const parents = DriveApp.getFileById(id).getParents();
    if (parents.hasNext()) {
      const folder = parents.next();
      props.setProperty('PHOTO_FOLDER_ID', folder.getId());
      return folder;
    }
  }
  throw new Error('No trobo la carpeta de fotos');
}

function trashPhoto_(path) {
  const id = resolvePhoto_(path);
  if (id) DriveApp.getFileById(id).setTrashed(true); // es pot recuperar de la paperera 30 dies
}

// ---------------------------------------------------------------- fulls

function readTable_(sheet) {
  const values = sheet.getDataRange().getValues();
  const headers = (values.shift() || []).map(h => String(h).trim());
  const col = {};
  headers.forEach((h, i) => { col[h] = i; });
  return { headers: headers, col: col, rows: values };
}

function readObjects_(sheet) {
  const t = readTable_(sheet);
  return t.rows
    .filter(r => r.some(c => c !== '' && c !== null))
    .map(r => {
      const o = {};
      t.headers.forEach((h, i) => {
        if (!h) return;
        const v = r[i];
        o[h] = v instanceof Date ? v.toISOString() : (v === null || v === undefined ? '' : String(v));
      });
      return o;
    });
}

function writeRow_(sheet, t, rowNumber, obj) {
  const range = sheet.getRange(rowNumber, 1, 1, t.headers.length);
  const current = range.getValues()[0];
  const next = t.headers.map((h, i) => (h in obj ? obj[h] : current[i]));
  if (t.col.ID !== undefined) sheet.getRange(rowNumber, t.col.ID + 1).setNumberFormat('@');
  range.setValues([next]);
}

function appendRow_(sheet, t, obj) {
  const rowNumber = sheet.getLastRow() + 1;
  // L'ID es desa com a text: així "12e45678" no es converteix en un número científic.
  if (t.col.ID !== undefined) sheet.getRange(rowNumber, t.col.ID + 1).setNumberFormat('@');
  if (t.col['Peça'] !== undefined) sheet.getRange(rowNumber, t.col['Peça'] + 1).setNumberFormat('@');
  sheet.getRange(rowNumber, 1, 1, t.headers.length)
    .setValues([t.headers.map(h => (h in obj ? obj[h] : ''))]);
}

// ---------------------------------------------------------------- utilitats

function newId_() {
  return Utilities.getUuid().replace(/-/g, '').slice(0, 8);
}

function withLock_(fn) {
  const lock = LockService.getScriptLock();
  lock.waitLock(30000);
  try {
    return fn();
  } finally {
    lock.releaseLock();
  }
}

function json_(obj) {
  return ContentService.createTextOutput(JSON.stringify(obj))
    .setMimeType(ContentService.MimeType.JSON);
}

/** Executa-ho un cop des de l'editor per comprovar que tot funciona. */
function provaArmari() {
  const r = armariList_();
  Logger.log('Peces: ' + r.peces.length + ', fotos: ' + r.fotos.length);
  const first = r.peces.find(p => p.Portada);
  if (first) Logger.log('Primera foto: ' + resolvePhoto_(first.Portada));
}

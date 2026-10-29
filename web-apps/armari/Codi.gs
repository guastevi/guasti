/**
 * Armari Guasteví — app web sobre el full "Armari Guasteví - Peces".
 * Les dades i les fotos es queden al teu Google Drive.
 */

const FOTOS_SS_ID = '1N6VQcSqTs_k8qwNxb1_PAt9bu70eoUkWOqj5V1G9tTs'; // full "Armari Guasteví - Fotos"
const ROOT_FOLDER_ID = '140k8OkRagQyRvpiTowv4EjpKNUSRiJXO';          // carpeta "Armari Guasteví"
const FOTO_DIR = 'fotos_Images';                                      // la mateixa carpeta que fa servir AppSheet
const PECES_HEADERS = ['ID', 'Nom', 'Tipus', 'Temporada', 'Ubicació', 'Color', 'Notes', 'Portada', 'Talla', 'Marca', 'Privada'];
const FOTOS_HEADERS = ['ID', 'Peça', 'Foto', 'Ordre'];

function doGet() {
  const out = HtmlService.createHtmlOutputFromFile('Index')
    .setTitle('Armari Guasteví')
    .addMetaTag('viewport', 'width=device-width, initial-scale=1, viewport-fit=cover');
  const metes = [
    ['apple-mobile-web-app-capable', 'yes'],
    ['mobile-web-app-capable', 'yes']
  ];
  metes.forEach(function (m) {
    try { out.addMetaTag(m[0], m[1]); } catch (e) {}
  });
  return out;
}

/* ---------- utilitats de full ---------- */

function pecesSheet_() {
  const ss = SpreadsheetApp.getActive();
  return ss.getSheetByName('Peces') || ss.getSheets()[0];
}
function fotosSheet_() {
  return SpreadsheetApp.openById(FOTOS_SS_ID).getSheets()[0];
}

// Llegeix una taula fent servir la fila 1 com a capçaleres; afegeix les columnes que faltin.
function table_(sh, required) {
  const lastCol = Math.max(sh.getLastColumn(), 1);
  const head = sh.getRange(1, 1, 1, lastCol).getValues()[0].map(function (x) { return String(x).trim(); });
  (required || []).forEach(function (r) {
    if (head.indexOf(r) < 0) { head.push(r); sh.getRange(1, head.length).setValue(r); }
  });
  const idx = {};
  head.forEach(function (h, i) { if (h) idx[h] = i; });
  const n = sh.getLastRow() - 1;
  const values = n > 0 ? sh.getRange(2, 1, n, head.length).getValues() : [];
  const rows = values.map(function (v, i) {
    const o = { _row: i + 2 };
    Object.keys(idx).forEach(function (h) { o[h] = v[idx[h]]; });
    return o;
  });
  return { sh: sh, head: head, idx: idx, rows: rows };
}

function rowArray_(t, obj) {
  const arr = t.head.map(function () { return ''; });
  Object.keys(obj).forEach(function (k) { if (k in t.idx) arr[t.idx[k]] = obj[k]; });
  return arr;
}

function setCell_(t, rowNum, col, value) {
  if (col in t.idx) t.sh.getRange(rowNum, t.idx[col] + 1).setValue(value);
}

function str_(v) { return v === null || v === undefined ? '' : String(v); }

/* ---------- fotos ---------- */

function root_() { return DriveApp.getFolderById(ROOT_FOLDER_ID); }

function fotoFolder_() {
  const it = root_().getFoldersByName(FOTO_DIR);
  return it.hasNext() ? it.next() : root_().createFolder(FOTO_DIR);
}

// Mapa "carpeta/fitxer" -> id de Drive per a totes les subcarpetes d'imatges.
function fileMap_() {
  const map = {};
  const folders = root_().getFolders();
  while (folders.hasNext()) {
    const f = folders.next();
    const files = f.getFiles();
    while (files.hasNext()) {
      const file = files.next();
      map[f.getName() + '/' + file.getName()] = file.getId();
    }
  }
  return map;
}

function resolve_(path, map) {
  path = str_(path).trim();
  if (!path) return '';
  if (map[path]) return map[path];
  const m = path.match(/[-\w]{25,}/); // URL o id de Drive
  return m ? m[0] : '';
}

/* ---------- API per a la pàgina ---------- */

// Torna una foto del teu Drive com a imatge que la pàgina pot mostrar directament.
// full = false: miniatura per a la galeria; full = true: foto sencera per a la fitxa.
function getImage(fileId, full) {
  const size = full ? 1600 : 700;
  let blob = null;
  // 1. Versió reduïda que prepara el mateix Drive (nítida i lleugera)
  try {
    const token = ScriptApp.getOAuthToken();
    const meta = UrlFetchApp.fetch('https://www.googleapis.com/drive/v3/files/' + encodeURIComponent(fileId) + '?fields=thumbnailLink',
      { headers: { Authorization: 'Bearer ' + token }, muteHttpExceptions: true });
    const link = meta.getResponseCode() === 200 ? JSON.parse(meta.getContentText()).thumbnailLink : '';
    if (link) {
      const r = UrlFetchApp.fetch(link.replace(/=s\d+$/, '') + '=s' + size,
        { headers: { Authorization: 'Bearer ' + token }, muteHttpExceptions: true });
      if (r.getResponseCode() === 200) blob = r.getBlob();
    }
  } catch (e) { blob = null; }
  // 2. Si encara no n'hi ha (foto acabada de pujar), la foto original
  if (!blob) {
    const file = DriveApp.getFileById(fileId);
    blob = file.getBlob();
    if (!full && blob.getBytes().length > 1500000) { try { blob = file.getThumbnail() || blob; } catch (e) {} }
  }
  const type = blob.getContentType() || 'image/jpeg';
  return 'data:' + type + ';base64,' + Utilities.base64Encode(blob.getBytes());
}

// Moltes miniatures de cop (per a la galeria), demanades en paral·lel al Drive.
function getImages(ids, size) {
  const out = {};
  const sz = Math.min(Math.max(Number(size) || 480, 120), 800);
  if (!ids || !ids.length) return out;
  const token = ScriptApp.getOAuthToken();
  const head = { Authorization: 'Bearer ' + token };
  let links = [];
  try {
    links = UrlFetchApp.fetchAll(ids.map(function (id) {
      return { url: 'https://www.googleapis.com/drive/v3/files/' + encodeURIComponent(id) + '?fields=thumbnailLink', headers: head, muteHttpExceptions: true };
    })).map(function (r) { return r.getResponseCode() === 200 ? (JSON.parse(r.getContentText()).thumbnailLink || '') : ''; });
  } catch (e) { links = ids.map(function () { return ''; }); }
  const want = [];
  ids.forEach(function (id, i) { if (links[i]) want.push({ id: id, url: links[i].replace(/=s\d+$/, '') + '=s' + sz }); });
  let res = [];
  try { res = UrlFetchApp.fetchAll(want.map(function (w) { return { url: w.url, headers: head, muteHttpExceptions: true }; })); } catch (e) { res = []; }
  want.forEach(function (w, i) {
    const r = res[i];
    if (r && r.getResponseCode() === 200) {
      const b = r.getBlob();
      out[w.id] = 'data:' + (b.getContentType() || 'image/jpeg') + ';base64,' + Utilities.base64Encode(b.getBytes());
    }
  });
  ids.forEach(function (id) { if (!out[id]) { try { out[id] = getImage(id, false); } catch (e) {} } });
  return out;
}

/* ---------- apartat privat ---------- */

function props_() { return PropertiesService.getUserProperties(); }
function hash_(pin) {
  const d = Utilities.computeDigest(Utilities.DigestAlgorithm.SHA_256, 'armari-guastevi:' + String(pin), Utilities.Charset.UTF_8);
  return Utilities.base64Encode(d);
}
function pinOk_(pin) {
  const h = props_().getProperty('pinHash');
  return !!h && !!pin && hash_(pin) === h;
}
function isPrivate_(v) { return /^(s[ií]|x|true|1)$/i.test(str_(v).trim()); }

// Crea o canvia la contrasenya de l'apartat privat.
function setPin(newPin, oldPin) {
  const h = props_().getProperty('pinHash');
  if (h && !pinOk_(oldPin)) throw new Error('La contrasenya actual no és correcta.');
  if (!newPin || String(newPin).length < 4) throw new Error('La contrasenya ha de tenir almenys 4 caràcters.');
  props_().setProperty('pinHash', hash_(newPin));
  return true;
}

function getData(pin) {
  const map = fileMap_();
  const P = table_(pecesSheet_(), PECES_HEADERS);
  const F = table_(fotosSheet_(), FOTOS_HEADERS);
  const byPiece = {};
  F.rows.forEach(function (r) {
    const file = resolve_(r['Foto'], map);
    if (!file || !r['Peça']) return;
    const k = str_(r['Peça']);
    (byPiece[k] = byPiece[k] || []).push({ id: str_(r['ID']), file: file, path: str_(r['Foto']), ordre: Number(r['Ordre']) || 0 });
  });
  const unlocked = pinOk_(pin);
  const pieces = P.rows.filter(function (r) { return str_(r['ID']) && (unlocked || !isPrivate_(r['Privada'])); }).map(function (r) {
    const id = str_(r['ID']);
    const fotos = (byPiece[id] || []).sort(function (a, b) { return a.ordre - b.ordre; });
    const coverPath = str_(r['Portada']);
    let cover = resolve_(coverPath, map);
    const coverInFotos = fotos.some(function (f) { return f.path === coverPath || f.file === cover; });
    if (!cover && fotos.length) cover = fotos[0].file;
    return {
      id: id, nom: str_(r['Nom']), tipus: str_(r['Tipus']), temporada: str_(r['Temporada']),
      ubicacio: str_(r['Ubicació']), color: str_(r['Color']), notes: str_(r['Notes']),
      talla: str_(r['Talla']), marca: str_(r['Marca']), privada: isPrivate_(r['Privada']),
      cover: cover, coverExtra: !!(coverPath && cover && !coverInFotos),
      fotos: fotos.map(function (f) { return { id: f.id, file: f.file }; })
    };
  });
  return { pieces: pieces, unlocked: unlocked, hasPin: !!props_().getProperty('pinHash') };
}

function savePiece(p) {
  const lock = LockService.getScriptLock(); lock.waitLock(20000);
  try {
    const t = table_(pecesSheet_(), PECES_HEADERS);
    const fields = {
      'Nom': p.nom || '', 'Tipus': p.tipus || '', 'Temporada': p.temporada || '', 'Ubicació': p.ubicacio || '',
      'Color': p.color || '', 'Notes': p.notes || '', 'Talla': p.talla || '', 'Marca': p.marca || '', 'Privada': p.privada ? 'Sí' : ''
    };
    if (p.id) {
      const row = t.rows.filter(function (r) { return str_(r['ID']) === p.id; })[0];
      if (!row) throw new Error('No he trobat la peça al full.');
      Object.keys(fields).forEach(function (k) { setCell_(t, row._row, k, fields[k]); });
      return p.id;
    }
    const id = Utilities.getUuid().slice(0, 8);
    fields['ID'] = id;
    t.sh.appendRow(rowArray_(t, fields));
    return id;
  } finally { lock.releaseLock(); }
}

function addPhoto(pieceId, b64, mime) {
  const lock = LockService.getScriptLock(); lock.waitLock(20000);
  try {
    const name = pieceId + '.Foto.' + Date.now() + '.jpg';
    const file = fotoFolder_().createFile(Utilities.newBlob(Utilities.base64Decode(b64), mime || 'image/jpeg', name));
    const path = FOTO_DIR + '/' + name;
    const F = table_(fotosSheet_(), FOTOS_HEADERS);
    const mine = F.rows.filter(function (r) { return str_(r['Peça']) === pieceId; });
    const ordre = mine.reduce(function (m, r) { return Math.max(m, Number(r['Ordre']) || 0); }, 0) + 1;
    const id = Utilities.getUuid().slice(0, 8);
    F.sh.appendRow(rowArray_(F, { 'ID': id, 'Peça': pieceId, 'Foto': path, 'Ordre': ordre }));
    const P = table_(pecesSheet_(), PECES_HEADERS);
    const row = P.rows.filter(function (r) { return str_(r['ID']) === pieceId; })[0];
    if (row && !str_(row['Portada'])) setCell_(P, row._row, 'Portada', path);
    return { id: id, file: file.getId() };
  } finally { lock.releaseLock(); }
}

// Substitueix una foto per una versió nova (p. ex. amb fons blanc).
// L'original va a la paperera del Drive (es pot recuperar durant 30 dies).
function replacePhoto(pieceId, oldFileId, b64) {
  const lock = LockService.getScriptLock(); lock.waitLock(20000);
  try {
    const map = fileMap_();
    const name = pieceId + '.Foto.' + Date.now() + '.jpg';
    const file = fotoFolder_().createFile(Utilities.newBlob(Utilities.base64Decode(b64), 'image/jpeg', name));
    const path = FOTO_DIR + '/' + name;
    let changed = 0;
    const F = table_(fotosSheet_(), FOTOS_HEADERS);
    F.rows.forEach(function (r) {
      if (str_(r['Peça']) === pieceId && resolve_(r['Foto'], map) === oldFileId) { setCell_(F, r._row, 'Foto', path); changed++; }
    });
    const P = table_(pecesSheet_(), PECES_HEADERS);
    P.rows.forEach(function (r) {
      if (str_(r['ID']) === pieceId && resolve_(r['Portada'], map) === oldFileId) { setCell_(P, r._row, 'Portada', path); changed++; }
    });
    if (!changed) { file.setTrashed(true); throw new Error('No he trobat la foto al full.'); }
    try { DriveApp.getFileById(oldFileId).setTrashed(true); } catch (e) {}
    return file.getId();
  } finally { lock.releaseLock(); }
}

// Posa una foto com a portada i la mou a la primera posició.
function setCover(pieceId, fotoId) {
  const F = table_(fotosSheet_(), FOTOS_HEADERS);
  const mine = F.rows.filter(function (r) { return str_(r['Peça']) === pieceId; })
    .sort(function (a, b) { return (Number(a['Ordre']) || 0) - (Number(b['Ordre']) || 0); });
  if (!mine.some(function (r) { return str_(r['ID']) === fotoId; })) throw new Error('No he trobat la foto.');
  const ids = [fotoId].concat(mine.map(function (r) { return str_(r['ID']); }).filter(function (x) { return x !== fotoId; }));
  return reorderPhotos(pieceId, ids);
}

// Desa l'ordre de les fotos d'una peça. La primera passa a ser la portada.
function reorderPhotos(pieceId, ids) {
  const lock = LockService.getScriptLock(); lock.waitLock(20000);
  try {
    const F = table_(fotosSheet_(), FOTOS_HEADERS);
    let firstPath = '';
    F.rows.forEach(function (r) {
      if (str_(r['Peça']) !== pieceId) return;
      const i = ids.indexOf(str_(r['ID']));
      if (i < 0) return;
      setCell_(F, r._row, 'Ordre', i + 1);
      if (i === 0) firstPath = str_(r['Foto']);
    });
    if (firstPath) {
      const P = table_(pecesSheet_(), PECES_HEADERS);
      const row = P.rows.filter(function (r) { return str_(r['ID']) === pieceId; })[0];
      if (row) setCell_(P, row._row, 'Portada', firstPath);
    }
    return true;
  } finally { lock.releaseLock(); }
}

function removePhoto(pieceId, fotoId) {
  const lock = LockService.getScriptLock(); lock.waitLock(20000);
  try {
    const map = fileMap_();
    const F = table_(fotosSheet_(), FOTOS_HEADERS);
    const foto = F.rows.filter(function (r) { return str_(r['ID']) === fotoId; })[0];
    if (!foto) return true;
    const path = str_(foto['Foto']);
    const file = resolve_(path, map);
    if (file) { try { DriveApp.getFileById(file).setTrashed(true); } catch (e) {} }
    F.sh.deleteRow(foto._row);
    const P = table_(pecesSheet_(), PECES_HEADERS);
    const row = P.rows.filter(function (r) { return str_(r['ID']) === pieceId; })[0];
    if (row && str_(row['Portada']) === path) {
      const next = F.rows.filter(function (r) { return str_(r['Peça']) === pieceId && r._row !== foto._row; })
        .sort(function (a, b) { return (Number(a['Ordre']) || 0) - (Number(b['Ordre']) || 0); })[0];
      setCell_(P, row._row, 'Portada', next ? str_(next['Foto']) : '');
    }
    return true;
  } finally { lock.releaseLock(); }
}

function deletePiece(pieceId) {
  const lock = LockService.getScriptLock(); lock.waitLock(20000);
  try {
    const map = fileMap_();
    const F = table_(fotosSheet_(), FOTOS_HEADERS);
    F.rows.filter(function (r) { return str_(r['Peça']) === pieceId; })
      .sort(function (a, b) { return b._row - a._row; })
      .forEach(function (r) {
        const file = resolve_(r['Foto'], map);
        if (file) { try { DriveApp.getFileById(file).setTrashed(true); } catch (e) {} }
        F.sh.deleteRow(r._row);
      });
    const P = table_(pecesSheet_(), PECES_HEADERS);
    const row = P.rows.filter(function (r) { return str_(r['ID']) === pieceId; })[0];
    if (row) {
      const cover = resolve_(row['Portada'], map);
      if (cover) { try { DriveApp.getFileById(cover).setTrashed(true); } catch (e) {} }
      P.sh.deleteRow(row._row);
    }
    return true;
  } finally { lock.releaseLock(); }
}

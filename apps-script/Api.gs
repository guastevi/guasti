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

// El full "Economia Guasti" de l'app web de Gastos (Finances).
const GASTOS = {
  sheetId: '1mREzAqTLYNk7e6Znj6SAwJiIRxpcmq2QdbAi03VfqLQ',
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
    'gastos.dades': () => gastosDades_(p.mes),
    'gastos.afegir': () => withLock_(() => gastosAfegir_(p.moviment, p.mes)),
    'gastos.esborrar': () => withLock_(() => gastosEsborrar_(p.id, p.mes)),
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

// ---------------------------------------------------------------- gastos
// La mateixa lògica que el Codi.gs de l'app web de Gastos, sobre el mateix full.

const G_MOV = 'Moviments';
const G_CAT = 'Categories';
const G_TIPUS = ['Despesa', 'Ingrés', 'Estalvi', 'Inversió'];
const G_TZ = 'Europe/Madrid';

function gastosSS_() {
  return SpreadsheetApp.openById(GASTOS.sheetId);
}

function gastosDades_(mes) {
  const ss = gastosSS_();
  const movs = gLlegirMoviments_(ss);
  const actual = Utilities.formatDate(new Date(), G_TZ, 'yyyy-MM');
  mes = mes || actual;
  const mesos = Array.from(new Set(movs.map(m => m.mes).concat([actual, mes]))).sort().reverse();
  return {
    mes: mes,
    mesActual: actual,
    avui: Utilities.formatDate(new Date(), G_TZ, 'yyyy-MM-dd'),
    mesos: mesos,
    categories: gCategories_(ss, movs),
    conceptes: gConceptes_(movs),
    resum: gResumMes_(movs, mes),
    evolucio: gEvolucio_(movs, mes, 6),
    moviments: movs.filter(m => m.mes === mes)
      .sort((a, b) => b.data.localeCompare(a.data) || b.fila - a.fila),
  };
}

function gastosAfegir_(d, mes) {
  d = d || {};
  const tipus = gTipusCanonic_(d.tipus || 'Despesa');
  const imp = gNum_(d.import);
  const cat = String(d.categoria || '').trim();
  const concepte = String(d.concepte || '').trim();
  if (!tipus) throw new Error('Tipus no vàlid');
  if (!(imp > 0)) throw new Error("L'import ha de ser més gran que 0");
  if (!cat) throw new Error('Falta la categoria');
  const data = gDataDe_(d.data);
  const ss = gastosSS_();
  const nom = gRegistraCategoria_(ss, cat, tipus);
  const sh = ss.getSheetByName(G_MOV);
  const fila = sh.getLastRow() + 1;
  sh.getRange(fila, 2).setNumberFormat('@');
  sh.getRange(fila, 1, 1, 7).setValues([[data, Utilities.formatDate(data, G_TZ, 'yyyy-MM'), tipus, nom, concepte, imp,
    Utilities.getUuid().slice(0, 8)]]);
  const out = gastosDades_(mes);
  out.missatge = 'Desat: ' + imp.toFixed(2).replace('.', ',') + ' € a ' + nom;
  return out;
}

function gastosEsborrar_(id, mes) {
  const sh = gastosSS_().getSheetByName(G_MOV);
  const m = /^FILA-(\d+)$/.exec(String(id));
  let fet = false;
  if (m) {
    sh.deleteRow(Number(m[1]));
    fet = true;
  } else {
    const n = sh.getLastRow() - 1;
    const ids = n > 0 ? sh.getRange(2, 7, n, 1).getValues() : [];
    for (let i = 0; i < ids.length; i++) {
      if (String(ids[i][0]) === String(id)) { sh.deleteRow(i + 2); fet = true; break; }
    }
  }
  if (!fet) throw new Error("No s'ha trobat el moviment");
  return gastosDades_(mes);
}

function gRegistraCategoria_(ss, nom, tipus) {
  const sh = ss.getSheetByName(G_CAT);
  const n = sh.getLastRow() - 1;
  const files = n > 0 ? sh.getRange(2, 1, n, 2).getValues() : [];
  const trobada = files.find(r =>
    String(r[0]).trim().toLowerCase() === nom.toLowerCase() && gTipusCanonic_(r[1]) === tipus);
  if (trobada) return String(trobada[0]).trim();
  const net = nom.charAt(0).toUpperCase() + nom.slice(1);
  sh.getRange(sh.getLastRow() + 1, 1, 1, 2).setValues([[net, tipus]]);
  return net;
}

function gLlegirMoviments_(ss) {
  const sh = ss.getSheetByName(G_MOV);
  if (!sh) return [];
  const n = sh.getLastRow() - 1;
  if (n < 1) return [];
  const out = [];
  sh.getRange(2, 1, n, 7).getValues().forEach((r, i) => {
    const imp = gNum_(r[5]);
    const tipus = gTipusCanonic_(r[2]);
    if (!tipus || !imp) return;
    const dataTxt = r[0] instanceof Date ? Utilities.formatDate(r[0], G_TZ, 'yyyy-MM-dd') : '';
    const mes = dataTxt ? dataTxt.slice(0, 7) : String(r[1]);
    if (!/^\d{4}-\d{2}$/.test(mes)) return;
    out.push({
      fila: i + 2,
      data: dataTxt || mes + '-01',
      mes: mes,
      tipus: tipus,
      categoria: String(r[3]).trim() || 'Sense categoria',
      concepte: String(r[4]).trim(),
      import: gArrod_(imp),
      id: String(r[6] || ('FILA-' + (i + 2))),
    });
  });
  return out;
}

function gResumMes_(movs, mes) {
  const r = { mes: mes, ingressos: 0, despeses: 0, estalvi: 0, inversio: 0 };
  const cats = {}, conc = {}, fonts = {};
  movs.filter(m => m.mes === mes).forEach(m => {
    if (m.tipus === 'Ingrés') {
      r.ingressos += m.import;
      fonts[m.categoria] = (fonts[m.categoria] || 0) + m.import;
    } else if (m.tipus === 'Despesa') {
      r.despeses += m.import;
      cats[m.categoria] = (cats[m.categoria] || 0) + m.import;
      const c = m.concepte || m.categoria;
      conc[c] = (conc[c] || 0) + m.import;
    } else if (m.tipus === 'Estalvi') {
      r.estalvi += m.import;
    } else if (m.tipus === 'Inversió') {
      r.inversio += m.import;
    }
  });
  ['ingressos', 'despeses', 'estalvi', 'inversio'].forEach(k => r[k] = gArrod_(r[k]));
  r.disponible = gArrod_(r.ingressos - r.despeses - r.estalvi - r.inversio);
  r.categories = gOrdena_(cats, r.despeses);
  r.conceptes = gOrdena_(conc, r.despeses).slice(0, 8);
  r.fonts = gOrdena_(fonts, r.ingressos);
  return r;
}

function gEvolucio_(movs, mesFinal, n) {
  let [y, m] = mesFinal.split('-').map(Number);
  const mesos = [];
  for (let i = 0; i < n; i++) {
    mesos.unshift(y + '-' + String(m).padStart(2, '0'));
    m--;
    if (m === 0) { m = 12; y--; }
  }
  return mesos.map(mes => {
    const r = gResumMes_(movs, mes);
    return { mes: mes, ingressos: r.ingressos, despeses: r.despeses, estalvi: gArrod_(r.estalvi + r.inversio) };
  });
}

function gCategories_(ss, movs) {
  const sh = ss.getSheetByName(G_CAT);
  const compte = {};
  G_TIPUS.forEach(t => compte[t] = {});
  const n = sh ? sh.getLastRow() - 1 : 0;
  if (n > 0) {
    sh.getRange(2, 1, n, 2).getValues().forEach(r => {
      const t = gTipusCanonic_(r[1]);
      const nom = String(r[0]).trim();
      if (t && nom && !(nom in compte[t])) compte[t][nom] = 0;
    });
  }
  movs.forEach(m => {
    if (compte[m.tipus]) compte[m.tipus][m.categoria] = (compte[m.tipus][m.categoria] || 0) + 1;
  });
  const out = {};
  G_TIPUS.forEach(t => {
    out[t] = Object.keys(compte[t]).sort((a, b) => compte[t][b] - compte[t][a] || a.localeCompare(b, 'ca'));
  });
  return out;
}

function gConceptes_(movs) {
  const c = {};
  movs.forEach(m => {
    if (!m.concepte) return;
    c[m.categoria] = c[m.categoria] || {};
    c[m.categoria][m.concepte] = (c[m.categoria][m.concepte] || 0) + 1;
  });
  const out = {};
  Object.keys(c).forEach(cat => {
    out[cat] = Object.keys(c[cat]).sort((a, b) => c[cat][b] - c[cat][a]).slice(0, 8);
  });
  return out;
}

function gTipusCanonic_(t) {
  const s = String(t || '').trim().toLowerCase().normalize('NFD').replace(/[\u0300-\u036f]/g, '');
  if (s.indexOf('despes') === 0) return 'Despesa';
  if (s.indexOf('ingres') === 0) return 'Ingrés';
  if (s.indexOf('estalvi') === 0) return 'Estalvi';
  if (s.indexOf('inversi') === 0) return 'Inversió';
  return '';
}

function gNum_(x) {
  if (typeof x === 'number') return x;
  let s = String(x || '').replace(/[\s€]/g, '');
  if (s.indexOf(',') > -1 && s.indexOf('.') > -1) s = s.replace(/\./g, '').replace(',', '.');
  else s = s.replace(',', '.');
  const n = parseFloat(s);
  return isNaN(n) ? 0 : n;
}

function gDataDe_(s) {
  const txt = /^\d{4}-\d{2}-\d{2}$/.test(String(s || ''))
    ? String(s) : Utilities.formatDate(new Date(), G_TZ, 'yyyy-MM-dd');
  const [y, m, d] = txt.split('-').map(Number);
  return new Date(y, m - 1, d, 12);
}

function gOrdena_(obj, total) {
  return Object.keys(obj)
    .map(k => ({ nom: k, total: gArrod_(obj[k]), pct: total ? Math.round(obj[k] / total * 1000) / 10 : 0 }))
    .sort((a, b) => b.total - a.total);
}

function gArrod_(n) { return Math.round(n * 100) / 100; }

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

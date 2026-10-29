// Arxiu de Repertori - Laura Guasteví
// App web sobre Google Sheets + Drive. Sense serveis externs.

const SHEET_ID = '1iNzkRGe8l0Ki-wOdAdvOQyxoYz0yy4pPnpNUkPZYmVs';
const ROOT_FOLDER_ID = '1-3orlwk0E5DpHzg65fDKsnlPP4yELHbq';

const KEYS = {
  Obres: 'ID', Documents: 'ID', Concerts: 'ID',
  Agrupacions: 'Agrupació', Directors: 'Director/a', Fagotades: 'Any'
};
const PREFIX = { Obres: 'O', Documents: 'D', Concerts: 'C' };

// Icona de l'app (partitura), guardada al Drive com a icona-arxiu.png
const ICON_ID = '1HATevkn2gATQOjjwzrFNLufhZ6dxmeZT';

function doGet() {
  const out = HtmlService.createHtmlOutputFromFile('Index')
    .setTitle('Arxiu de Repertori')
    .addMetaTag('viewport', 'width=device-width, initial-scale=1, viewport-fit=cover')
    .addMetaTag('apple-mobile-web-app-capable', 'yes')
    .addMetaTag('mobile-web-app-capable', 'yes')
    .setXFrameOptionsMode(HtmlService.XFrameOptionsMode.ALLOWALL);
  try { out.setFaviconUrl('https://drive.google.com/thumbnail?id=' + ICON_ID + '&sz=w256&format=png'); } catch (e) {}
  return out;
}

function ss_() { return SpreadsheetApp.openById(SHEET_ID); }

function readSheet_(name) {
  const sh = ss_().getSheetByName(name);
  const v = sh.getDataRange().getDisplayValues();
  const h = v.shift();
  const rows = v.filter(r => r.some(c => c !== ''))
    .map(r => { const o = {}; h.forEach((k, i) => o[k] = r[i]); return o; });
  return { headers: h, rows: rows };
}

// Opcions que surten sempre com a botons (es poden ampliar des de l'app)
const DEFAULT_LISTS = {
  'Instrument': ['Fagot sol', 'Fagot i piano', 'Fagot i orquestra', 'Fagot i banda', 'Fagot i cambra',
                 'Fagot 1r', 'Fagot 2n', 'Fagot 3r', 'Fagot/contrafagot', 'Contrafagot',
                 'Fagotino en sol', 'Fagotino en fa', 'Flauta'],
  'Àmbit': ['Concert', 'Fagotada', 'Pedagògic', 'Estudi personal', 'Prova / audició'],
  'Curs': ['Iniciació', 'Elemental 1r', 'Elemental 2n', 'Elemental 3r', 'Elemental 4t',
           'Professional 1r', 'Professional 2n', 'Professional 3r', 'Professional 4t', 'Professional 5è', 'Professional 6è',
           'Música de cambra', 'EMMCA', 'Ministrils', "Toc d'inici"],
  'Centre': ['Vila-seca', "L'Hospitalet"],
  'Tipus document': ['Particel·la', 'Partitura general', 'Programa de concert', 'Mètode / estudis',
                     'Llibre de música', 'Fragments orquestrals', 'Altres'],
  'Format': ['PDF', 'MusicXML', 'MuseScore', 'Notion', 'Finale', 'Sibelius', 'Dorico', 'MIDI', 'Àudio', 'Vídeo', 'Imatge'],
  'Categoria': ['Repertori fagotístic', 'Orquestra', 'Banda', 'Cambra', 'Flauta', 'Teoria musical', 'Llibres'],
  'Formació: Llibres': ['Relaxació', 'Didàctica', 'Canyes de fagot', 'Altres'],
  'Formació: Repertori fagotístic': ['Fagot sol', 'Fagot i piano', 'Fagot i orquestra', 'Fagot i banda', 'Duo de fagots',
    'Trio de fagots', 'Quartet de fagots', 'Quintet de fagots', 'Ensemble de fagots', 'Contrafagot sol', 'Contrafagot i piano',
    'Fagotino', 'Estudis i mètodes', 'Fragments orquestrals'],
  'Formació: Banda': ['Concert', 'Marxes i processons', 'Pasdobles', 'Música festiva', 'Arranjaments'],
  'Formació: Cambra': ['Duo', 'Trio', 'Quartet', 'Quintet de vent', 'Sextet', 'Octet / harmonia', 'Ensemble', 'Amb piano'],
  'Formació: Flauta': ['Flauta sola', 'Flauta i piano', 'Duo de flautes', 'Trio de flautes', 'Quartet de flautes',
    'Ensemble de flautes', 'Estudis i mètodes'],
  'Etiquetes': ['Vila-seca', 'EMMCA', 'Arranjament propi', 'Genís Mayola']
};
// Columna de la fitxa -> llista d'etiquetes
const LIST_OF = { 'Instrument': 'Instrument', 'Instruments': 'Instrument', 'Àmbit': 'Àmbit',
  'Centre': 'Centre', 'Tipus': 'Tipus document', 'Format': 'Format', 'Categoria': 'Categoria' };

function llistesCol_(sh, name) {
  const lastCol = Math.max(sh.getLastColumn(), 1);
  const h = sh.getRange(1, 1, 1, lastCol).getValues()[0];
  let c = h.indexOf(name) + 1;
  if (!c) { c = (h.filter(String).length ? lastCol + 1 : 1); sh.getRange(1, c).setValue(name).setFontWeight('bold'); }
  return c;
}
function colValues_(sh, c) {
  const n = Math.max(sh.getLastRow() - 1, 0);
  return n ? sh.getRange(2, c, n, 1).getDisplayValues().map(r => r[0]).filter(String) : [];
}
function ensureHeader_(sheetName, col) {
  const sh = ss_().getSheetByName(sheetName);
  const h = sh.getRange(1, 1, 1, sh.getLastColumn()).getValues()[0];
  if (h.indexOf(col) === -1) {
    const c = sh.getLastColumn() + 1;
    sh.getRange(1, c).setValue(col);
    sh.getRange(1, 1, 1, c).copyFormatToRange(sh, c, c, 1, 1);
  }
}
function syncLists_() {
  ensureHeader_('Documents', 'Anotacions');
  ensureHeader_('Documents', 'Llibre');
  ensureHeader_('Documents', 'Compositor');
  ensureHeader_('Documents', 'Revisat');
  ensureHeader_('Documents', 'Instrument');
  ensureHeader_('Obres', 'Categoria');
  ensureHeader_('Obres', 'Etiquetes');
  const sh = ss_().getSheetByName('Llistes');
  // Llistes que ja no es fan servir (s'esborren del full)
  ['Formaci\u00f3: Teoria musical'].forEach(name => {
    const h = sh.getRange(1, 1, 1, Math.max(sh.getLastColumn(), 1)).getValues()[0];
    const c = h.indexOf(name) + 1;
    if (c) sh.getRange(1, c, Math.max(sh.getLastRow(), 1), 1).clearContent();
  });
  Object.keys(DEFAULT_LISTS).forEach(name => {
    const c = llistesCol_(sh, name);
    const cur = colValues_(sh, c);
    const gone = name === 'Instrument' ? ['Fagot'] : [];
    const merged = DEFAULT_LISTS[name].concat(cur.filter(v => DEFAULT_LISTS[name].indexOf(v) === -1 && gone.indexOf(v) === -1));
    if (JSON.stringify(merged) !== JSON.stringify(cur)) {
      const n = Math.max(sh.getLastRow() - 1, merged.length);
      sh.getRange(2, c, n, 1).clearContent();
      sh.getRange(2, c, merged.length, 1).setValues(merged.map(v => [v]));
    }
  });
}
function ensureInLlistes_(name, value) {
  if (!value) return;
  const sh = ss_().getSheetByName('Llistes');
  const c = llistesCol_(sh, name);
  const cur = colValues_(sh, c);
  if (cur.indexOf(String(value)) === -1) sh.getRange(cur.length + 2, c).setValue(value);
}
function ensureLabels_(obj) {
  Object.keys(LIST_OF).forEach(k => { if (obj[k]) String(obj[k]).split(k === 'Tipus' || k === 'Instrument' ? /\s*,\s*/ : /\n\n\n/).filter(String).forEach(t => ensureInLlistes_(LIST_OF[k], t)); });
  if (obj['Curs']) String(obj['Curs']).split(/\s*,\s*/).filter(String).forEach(t => ensureInLlistes_('Curs', t));
  if (obj['Etiquetes']) String(obj['Etiquetes']).split(/\s*,\s*/).filter(String).forEach(t => ensureInLlistes_('Etiquetes', t));
  if (obj['Categoria'] && obj['Formació']) ensureInLlistes_('Formació: ' + obj['Categoria'], obj['Formació']);
  if (obj['Agrupació']) ensureInList_('Agrupacions', 'Agrupació', obj['Agrupació']);
  if (obj['Director/a']) ensureInList_('Directors', 'Director/a', obj['Director/a']);
  if (obj['Fagotada']) ensureInList_('Fagotades', 'Any', obj['Fagotada']);
}

// Concerts sense data: si el títol o les notes porten la data ("25 de novembre de 2026", "25/11/2026"), s'omple sola
const MESOS_ = ['gener','febrer','març','abril','maig','juny','juliol','agost','setembre','octubre','novembre','desembre'];
function parseCatDate_(txt) {
  const t = String(txt || '').toLowerCase();
  let m = /\b(\d{1,2})\s+(?:de\s+|d')?(gener|febrer|mar[çc]|abril|maig|juny|juliol|agost|setembre|octubre|novembre|desembre)(?:\s+(?:de\s+|del\s+)?(\d{4}))?/.exec(t);
  let d, mo, y;
  if (m) { d = +m[1]; mo = MESOS_.indexOf(m[2].replace('marc', 'març')) + 1; y = m[3] ? +m[3] : 0; }
  else if ((m = /\b(\d{1,2})[\/.-](\d{1,2})[\/.-](\d{2,4})\b/.exec(t))) { d = +m[1]; mo = +m[2]; y = +m[3]; if (y < 100) y += 2000; }
  else return '';
  if (!(d >= 1 && d <= 31 && mo >= 1 && mo <= 12)) return '';
  if (!y) { const now = new Date(); y = now.getFullYear(); if (new Date(y, mo - 1, d) < new Date(now.getFullYear(), now.getMonth(), now.getDate() - 1)) y++; }
  return y + '-' + ('0' + mo).slice(-2) + '-' + ('0' + d).slice(-2);
}
function fixConcertDates_() {
  const sh = ss_().getSheetByName('Concerts');
  const v = sh.getDataRange().getDisplayValues();
  const h = v[0], di = h.indexOf('Data'), ti = h.indexOf('Títol'), pi = h.indexOf('Programa'), ni = h.indexOf('Notes');
  if (di < 0) return;
  for (let r = 1; r < v.length; r++) {
    if (v[r][di] || !v[r].some(String)) continue;
    const f = parseCatDate_(v[r][ti]) || parseCatDate_(ni > -1 ? v[r][ni] : '') || parseCatDate_(pi > -1 ? v[r][pi] : '');
    if (f) { const c = sh.getRange(r + 1, di + 1); c.setNumberFormat('@'); c.setValue(f); }
  }
}

function getData() {
  try { syncLists_(); } catch (e) {}
  try { fixConcertDates_(); } catch (e) {}
  const out = {};
  ['Obres', 'Documents', 'Concerts', 'Agrupacions', 'Directors', 'Fagotades']
    .forEach(n => out[n] = readSheet_(n));
  const l = ss_().getSheetByName('Llistes').getDataRange().getDisplayValues();
  const h = l.shift();
  out.Llistes = {};
  h.forEach((k, i) => out.Llistes[k] = l.map(r => r[i]).filter(Boolean));
  try { out.pendents = getInventariRows().length; } catch (e) { out.pendents = 0; }
  try { out.url = ScriptApp.getService().getUrl(); } catch (e) {}
  return out;
}

function saveRow(name, obj) {
  const lock = LockService.getScriptLock();
  lock.waitLock(20000);
  try {
    const id = saveRowNoLock_(name, obj);
    // Qualsevol valor nou (agrupació, director/a, instrument, nivell...) passa a ser un botó més
    if (name === 'Obres' || name === 'Concerts' || name === 'Documents') ensureLabels_(obj);
    if (name === 'Documents' && obj['Llibre']) { try { moveDocToBook_(id); } catch (e) {} }
    return id;
  } finally {
    lock.releaseLock();
  }
}

function saveRowNoLock_(name, obj) {
  const sh = ss_().getSheetByName(name);
  if (name === 'Concerts') sh.getRange('B:C').setNumberFormat('@');
  const data = sh.getDataRange().getValues();
  const h = data[0];
  const key = KEYS[name];
  const ki = h.indexOf(key);
  const orig = (obj.__orig !== undefined && obj.__orig !== '') ? obj.__orig : obj[key];
  delete obj.__orig;
  if (PREFIX[name] && !obj[key]) obj[key] = PREFIX[name] + '-' + Utilities.getUuid().slice(0, 8);

  let idx = -1;
  if (orig !== undefined && orig !== '') {
    for (let i = 1; i < data.length; i++) {
      if (String(data[i][ki]) === String(orig)) { idx = i; break; }
    }
  }
  if (idx > 0) {
    const merged = h.map((k, j) => obj[k] !== undefined ? obj[k] : data[idx][j]);
    sh.getRange(idx + 1, 1, 1, h.length).setValues([merged]);
  } else {
    sh.appendRow(h.map(k => obj[k] !== undefined ? obj[k] : ''));
  }
  return obj[key];
}

function ensureInList_(name, col, value) {
  if (!value) return;
  const sh = ss_().getSheetByName(name);
  const vals = sh.getRange(2, 1, Math.max(sh.getLastRow() - 1, 1), 1).getDisplayValues().map(r => r[0]);
  if (vals.indexOf(String(value)) === -1) {
    const h = sh.getRange(1, 1, 1, sh.getLastColumn()).getValues()[0];
    sh.appendRow(h.map(k => k === col ? value : ''));
  }
}

function deleteRow(name, id) {
  const lock = LockService.getScriptLock();
  lock.waitLock(20000);
  try {
    const sh = ss_().getSheetByName(name);
    const data = sh.getDataRange().getValues();
    const ki = data[0].indexOf(KEYS[name]);
    for (let i = 1; i < data.length; i++) {
      if (String(data[i][ki]) === String(id)) { sh.deleteRow(i + 1); return true; }
    }
    return false;
  } finally {
    lock.releaseLock();
  }
}

// Esborra un document de l'arxiu i envia el fitxer a la paperera del Drive (recuperable 30 dies).
// Si el fitxer és d'una altra persona o el fa servir un altre document, només es treu de l'arxiu.
function deleteDocument(id) {
  const lock = LockService.getScriptLock();
  lock.waitLock(20000);
  try {
    const sh = ss_().getSheetByName('Documents');
    const v = sh.getDataRange().getValues();
    const h = v[0], ii = h.indexOf('ID'), fi = h.indexOf('Fitxer'), li = h.indexOf('Enlla\u00e7 Drive');
    const fid = r => { const m = /\/d\/([-\w]{20,})/.exec(String((fi > -1 && r[fi]) || (li > -1 && r[li]) || '')) ||
                               /[?&]id=([-\w]{20,})/.exec(String((fi > -1 && r[fi]) || (li > -1 && r[li]) || '')); return m ? m[1] : ''; };
    let row = -1;
    for (let r = 1; r < v.length; r++) if (String(v[r][ii]) === String(id)) { row = r; break; }
    if (row < 0) return 'No s\'ha trobat el document';
    const f = fid(v[row]);
    let msg = 'Esborrat de l\'arxiu';
    if (f) {
      const shared = v.some((r, i) => i > 0 && i !== row && fid(r) === f);
      if (shared) msg += ' (el fitxer es queda al Drive perqu\u00e8 el fa servir un altre document)';
      else {
        try {
          const file = DriveApp.getFileById(f);
          let me = '', owner = '';
          try { me = DriveApp.getRootFolder().getOwner().getEmail(); } catch (e) {}
          try { owner = file.getOwner() ? file.getOwner().getEmail() : ''; } catch (e) {}
          if (!owner || owner === me) { file.setTrashed(true); msg += ' i enviat a la paperera del Drive'; }
          else msg += ' (el fitxer \u00e9s de ' + owner + ' i no es pot esborrar del seu Drive)';
        } catch (e) { msg += ' (el fitxer ja no era al Drive)'; }
      }
    }
    sh.deleteRow(row + 1);
    return msg;
  } finally {
    lock.releaseLock();
  }
}

// Afegeix o treu un concert de la llista de concerts d'un document (columna Concert, separada per comes)
function linkDocConcert(docId, concertId, add) {
  const lock = LockService.getScriptLock();
  lock.waitLock(20000);
  try {
    const sh = ss_().getSheetByName('Documents');
    const v = sh.getDataRange().getValues();
    const h = v[0], ii = h.indexOf('ID'), ci = h.indexOf('Concert');
    for (let r = 1; r < v.length; r++) {
      if (String(v[r][ii]) !== String(docId)) continue;
      let list = String(v[r][ci] || '').split(/\s*,\s*/).filter(String).filter(x => x !== concertId);
      if (add) list.push(concertId);
      const val = list.join(', ');
      sh.getRange(r + 1, ci + 1).setValue(val);
      return val;
    }
    throw new Error('No s\'ha trobat el document');
  } finally { lock.releaseLock(); }
}

// Els fitxers es desen a "Arxiu de Repertori/Documents/<Tipus>"
function docsFolder_(tipus) {
  const root = DriveApp.getFolderById(ROOT_FOLDER_ID);
  const getOrCreate = (parent, name) => {
    const it = parent.getFoldersByName(name);
    return it.hasNext() ? it.next() : parent.createFolder(name);
  };
  const docs = getOrCreate(root, 'Documents');
  tipus = String(tipus || '').split(/\s*,\s*/)[0];
  return tipus ? getOrCreate(docs, tipus.replace(/\//g, '-')) : docs;
}

function guessFormat_(n) {
  const e = String(n).split('.').pop().toLowerCase();
  const map = {
    pdf: 'PDF', xml: 'MusicXML', musicxml: 'MusicXML', mxl: 'MusicXML',
    mscz: 'MuseScore', mscx: 'MuseScore', notion: 'Notion', musx: 'Finale', mus: 'Finale', sib: 'Sibelius',
    dorico: 'Dorico', mid: 'MIDI', midi: 'MIDI', ly: 'LilyPond', gp: 'Guitar Pro', gpx: 'Guitar Pro',
    mp3: 'Àudio', wav: 'Àudio', m4a: 'Àudio', aif: 'Àudio', aiff: 'Àudio',
    mp4: 'Vídeo', mov: 'Vídeo', jpg: 'Imatge', jpeg: 'Imatge', png: 'Imatge', heic: 'Imatge'
  };
  return map[e] || '';
}

/* ================= INVENTARI DEL DRIVE =================
   Recorre tots els PDFs i fitxers de partitura (MusicXML, MuseScore, Notion)
   del Drive, els classifica i els registra a Documents amb el seu enllaç.
   No mou ni copia cap fitxer. Els que no semblen musicals van a la pestanya
   "Inventari" perquè es puguin revisar i importar després.
   Si s'atura per temps, es torna a executar i continua on era. */

const MUSIC_WORDS = /fagot|fagott|bassoon|basson|contrafag|contrabass|fagotin|\bfg\b|partitura|particel|\bscore\b|\bparts?\b|concert|sonata|sonatin|estudi|studies|studien|etude|metode|metodo|method|schule|album|duet|duo\b|trio|quartet|quintet|sextet|octet|sinfon|symphon|simfon|suite|polca|polka|vals|waltz|marxa|march|sardana|cancon|canco|opera|traviata|tosca|butterfly|boheme|carmen|mozart|vivaldi|weber|kozeluch|rota|bozza|telemann|haydn|beethoven|brahms|bach|handel|elgar|saint.?saens|probespiel|excerpt|flauta|flute|oboe|clarinet|trompa|horn|trompeta|trumpet|trombo|violi|violin|viola|cello|violoncel|contrabaix|piano|arpa|harp|percussi|timpani|director|banda|orquestra|orchestra|fagotada|repertori|lieder|classics|melod|harmony|band.?time/;
const MUSIC_FOLDERS = /fagot|bassoon|repertori|partitur|banda|orquestra|orchestra|camerata|osv|morphosis|fagotada|concert|alumnes|elemental|professional|iniciacio|musica|music|opera|tosca|traviata|butterfly|cambra|quintet|quartet|duo|trio|metode|estudis/;

function norm_(s) {
  return String(s || '').toLowerCase().normalize('NFD').replace(/[\u0300-\u036f]/g, '');
}

function tipus_(n) {
  if (/probespiel|excerpt|orchesterstud|orchestral stud|fragments? orquestr|pasajes/.test(n)) return 'Fragments orquestrals';
  if (/\bprograma\b|\bprogram\b|programm|\bprog\b/.test(n)) return 'Programa de concert';
  if (/estudi|studies|studien|\bstudy|etude|metode|metodo|method|schule|exercic|escales|scales|technical|tecnic|lessons|llicons|schnellkurs|warm.?up|starter/.test(n)) return 'Mètode / estudis';
  if (/album|collection|classics|duets|lieder|songbook|llibre|\bbook|volum|\bvol\b|antolog|easy|pieces|piezas|\bpeces|lieblings|barock|band.?time/.test(n)) return 'Llibre de música';
  if (/general|director|full.?score|\bscore\b|partitura|fg i pno|fg_i_pno|i piano|and piano/.test(n)) return 'Partitura general';
  return 'Particel·la';
}

function inventari() {
  const t0 = Date.now();
  const props = PropertiesService.getUserProperties();
  const ss = ss_();
  ensureTipusLlibre_(ss);

  // Pestanya Inventari (per als fitxers dubtosos)
  let inv = ss.getSheetByName('Inventari');
  if (!inv) {
    inv = ss.insertSheet('Inventari');
    inv.appendRow(['Incloure', 'Títol', 'Tipus proposat', 'Format', 'Carpeta', 'Enllaç', 'ID fitxer', 'Propietari']);
    inv.getRange('1:1').setFontWeight('bold');
  }

  // IDs ja registrats (a Documents o a Inventari) i claus de duplicat
  const docs = ss.getSheetByName('Documents');
  const dv = docs.getDataRange().getValues();
  const dh = dv[0];
  const seen = {};
  const dupKey = {};
  const linkCol = dh.indexOf('Enllaç Drive');
  dv.slice(1).forEach(r => { const m = /[-\w]{25,}/.exec(r[linkCol] || ''); if (m) seen[m[0]] = true; });
  inv.getDataRange().getValues().slice(1).forEach(r => { if (r[6]) seen[r[6]] = true; });
  const stored = props.getProperty('INV_DUPS');
  if (stored) Object.assign(dupKey, JSON.parse(stored));

  const q = "trashed = false and (mimeType = 'application/pdf' or title contains '.mscz' or title contains '.mscx' " +
            "or title contains '.musicxml' or title contains '.mxl' or title contains '.xml' or title contains '.notion' " +
            "or title contains '.musx' or title contains '.mus' or title contains '.sib' or title contains '.dorico' or title contains '.mid')";
  const token = props.getProperty('INV_TOKEN');
  const it = token ? DriveApp.continueFileIterator(token) : DriveApp.searchFiles(q);

  let me = '';
  try { me = DriveApp.getRootFolder().getOwner().getEmail(); } catch (e) {}
  const newDocs = [], newInv = [];
  let processed = 0, done = true;
  while (it.hasNext()) {
    if (Date.now() - t0 > 4.5 * 60 * 1000) { done = false; break; }
    const f = it.next();
    processed++;
    const id = f.getId();
    if (seen[id]) continue;
    seen[id] = true;
    if (id === SHEET_ID) continue;

    const name = f.getName();
    const ext = name.split('.').pop().toLowerCase();
    if (f.getMimeType() !== 'application/pdf' && !/^(mscz|mscx|musicxml|mxl|xml|notion|musx|mus|sib|dorico|mid|midi)$/.test(ext)) continue;
    if (ext === 'xml' && !/score|partwise|musicxml/i.test(f.getMimeType() + name)) {
      // els .xml genèrics només si semblen partitura pel nom
      if (!MUSIC_WORDS.test(norm_(name))) continue;
    }
    let folder = '';
    try { const ps = f.getParents(); if (ps.hasNext()) folder = ps.next().getName(); } catch (e) {}
    let owner = '';
    try { owner = f.getOwner() ? f.getOwner().getEmail() : ''; } catch (e) {}

    const n = norm_(name.replace(/\.[^.]+$/, '').replace(/[_-]+/g, ' '));
    const isScoreFile = /^(mscz|mscx|musicxml|mxl|notion|musx|mus|sib|dorico|mid|midi)$/.test(ext);
    const isMusic = isScoreFile || MUSIC_WORDS.test(n) || MUSIC_FOLDERS.test(norm_(folder));
    const tipus = tipus_(n);
    const format = guessFormat_(name) || 'PDF';
    const title = name.replace(/\.[^.]+$/, '').replace(/^(c[oò]pia de |copy of )/i, '').trim();

    // Duplicats: mateix nom net i mateixa mida
    const key = norm_(title).replace(/\s*\(\d+\)$|\s+\d$/, '') + '|' + f.getSize();
    let notes = 'Carpeta: ' + (folder || '(arrel)');
    if (owner && owner !== me) notes += ' · Compartit per ' + owner;
    if (dupKey[key]) notes += ' · DUPLICAT (ja registrat: ' + dupKey[key] + ')';
    else dupKey[key] = folder || '(arrel)';

    if (isMusic) {
      const g = classify_(title, notes);
      newDocs.push({ 'ID': 'D-' + Utilities.getUuid().slice(0, 8), 'Títol': title, 'Tipus': tipus,
        'Format': format, 'Enllaç Drive': f.getUrl(), 'Notes': notes,
        'Categoria': g.cat, 'Formació': g.form, 'Curs': g.curs.join(', ') });
    } else {
      newInv.push(['', title, tipus, format, folder, f.getUrl(), id, owner]);
    }
  }

  if (newDocs.length) {
    const rowsOut = newDocs.map(o => dh.map(k => o[k] !== undefined ? o[k] : ''));
    docs.getRange(docs.getLastRow() + 1, 1, rowsOut.length, dh.length).setValues(rowsOut);
  }
  if (newInv.length) inv.getRange(inv.getLastRow() + 1, 1, newInv.length, newInv[0].length).setValues(newInv);

  props.setProperty('INV_DUPS', JSON.stringify(dupKey));
  if (done) { props.deleteProperty('INV_TOKEN'); props.deleteProperty('INV_DUPS'); }
  else props.setProperty('INV_TOKEN', it.getContinuationToken());

  const msg = (done ? 'Inventari acabat. ' : 'Inventari parcial (torna a executar per continuar). ') +
    'Revisats: ' + processed + ' · Afegits a Documents: ' + newDocs.length + ' · A revisar: ' + newInv.length;
  Logger.log(msg);
  return msg;
}

// Importa a Documents les files de la pestanya Inventari marcades amb "Sí" a la columna Incloure
function importaInventari() {
  const ss = ss_();
  const inv = ss.getSheetByName('Inventari');
  if (!inv) return 'No hi ha pestanya Inventari';
  const v = inv.getDataRange().getValues();
  const docs = ss.getSheetByName('Documents');
  const dh = docs.getRange(1, 1, 1, docs.getLastColumn()).getValues()[0];
  const out = [], keep = [v[0]];
  v.slice(1).forEach(r => {
    if (/^(si|sí|x|true)$/i.test(String(r[0]).trim())) {
      const o = { 'ID': 'D-' + Utilities.getUuid().slice(0, 8), 'Títol': r[1], 'Tipus': r[2], 'Format': r[3],
        'Enllaç Drive': r[5], 'Notes': 'Carpeta: ' + (r[4] || '(arrel)') };
      out.push(dh.map(k => o[k] !== undefined ? o[k] : ''));
    } else keep.push(r);
  });
  if (out.length) docs.getRange(docs.getLastRow() + 1, 1, out.length, dh.length).setValues(out);
  inv.clearContents();
  inv.getRange(1, 1, keep.length, keep[0].length).setValues(keep);
  return 'Importats: ' + out.length;
}

function ensureTipusLlibre_(ss) {
  const l = ss.getSheetByName('Llistes');
  const h = l.getRange(1, 1, 1, l.getLastColumn()).getValues()[0];
  const c = h.indexOf('Tipus document') + 1;
  const vals = l.getRange(2, c, l.getLastRow(), 1).getValues().map(r => r[0]).filter(String);
  if (vals.indexOf('Llibre de música') === -1) l.getRange(vals.length + 2, c).setValue('Llibre de música');
}

function getInventari() {
  const sh = ss_().getSheetByName('Inventari');
  return sh ? sh.getLastRow() - 1 : 0;
}

function uploadFile(p) {
  const blob = Utilities.newBlob(Utilities.base64Decode(p.data),
    p.mimeType || 'application/octet-stream', p.name);
  const meta = p.meta || {};
  const f = docsFolder_(meta['Tipus']).createFile(blob);
  meta['Fitxer'] = f.getUrl();
  if (!meta['Títol']) meta['Títol'] = p.name.replace(/\.[^.]+$/, '');
  if (!meta['Format']) meta['Format'] = guessFormat_(p.name);
  const lock = LockService.getScriptLock();
  lock.waitLock(20000);
  try { const id = saveRowNoLock_('Documents', meta); ensureLabels_(meta); return id; } finally { lock.releaseLock(); }
}

/* ================= CLASSIFICACIÓ AUTOMÀTICA DE DOCUMENTS =================
   A partir del nom del fitxer i de la carpeta (guardada a Notes) endevina
   Categoria, Formació i Curs. Només omple els camps buits. */
function classify_(title, notes) {
  const folder = (String(notes || '').match(/Carpeta: ([^\u00b7]*)/) || [, ''])[1];
  const t = norm_(String(title).replace(/[_\-]+/g, ' '));
  const f = norm_(folder);
  const all = t + ' ' + f;
  const out = { cat: '', form: '', curs: [] };

  // Cursos (sobretot a partir de les carpetes de Vila-seca)
  const ord = { '1': '1r', '2': '2n', '3': '3r', '4': '4t', '5': '5è', '6': '6è' };
  let m = /(\d)\S*\s*(?:i|,|-)\s*(\d)\S*\s*(?:de\s*)?grau professional/.exec(all);
  if (m) { out.curs.push('Professional ' + ord[m[1]], 'Professional ' + ord[m[2]]); }
  else if ((m = /(\d)\S*\s*(?:de\s*)?grau professional|professional\s*(\d)/.exec(all))) out.curs.push('Professional ' + ord[m[1] || m[2]]);
  if ((m = /(\d)\S*\s*(?:i|,|-)\s*(\d)\S*\s*(?:de\s*)?(?:grau\s*)?elemental/.exec(all))) out.curs.push('Elemental ' + ord[m[1]], 'Elemental ' + ord[m[2]]);
  else if ((m = /(\d)\S*\s*(?:de\s*)?(?:grau\s*)?elemental|elemental\s*(\d)/.exec(all))) out.curs.push('Elemental ' + ord[m[1] || m[2]]);
  if (/iniciaci/.test(all)) out.curs.push('Iniciació');
  out.curs = out.curs.filter(c => !/undefined/.test(c));

  const fag = /fagot|fagott|fagpt|bassoon|basson|\bfg\b|\bfgs?\b/.test(all);
  const contra = /contrafag|contrabassoon|kontrafag/.test(all);
  const num = (() => { const x = /\b(\d)\s*(?:fagot|fagots|fagotes|fagotti|bassoons|fg)\b/.exec(t); return x ? +x[1] : 0; })();

  // Òpera i orquestra (tot dins Orquestra)
  if (/tosca|traviata|butterf+ly|turandot|schicchi|boheme|carmen|rigoletto|nabucco|aida|sarsuela|zarzuela|opera|simfon|symphon|sinfon|obertura|overture|ouverture|orquestra|orchestra|\bosv\b|camerata|dansa eslava|slavonic/.test(all) && !/fagotada/.test(all)) {
    out.cat = 'Orquestra';
  }
  if (/banda|\bband\b|band time|pasdoble|pasodoble|marxa|marcha|processo/.test(all)) { out.cat = 'Banda';
    out.form = /pasdoble|pasodoble/.test(all) ? 'Pasdobles' : /marxa|marcha|processo/.test(all) ? 'Marxes i processons' : ''; }
  // Teoria musical
  if (/teoria|llenguatge musical|lenguaje musical|solfeig|solfeo|harmonia|armonia|harmony|dictat|dictado|analisi musical|analisis musical|historia de la musica|music theory/.test(all)) {
    out.cat = 'Teoria musical';
    return out;
  }
  // Llibres (relaxaci\u00f3, did\u00e0ctica, canyes...)
  if (/canya|canyes|\breeds?\b|reed ?making|cana de fagot|canas|rohrbau/.test(all)) { out.cat = 'Llibres'; out.form = 'Canyes de fagot'; return out; }
  if (/relax|mindful|ioga|yoga|respiraci|alexander|meditaci|ansietat|ansiedad|esc\u00e8nica|miedo escenico|por esc/.test(all)) { out.cat = 'Llibres'; out.form = 'Relaxaci\u00f3'; return out; }
  if (/didactic|pedagog|ensenyament|ensenanza|ense\u00f1anza|teaching/.test(all)) { out.cat = 'Llibres'; out.form = 'Did\u00e0ctica'; return out; }
  if (/flaut|flute|flote/.test(all) && !fag) { out.cat = 'Flauta';
    out.form = /estudi|studies|etude|metode|method/.test(all) ? 'Estudis i mètodes' : /piano/.test(all) ? 'Flauta i piano' : ''; }

  // Repertori fagotístic (té prioritat si el fitxer és clarament de fagot i no és una part d'orquestra)
  // Particel·les numerades (Fagot 1, Bassoon II...) sense pistes de repertori propi: són d'orquestra o banda
  const part = (/^\d{1,3}\s/.test(t) || /(?:fagot+|fagpt|bassoon|basson|fg|contrafagot)\s*(?:n\.?\s*|no\.?\s*)?(?:[1-4]\b|[1-4](?:r|n|t|st|nd|rd|o|a)\b|i{1,3}\b|iv\b|primer|segon)/.test(t)) &&
    !/estudi|studies|studien|etude|metode|method|schule|sonat|concert|konzert|solo|piano|pno|klavier|duo|duet|trio|quartet|cuarteto|quintet|ensemble|fagotino|fagottino|fagotada|probespiel|excerpt/.test(all) && !num;
  const isFagRep = (fag || contra) && !out.cat && !part ||
    /fagotada|fagotino|probespiel|excerpt|duets? .*fagot|fagots? i contrafagot|bassoon (duet|trio|quartet)/.test(all);
  if (isFagRep) {
    out.cat = 'Repertori fagotístic';
    if (/probespiel|excerpt|orchesterstud|fragment/.test(all)) out.form = 'Fragments orquestrals';
    else if (/fagotino|mini bas+on|fagottino/.test(all)) out.form = 'Fagotino';
    else if (/estudi|studies|studien|etude|metode|method|schule|schnellkurs|starter|technical/.test(all)) out.form = 'Estudis i mètodes';
    else if (/concert|concerto|konzert/.test(all) && !/concert de|concert pedag/.test(all)) out.form = 'Fagot i orquestra';
    else if (/piano|pno|klavier/.test(all)) out.form = contra && !fag ? 'Contrafagot i piano' : 'Fagot i piano';
    else if (num >= 6 || /ensemble|fagotada/.test(all)) out.form = 'Ensemble de fagots';
    else if (num === 5 || /quintet/.test(all)) out.form = 'Quintet de fagots';
    else if (num === 4 || /quartet|cuarteto/.test(all)) out.form = 'Quartet de fagots';
    else if (num === 3 || /trio/.test(all)) out.form = 'Trio de fagots';
    else if (num === 2 || /duet|duo/.test(all)) out.form = 'Duo de fagots';
    else if (contra && !fag) out.form = 'Contrafagot sol';
  } else if (!out.cat && /quintet de vent|wind quintet|woodwind|blaser|quinteto de viento/.test(all)) {
    out.cat = 'Cambra'; out.form = 'Quintet de vent';
  } else if (!out.cat && /\btrio\b|\bduo\b|quartet|cuarteto|sextet|octet/.test(all)) {
    out.cat = 'Cambra';
    out.form = /trio/.test(all) ? 'Trio' : /duo/.test(all) ? 'Duo' : /quartet|cuarteto/.test(all) ? 'Quartet' : /sextet/.test(all) ? 'Sextet' : 'Octet / harmonia';
  }
  return out;
}

function classificaDocuments(reset) {
  // Regles millorades (v2): es tornen a calcular un sol cop totes les classificacions automàtiques
  const props = PropertiesService.getScriptProperties();
  if (props.getProperty('classV') !== '2') { reset = true; props.setProperty('classV', '2'); }
  ensureHeader_('Documents', 'Categoria');
  ensureHeader_('Documents', 'Formació');
  ensureHeader_('Documents', 'Curs');
  const sh = ss_().getSheetByName('Documents');
  const v = sh.getDataRange().getValues();
  const h = v[0];
  const ci = h.indexOf('Categoria'), fi = h.indexOf('Formació'), ki = h.indexOf('Curs');
  const ti = h.indexOf('Títol'), ni = h.indexOf('Notes');
  let changed = 0;
  for (let r = 1; r < v.length; r++) {
    if (reset === true) { v[r][ci] = ''; v[r][fi] = ''; v[r][ki] = ''; }
    if (v[r][ci] && v[r][fi] && v[r][ki]) continue;
    const g = classify_(v[r][ti], v[r][ni]);
    if (!v[r][ci] && g.cat) { v[r][ci] = g.cat; changed++; }
    if (!v[r][fi] && g.form && (v[r][ci] === g.cat)) v[r][fi] = g.form;
    if (!v[r][ki] && g.curs.length) v[r][ki] = g.curs.join(', ');
  }
  sh.getRange(1, 1, v.length, h.length).setValues(v);
  return 'Classificats: ' + changed + ' de ' + (v.length - 1) + ' \u00b7 ' + agrupaLlibres() + ' \u00b7 ' + omplirCompositors() + ' \u00b7 ' + omplirInstruments();
}

/* ================= COMPOSITORS =================
   Omple el camp Compositor dels documents que no en tenen si el nom del fitxer
   (o la carpeta) cont\u00e9 el cognom d'un compositor conegut. No toca els que ja en tenen. */
const COMPOSITORS = ['Albéniz','Albinoni','Arban','Arnold','Bach','Barber','Bartók','Beethoven','Berlioz','Bernstein','Bitsch','Bizet',
  'Boismortier','Borodin','Bozza','Brahms','Britten','Bruckner','Busser','Casals','Chopin','Cimarosa','Copland','Corelli','Corrette',
  'Danzi','Debussy','Delibes','Devienne','Donizetti','Dukas','Dutilleux','Dvořák','Elgar','Falla','Fasch','Fauré','Françaix','Galliard',
  'Gershwin','Glinka','Glière','Gluck','Gounod','Granados','Grieg','Handel','Haydn','Hindemith','Holst','Hummel','Ibert','Jacob','Jancourt',
  'Janáček','Kozeluch','Kopprasch','Krommer','Lalo','Leoncavallo','Mahler','Marcello','Mascagni','Massenet','Mendelssohn','Milde','Mompou',
  'Montsalvatge','Morera','Mozart','Mussorgsky','Nielsen','Offenbach','Orff','Ozi','Pachelbel','Paganini','Pergolesi','Piazzolla','Pierné',
  'Ponchielli','Poulenc','Prokofiev','Puccini','Purcell','Rachmaninov','Rameau','Ravel','Reicha','Respighi','Rimsky-Korsakov','Rossini',
  'Rota','Saint-Saëns','Satie','Scarlatti','Schubert','Schumann','Shostakovich','Sibelius','Smetana','Sousa','Strauss','Stravinsky','Tansman',
  'Tchaikovsky','Telemann','Toldrà','Tomasi','Turina','Vaughan Williams','Verdi','Villa-Lobos','Vivaldi','Wagner','Weber','Weissenborn',
  'Williams','Wolf-Ferrari','Zelenka'];
function omplirCompositors() {
  ensureHeader_('Documents', 'Compositor');
  const sh = ss_().getSheetByName('Documents');
  const v = sh.getDataRange().getValues();
  const h = v[0], ti = h.indexOf('T\u00edtol'), ni = h.indexOf('Notes'), ci = h.indexOf('Compositor');
  const keys = COMPOSITORS.map(n => ({ n: n, re: new RegExp('(^|[^a-z])' + norm_(n).replace(/[-\s]/g, '[- _]?') + '([^a-z]|$)') }));
  const alias = [[/tchaik|chaikovs|tschaik/, 'Tchaikovsky'], [/shostak|chostak|schostak/, 'Shostakovich'], [/dvorak/, 'Dvořák'],
    [/haendel|h\u00e4ndel/, 'Handel'], [/rimski/, 'Rimsky-Korsakov'], [/rachmanin|rajmanin/, 'Rachmaninov'], [/prokofi/, 'Prokofiev'],
    [/tosca|turandot|boheme|butterf+ly|schicchi|manon lescaut/, 'Puccini'], [/traviata|rigoletto|nabucco|\baida\b|trovatore|otello|falstaff/, 'Verdi'],
    [/\bcarmen\b|arlesienne/, 'Bizet'], [/west side story/, 'Bernstein'], [/bolero/, 'Ravel'], [/flauta magica|zauberflote|don giovanni|nozze di figaro/, 'Mozart'],
    [/barbiere|guillaume tell|gazza ladra/, 'Rossini'], [/cavalleria rusticana/, 'Mascagni'], [/pagliacci/, 'Leoncavallo']];
  let n = 0;
  for (let r = 1; r < v.length; r++) {
    if (v[r][ci]) continue;
    const folder = (String(v[r][ni] || '').match(/Carpeta: ([^\u00b7]*)/) || [, ''])[1];
    const t = norm_(String(v[r][ti]).replace(/[_]+/g, ' ')) + ' | ' + norm_(folder);
    let hit = keys.filter(k => k.re.test(t)).map(k => k.n);
    if (!hit.length) alias.forEach(a => { if (a[0].test(t)) hit.push(a[1]); });
    // "Williams" i "Strauss" nom\u00e9s si no n'hi ha cap altre (s\u00f3n cognoms massa comuns)
    if (hit.length > 1) hit = hit.filter(x => x !== 'Williams');
    if (hit.length === 1) { v[r][ci] = hit[0]; n++; }
  }
  if (n) sh.getRange(1, 1, v.length, h.length).setValues(v);
  return 'Compositors trobats: ' + n;
}

/* ================= LLIBRES / RECULLS =================
   Els fitxers d'un mateix llibre ("06 BASSOON - World Tour", "07 1st TRUMPET - World Tour"...)
   es marquen amb el mateix valor a la columna Llibre i a l'app es mostren junts. */
function agrupaLlibres() {
  ensureHeader_('Documents', 'Llibre');
  const sh = ss_().getSheetByName('Documents');
  const v = sh.getDataRange().getValues();
  const h = v[0], ti = h.indexOf('T\u00edtol'), li = h.indexOf('Llibre');
  const count = {}, name = {};
  const suf = t => { const m = /^\s*\d{1,3}[a-z]?[\s.]+.+?\s+-\s+([^-]{5,})$/i.exec(String(t)); return m ? m[1].trim() : ''; };
  for (let r = 1; r < v.length; r++) {
    const s = suf(v[r][ti]); if (!s) continue;
    const k = norm_(s);
    if (/fagot|bassoon|\bfg\b|\bpart|score|general|piano|flaut|flute|oboe|clarinet|sax|trompet|trumpet|trompa|horn|trombo|tuba|percus|timbal|timpani|violi|viola|cello|violoncel|contrabai|bass|guitar|\d/.test(k)) continue;
    count[k] = (count[k] || 0) + 1; name[k] = name[k] || s;
  }
  const books = Object.keys(count).filter(k => count[k] >= 4);
  let n = 0;
  for (let r = 1; r < v.length; r++) {
    if (v[r][li]) continue;
    const t = norm_(v[r][ti]);
    const k = books.filter(b => t.slice(-b.length - 3) === ' - ' + b || t.slice(-b.length - 2) === '- ' + b)[0];
    if (k) { v[r][li] = name[k]; n++; }
  }
  if (n) sh.getRange(1, 1, v.length, h.length).setValues(v);
  return 'Agrupats en llibres: ' + n + ' fitxers (' + books.length + ' llibres)';
}

// Posa (o treu, amb nom buit) el mateix llibre a tots els documents d'una carpeta, o a una llista d'IDs
function setLlibre(ids, folder, llibre) {
  ensureHeader_('Documents', 'Llibre');
  const sh = ss_().getSheetByName('Documents');
  const v = sh.getDataRange().getValues();
  const h = v[0], li = h.indexOf('Llibre'), ni = h.indexOf('Notes'), ii = h.indexOf('ID');
  const want = {}; (ids || []).forEach(i => want[i] = true);
  let n = 0;
  for (let r = 1; r < v.length; r++) {
    const inFolder = folder && String(v[r][ni]).indexOf('Carpeta: ' + folder) === 0 &&
      /^(\s*\u00b7|$)/.test(String(v[r][ni]).slice(('Carpeta: ' + folder).length));
    if (want[v[r][ii]] || inFolder) { v[r][li] = llibre || ''; n++; }
  }
  if (n) sh.getRange(1, 1, v.length, h.length).setValues(v);
  if (n && llibre) { try { moveBook(llibre); } catch (e) {} }
  return n;
}

/* ================= LLIBRES AL DRIVE =================
   Els fitxers d'un llibre es mouen a Arxiu de Repertori / Llibres / <nom del llibre>.
   L'enllaç no canvia (el fitxer és el mateix), només la carpeta. Si el fitxer és d'una altra
   persona no es pot moure: s'hi posa una drecera. */
function bookFolder_(llibre) {
  const root = DriveApp.getFolderById(ROOT_FOLDER_ID);
  const sub = (parent, name) => { const it = parent.getFoldersByName(name); return it.hasNext() ? it.next() : parent.createFolder(name); };
  return sub(sub(root, 'Llibres'), String(llibre).replace(/[\/\\]+/g, '-').trim());
}
function docFileId_(h, row) {
  const fi = h.indexOf('Fitxer'), li = h.indexOf('Enllaç Drive');
  const s = String((fi > -1 && row[fi]) || (li > -1 && row[li]) || '');
  const m = /\/d\/([-\w]{20,})/.exec(s) || /[?&]id=([-\w]{20,})/.exec(s);
  return m ? m[1] : '';
}
// Mou un fitxer a la carpeta del llibre. Retorna 'mogut', 'drecera', 'ja hi era' o ''
function moveFileToBook_(fid, folder, me) {
  if (!fid) return '';
  let file; try { file = DriveApp.getFileById(fid); } catch (e) { return ''; }
  const fidFolder = folder.getId();
  const ps = file.getParents();
  while (ps.hasNext()) if (ps.next().getId() === fidFolder) return 'ja hi era';
  let owner = ''; try { owner = file.getOwner() ? file.getOwner().getEmail() : ''; } catch (e) {}
  if (!owner || owner === me) { file.moveTo(folder); return 'mogut'; }
  const it = folder.getFilesByType(MimeType.SHORTCUT);
  while (it.hasNext()) { try { if (it.next().getTargetId() === fid) return 'ja hi era'; } catch (e) {} }
  folder.createShortcut(fid); return 'drecera';
}
function setCarpetaNote_(note, llibre) {
  const c = 'Carpeta: Llibres/' + llibre;
  note = String(note || '');
  return /^Carpeta: [^·]*/.test(note) ? note.replace(/^Carpeta: [^·]*?(\s*(·|$))/, c + '$1') : (note ? c + ' · ' + note : c);
}
function moveBook(llibre) {
  if (!llibre) return 'Sense llibre';
  const sh = ss_().getSheetByName('Documents');
  const v = sh.getDataRange().getValues();
  const h = v[0], li = h.indexOf('Llibre'), ni = h.indexOf('Notes');
  const folder = bookFolder_(llibre);
  let me = ''; try { me = DriveApp.getRootFolder().getOwner().getEmail(); } catch (e) {}
  const c = { 'mogut': 0, 'drecera': 0, 'ja hi era': 0 }, seen = {};
  const t0 = Date.now();
  let pend = 0;
  for (let r = 1; r < v.length; r++) {
    if (String(v[r][li]) !== String(llibre)) continue;
    const fid = docFileId_(h, v[r]);
    if (!fid || seen[fid]) continue;
    if (Date.now() - t0 > 300000) { pend++; continue; }
    seen[fid] = 1;
    const res = moveFileToBook_(fid, folder, me);
    if (res) { c[res]++; if (ni > -1) v[r][ni] = setCarpetaNote_(v[r][ni], llibre); }
  }
  if (ni > -1) sh.getRange(1, ni + 1, v.length, 1).setValues(v.map(x => [x[ni]]));
  return 'Carpeta Llibres/' + llibre + ': ' + c['mogut'] + ' fitxers moguts' +
    (c['drecera'] ? ', ' + c['drecera'] + ' dreceres (fitxers d\'altres persones)' : '') +
    (c['ja hi era'] ? ', ' + c['ja hi era'] + ' ja hi eren' : '') + (pend ? '. En queden ' + pend + ': torna a tocar el botó' : '');
}
// Quan es desa un document amb llibre, el seu fitxer va a la carpeta del llibre
function moveDocToBook_(docId) {
  const sh = ss_().getSheetByName('Documents');
  const v = sh.getDataRange().getValues();
  const h = v[0], ii = h.indexOf('ID'), li = h.indexOf('Llibre'), ni = h.indexOf('Notes');
  for (let r = 1; r < v.length; r++) {
    if (String(v[r][ii]) !== String(docId)) continue;
    const llibre = String(v[r][li] || '');
    if (!llibre) return;
    let me = ''; try { me = DriveApp.getRootFolder().getOwner().getEmail(); } catch (e) {}
    const res = moveFileToBook_(docFileId_(h, v[r]), bookFolder_(llibre), me);
    if (res && ni > -1) sh.getRange(r + 1, ni + 1).setValue(setCarpetaNote_(v[r][ni], llibre));
    return;
  }
}

/* ================= REVISIÓ DE L'INVENTARI ================= */
function getInventariRows() {
  const sh = ss_().getSheetByName('Inventari');
  if (!sh) return [];
  const v = sh.getDataRange().getValues();
  return v.slice(1).filter(r => !r[0]).map(r => ({ t: r[1], tipus: r[2], fmt: r[3], folder: r[4], url: r[5], id: r[6], owner: r[7] }));
}

// include = true -> passa a Documents; false -> queda marcat "No" i no torna a sortir
function decideInventari(id, include) {
  const lock = LockService.getScriptLock();
  lock.waitLock(20000);
  try {
    const ss = ss_();
    const inv = ss.getSheetByName('Inventari');
    const v = inv.getDataRange().getValues();
    for (let i = 1; i < v.length; i++) {
      if (String(v[i][6]) !== String(id)) continue;
      if (include) {
        const r = v[i];
        const docs = ss.getSheetByName('Documents');
        const dh = docs.getRange(1, 1, 1, docs.getLastColumn()).getValues()[0];
        const notes = 'Carpeta: ' + (r[4] || '(arrel)');
        const g = classify_(r[1], notes);
        const o = { 'ID': 'D-' + Utilities.getUuid().slice(0, 8), 'Títol': r[1], 'Tipus': r[2], 'Format': r[3],
          'Enllaç Drive': r[5], 'Notes': notes, 'Categoria': g.cat, 'Formació': g.form, 'Curs': g.curs.join(', ') };
        docs.appendRow(dh.map(k => o[k] !== undefined ? o[k] : ''));
        inv.deleteRow(i + 1);
        return o['ID'];
      } else {
        inv.getRange(i + 1, 1).setValue('No');
        return '';
      }
    }
    return '';
  } finally { lock.releaseLock(); }
}

/* ================= COMPARTIR ================= */
function getShareInfo(id) {
  const f = DriveApp.getFileById(id);
  let me = '', owner = '';
  try { me = DriveApp.getRootFolder().getOwner().getEmail(); } catch (e) {}
  try { owner = f.getOwner() ? f.getOwner().getEmail() : ''; } catch (e) {}
  let isPublic = false;
  try { const a = f.getSharingAccess(); isPublic = (a === DriveApp.Access.ANYONE_WITH_LINK || a === DriveApp.Access.ANYONE); } catch (e) {}
  return { name: f.getName(), size: f.getSize(), mime: f.getMimeType(), url: f.getUrl(),
           isPublic: isPublic, canLink: !owner || owner === me };
}

// Fa que l'enllaç es pugui obrir sense compte (només lectura). Només per a fitxers propis.
function makePublicLink(id) {
  const f = DriveApp.getFileById(id);
  f.setSharing(DriveApp.Access.ANYONE_WITH_LINK, DriveApp.Permission.VIEW);
  return f.getUrl();
}

// Retorna el fitxer en base64 per enviar-lo directament (fins a ~20 MB)
function getFileData(id) {
  const f = DriveApp.getFileById(id);
  if (f.getSize() > 20 * 1024 * 1024) throw new Error('El fitxer fa més de 20 MB: envia millor l\'enllaç.');
  const b = f.getBlob();
  return { name: f.getName(), mime: b.getContentType() || 'application/pdf', data: Utilities.base64Encode(b.getBytes()) };
}

/* ================= EDICIÓ DE PÀGINES DEL PDF =================
   L'app munta el PDF nou al navegador (treure, girar, ordenar, afegir pàgines)
   i aquí només es desa. Si el fitxer és teu se substitueix el contingut (mateix enllaç,
   el Drive guarda la versió anterior). Si és d'una altra persona se'n fa una còpia teva. */
// Per veure fitxers que no són PDF (àudio, vídeo, imatges, MusicXML, MuseScore...) dins l'app
function getFileForView(id, metaOnly) {
  const f = DriveApp.getFileById(id);
  const out = { name: f.getName(), mime: f.getMimeType(), size: f.getSize(), url: f.getUrl() };
  if (metaOnly) return out;
  if (out.size > 30 * 1024 * 1024) { out.tooBig = true; return out; }
  out.data = Utilities.base64Encode(f.getBlob().getBytes());
  return out;
}

function getPdfForEdit(id) {
  const f = DriveApp.getFileById(id);
  if (f.getSize() > 30 * 1024 * 1024) throw new Error('El PDF fa més de 30 MB i no es pot editar des de l\'app.');
  const b = f.getBlob();
  let me = '', owner = '';
  try { me = DriveApp.getRootFolder().getOwner().getEmail(); } catch (e) {}
  try { owner = f.getOwner() ? f.getOwner().getEmail() : ''; } catch (e) {}
  return { name: f.getName(), data: Utilities.base64Encode(b.getBytes()), mine: !owner || owner === me, owner: owner };
}

function savePdf(id, b64, docId) {
  const f = DriveApp.getFileById(id);
  const name = f.getName();
  const blob = Utilities.newBlob(Utilities.base64Decode(b64), 'application/pdf', name);
  let me = '', owner = '';
  try { me = DriveApp.getRootFolder().getOwner().getEmail(); } catch (e) {}
  try { owner = f.getOwner() ? f.getOwner().getEmail() : ''; } catch (e) {}
  if (!owner || owner === me) {
    Drive.Files.update({}, id, blob);
    return { id: id, url: f.getUrl(), copy: false };
  }
  // Fitxer d'una altra persona: còpia editada dins l'arxiu i el document passa a apuntar-hi
  const lock = LockService.getScriptLock();
  lock.waitLock(20000);
  try {
    const sh = ss_().getSheetByName('Documents');
    const v = sh.getDataRange().getValues();
    const h = v[0], ii = h.indexOf('ID'), ti = h.indexOf('Tipus');
    let row = -1;
    for (let r = 1; r < v.length; r++) if (String(v[r][ii]) === String(docId)) { row = r; break; }
    const nf = docsFolder_(row > 0 ? v[row][ti] : '').createFile(blob);
    if (row > 0) {
      const set = (col, val) => { const c = h.indexOf(col); if (c > -1) v[row][c] = val; };
      set('Fitxer', nf.getUrl());
      set('Enllaç Drive', nf.getUrl());
      const ni = h.indexOf('Notes');
      if (ni > -1) v[row][ni] = String(v[row][ni] || '') + ' · Còpia editada (original de ' + owner + ': ' + f.getUrl() + ')';
      sh.getRange(row + 1, 1, 1, h.length).setValues([v[row]]);
    }
    return { id: nf.getId(), url: nf.getUrl(), copy: true };
  } finally { lock.releaseLock(); }
}

// Desa un PDF fet a l'app (paquet de concert, curs o llibre) a "Arxiu de Repertori/Paquets"
function savePackage(b64, name) {
  const root = DriveApp.getFolderById(ROOT_FOLDER_ID);
  const it = root.getFoldersByName('Paquets');
  const folder = it.hasNext() ? it.next() : root.createFolder('Paquets');
  const f = folder.createFile(Utilities.newBlob(Utilities.base64Decode(b64), 'application/pdf', name));
  return { id: f.getId(), url: f.getUrl() };
}

/* ================= ANOTACIONS =================
   Les anotacions fetes amb el llapis es guarden a part, en un fitxer JSON per document
   a "Arxiu de Repertori/Anotacions". La partitura original no es modifica mai. */
function annFolder_() {
  const root = DriveApp.getFolderById(ROOT_FOLDER_ID);
  const it = root.getFoldersByName('Anotacions');
  return it.hasNext() ? it.next() : root.createFolder('Anotacions');
}
function getAnnotations(docId) {
  const it = annFolder_().getFilesByName(docId + '.json');
  return it.hasNext() ? it.next().getBlob().getDataAsString() : '';
}
function saveAnnotations(docId, json) {
  const folder = annFolder_();
  const it = folder.getFilesByName(docId + '.json');
  if (json) {
    if (it.hasNext()) it.next().setContent(json);
    else folder.createFile(docId + '.json', json, 'application/json');
  } else {
    while (it.hasNext()) it.next().setTrashed(true);
  }
  ensureHeader_('Documents', 'Anotacions');
  const sh = ss_().getSheetByName('Documents');
  const v = sh.getDataRange().getValues();
  const h = v[0], ii = h.indexOf('ID'), ai = h.indexOf('Anotacions');
  for (let r = 1; r < v.length; r++) {
    if (String(v[r][ii]) === String(docId)) { sh.getRange(r + 1, ai + 1).setValue(json ? 'S\u00ed' : ''); break; }
  }
  return true;
}

// Miniatures servides per l'app (per als navegadors que bloquegen les de Google Drive). Es guarden 6 h a la mem\u00f2ria cau.
function getThumbs(ids) {
  const cache = CacheService.getScriptCache();
  const got = cache.getAll(ids.map(i => 'th_' + i));
  const out = {};
  ids.forEach(id => {
    let v = got['th_' + id];
    if (!v) {
      try {
        const b = DriveApp.getFileById(id).getThumbnail();
        v = b ? 'data:' + (b.getContentType() || 'image/png') + ';base64,' + Utilities.base64Encode(b.getBytes()) : '-';
      } catch (e) { v = '-'; }
      if (v.length < 95000) { try { cache.put('th_' + id, v, 21600); } catch (e) {} }
    }
    out[id] = v === '-' ? '' : v;
  });
  return out;
}

// Omple el camp Instrument (nom\u00e9s fagot, contrafagot i fagotino) a partir del nom del fitxer, si est\u00e0 buit
function omplirInstruments() {
  ensureHeader_('Documents', 'Instrument');
  const sh = ss_().getSheetByName('Documents');
  const v = sh.getDataRange().getValues();
  const h = v[0], ti = h.indexOf('T\u00edtol'), ii = h.indexOf('Instrument');
  let n = 0;
  for (let r = 1; r < v.length; r++) {
    if (v[r][ii]) continue;
    const t = ' ' + norm_(String(v[r][ti]).replace(/[_\-.]+/g, ' ')) + ' ';
    let ins = '';
    if (/contrafag|contrabassoon|kontrafag|contrabasson/.test(t)) ins = /\b(fagot|bassoon|fg)\b/.test(t.replace(/contra\w+/g, '')) ? 'Fagot/contrafagot' : 'Contrafagot';
    else if (/fagotino|fagottino|mini ?bas+o+n/.test(t)) ins = /\bin f\b|\ben fa\b/.test(t) ? 'Fagotino en fa' : 'Fagotino en sol';
    else if (/fagot|fagott|bassoon|basson|\bfg\d?\b/.test(t)) {
      if (/(fagot+|bassoon|fg)\s+(i|and|e|y|und|&)\s+(orq|orch)/.test(t)) ins = 'Fagot i orquestra';
      else if (/piano|pno|klavier/.test(t)) ins = 'Fagot i piano';
      else if (/\bsolo\b|unaccompanied|\bsol\b|\bsolo bassoon\b/.test(t) && !/\bsol\s*(major|menor|minor|m\b)/.test(t)) ins = 'Fagot sol';
      else {
        const m = /(?:fagot+|fagotes|bassoons?|basson|\bfg)\s*(?:n\s*|no\s*)?(1|2|3|i{1,3}|1r|2n|3r|1st|2nd|3rd|1o|2o|3o)\b/.exec(t) ||
          /\b(1|2|3|1r|2n|3r|1st|2nd|3rd)\s*(?:fagot|bassoon|fg)/.exec(t);
        const k = m ? m[1].replace(/st|nd|rd|r|n|o/g, '') : '';
        ins = (k === '1' || k === 'i') ? 'Fagot 1r' : (k === '2' || k === 'ii') ? 'Fagot 2n' : (k === '3' || k === 'iii') ? 'Fagot 3r' : '';
      }
    }
    if (ins) { v[r][ii] = ins; n++; }
  }
  if (n) sh.getRange(1, 1, v.length, h.length).setValues(v);
  return 'Instruments trobats: ' + n;
}

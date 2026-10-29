/**
 * FINANCES PERSONALS — Google Sheets + app per al mòbil
 *
 * 1) Executa la funció configurar() una sola vegada.
 * 2) Implementa > Implementació nova > Aplicació web
 *    (Executa com: Jo · Qui hi té accés: Qualsevol persona).
 * 3) Al full, menú Finances > Prepara l'enllaç de l'app.
 */

const FULL_MOV = 'Moviments';
const FULL_CAT = 'Categories';
const FULL_REC = 'Recurrents';
const FULL_RES = 'Resum';
const FULL_CFG = 'Config';
const TIPUS = ['Despesa', 'Ingrés', 'Estalvi', 'Inversió'];
const TZ = 'Europe/Madrid';
const FORMAT_EUR = '#,##0.00 "€"';

/* ------------------------------------------------------------------ */
/* Menú del full                                                       */
/* ------------------------------------------------------------------ */

function onOpen() {
  SpreadsheetApp.getUi()
    .createMenu('Finances')
    .addItem("Prepara l'enllaç de l'app", 'enllacos')
    .addItem('Afegeix els recurrents pendents', 'afegirRecurrents')
    .addToUi();
}

/* ------------------------------------------------------------------ */
/* Configuració inicial                                                */
/* ------------------------------------------------------------------ */

function configurar() {
  const ss = SpreadsheetApp.getActiveSpreadsheet();
  ss.setSpreadsheetTimeZone(TZ);
  token_();

  // Moviments
  const mov = full_(ss, FULL_MOV);
  if (mov.getLastRow() === 0) {
    capcalera_(mov, ['Data', 'Mes', 'Tipus', 'Categoria', 'Concepte', 'Import', 'ID']);
    mov.getRange('A:A').setNumberFormat('dd/mm/yyyy');
    mov.getRange('B:B').setNumberFormat('@');
    mov.getRange('F:F').setNumberFormat(FORMAT_EUR);
    mov.getRange('C2:C').setDataValidation(llistaTipus_());
    dadesInicials_(mov);
    mov.setColumnWidths(1, 6, 120);
    mov.setColumnWidth(5, 180);
    mov.hideColumns(7);
  }

  // Categories
  const cat = full_(ss, FULL_CAT);
  if (cat.getLastRow() === 0) {
    capcalera_(cat, ['Categoria', 'Tipus']);
    const llista = [
      ['Habitatge', 'Despesa'], ['Transport', 'Despesa'], ['Supermercat', 'Despesa'],
      ['Telefonia', 'Despesa'], ['Viatges', 'Despesa'], ['Salut', 'Despesa'], ['Altres', 'Despesa'],
      ['Vila-seca', 'Ingrés'], ['EMMCA', 'Ingrés'], ['AJC', 'Ingrés'],
      ['Trade', 'Estalvi'], ['Trade', 'Inversió']
    ];
    cat.getRange(2, 1, llista.length, 2).setValues(llista);
    cat.getRange('B2:B').setDataValidation(llistaTipus_());
    cat.setColumnWidths(1, 2, 150);
  }

  // Recurrents (s'afegeixen sols cada mes)
  const rec = full_(ss, FULL_REC);
  if (rec.getLastRow() === 0) {
    capcalera_(rec, ['Dia del mes', 'Tipus', 'Categoria', 'Concepte', 'Import', 'Actiu']);
    rec.getRange('F2:F50').insertCheckboxes();
    rec.getRange(2, 1, 2, 6).setValues([
      [1, 'Estalvi', 'Trade', 'Estalvi mensual', 100, true],
      [1, 'Inversió', 'Trade', 'Inversió mensual', 40, true]
    ]);
    rec.getRange('B2:B50').setDataValidation(llistaTipus_());
    rec.getRange('E:E').setNumberFormat(FORMAT_EUR);
    rec.setColumnWidths(1, 6, 130);
  }

  // Resum (taules automàtiques)
  const res = full_(ss, FULL_RES);
  res.clear();
  res.getRange('A1').setValue('Balanç per mes').setFontWeight('bold').setFontSize(12);
  res.getRange('A3').setFormula(
    "=IFERROR(QUERY(Moviments!B:F, \"select B, sum(F) where B <> '' group by B pivot C order by B desc\", 1), \"\")"
  );
  res.getRange('H1').setValue('Despesa per categoria i mes').setFontWeight('bold').setFontSize(12);
  res.getRange('H3').setFormula(
    "=IFERROR(QUERY(Moviments!B:F, \"select D, sum(F) where C = 'Despesa' and B <> '' group by D pivot B\", 1), \"\")"
  );
  res.getRange('B4:F300').setNumberFormat(FORMAT_EUR);
  res.getRange('I4:Z300').setNumberFormat(FORMAT_EUR);
  res.getRange('A3:F3').setFontWeight('bold');
  res.getRange('H3:Z3').setFontWeight('bold');

  // Ordre de les pestanyes i neteja de la pestanya buida inicial
  ss.setActiveSheet(mov);
  ss.moveActiveSheet(1);
  const nostres = [FULL_MOV, FULL_CAT, FULL_REC, FULL_RES, FULL_CFG];
  ss.getSheets().forEach(s => {
    if (nostres.indexOf(s.getName()) === -1 && s.getLastRow() === 0 && ss.getSheets().length > 1) {
      ss.deleteSheet(s);
    }
  });

  // Activador diari per als moviments recurrents
  ScriptApp.getProjectTriggers()
    .filter(t => t.getHandlerFunction() === 'afegirRecurrents')
    .forEach(t => ScriptApp.deleteTrigger(t));
  ScriptApp.newTrigger('afegirRecurrents').timeBased().everyDays(1).atHour(7).inTimezone(TZ).create();
  afegirRecurrents();

  avis_("Configuració feta.\n\nAra ves a Implementa > Implementació nova > Aplicació web. " +
        "Després, al full, fes servir el menú Finances > Prepara l'enllaç de l'app.");
}

function dadesInicials_(sh) {
  const ara = new Date();
  const data = new Date(ara.getFullYear(), ara.getMonth(), 1, 12);
  const mes = Utilities.formatDate(data, TZ, 'yyyy-MM');
  // Còpia pública: s'han tret els imports reals que hi havia com a dades inicials.
  const files = [
    ['Despesa', 'Altres', 'Exemple', 1]
  ];
  const valors = files.map(f => [data, mes, f[0], f[1], f[2], f[3], nouId_()]);
  sh.getRange(2, 1, valors.length, 7).setValues(valors);
}

/* ------------------------------------------------------------------ */
/* Enllaç de l'app                                                     */
/* ------------------------------------------------------------------ */

function enllacos() {
  const ui = SpreadsheetApp.getUi();
  let url = '';
  try { url = ScriptApp.getService().getUrl() || ''; } catch (e) { url = ''; }
  if (!/\/exec$/.test(url)) {
    const r = ui.prompt("Enllaç de l'app",
      "Enganxa l'URL de l'aplicació web (el que acaba en /exec):", ui.ButtonSet.OK_CANCEL);
    if (r.getSelectedButton() !== ui.Button.OK) return;
    url = r.getResponseText().trim().split('?')[0];
  }
  if (!/^https:\/\/script\.google\.com\/.+\/exec$/.test(url)) {
    ui.alert("Aquest URL no sembla correcte. Ha de començar per https://script.google.com i acabar en /exec.");
    return;
  }
  const app = url + '?k=' + token_();
  const ss = SpreadsheetApp.getActiveSpreadsheet();
  const cfg = full_(ss, FULL_CFG);
  cfg.clear();
  cfg.getRange(1, 1, 3, 2).setValues([
    ["Enllaç de l'app", app],
    ['Ús', "Obre'l a Safari i afegeix-lo a la pantalla d'inici. També és l'enllaç per al giny i la drecera."],
    ['Important', 'No el comparteixis: qui el tingui pot veure i afegir moviments.']
  ]);
  cfg.getRange('A1:A3').setFontWeight('bold');
  cfg.setColumnWidth(1, 140);
  cfg.setColumnWidth(2, 700);
  ui.alert("Enllaç desat a la pestanya Config:\n\n" + app);
}

/* ------------------------------------------------------------------ */
/* Recurrents                                                          */
/* ------------------------------------------------------------------ */

function afegirRecurrents() {
  const ss = SpreadsheetApp.getActiveSpreadsheet();
  const rec = ss.getSheetByName(FULL_REC);
  if (!rec || rec.getLastRow() < 2) return;
  const avui = new Date();
  const mes = Utilities.formatDate(avui, TZ, 'yyyy-MM');
  const dia = Number(Utilities.formatDate(avui, TZ, 'd'));
  const props = PropertiesService.getScriptProperties();
  const ids = new Set(llegirMoviments_().map(m => m.id));
  const files = rec.getRange(2, 1, rec.getLastRow() - 1, 6).getValues();

  files.forEach(r => {
    const actiu = r[5] === true || String(r[5]).toLowerCase() === 'sí';
    const tipus = tipusCanonic_(r[1]);
    const imp = num_(r[4]);
    const cat = String(r[2]).trim();
    if (!actiu || !tipus || !(imp > 0) || !cat) return;
    const diaRec = Math.min(Math.max(Number(r[0]) || 1, 1), 28);
    if (dia < diaRec) return;
    const id = ['REC', mes, tipus, cat, String(r[3]).trim(), imp].join('|');
    if (ids.has(id) || props.getProperty(id)) return;
    const [y, m] = mes.split('-').map(Number);
    escriuFila_(ss, new Date(y, m - 1, diaRec, 12), tipus, cat, String(r[3]).trim(), imp, id);
    registraCategoria_(ss, cat, tipus);
    props.setProperty(id, '1');
  });
}

/* ------------------------------------------------------------------ */
/* Web app i API                                                       */
/* ------------------------------------------------------------------ */

function doGet(e) {
  const p = (e && e.parameter) || {};
  if (p.api) return api_(p.api, p);
  if (p.k !== token_()) {
    return HtmlService.createHtmlOutput(
      '<p style="font-family:-apple-system,sans-serif;padding:24px">Enllaç no vàlid. ' +
      'Fes servir l\'enllaç de la pestanya Config del full.</p>').setTitle('Finances');
  }
  const t = HtmlService.createTemplateFromFile('Index');
  t.k = p.k;
  return t.evaluate()
    .setTitle('Finances')
    .addMetaTag('viewport', 'width=device-width, initial-scale=1, viewport-fit=cover');
}

function doPost(e) {
  let cos = {};
  try { cos = JSON.parse(e.postData.contents); } catch (err) { cos = {}; }
  const p = Object.assign({}, (e && e.parameter) || {}, cos);
  return api_(p.api || 'afegir', p);
}

function api_(accio, p) {
  if (p.k !== token_()) return json_({ ok: false, error: 'Accés no autoritzat' });
  try {
    if (accio === 'resum') {
      const movs = llegirMoviments_();
      return json_(Object.assign({ ok: true }, resumMes_(movs, p.mes || mesActual_())));
    }
    if (accio === 'categories') {
      const t = tipusCanonic_(p.tipus || 'Despesa') || 'Despesa';
      return json_({ ok: true, categories: categories_(llegirMoviments_())[t] });
    }
    if (accio === 'afegir') return json_(afegirMoviment_(p));
    return json_({ ok: false, error: 'Acció desconeguda' });
  } catch (err) {
    return json_({ ok: false, error: String(err && err.message || err) });
  }
}

function json_(o) {
  return ContentService.createTextOutput(JSON.stringify(o)).setMimeType(ContentService.MimeType.JSON);
}

/* Funcions que crida l'app (Index.html) */

function dadesApp(k, mes) {
  comprova_(k);
  const movs = llegirMoviments_();
  const actual = mesActual_();
  mes = mes || actual;
  const mesos = Array.from(new Set(movs.map(m => m.mes).concat([actual, mes]))).sort().reverse();
  return {
    mes: mes,
    mesActual: actual,
    avui: Utilities.formatDate(new Date(), TZ, 'yyyy-MM-dd'),
    mesos: mesos,
    categories: categories_(movs),
    conceptes: conceptes_(movs),
    resum: resumMes_(movs, mes),
    evolucio: evolucio_(movs, mes, 6),
    moviments: movs.filter(m => m.mes === mes)
      .sort((a, b) => b.data.localeCompare(a.data) || b.fila - a.fila)
  };
}

function afegirDesDeApp(k, d, mesVista) {
  comprova_(k);
  const r = afegirMoviment_(d);
  if (!r.ok) throw new Error(r.error);
  const out = dadesApp(k, mesVista);
  out.missatge = r.missatge;
  return out;
}

function esborrarDesDeApp(k, id, mesVista) {
  comprova_(k);
  esborra_(id);
  return dadesApp(k, mesVista);
}

/* ------------------------------------------------------------------ */
/* Lògica de dades                                                     */
/* ------------------------------------------------------------------ */

function afegirMoviment_(d) {
  const tipus = tipusCanonic_(d.tipus || 'Despesa');
  const imp = num_(d.import);
  const cat = String(d.categoria || '').trim();
  const concepte = String(d.concepte || '').trim();
  if (!tipus) return { ok: false, error: 'Tipus no vàlid' };
  if (!(imp > 0)) return { ok: false, error: "L'import ha de ser més gran que 0" };
  if (!cat) return { ok: false, error: 'Falta la categoria' };
  const data = dataDe_(d.data);
  const lock = LockService.getScriptLock();
  lock.waitLock(15000);
  let nom;
  try {
    const ss = SpreadsheetApp.getActiveSpreadsheet();
    nom = registraCategoria_(ss, cat, tipus);
    escriuFila_(ss, data, tipus, nom, concepte, imp, nouId_());
  } finally {
    lock.releaseLock();
  }
  return { ok: true, missatge: 'Desat: ' + eur_(imp) + ' a ' + nom };
}

function escriuFila_(ss, data, tipus, cat, concepte, imp, id) {
  const sh = ss.getSheetByName(FULL_MOV);
  const fila = sh.getLastRow() + 1;
  const mes = Utilities.formatDate(data, TZ, 'yyyy-MM');
  sh.getRange(fila, 2).setNumberFormat('@');
  sh.getRange(fila, 1, 1, 7).setValues([[data, mes, tipus, cat, concepte, imp, id]]);
}

function registraCategoria_(ss, nom, tipus) {
  const sh = ss.getSheetByName(FULL_CAT);
  const n = sh.getLastRow() - 1;
  const files = n > 0 ? sh.getRange(2, 1, n, 2).getValues() : [];
  const trobada = files.find(r =>
    String(r[0]).trim().toLowerCase() === nom.toLowerCase() && tipusCanonic_(r[1]) === tipus);
  if (trobada) return String(trobada[0]).trim();
  const net = nom.charAt(0).toUpperCase() + nom.slice(1);
  sh.getRange(sh.getLastRow() + 1, 1, 1, 2).setValues([[net, tipus]]);
  return net;
}

function esborra_(id) {
  const sh = SpreadsheetApp.getActiveSpreadsheet().getSheetByName(FULL_MOV);
  const m = /^FILA-(\d+)$/.exec(id);
  if (m) { sh.deleteRow(Number(m[1])); return; }
  const n = sh.getLastRow() - 1;
  if (n < 1) return;
  const ids = sh.getRange(2, 7, n, 1).getValues();
  for (let i = 0; i < ids.length; i++) {
    if (String(ids[i][0]) === String(id)) { sh.deleteRow(i + 2); return; }
  }
  throw new Error("No s'ha trobat el moviment");
}

function llegirMoviments_() {
  const sh = SpreadsheetApp.getActiveSpreadsheet().getSheetByName(FULL_MOV);
  if (!sh) return [];
  const n = sh.getLastRow() - 1;
  if (n < 1) return [];
  const v = sh.getRange(2, 1, n, 7).getValues();
  const out = [];
  v.forEach((r, i) => {
    const imp = num_(r[5]);
    const tipus = tipusCanonic_(r[2]);
    if (!tipus || !imp) return;
    const dataTxt = r[0] instanceof Date ? Utilities.formatDate(r[0], TZ, 'yyyy-MM-dd') : '';
    const mes = dataTxt ? dataTxt.slice(0, 7) : String(r[1]);
    if (!/^\d{4}-\d{2}$/.test(mes)) return;
    out.push({
      fila: i + 2,
      data: dataTxt || mes + '-01',
      mes: mes,
      tipus: tipus,
      categoria: String(r[3]).trim() || 'Sense categoria',
      concepte: String(r[4]).trim(),
      import: arrodoneix_(imp),
      id: String(r[6] || ('FILA-' + (i + 2)))
    });
  });
  return out;
}

function resumMes_(movs, mes) {
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
  ['ingressos', 'despeses', 'estalvi', 'inversio'].forEach(k => r[k] = arrodoneix_(r[k]));
  r.disponible = arrodoneix_(r.ingressos - r.despeses - r.estalvi - r.inversio);
  r.categories = ordena_(cats, r.despeses);
  r.conceptes = ordena_(conc, r.despeses).slice(0, 8);
  r.fonts = ordena_(fonts, r.ingressos);
  return r;
}

function evolucio_(movs, mesFinal, n) {
  return mesosEnrere_(mesFinal, n).map(mes => {
    const r = resumMes_(movs, mes);
    return { mes: mes, ingressos: r.ingressos, despeses: r.despeses, estalvi: arrodoneix_(r.estalvi + r.inversio) };
  });
}

function categories_(movs) {
  const sh = SpreadsheetApp.getActiveSpreadsheet().getSheetByName(FULL_CAT);
  const compte = {};
  TIPUS.forEach(t => compte[t] = {});
  const n = sh ? sh.getLastRow() - 1 : 0;
  if (n > 0) {
    sh.getRange(2, 1, n, 2).getValues().forEach(r => {
      const t = tipusCanonic_(r[1]);
      const nom = String(r[0]).trim();
      if (t && nom && !(nom in compte[t])) compte[t][nom] = 0;
    });
  }
  movs.forEach(m => {
    if (compte[m.tipus]) compte[m.tipus][m.categoria] = (compte[m.tipus][m.categoria] || 0) + 1;
  });
  const out = {};
  TIPUS.forEach(t => {
    out[t] = Object.keys(compte[t]).sort((a, b) => compte[t][b] - compte[t][a] || a.localeCompare(b, 'ca'));
  });
  return out;
}

function conceptes_(movs) {
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

/* ------------------------------------------------------------------ */
/* Utilitats                                                           */
/* ------------------------------------------------------------------ */

function token_() {
  const p = PropertiesService.getScriptProperties();
  let t = p.getProperty('TOKEN');
  if (!t) {
    t = Utilities.getUuid().replace(/-/g, '').slice(0, 20);
    p.setProperty('TOKEN', t);
  }
  return t;
}

function comprova_(k) {
  if (!k || k !== token_()) throw new Error('Accés no autoritzat');
}

function tipusCanonic_(t) {
  const s = String(t || '').trim().toLowerCase().normalize('NFD').replace(/[\u0300-\u036f]/g, '');
  if (s.indexOf('despes') === 0) return 'Despesa';
  if (s.indexOf('ingres') === 0) return 'Ingrés';
  if (s.indexOf('estalvi') === 0) return 'Estalvi';
  if (s.indexOf('inversi') === 0) return 'Inversió';
  return '';
}

function num_(x) {
  if (typeof x === 'number') return x;
  let s = String(x || '').replace(/[\s€]/g, '');
  if (s.indexOf(',') > -1 && s.indexOf('.') > -1) s = s.replace(/\./g, '').replace(',', '.');
  else s = s.replace(',', '.');
  const n = parseFloat(s);
  return isNaN(n) ? 0 : n;
}

function dataDe_(s) {
  const txt = /^\d{4}-\d{2}-\d{2}$/.test(String(s || ''))
    ? String(s) : Utilities.formatDate(new Date(), TZ, 'yyyy-MM-dd');
  const [y, m, d] = txt.split('-').map(Number);
  return new Date(y, m - 1, d, 12);
}

function mesActual_() {
  return Utilities.formatDate(new Date(), TZ, 'yyyy-MM');
}

function mesosEnrere_(mesFinal, n) {
  let [y, m] = mesFinal.split('-').map(Number);
  const out = [];
  for (let i = 0; i < n; i++) {
    out.unshift(y + '-' + String(m).padStart(2, '0'));
    m--;
    if (m === 0) { m = 12; y--; }
  }
  return out;
}

function ordena_(obj, total) {
  return Object.keys(obj)
    .map(k => ({ nom: k, total: arrodoneix_(obj[k]), pct: total ? Math.round(obj[k] / total * 1000) / 10 : 0 }))
    .sort((a, b) => b.total - a.total);
}

function arrodoneix_(n) { return Math.round(n * 100) / 100; }
function eur_(n) { return n.toFixed(2).replace('.', ',') + ' €'; }
function nouId_() { return Utilities.getUuid().slice(0, 8); }

function full_(ss, nom) { return ss.getSheetByName(nom) || ss.insertSheet(nom); }

function capcalera_(sh, cols) {
  sh.getRange(1, 1, 1, cols.length).setValues([cols])
    .setFontWeight('bold').setFontColor('#ffffff').setBackground('#3d3d3d');
  sh.setFrozenRows(1);
}

function llistaTipus_() {
  return SpreadsheetApp.newDataValidation().requireValueInList(TIPUS, true).build();
}

function avis_(msg) {
  try { SpreadsheetApp.getUi().alert(msg); } catch (e) { Logger.log(msg); }
}

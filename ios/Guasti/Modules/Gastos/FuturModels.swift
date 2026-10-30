import Foundation

// MARK: - Pestanyes del full "Economia Guasti"

/// Una pestanya del full: nom i columnes. L'script la crea sola la primera vegada.
struct FinTaula {
    let nom: String
    let cols: [String]

    static let comptes = FinTaula(nom: "Comptes", cols: ["ID", "Nom", "Tipus", "Saldo", "Actualitzat"])
    static let saldos = FinTaula(nom: "Saldos", cols: ["ID", "Data", "Compte", "Nom", "Saldo"])
    static let contractes = FinTaula(nom: "Contractes", cols: ["ID", "Nom", "Brut mensual", "Pagues", "IRPF %", "SS %", "Des de", "Fins a"])
    static let bolos = FinTaula(nom: "Bolos", cols: ["ID", "Data", "Concepte", "Pagador", "Brut", "Retenció %", "Cobrat"])
    static let previstos = FinTaula(nom: "Previstos", cols: ["ID", "Nom", "Tipus", "Import", "Mes", "Any"])
    static let ajustos = FinTaula(nom: "Ajustos", cols: ["ID", "Valor"])
    /// La de l'app web: només es llegeix.
    static let moviments = FinTaula(nom: "Moviments", cols: [])

    static let totes: [FinTaula] = [comptes, saldos, contractes, bolos, previstos, ajustos, moviments]
    static var defs: [String: [String]] { Dictionary(uniqueKeysWithValues: totes.map { ($0.nom, $0.cols) }) }

    static func nouId() -> String { String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(8)).lowercased() }
}

typealias FinFila = [String: String]

extension Dictionary where Key == String, Value == String {
    func txt(_ k: String) -> String { (self[k] ?? "").trimmingCharacters(in: .whitespaces) }
    func num(_ k: String) -> Double { Fin.number(txt(k)) }
    func bool(_ k: String) -> Bool { ["true", "sí", "si", "1", "x"].contains(txt(k).lowercased()) }
}

struct Compte: Identifiable, Hashable {
    static let tipus = ["Corrent", "Estalvi", "Inversió"]

    var id: String
    var nom: String
    var tipus: String
    var saldo: Double
    var actualitzat: String

    /// Diners que es poden fer servir de seguida (compte corrent i estalvi, també el de Trade Republic).
    var liquid: Bool { tipus != "Inversió" }

    init(id: String = "", nom: String = "", tipus: String = "Corrent", saldo: Double = 0, actualitzat: String = "") {
        self.id = id; self.nom = nom; self.tipus = tipus; self.saldo = saldo; self.actualitzat = actualitzat
    }

    init(_ f: FinFila) {
        self.init(id: f.txt("ID"), nom: f.txt("Nom"), tipus: Compte.tipus.contains(f.txt("Tipus")) ? f.txt("Tipus") : "Corrent",
                  saldo: f.num("Saldo"), actualitzat: f.txt("Actualitzat"))
    }

    var fila: [String: Any] { ["ID": id, "Nom": nom, "Tipus": tipus, "Saldo": saldo, "Actualitzat": actualitzat] }
}

struct SaldoHist {
    var data: String
    var compte: String
    var saldo: Double

    init(_ f: FinFila) { data = f.txt("Data"); compte = f.txt("Compte"); saldo = f.num("Saldo") }
}

struct Contracte: Identifiable, Hashable {
    var id: String
    var nom: String
    var brut: Double
    var pagues: Int
    var irpf: Double
    var ss: Double
    var desDe: String
    var finsA: String

    init(id: String = "", nom: String = "", brut: Double = 0, pagues: Int = 14, irpf: Double = 15, ss: Double = 6.5,
         desDe: String = "", finsA: String = "") {
        self.id = id; self.nom = nom; self.brut = brut; self.pagues = pagues; self.irpf = irpf; self.ss = ss
        self.desDe = desDe; self.finsA = finsA
    }

    init(_ f: FinFila) {
        self.init(id: f.txt("ID"), nom: f.txt("Nom"), brut: f.num("Brut mensual"),
                  pagues: Int(f.num("Pagues")) == 12 ? 12 : 14, irpf: f.num("IRPF %"),
                  ss: f.txt("SS %").isEmpty ? 6.5 : f.num("SS %"),
                  desDe: String(f.txt("Des de").prefix(7)), finsA: String(f.txt("Fins a").prefix(7)))
    }

    var fila: [String: Any] {
        ["ID": id, "Nom": nom, "Brut mensual": brut, "Pagues": pagues, "IRPF %": irpf, "SS %": ss,
         "Des de": desDe, "Fins a": finsA]
    }

    func actiu(_ mes: String) -> Bool {
        (desDe.isEmpty || mes >= desDe) && (finsA.isEmpty || mes <= finsA)
    }

    /// La Seguretat Social es paga cada mes sobre el sou amb les pagues extra prorratejades.
    var ssMensual: Double { brut * ss / 100 * Double(pagues) / 12 }
    var netMensual: Double { brut - brut * irpf / 100 - ssMensual }
    var netExtra: Double { brut - brut * irpf / 100 }

    /// Les pagues extra es cobren al juny i al desembre.
    func teExtra(_ mes: String) -> Bool { pagues == 14 && (mes.hasSuffix("-06") || mes.hasSuffix("-12")) }
}

struct Bolo: Identifiable, Hashable {
    var id: String
    var data: String
    var concepte: String
    var pagador: String
    var brut: Double
    var retencio: Double
    var cobrat: Bool

    init(id: String = "", data: String = "", concepte: String = "", pagador: String = "", brut: Double = 0,
         retencio: Double = 15, cobrat: Bool = false) {
        self.id = id; self.data = data; self.concepte = concepte; self.pagador = pagador; self.brut = brut
        self.retencio = retencio; self.cobrat = cobrat
    }

    init(_ f: FinFila) {
        self.init(id: f.txt("ID"), data: f.txt("Data"), concepte: f.txt("Concepte"), pagador: f.txt("Pagador"),
                  brut: f.num("Brut"), retencio: f.num("Retenció %"), cobrat: f.bool("Cobrat"))
    }

    var fila: [String: Any] {
        ["ID": id, "Data": data, "Concepte": concepte, "Pagador": pagador, "Brut": brut, "Retenció %": retencio,
         "Cobrat": cobrat]
    }

    var retingut: Double { brut * retencio / 100 }
    var net: Double { brut - retingut }
    var mes: String { String(data.prefix(7)) }
    var anyData: Int { Int(data.prefix(4)) ?? 0 }
    var titol: String { concepte.isEmpty ? (pagador.isEmpty ? "Bolo" : pagador) : concepte }
}

/// Un ingrés o una despesa que se sap que vindrà: assegurances, IBI, una paga extra, un retorn...
struct Previst: Identifiable, Hashable {
    var id: String
    var nom: String
    var tipus: String
    var imp: Double
    var mes: Int
    /// 0 = cada any
    var anyFix: Int

    init(id: String = "", nom: String = "", tipus: String = "Despesa", imp: Double = 0, mes: Int = 1, anyFix: Int = 0) {
        self.id = id; self.nom = nom; self.tipus = tipus; self.imp = imp; self.mes = mes; self.anyFix = anyFix
    }

    init(_ f: FinFila) {
        let m = Int(f.num("Mes"))
        self.init(id: f.txt("ID"), nom: f.txt("Nom"), tipus: f.txt("Tipus") == "Ingrés" ? "Ingrés" : "Despesa",
                  imp: f.num("Import"), mes: (1...12).contains(m) ? m : 1, anyFix: Int(f.num("Any")))
    }

    var fila: [String: Any] {
        ["ID": id, "Nom": nom, "Tipus": tipus, "Import": imp, "Mes": mes, "Any": anyFix == 0 ? "" : String(anyFix)]
    }

    func toca(_ mesTxt: String) -> Bool {
        guard let y = Int(mesTxt.prefix(4)), let m = Int(mesTxt.suffix(2)) else { return false }
        return m == mes && (anyFix == 0 || anyFix == y)
    }
}

// MARK: - IRPF

/// Estimació de la renda (escales estatal i catalana, rendiments del treball).
/// Els bolos es compten com a rendiments del treball; és una aproximació, no la declaració.
struct IRPF {
    struct Tram: Identifiable {
        var desDe: Double
        var finsA: Double?
        var tipus: Double
        var base: Double
        var quota: Double
        var id: Double { desDe }
    }

    static let estatal: [(Double, Double)] = [(12_450, 9.5), (20_200, 12), (35_200, 15), (60_000, 18.5),
                                              (300_000, 22.5), (.infinity, 24.5)]
    static let catalana: [(Double, Double)] = [(12_450, 10.5), (17_707.20, 12), (21_000, 14), (33_007.20, 15),
                                               (53_407.20, 18.8), (90_000, 21.5), (120_000, 23.5),
                                               (175_000, 24.5), (.infinity, 25.5)]
    static let minimPersonal = 5_550.0
    static let altresDespeses = 2_000.0

    var exercici: Int
    var brutNomines = 0.0
    var brutBolos = 0.0
    var seguretatSocial = 0.0
    var retencionsNomines = 0.0
    var retencionsBolos = 0.0
    var nBolos = 0

    var brut: Double { brutNomines + brutBolos }
    var retencions: Double { retencionsNomines + retencionsBolos }
    var rendimentNet: Double { Swift.max(0, brut - seguretatSocial - IRPF.altresDespeses) }

    /// Reducció per obtenció de rendiments del treball (des del 2024).
    var reduccio: Double {
        let r = rendimentNet
        let v: Double
        if r <= 14_852 { v = 7_302 }
        else if r <= 17_673.52 { v = 7_302 - 1.75 * (r - 14_852) }
        else if r <= 19_747.50 { v = 2_364.34 - 1.14 * (r - 17_673.52) }
        else { v = 0 }
        return Swift.min(r, Swift.max(0, v))
    }

    var base: Double { Swift.max(0, rendimentNet - reduccio) }

    /// Els trams sumant l'estatal i el català, amb la part de la base que cau a cada un.
    var trams: [Tram] {
        let punts = Array(Set(IRPF.estatal.map { $0.0 } + IRPF.catalana.map { $0.0 })).sorted()
        var out: [Tram] = []
        var desDe = 0.0
        for fins in punts {
            let tipus = IRPF.tipus(IRPF.estatal, desDe) + IRPF.tipus(IRPF.catalana, desDe)
            let b = Swift.max(0, Swift.min(base, fins) - desDe)
            out.append(Tram(desDe: desDe, finsA: fins.isFinite ? fins : nil, tipus: tipus, base: b, quota: b * tipus / 100))
            desDe = fins
            if !fins.isFinite { break }
        }
        return out
    }

    /// El mínim personal no tributa: es resta a la quota al tipus del primer tram.
    var descompteMinim: Double {
        IRPF.quota(IRPF.estatal, IRPF.minimPersonal) + IRPF.quota(IRPF.catalana, IRPF.minimPersonal)
    }

    var quota: Double { Swift.max(0, trams.reduce(0) { $0 + $1.quota } - descompteMinim) }

    /// Positiu: a pagar a la renda. Negatiu: et tornen.
    var resultat: Double { quota - retencions }
    var tipusEfectiu: Double { brut > 0 ? quota / brut * 100 : 0 }

    /// El que "costa" en impostos cada euro de més d'un bolo (inclou l'efecte de perdre la reducció).
    var tipusMarginal: Double {
        var mes = self
        mes.brutBolos += 100
        return Swift.max(0, mes.quota - quota)
    }

    /// Quant hauries de retenir als bolos (sobre el brut) perquè la renda quedi a zero.
    var retencioIdealBolos: Double? {
        guard brutBolos > 0 else { return nil }
        let falta = quota - retencionsNomines
        return Swift.min(100, Swift.max(0, falta / brutBolos * 100))
    }

    static func tipus(_ escala: [(Double, Double)], _ x: Double) -> Double {
        escala.first { x < $0.0 }?.1 ?? escala.last!.1
    }

    static func quota(_ escala: [(Double, Double)], _ base: Double) -> Double {
        var q = 0.0, desDe = 0.0
        for (fins, t) in escala {
            q += Swift.max(0, Swift.min(base, fins) - desDe) * t / 100
            if base <= fins { break }
            desDe = fins
        }
        return q
    }

    static func calcula(exercici: Int, contractes: [Contracte], bolos: [Bolo]) -> IRPF {
        var r = IRPF(exercici: exercici)
        for c in contractes {
            for m in 1...12 {
                let mes = String(format: "%04d-%02d", exercici, m)
                guard c.actiu(mes) else { continue }
                var b = c.brut
                if c.teExtra(mes) { b += c.brut }
                r.brutNomines += b
                r.retencionsNomines += b * c.irpf / 100
                r.seguretatSocial += c.ssMensual
            }
        }
        for b in bolos where b.anyData == exercici {
            r.brutBolos += b.brut
            r.retencionsBolos += b.retingut
            r.nBolos += 1
        }
        return r
    }
}

// MARK: - Previsió de saldo

struct Previsio {
    struct Linia: Identifiable {
        var nom: String
        var imp: Double
        let id = UUID()
    }

    struct Mes: Identifiable {
        var mes: String
        var linies: [Linia]
        var saldo: Double
        var id: String { mes }
        var net: Double { linies.reduce(0) { $0 + $1.imp } }
    }

    var saldoInicial: Double
    var despesaMensual: Double
    var mesos: [Mes]

    var minim: Mes? { mesos.min { $0.saldo < $1.saldo } }

    /// 12 mesos a partir del següent al mes actual.
    static func calcula(mesActual: String, saldoInicial: Double, despesaMensual: Double, contractes: [Contracte],
                        bolos: [Bolo], previstos: [Previst], irpf: (Int) -> IRPF?) -> Previsio {
        var saldo = saldoInicial
        var out: [Mes] = []
        let primer = FinMes.suma(mesActual, 1)
        for i in 0..<12 {
            let mes = FinMes.suma(mesActual, i + 1)
            var l: [Linia] = []
            for c in contractes where c.actiu(mes) {
                l.append(Linia(nom: "Nòmina " + c.nom, imp: c.netMensual))
                if c.teExtra(mes) { l.append(Linia(nom: "Paga extra " + c.nom, imp: c.netExtra)) }
            }
            // Els bolos pendents de cobrar que ja han passat es compten al primer mes.
            for b in bolos where !b.cobrat && (b.mes == mes || (mes == primer && b.mes < primer && !b.mes.isEmpty)) {
                l.append(Linia(nom: "Bolo " + b.titol, imp: b.net))
            }
            for p in previstos where p.toca(mes) {
                l.append(Linia(nom: p.nom, imp: p.tipus == "Ingrés" ? p.imp : -p.imp))
            }
            if let y = Int(mes.prefix(4)), let r = irpf(y - 1), r.brut > 0 {
                if mes.hasSuffix("-06"), r.resultat > 0 { l.append(Linia(nom: "Renda \(y - 1) (a pagar)", imp: -r.resultat)) }
                if mes.hasSuffix("-07"), r.resultat < 0 { l.append(Linia(nom: "Renda \(y - 1) (et tornen)", imp: -r.resultat)) }
            }
            if despesaMensual > 0 { l.append(Linia(nom: "Despesa habitual", imp: -despesaMensual)) }
            saldo += l.reduce(0) { $0 + $1.imp }
            out.append(Mes(mes: mes, linies: l, saldo: saldo))
        }
        return Previsio(saldoInicial: saldoInicial, despesaMensual: despesaMensual, mesos: out)
    }
}

enum FinMes {
    /// "2026-11" + 3 → "2027-02"
    static func suma(_ mes: String, _ n: Int) -> String {
        guard let y = Int(mes.prefix(4)), let m = Int(mes.suffix(2)) else { return mes }
        let t = y * 12 + (m - 1) + n
        return String(format: "%04d-%02d", t / 12, t % 12 + 1)
    }

    static func actual() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "Europe/Madrid")
        f.dateFormat = "yyyy-MM"
        return f.string(from: Date())
    }

    static func avui() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "Europe/Madrid")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }
}

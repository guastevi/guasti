import SwiftUI

/// Un fitxer de Drive enganxat a un registre (PDF del contracte, foto d'una factura...).
struct CasaFitxer: Codable, Hashable, Identifiable {
    let id: String
    let nom: String
    let mime: String

    var isImage: Bool { mime.hasPrefix("image/") }
    var isPDF: Bool { mime == "application/pdf" }
}

/// Una fila del full "Casa Guasti". Tots els tipus fan servir les mateixes columnes;
/// `CasaTipus` diu què vol dir cada una (p. ex. "Venciment" és la garantia d'una compra).
struct CasaRegistre: Codable, Hashable, Identifiable {
    var id: String
    var tipus: String
    var data: String
    var titol: String
    var imp: String
    var qui: String
    var estat: String
    var venciment: String
    var cada: String
    var notes: String
    var fitxers: [CasaFitxer]
    var creat: String
    /// Factures de llum, aigua i gas: el consum que diu el PDF ("-" si no se n'ha trobat),
    /// la unitat (kWh o m³) i l'inici del període (el final és `venciment`).
    var consum: String? = nil
    var unitat: String? = nil
    var inici: String? = nil

    enum CodingKeys: String, CodingKey {
        case id, tipus, data, titol, imp = "import", qui, estat, venciment, cada, notes, fitxers, creat
        case consum, unitat, inici
    }

    static func nou(_ tipus: CasaTipus, avui: String) -> CasaRegistre {
        var propera = ""
        if tipus == .manteniment, let d = CasaFmt.date(avui),
           let next = Calendar(identifier: .gregorian).date(byAdding: .month, value: 12, to: d) {
            propera = CasaFmt.string(next)
        }
        return CasaRegistre(id: "", tipus: tipus.rawValue, data: avui, titol: "", imp: "", qui: "",
                     estat: tipus == .reparacio ? "Pendent" : "", venciment: propera, cada: tipus == .manteniment ? "12" : "",
                     notes: "", fitxers: [], creat: "")
    }

    var kind: CasaTipus { CasaTipus(rawValue: tipus) ?? .document }
    var importValue: Double? { Double(imp.replacingOccurrences(of: ",", with: ".")) }
    var consumValue: Double? { consum.flatMap { Double($0.replacingOccurrences(of: ",", with: ".")) } }
    var dataDate: Date? { CasaFmt.date(data) }
    var vencimentDate: Date? { CasaFmt.date(venciment) }

    /// Títol que es veu a les llistes (si no n'hi ha, el del tipus).
    var displayTitle: String {
        let t = titol.trimmingCharacters(in: .whitespaces)
        return t.isEmpty ? kind.singular : t
    }

    func matches(_ text: String) -> Bool {
        let q = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        return [titol, qui, notes, estat, kind.title, imp].contains {
            $0.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).contains(q)
        } || fitxers.contains { $0.nom.localizedCaseInsensitiveContains(text) }
    }
}

struct CasaDades: Codable {
    let avui: String
    let registres: [CasaRegistre]
    let fullUrl: String?
}

struct CasaImportResposta: Decodable {
    let avui: String
    let registres: [CasaRegistre]
    let fullUrl: String?
    let nous: Int
    let pendents: Int
    /// Ja s'estan portant de fons (cada minut), així que l'app no hi ha d'insistir.
    var deFons: Bool? = nil

    var dades: CasaDades { CasaDades(avui: avui, registres: registres, fullUrl: fullUrl) }
}

struct CasaDesaResposta: Decodable {
    let avui: String
    let registres: [CasaRegistre]
    let fullUrl: String?
    let id: String?

    var dades: CasaDades { CasaDades(avui: avui, registres: registres, fullUrl: fullUrl) }
}

/// Els apartats del llibre de la casa i què vol dir cada columna en cadascun.
enum CasaTipus: String, CaseIterable, Identifiable {
    case contracte, renda, factura, reparacio, manteniment, compra, document

    var id: String { rawValue }

    var title: String {
        switch self {
        case .contracte: return "Contracte de lloguer"
        case .renda: return "Renovacions i renda"
        case .factura: return "Factures i subministraments"
        case .reparacio: return "Reparacions"
        case .manteniment: return "Manteniment"
        case .compra: return "Compres per a casa"
        case .document: return "Documents importants"
        }
    }

    var short: String {
        switch self {
        case .contracte: return "Contracte"
        case .renda: return "Renda"
        case .factura: return "Factures"
        case .reparacio: return "Reparacions"
        case .manteniment: return "Manteniment"
        case .compra: return "Compres"
        case .document: return "Documents"
        }
    }

    var singular: String {
        switch self {
        case .contracte: return "Contracte"
        case .renda: return "Actualització de renda"
        case .factura: return "Factura"
        case .reparacio: return "Reparació"
        case .manteniment: return "Tasca de manteniment"
        case .compra: return "Compra"
        case .document: return "Document"
        }
    }

    var icon: String {
        switch self {
        case .contracte: return "signature"
        case .renda: return "chart.line.uptrend.xyaxis"
        case .factura: return "bolt.fill"
        case .reparacio: return "wrench.and.screwdriver.fill"
        case .manteniment: return "checklist"
        case .compra: return "bag.fill"
        case .document: return "folder.fill"
        }
    }

    // Etiquetes dels camps. nil = aquest tipus no fa servir el camp.
    var titolLabel: String {
        switch self {
        case .contracte: return "Pis / adreça"
        case .renda: return "Motiu (IPC, renovació...)"
        case .factura: return "Subministrament"
        case .reparacio: return "Què s'ha espatllat"
        case .manteniment: return "Tasca"
        case .compra: return "Què has comprat"
        case .document: return "Nom del document"
        }
    }

    var titolSuggeriments: [String] {
        switch self {
        case .factura: return ["Llum", "Aigua", "Gas", "Internet", "Mòbil", "Comunitat", "Assegurança de la llar", "Escombraries"]
        case .renda: return ["Actualització IPC", "Renovació del contracte", "Pacte amb el propietari"]
        case .manteniment: return ["Revisió de la caldera", "Netejar filtres de l'aire", "Purgar radiadors", "Descalcificar aixetes", "Netejar el forn", "Revisar detector de fum"]
        case .document: return ["Assegurança de la llar", "Cèdula d'habitabilitat", "Certificat energètic", "Inventari del pis", "Rebut de la fiança", "Empadronament"]
        default: return []
        }
    }

    var dataLabel: String {
        switch self {
        case .contracte: return "Inici del contracte"
        case .renda: return "Des de"
        case .factura: return "Data de la factura"
        case .reparacio: return "Data"
        case .manteniment: return "Últim cop fet"
        case .compra: return "Data de compra"
        case .document: return "Data"
        }
    }

    var importLabel: String? {
        switch self {
        case .contracte: return "Renda mensual"
        case .renda: return "Renda nova"
        case .factura: return "Import"
        case .reparacio: return "Cost"
        case .compra: return "Preu"
        case .manteniment, .document: return nil
        }
    }

    var quiLabel: String? {
        switch self {
        case .contracte: return "Propietari / agència"
        case .renda: return nil
        case .factura: return "Companyia"
        case .reparacio: return "Qui ho arregla"
        case .manteniment: return "Qui ho fa"
        case .compra: return "Botiga"
        case .document: return "Entitat"
        }
    }

    var vencimentLabel: String? {
        switch self {
        case .contracte: return "Fi del contracte"
        case .manteniment: return "Propera vegada"
        case .compra: return "Garantia fins a"
        case .document: return "Caduca el"
        case .factura: return "Fi del període"
        case .renda, .reparacio: return nil
        }
    }

    var notesPlaceholder: String {
        switch self {
        case .contracte: return "Fiança, durada, clàusules, telèfon del propietari..."
        case .renda: return "Renda anterior, % aplicat..."
        case .factura: return "Període, número de contracte, consum..."
        case .reparacio: return "Què ha passat, qui ho paga (tu o el propietari)..."
        case .manteniment: return "Com es fa, telèfon del tècnic..."
        case .compra: return "Model, on és el tiquet..."
        case .document: return "On és l'original..."
        }
    }
}

enum CasaFmt {
    static let estatsReparacio = ["Pendent", "En curs", "Fet"]

    private static let iso: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "Europe/Madrid")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static let curt: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ca_ES")
        f.timeZone = TimeZone(identifier: "Europe/Madrid")
        f.dateFormat = "d MMM yyyy"
        return f
    }()

    static func date(_ s: String) -> Date? { s.isEmpty ? nil : iso.date(from: String(s.prefix(10))) }
    static func string(_ d: Date) -> String { iso.string(from: d) }
    static func human(_ s: String) -> String { date(s).map { curt.string(from: $0) } ?? s }

    static func euros(_ v: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "EUR"
        f.locale = Locale(identifier: "ca_ES")
        f.maximumFractionDigits = v.rounded() == v ? 0 : 2
        return f.string(from: v as NSNumber) ?? "\(v) €"
    }

    /// Dies que falten (negatiu si ja ha passat).
    static func dies(fins s: String, avui: String) -> Int? {
        guard let d = date(s), let a = date(avui) else { return nil }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Madrid") ?? .current
        return cal.dateComponents([.day], from: a, to: d).day
    }

    static func falten(_ dies: Int) -> String {
        switch dies {
        case ..<(-1): return "fa \(-dies) dies"
        case -1: return "ahir"
        case 0: return "avui"
        case 1: return "demà"
        case 2..<60: return "d'aquí a \(dies) dies"
        default: return "d'aquí a \(dies / 30) mesos"
        }
    }
}

/// Els colors de la secció: verd oliva, amb la lletra de Guasti.
enum CasaTheme {
    static let green = Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: 0x6E9B72) : UIColor(hex: 0x3E6B48) })
    static let warn = Color(UIColor(hex: 0xC9822B))
    static let late = Color(UIColor(hex: 0xC42A3A))
}

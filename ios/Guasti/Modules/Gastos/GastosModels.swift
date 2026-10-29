import SwiftUI
import UIKit

/// El que torna "gastos.dades": el mateix objecte que dadesApp() de l'app web.
struct GastosDades: Codable {
    var mes: String
    var mesActual: String
    var avui: String
    var mesos: [String]
    var categories: [String: [String]]
    var conceptes: [String: [String]]
    var resum: GastosResum
    var evolucio: [GastosEvolucio]
    var moviments: [Moviment]
    var missatge: String?
}

struct GastosResum: Codable {
    var mes: String
    var ingressos: Double
    var despeses: Double
    var estalvi: Double
    var inversio: Double
    var disponible: Double
    var categories: [GastosPart]
    var conceptes: [GastosPart]
    var fonts: [GastosPart]
}

struct GastosPart: Codable, Identifiable {
    var nom: String
    var total: Double
    var pct: Double
    var id: String { nom }
}

struct GastosEvolucio: Codable, Identifiable {
    var mes: String
    var ingressos: Double
    var despeses: Double
    var estalvi: Double
    var id: String { mes }
}

struct Moviment: Codable, Identifiable {
    var fila: Int
    var data: String
    var mes: String
    var tipus: String
    var categoria: String
    var concepte: String
    var imp: Double
    var id: String

    enum CodingKeys: String, CodingKey {
        case fila, data, mes, tipus, categoria, concepte, id
        case imp = "import"
    }
}

/// Colors, noms de mes i format de números de l'app web de Gastos.
enum Fin {
    static let tipus = ["Despesa", "Ingrés", "Estalvi", "Inversió"]
    static let mesos = ["gener", "febrer", "març", "abril", "maig", "juny", "juliol", "agost", "setembre", "octubre",
                        "novembre", "desembre"]
    static let paleta: [Color] = ([0x2f8fe0, 0xe2442f, 0x3fa34d, 0xf2b134, 0x8e5bd6, 0xef7d3c, 0x20a4a4, 0xd6589a,
                                  0x7a8a99, 0xa1c935, 0xb5651d, 0x5c6bc0] as [UInt32]).map { Color(UIColor(hex: $0)) }

    static let entrada = Color(UIColor(hex: 0x3fa34d))
    static let sortida = Color(UIColor(hex: 0xe2442f))
    static let estalvi = Color(UIColor(hex: 0x2f8fe0))
    static let inversio = Color(UIColor(hex: 0x8e5bd6))

    static let bg = dynamic(0xf4f4f1, 0x141413)
    static let card = dynamic(0xffffff, 0x1f1f1d)
    static let text = dynamic(0x1d1d1b, 0xf2f1ec)
    static let muted = dynamic(0x77776f, 0xa3a29a)
    static let line = dynamic(0xe6e5df, 0x32322f)

    static func color(_ tipus: String) -> Color {
        switch tipus {
        case "Ingrés": return entrada
        case "Estalvi": return estalvi
        case "Inversió": return inversio
        default: return sortida
        }
    }

    private static func dynamic(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light) })
    }

    private static let eurFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "ca_ES")
        f.numberStyle = .currency
        f.currencyCode = "EUR"
        return f
    }()

    private static let eur0Formatter: NumberFormatter = {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "ca_ES")
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        return f
    }()

    /// 1.234,56 €
    static func eur(_ n: Double) -> String {
        eurFormatter.string(from: NSNumber(value: n)) ?? String(format: "%.2f €", n)
    }

    /// 1.235 €
    static func eur0(_ n: Double) -> String {
        (eur0Formatter.string(from: NSNumber(value: n)) ?? String(Int(n))) + " €"
    }

    /// "2026-10" → "Octubre 2026"
    static func nomMes(_ m: String) -> String {
        let parts = m.split(separator: "-")
        guard parts.count == 2, let mm = Int(parts[1]), (1...12).contains(mm) else { return m }
        let n = mesos[mm - 1]
        return n.prefix(1).uppercased() + n.dropFirst() + " " + parts[0]
    }

    /// "2026-10-29" → "29 d'octubre"
    static func nomDia(_ d: String) -> String {
        let parts = d.split(separator: "-")
        guard parts.count == 3, let mm = Int(parts[1]), let dd = Int(parts[2]), (1...12).contains(mm) else { return d }
        let n = mesos[mm - 1]
        let vocal = "aeiou".contains(n.prefix(1))
        return "\(dd)" + (vocal ? " d'" : " de ") + n
    }

    /// "2026-10" → "oct"
    static func mesCurt(_ m: String) -> String {
        guard let mm = Int(m.suffix(2)), (1...12).contains(mm) else { return m }
        return String(mesos[mm - 1].prefix(3))
    }

    /// Com l'app web: "1.234,5" o "12,30" → 12.3
    static func number(_ text: String) -> Double {
        var s = text.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "€", with: "")
        if s.contains(","), s.contains(".") {
            s = s.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".")
        } else {
            s = s.replacingOccurrences(of: ",", with: ".")
        }
        return Double(s) ?? 0
    }

    /// "29,5" amb un decimal, com a l'app web ("29,5 %")
    static func pct(_ n: Double) -> String {
        let v = (n * 10).rounded() / 10
        let s = v == v.rounded() ? String(Int(v)) : String(v)
        return s.replacingOccurrences(of: ".", with: ",") + " %"
    }
}

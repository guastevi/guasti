import SwiftUI
import UIKit

/// Una fila d'un full (Obres, Documents, Concerts...): columna → valor, com a l'app web.
typealias Fila = [String: String]

/// Un full tal com el torna getData(): capçaleres i files amb els valors que es veuen al full.
struct Taula: Codable {
    var headers: [String]
    var rows: [Fila]

    enum CodingKeys: String, CodingKey { case headers, rows }

    init(headers: [String] = [], rows: [Fila] = []) {
        self.headers = headers
        self.rows = rows
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        headers = (try? c.decode([FlexText].self, forKey: .headers).map(\.value)) ?? []
        let raw = (try? c.decode([[String: FlexText]].self, forKey: .rows)) ?? []
        rows = raw.map { $0.mapValues(\.value) }
    }
}

/// Accepta text, números o sí/no i ho torna sempre com a text.
struct FlexText: Codable {
    let value: String

    init(_ value: String) { self.value = value }

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let s = try? c.decode(String.self) { value = s }
        else if let i = try? c.decode(Int.self) { value = String(i) }
        else if let d = try? c.decode(Double.self) { value = String(d) }
        else if let b = try? c.decode(Bool.self) { value = b ? "Sí" : "" }
        else { value = "" }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(value)
    }
}

/// El que torna getData() de l'app web.
struct ArxiuDades: Codable {
    var Obres: Taula
    var Documents: Taula
    var Concerts: Taula
    var Agrupacions: Taula
    var Directors: Taula
    var Fagotades: Taula
    var Llistes: [String: [String]]
    var pendents: Int?

    func taula(_ nom: String) -> [Fila] {
        switch nom {
        case "Obres": return Obres.rows
        case "Documents": return Documents.rows
        case "Concerts": return Concerts.rows
        case "Agrupacions": return Agrupacions.rows
        case "Directors": return Directors.rows
        case "Fagotades": return Fagotades.rows
        default: return []
        }
    }

    mutating func update(_ nom: String, _ f: (inout [Fila]) -> Void) {
        switch nom {
        case "Obres": f(&Obres.rows)
        case "Documents": f(&Documents.rows)
        case "Concerts": f(&Concerts.rows)
        case "Agrupacions": f(&Agrupacions.rows)
        case "Directors": f(&Directors.rows)
        case "Fagotades": f(&Fagotades.rows)
        default: break
        }
    }
}

/// Resposta de l'acció "partitures" del Guasti API: el resultat va dins de `r`.
struct PResult<T: Decodable>: Decodable {
    let r: T
}

struct PFitxer: Decodable {
    var name: String
    var mime: String?
    var size: Double?
    var url: String?
    var tooBig: Bool?
    var data: String?
}

struct PPdf: Decodable {
    var name: String
    var data: String
    var mine: Bool?
    var owner: String?
}

struct PShareInfo: Decodable {
    var name: String
    var size: Double
    var mime: String?
    var url: String
    var isPublic: Bool
    var canLink: Bool
}

struct PPaquet: Decodable {
    var id: String
    var url: String
}

struct PInventari: Decodable, Identifiable {
    var t: FlexText
    var fmt: FlexText?
    var folder: FlexText?
    var url: FlexText?
    var id: String
}

/// Anotacions fetes amb el llapis: el mateix JSON que guarda l'app web
/// ({"v":1,"pages":{"1":[{"c":"#111111","w":0.0025,"p":[x,y,x,y...]}]}}), amb coordenades de 0 a 1.
struct Anotacions: Codable {
    var v: Int = 1
    var pages: [String: [Traç]] = [:]

    struct Traç: Codable {
        var c: String
        var w: Double
        var p: [Double]
    }

    var isEmpty: Bool { pages.values.allSatisfy(\.isEmpty) }
}

// MARK: - Colors i lletra de l'app web (Index.html)

/// Colors de "Arxiu de Repertori": blanc i negre amb el blau #2AABEE.
enum P {
    static let paper = dyn(0xffffff, 0x000000)
    static let card = dyn(0xffffff, 0x121212)
    static let ink = dyn(0x111111, 0xf5f5f5)
    static let mute = dyn(0x6e6e73, 0x9a9a9a)
    static let line = dyn(0xe2e2e2, 0x2c2c2c)
    static let accent = dyn(0x111111, 0xf5f5f5)
    static let onAccent = dyn(0xffffff, 0x000000)
    static let blue = Color(UIColor(hex: 0x2AABEE))
    static let blueInk = dyn(0x1683c9, 0x5cc0f2)
    static let accentSoft = dyn(0xe8f5fd, 0x0c2a3b)
    static let chip = dyn(0xf2f2f2, 0x1e1e1e)
    static let danger = Color(UIColor(hex: 0xb3261e))
    static let red = Color(UIColor(hex: 0xc62828))

    private static func dyn(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light) })
    }
}

// MARK: - Les mateixes regles que l'app web

enum Arxiu {
    static let keys = ["Obres": "ID", "Documents": "ID", "Concerts": "ID", "Agrupacions": "Agrupació",
                       "Directors": "Director/a", "Fagotades": "Any"]
    static let singular = ["Obres": "obra", "Documents": "document", "Concerts": "concert", "Fagotades": "fagotada",
                           "Agrupacions": "agrupació", "Directors": "director/a"]

    /// Les pestanyes de dalt: (full o vista, nom que es veu).
    static let tabs: [(String, String)] = [("Inici", "Inici"), ("Obres", "Obres"), ("Compositors", "Compositors"),
                                           ("Cursos", "Pedagògic"), ("Documents", "Documents"), ("Concerts", "Concerts"),
                                           ("Fagotades", "Fagotades"), ("Agrupacions", "Agrupacions"), ("Directors", "Directors")]

    enum Tipus { case text, number, date, time, url, area, check, chips, multi, ref, comp, book, files }

    struct Camp {
        let k: String
        let t: Tipus
        var src = ""
        var showIf = ""
    }

    /// Els camps de cada fitxa, en el mateix ordre que SCHEMA de l'app web.
    static let schema: [String: [Camp]] = [
        "Obres": [
            Camp(k: "Categoria", t: .chips, src: "L:Categoria"), Camp(k: "Formació", t: .chips, src: "F:"),
            Camp(k: "Obra", t: .text), Camp(k: "Compositor", t: .text),
            Camp(k: "Àmbit", t: .chips, src: "L:Àmbit"),
            Camp(k: "Instrument", t: .chips, src: "L:Instrument"),
            Camp(k: "Etiquetes", t: .multi, src: "L:Etiquetes"),
            Camp(k: "Agrupació", t: .chips, src: "S:Agrupacions", showIf: "Àmbit=|Concert|Fagotada|Prova / audició|Estudi personal"),
            Camp(k: "Director/a", t: .chips, src: "S:Directors", showIf: "Àmbit=|Concert|Fagotada"),
            Camp(k: "Concert", t: .ref, src: "Concerts", showIf: "Àmbit=Concert"),
            Camp(k: "Fagotada", t: .chips, src: "S:Fagotades", showIf: "Àmbit=Fagotada"),
            Camp(k: "Curs", t: .multi, src: "L:Curs", showIf: "Àmbit=Pedagògic|Prova / audició|Estudi personal;Etiquetes~Vila-seca|EMMCA"),
            Camp(k: "Centre", t: .chips, src: "L:Centre", showIf: "Àmbit=Pedagògic;Etiquetes~Vila-seca"),
            Camp(k: "Any aproximat", t: .number), Camp(k: "Durada (min)", t: .number),
            Camp(k: "Fragment orquestral", t: .check), Camp(k: "Gravació", t: .url), Camp(k: "Notes", t: .area),
            Camp(k: "__files", t: .files, src: "Particel·la"),
        ],
        "Documents": [
            Camp(k: "Títol", t: .text), Camp(k: "Compositor", t: .comp), Camp(k: "Instrument", t: .multi, src: "L:Instrument"),
            Camp(k: "Llibre", t: .book), Camp(k: "Categoria", t: .chips, src: "L:Categoria"), Camp(k: "Formació", t: .chips, src: "F:"),
            Camp(k: "Curs", t: .multi, src: "L:Curs"), Camp(k: "Tipus", t: .multi, src: "L:Tipus document"),
            Camp(k: "Format", t: .chips, src: "L:Format"), Camp(k: "Enllaç Drive", t: .url), Camp(k: "Obra", t: .ref, src: "Obres"),
            Camp(k: "Notes", t: .area),
        ],
        "Concerts": [
            Camp(k: "Data", t: .date), Camp(k: "Hora", t: .time), Camp(k: "Títol", t: .text),
            Camp(k: "Agrupació", t: .chips, src: "S:Agrupacions"), Camp(k: "Lloc", t: .text), Camp(k: "Població", t: .text),
            Camp(k: "Instruments", t: .chips, src: "L:Instrument"), Camp(k: "Director/a", t: .chips, src: "S:Directors"),
            Camp(k: "Solistes", t: .text), Camp(k: "Programa", t: .area), Camp(k: "Notes", t: .area),
            Camp(k: "__files", t: .files, src: "Programa de concert"),
        ],
        "Fagotades": [Camp(k: "Any", t: .number), Camp(k: "Lloc", t: .text), Camp(k: "Dates", t: .text),
                      Camp(k: "Carpeta repertori", t: .url), Camp(k: "Notes", t: .area)],
        "Agrupacions": [Camp(k: "Agrupació", t: .text), Camp(k: "Tipus", t: .text), Camp(k: "Notes", t: .area)],
        "Directors": [Camp(k: "Director/a", t: .text), Camp(k: "Agrupacions", t: .text), Camp(k: "Notes", t: .area)],
    ]

    static let labels = ["Compositor": "Compositor / autor", "Llibre": "Llibre / recull", "Àmbit": "Activitat",
                         "Instrument": "Instrument / paper", "Curs": "Curs / grup", "Instruments": "Instrument / paper",
                         "Agrupació": "Agrupació (banda, orquestra, conjunt...)", "__tipus": "Tipus de fitxer"]
    static let hints = [
        "Instrument": "Per a què és: fagot sol, fagot i piano, fagot i orquestra, fagotino... o quin paper (1r, 2n, 3r, contrafagot). Pots marcar-ne diversos.",
        "Compositor": "Si no el saps, posa «Anònim» o «Popular».",
        "Llibre": "Els documents amb el mateix llibre es mostren junts i el fitxer es mou al Drive a la carpeta Llibres / nom del llibre.",
        "Curs": "Pots marcar-ne diversos si l'obra serveix per a més d'un curs.",
        "Etiquetes": "Pots marcar-ne diverses.",
        "Categoria": "Tria primer de quin tipus de repertori es tracta.",
        "Àmbit": "Per a què és: un concert, una fagotada, classe (pedagògic), estudi personal o una prova.",
    ]
    static func lbl(_ k: String) -> String { labels[k] ?? k }

    /// Grups propis de cada centre (a més dels cursos d'Iniciació, Elemental i Professional).
    static let centreGroups: [String: [String]] = ["Vila-seca": ["Música de cambra"], "L'Hospitalet": ["EMMCA", "Ministrils", "Toc d'inici"]]
    static func isGroup(_ c: String) -> Bool { centreGroups.values.contains { $0.contains(c) } }

    static let mesos = ["gener", "febrer", "març", "abril", "maig", "juny", "juliol", "agost", "setembre", "octubre", "novembre", "desembre"]
    static let dies = ["Dg.", "Dl.", "Dt.", "Dc.", "Dj.", "Dv.", "Ds."]

    // MARK: text

    static func norm(_ s: String?) -> String {
        (s ?? "").folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "ca_ES")).lowercased()
    }

    static func splitTags(_ v: String?) -> [String] {
        (v ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    static func uniq(_ arr: [String?]) -> [String] {
        var seen = Set<String>()
        return arr.compactMap { $0 }.filter { !$0.isEmpty && seen.insert($0).inserted }.sorted()
    }

    static func sortNorm(_ a: String?, _ b: String?) -> Bool {
        norm(a).compare(norm(b), locale: Locale(identifier: "ca_ES")) == .orderedAscending
    }

    // MARK: dates

    private static func ymd(_ d: String?) -> (Int, Int, Int)? {
        let s = d ?? ""
        guard s.count >= 10 else { return nil }
        let p = s.prefix(10).split(separator: "-")
        guard p.count == 3, let y = Int(p[0]), let m = Int(p[1]), let dd = Int(p[2]), (1...12).contains(m) else { return nil }
        return (y, m, dd)
    }

    static func fmtDate(_ d: String?) -> String {
        guard let (y, m, dd) = ymd(d) else { return d ?? "" }
        return String(format: "%02d/%02d/%d", dd, m, y)
    }

    static func today() -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    static func monthName(_ d: String?) -> String {
        guard let (y, m, _) = ymd((d ?? "") + (d?.count == 7 ? "-01" : "")) else { return "" }
        let n = mesos[m - 1]
        let year = Calendar.current.component(.year, from: Date())
        return n.prefix(1).uppercased() + n.dropFirst() + (y != year ? " \(y)" : "")
    }

    static func dayLabel(_ d: String?) -> String {
        guard let (y, m, dd) = ymd(d) else { return d ?? "" }
        var c = DateComponents()
        c.year = y; c.month = m; c.day = dd
        let wd = Calendar(identifier: .gregorian).date(from: c).map { Calendar(identifier: .gregorian).component(.weekday, from: $0) - 1 } ?? 0
        let n = mesos[m - 1]
        return dies[wd] + " \(dd)" + ("aeiou".contains(n.prefix(1)) ? " d'" : " de ") + n
    }

    // MARK: fitxers

    static func docUrl(_ d: Fila) -> String { (d["Fitxer"]?.isEmpty == false ? d["Fitxer"] : d["Enllaç Drive"]) ?? "" }

    static func fileId(_ u: String) -> String {
        for pattern in [#"/d/([-\w]{20,})"#, #"[?&]id=([-\w]{20,})"#] {
            if let r = u.range(of: pattern, options: .regularExpression) {
                let m = String(u[r])
                if let s = m.range(of: #"[-\w]{20,}"#, options: .regularExpression) { return String(m[s]) }
            }
        }
        return ""
    }

    static func fileId(_ d: Fila) -> String { fileId(docUrl(d)) }

    static let editFormats: Set<String> = ["musicxml", "musescore", "notion", "finale", "sibelius", "dorico", "midi", "lilypond",
                                           "capella", "encore", "guitar pro"]

    /// PDF / fitxers editables de partitura / la resta (àudio, vídeo, imatges).
    static func docKind(_ d: Fila) -> String {
        let f = (d["Format"] ?? "").lowercased()
        if f.isEmpty || f == "pdf" { return "pdf" }
        if editFormats.contains(f) { return "ed" }
        return "alt"
    }

    static func isPdf(_ d: Fila) -> Bool { docKind(d) == "pdf" && !fileId(d).isEmpty }

    static func fileExt(_ name: String) -> String {
        guard let r = name.range(of: #"\.([A-Za-z0-9]{1,8})$"#, options: .regularExpression) else { return "" }
        return String(name[r].dropFirst()).lowercased()
    }

    enum Vista { case pdf, audio, video, image, other }

    static func viewKind(_ d: Fila, name: String? = nil) -> Vista {
        let f = (d["Format"] ?? "").lowercased(), e = fileExt(name ?? d["Títol"] ?? "")
        if e == "pdf" || (e.isEmpty && (f.isEmpty || f == "pdf")) { return .pdf }
        if ["mp3", "wav", "m4a", "aac", "ogg", "oga", "flac", "aif", "aiff", "opus"].contains(e) || f == "àudio" { return .audio }
        if ["mp4", "mov", "m4v", "webm"].contains(e) || f == "vídeo" { return .video }
        if ["jpg", "jpeg", "png", "gif", "webp", "heic", "bmp"].contains(e) || f == "imatge" { return .image }
        if f == "pdf" { return .pdf }
        return .other
    }

    static let fmtNames = ["musx": "Finale", "mus": "Finale", "sib": "Sibelius", "dorico": "Dorico", "mscz": "MuseScore",
                           "mscx": "MuseScore", "notion": "Notion", "mid": "MIDI", "midi": "MIDI", "ly": "LilyPond",
                           "gp": "Guitar Pro", "gpx": "Guitar Pro"]

    static func guessFormat(_ name: String) -> String {
        switch fileExt(name) {
        case "pdf": return "PDF"
        case "xml", "musicxml", "mxl": return "MusicXML"
        case "mscz", "mscx": return "MuseScore"
        case "notion": return "Notion"
        case "musx", "mus": return "Finale"
        case "sib": return "Sibelius"
        case "dorico": return "Dorico"
        case "mid", "midi": return "MIDI"
        case "mp3", "wav", "m4a", "aac", "ogg", "flac", "aif", "aiff": return "Àudio"
        case "mp4", "mov", "m4v", "webm": return "Vídeo"
        case "jpg", "jpeg", "png", "gif", "webp", "heic": return "Imatge"
        default: return ""
        }
    }

    static func mime(_ name: String) -> String {
        switch fileExt(name) {
        case "pdf": return "application/pdf"
        case "xml", "musicxml": return "application/xml"
        case "mp3": return "audio/mpeg"
        case "m4a", "aac": return "audio/mp4"
        case "wav": return "audio/wav"
        case "mp4", "m4v": return "video/mp4"
        case "mov": return "video/quicktime"
        case "jpg", "jpeg": return "image/jpeg"
        case "png": return "image/png"
        case "heic": return "image/heic"
        default: return "application/octet-stream"
        }
    }

    /// Ordre de guió de director: general, vent fusta, vent metall, percussió, teclats/arpa, veus, corda.
    static let scoreOrder: [(String, Int)] = [
        (#"partitura general|full score|\bscore\b|\bguio\b|\bdirector\b|conductor|\bgeneral\b|partitur\b|\bdirettore\b"#, 0),
        (#"piccolo|flauti|ottavino"#, 10), (#"alto flute|flauta en sol|flauta alt"#, 12), (#"flaut|flute|flote|\bfl\b"#, 11),
        (#"english horn|cor angl|corno ingl|corn angl|cor anglais|englischhorn"#, 22), (#"oboe|oboi|hautbois|\bob\b"#, 20),
        (#"requint|clarinet(e|o)? (in |en )?(eb|mib)|eb clarinet"#, 29),
        (#"bass clarinet|clarinet(e|o)? baix|clarinete bajo|clarone|bassklarinet"#, 32), (#"clarin|klarinet|\bcl\b"#, 30),
        (#"soprano sax|saxo(fon|phone)? soprano|sax soprano"#, 34), (#"alto sax|saxo(fon|phone)? alt|sax alt"#, 35),
        (#"tenor sax|saxo(fon|phone)? tenor|sax tenor"#, 36), (#"baritone sax|saxo(fon|phone)? bariton|sax bariton"#, 37),
        (#"saxo|\bsax\b"#, 35),
        (#"contrafag|contrabassoon|kontrafag|contrabasson|controfag"#, 42), (#"fagot|bassoon|basson|\bfg\b|\bbsn\b"#, 40),
        (#"\bhorn|trompa|corno|\bhrn\b|waldhorn"#, 50), (#"trumpet|trompet|tromba|cornet|fliscorn|flugel|\btpt\b"#, 55),
        (#"bass trombone|trombo baix|trombon bajo"#, 62), (#"trombo|posaune|\btbn\b"#, 60),
        (#"euphonium|bombard|baritone|tenor tuba"#, 64), (#"tuba|\btb\b"#, 66),
        (#"timpan|timbal|pauken"#, 70),
        (#"percus|bateria|drum|caixa|bombo|plats|cymbal|glock|xilo|xylo|marimba|vibraf|vibraph|lamines|claves|triangle"#, 72),
        (#"arpa|harp|harpe"#, 80), (#"celest"#, 81), (#"piano|pno|klavier|teclat|keyboard|organ|orgue"#, 82),
        (#"guitar|guitarra"#, 83),
        (#"soprano|\bsop\b"#, 85), (#"contralt|mezzo"#, 86), (#"\btenor\b"#, 87), (#"baritono|\bbaix\b voz|\bbass voice"#, 88),
        (#"\bcor\b mixt|choir|coral"#, 89),
        (#"violin|violi\b|violino|\bvln?\b|geige"#, 90), (#"viola\b|\bvla\b|\balto\b"#, 92), (#"cello|violoncel|\bvc\b"#, 93),
        (#"contrabai|double bass|contrabass|kontrabass|contrabajo|\bcb\b|\bbass\b"#, 94),
    ]

    static func scoreRank(_ d: Fila) -> Int {
        let tip = d["Tipus"] ?? ""
        var title = (d["Títol"] ?? "").replacingOccurrences(of: #"^\s*\d{1,3}[a-zA-Z]?[\s._-]+"#, with: "", options: .regularExpression)
        title = title.replacingOccurrences(of: #"[_\-.()]+"#, with: " ", options: .regularExpression)
        let t = " " + norm(title) + " ", ins = " " + norm(d["Instrument"]) + " "
        var r = 99
        if tip.range(of: "partitura general", options: .caseInsensitive) != nil, tip.range(of: "particel", options: .caseInsensitive) == nil {
            r = 0
        } else {
            for (p, v) in scoreOrder where t.range(of: p, options: .regularExpression) != nil || ins.range(of: p, options: .regularExpression) != nil {
                r = v
                break
            }
        }
        var k = 0
        let both = t + ins
        if let m = both.range(of: #"(^|\s)([1-4])(st|nd|rd|th|r|n|o|t)?(?=\s)"#, options: .regularExpression),
           let digit = both[m].first(where: \.isNumber), let n = Int(String(digit)) {
            k = n
        } else if both.range(of: #"(^|\s)iv(?=\s)"#, options: .regularExpression) != nil { k = 4 }
        else if both.range(of: #"(^|\s)iii(?=\s)"#, options: .regularExpression) != nil { k = 3 }
        else if both.range(of: #"(^|\s)ii(?=\s)"#, options: .regularExpression) != nil { k = 2 }
        return r * 10 + k
    }

    static func sortScore(_ docs: [Fila]) -> [Fila] {
        docs.enumerated().map { ($0.element, scoreRank($0.element)) }
            .sorted { $0.1 != $1.1 ? $0.1 < $1.1 : sortNorm($0.0["Títol"], $1.0["Títol"]) }
            .map(\.0)
    }
}

extension Color {
    init(hexString: String) {
        let h = hexString.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        self.init(UIColor(hex: UInt32(h, radix: 16) ?? 0x111111))
    }
}

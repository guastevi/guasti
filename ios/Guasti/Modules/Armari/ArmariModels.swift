import Foundation

/// Una fila del full "Armari Guasteví - Peces". Les claus són els noms de columna del full.
struct Peca: Codable, Identifiable, Hashable {
    var id: String
    var nom: String
    var tipus: String
    var temporada: String
    var ubicacio: String
    var color: String
    var notes: String
    var portada: String
    var talla: String
    var marca: String
    var privada: String

    enum CodingKeys: String, CodingKey {
        case id = "ID"
        case nom = "Nom"
        case tipus = "Tipus"
        case temporada = "Temporada"
        case ubicacio = "Ubicació"
        case color = "Color"
        case notes = "Notes"
        case portada = "Portada"
        case talla = "Talla"
        case marca = "Marca"
        case privada = "Privada"
    }

    init(id: String, nom: String = "", tipus: String = "", temporada: String = "", ubicacio: String = "",
         color: String = "", notes: String = "", portada: String = "", talla: String = "", marca: String = "",
         privada: String = "") {
        self.id = id
        self.nom = nom
        self.tipus = tipus
        self.temporada = temporada
        self.ubicacio = ubicacio
        self.color = color
        self.notes = notes
        self.portada = portada
        self.talla = talla
        self.marca = marca
        self.privada = privada
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func s(_ key: CodingKeys) -> String { (try? c.decodeIfPresent(String.self, forKey: key)) ?? "" }
        id = s(.id)
        nom = s(.nom)
        tipus = s(.tipus)
        temporada = s(.temporada)
        ubicacio = s(.ubicacio)
        color = s(.color)
        notes = s(.notes)
        portada = s(.portada).trimmingCharacters(in: .whitespacesAndNewlines)
        talla = s(.talla)
        marca = s(.marca)
        privada = s(.privada)
    }

    static func nova() -> Peca {
        Peca(id: String(UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased().prefix(8)),
             tipus: "Roba de carrer", temporada: "Tot l'any")
    }

    var isPrivate: Bool {
        let v = privada.trimmingCharacters(in: .whitespaces).lowercased()
        return v.hasPrefix("s") || v == "true" || v == "1"
    }

    /// "Granat, Negre" → ["Granat", "Negre"]
    var colors: [String] {
        color.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    var searchText: String {
        [nom, tipus, temporada, ubicacio, color, notes, talla, marca].joined(separator: " ")
    }

    func jsonObject() throws -> [String: Any] {
        let data = try JSONEncoder().encode(self)
        return (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }
}

/// Una fila del full "Armari Guasteví - Fotos".
struct Foto: Codable, Identifiable, Hashable {
    var id: String
    var peca: String
    var path: String
    var ordre: String

    enum CodingKeys: String, CodingKey {
        case id = "ID"
        case peca = "Peça"
        case path = "Foto"
        case ordre = "Ordre"
    }

    init(id: String, peca: String, path: String, ordre: String) {
        self.id = id
        self.peca = peca
        self.path = path
        self.ordre = ordre
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func s(_ key: CodingKeys) -> String { (try? c.decodeIfPresent(String.self, forKey: key)) ?? "" }
        id = s(.id)
        peca = s(.peca)
        path = s(.path).trimmingCharacters(in: .whitespacesAndNewlines)
        ordre = s(.ordre)
    }

    var order: Int { Int(Double(ordre) ?? 0) }
}

/// Les mateixes llistes que fa servir l'app web de l'Armari.
enum ArmariCatalog {
    static let tipus = ["Roba de concert", "Roba de carrer", "Roba de casa"]
    static func tipusLabel(_ t: String) -> String {
        switch t {
        case "Roba de concert": return "Concert"
        case "Roba de casa": return "Casa"
        default: return "Carrer"
        }
    }

    static let temporades = ["Hivern", "Estiu", "Tot l'any"]

    static let ubicacions = ["Armari petit", "Armari dreta", "Armari esquerra", "Perxes dreta", "Perxes esquerra",
                             "Porta", "Còmoda 1r calaix", "Còmoda 2n calaix", "Còmoda 3r calaix"]

    static let colors: [(name: String, hex: String)] = [
        ("Negre", "111111"), ("Blau marí", "1d2b4c"), ("Granat", "6e1423"), ("Vermell", "c8102e"),
        ("Verd", "2e7d32"), ("Blanc", "ffffff"), ("Groc", "f2c200"), ("Marró", "6b4226"), ("Gris", "8c8c8c"),
        ("Beix", "d9c4a3"), ("Blau", "1f5fbf"), ("Blau cel", "8ec5e8"), ("Rosa", "f3a6b8"), ("Fúcsia", "d1127a"),
        ("Lila", "9b6fc4"), ("Taronja", "ec7a1c"), ("Daurat", "c9a227"), ("Platejat", "c4c4c4"), ("Multicolor", "multi"),
    ]

    /// Les peces del desplegable "Peça", en el mateix ordre que l'app web.
    static let kinds = ["Americana", "Abric", "Jaqueta", "Armilla", "Jersei", "Rebeca", "Dessuadora", "Camisa", "Blusa",
                        "Samarreta", "Top", "Vestit", "Faldilla", "Pantaló", "Texans", "Malles", "Sabates", "Botes",
                        "Botins", "Sandàlies", "Bambes", "Bossa", "Fulard", "Cinturó", "Barret", "Mitjons", "Mitges",
                        "Bragues", "Sostenidors", "Lligacames", "Body", "Combinació", "Pijama", "Banyador", "Llençols",
                        "Funda de coixí", "Funda nòrdica", "Edredó", "Manta", "Tovallola", "Barnús", "Estovalles"]
    /// Roba de casa: en triar-les, el tipus passa a "Casa".
    static let home = ["Llençols", "Funda de coixí", "Funda nòrdica", "Edredó", "Manta", "Tovallola", "Barnús", "Estovalles"]
    static let shoes = ["Sabates", "Botes", "Botins", "Sandàlies", "Bambes"]
    /// Roba íntima: en triar-la, la peça es marca com a privada.
    static let intimate = ["Mitges", "Bragues", "Sostenidors", "Lligacames", "Body", "Combinació"]

    /// Ordre "com un armari" de l'app web.
    static let ordre = ["Jersei", "Rebeca", "Dessuadora", "Armilla", "Americana", "Jaqueta", "Abric", "Camisa", "Blusa",
                        "Samarreta", "Top", "Body", "Vestit", "Faldilla", "Texans", "Pantaló", "Malles", "Sabates",
                        "Botins", "Botes", "Sandàlies", "Bambes", "Bossa", "Fulard", "Cinturó", "Barret", "Mitjons",
                        "Mitges", "Bragues", "Sostenidors", "Lligacames", "Combinació", "Pijama", "Banyador", "Llençols",
                        "Funda de coixí", "Funda nòrdica", "Edredó", "Manta", "Tovallola", "Barnús", "Estovalles"]

    /// "Samarreta interior màniga llarga" → "Samarreta"
    static func kind(of nom: String) -> String {
        let t = nom.trimmingCharacters(in: .whitespaces)
        let l = t.lowercased()
        return ordre.first { l == $0.lowercased() || l.hasPrefix($0.lowercased() + " ") } ?? t
    }

    static func orderIndex(_ p: Peca) -> Int {
        ordre.firstIndex(of: kind(of: p.nom)) ?? ordre.count
    }

    static func group(_ p: Peca) -> Int {
        switch p.tipus {
        case "Roba de concert": return 1
        case "Roba de casa": return 2
        default: return 0
        }
    }
}

enum ArmariSort: String, CaseIterable, Identifiable {
    case armari, nom, noves, ubicacio, peca
    var id: String { rawValue }
    var title: String {
        switch self {
        case .armari: return "Ordena com un armari"
        case .nom: return "Ordena per nom (A-Z)"
        case .noves: return "Ordena per últimes afegides"
        case .ubicacio: return "Ordena per ubicació"
        case .peca: return "Ordena per tipus de peça (A-Z)"
        }
    }
}

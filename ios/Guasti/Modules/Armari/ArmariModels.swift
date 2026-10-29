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
        portada = s(.portada)
        talla = s(.talla)
        marca = s(.marca)
        privada = s(.privada)
    }

    static func nova() -> Peca {
        Peca(id: String(UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased().prefix(8)))
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
        path = s(.path)
        ordre = s(.ordre)
    }

    var order: Int { Int(Double(ordre) ?? 0) }
}

struct PecaRoute: Hashable {
    let id: String
}

import Foundation

/// Les dades de Gastos. Es guarda l'últim mes vist al mòbil perquè s'obri al moment;
/// tot es llegeix i s'escriu al full "Economia Guasti", el mateix de l'app web.
@MainActor
final class GastosStore: ObservableObject {
    static let shared = GastosStore()

    @Published private(set) var dades: GastosDades?
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private let cacheURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("gastos.json")
    }()

    private init() {
        if let data = try? Data(contentsOf: cacheURL) {
            dades = try? JSONDecoder().decode(GastosDades.self, from: data)
        }
    }

    /// Carrega un mes (nil = el mes actual).
    func load(_ mes: String? = nil) async {
        guard let client = Connection.shared.client else {
            errorMessage = "Falta configurar la connexió amb Google (engranatge de la pantalla d'inici)."
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            var params: [String: Any] = [:]
            if let mes { params["mes"] = mes }
            let result: GastosDades = try await client.call("gastos.dades", params)
            set(result)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Desa un moviment i torna el missatge de confirmació ("Desat: 12,30 € a Menjar").
    func afegir(tipus: String, imp: String, categoria: String, concepte: String, data: String) async throws -> String {
        let moviment: [String: Any] = ["tipus": tipus, "import": imp, "categoria": categoria,
                                       "concepte": concepte, "data": data]
        let result: GastosDades = try await requireClient().call("gastos.afegir", ["moviment": moviment, "mes": dades?.mes ?? ""])
        set(result)
        return result.missatge ?? "Desat"
    }

    func esborrar(_ moviment: Moviment) async throws {
        let result: GastosDades = try await requireClient().call("gastos.esborrar", ["id": moviment.id, "mes": dades?.mes ?? ""])
        set(result)
    }

    private func set(_ result: GastosDades) {
        dades = result
        errorMessage = nil
        if let data = try? JSONEncoder().encode(result) {
            try? data.write(to: cacheURL, options: .atomic)
        }
    }

    private func requireClient() throws -> AppsScriptClient {
        guard let client = Connection.shared.client else {
            throw APIError(message: "Falta configurar la connexió amb Google.")
        }
        return client
    }
}

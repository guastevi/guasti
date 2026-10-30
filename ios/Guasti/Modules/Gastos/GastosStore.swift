import Foundation

/// Les dades de Gastos. Es guarda l'últim mes vist al mòbil perquè s'obri al moment;
/// tot es llegeix i s'escriu al full "Economia Guasti", el mateix de l'app web.
@MainActor
final class GastosStore: ObservableObject {
    static let shared = GastosStore()

    @Published private(set) var dades: GastosDades?
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?
    /// Tots els moviments de tots els mesos, per al cercador universal.
    @Published private(set) var tots: [Moviment] = []
    private var totsAlDia = false

    private let totsURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("gastos-tots.json")
    }()

    private let cacheURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("gastos.json")
    }()

    private init() {
        if let data = try? Data(contentsOf: cacheURL) {
            dades = try? JSONDecoder().decode(GastosDades.self, from: data)
        }
        if let data = try? Data(contentsOf: totsURL) {
            tots = (try? JSONDecoder().decode([Moviment].self, from: data)) ?? []
        }
        if tots.isEmpty { tots = dades?.moviments ?? [] }
    }

    /// Baixa els moviments de tots els mesos (un cop per sessió) perquè el cercador els trobi.
    /// L'Apps Script dona els moviments mes a mes, així que es demanen de 4 en 4.
    func carregaTots() async {
        guard !totsAlDia, let client = Connection.shared.client else { return }
        do {
            let actual: GastosDades = try await client.call("gastos.dades")
            var perMes: [String: [Moviment]] = [actual.mes: actual.moviments]
            let pendents = actual.mesos.filter { $0 != actual.mes }
            for lot in stride(from: 0, to: pendents.count, by: 4).map({ Array(pendents[$0..<min($0 + 4, pendents.count)]) }) {
                try await withThrowingTaskGroup(of: (String, [Moviment]).self) { group in
                    for mes in lot {
                        group.addTask {
                            let d: GastosDades = try await client.call("gastos.dades", ["mes": mes])
                            return (mes, d.moviments)
                        }
                    }
                    for try await (mes, movs) in group { perMes[mes] = movs }
                }
            }
            tots = perMes.values.flatMap { $0 }.sorted { $0.data != $1.data ? $0.data > $1.data : $0.fila > $1.fila }
            totsAlDia = true
            if let data = try? JSONEncoder().encode(tots) {
                try? data.write(to: totsURL, options: .atomic)
            }
        } catch {
            // Sense connexió: el cercador fa servir la còpia que hi hagi al mòbil.
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
        } catch is CancellationError {
            // La pantalla s'ha tancat: no és un error.
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
        // El mes que acaba d'arribar substitueix el que hi havia a la llista del cercador
        tots = (tots.filter { $0.mes != result.mes } + result.moviments)
            .sorted { $0.data != $1.data ? $0.data > $1.data : $0.fila > $1.fila }
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

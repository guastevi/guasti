import Foundation

/// Comptes, bolos, nòmines i previstos: pestanyes noves del full "Economia Guasti".
/// L'script només llegeix i desa files; la previsió i l'IRPF es calculen aquí.
@MainActor
final class FuturStore: ObservableObject {
    static let shared = FuturStore()

    @Published private(set) var taules: [String: [FinFila]] = [:]
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private struct Resposta: Codable {
        var taules: [String: [FinFila]]
    }

    private let cacheURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("gastos-futur.json")
    }()

    private init() {
        if let data = try? Data(contentsOf: cacheURL), let r = try? JSONDecoder().decode(Resposta.self, from: data) {
            taules = r.taules
        }
    }

    var carregat: Bool { !taules.isEmpty }

    // MARK: Dades

    var comptes: [Compte] { (taules[FinTaula.comptes.nom] ?? []).map(Compte.init).filter { !$0.nom.isEmpty } }
    var saldos: [SaldoHist] { (taules[FinTaula.saldos.nom] ?? []).map(SaldoHist.init).filter { !$0.data.isEmpty } }
    var contractes: [Contracte] { (taules[FinTaula.contractes.nom] ?? []).map(Contracte.init).filter { $0.brut > 0 } }
    var bolos: [Bolo] {
        (taules[FinTaula.bolos.nom] ?? []).map(Bolo.init).filter { $0.brut > 0 }.sorted { $0.data > $1.data }
    }
    var previstos: [Previst] {
        (taules[FinTaula.previstos.nom] ?? []).map(Previst.init).filter { $0.imp > 0 }
            .sorted { ($0.mes, $0.nom) < ($1.mes, $1.nom) }
    }

    func ajust(_ clau: String) -> String {
        (taules[FinTaula.ajustos.nom] ?? []).first { $0.txt("ID") == clau }?.txt("Valor") ?? ""
    }

    var coixiMesos: Double {
        let v = Fin.number(ajust("coixiMesos"))
        return v > 0 ? v : 6
    }

    /// Mitjana de despesa (i diners que van a inversió) dels 3 últims mesos sencers.
    var despesaMitjana: Double {
        let actual = FinMes.actual()
        let mesos = (1...3).map { FinMes.suma(actual, -$0) }
        var total = 0.0
        for f in taules[FinTaula.moviments.nom] ?? [] {
            let mes = String((f.txt("Data").isEmpty ? f.txt("Mes") : f.txt("Data")).prefix(7))
            guard mesos.contains(mes) else { continue }
            let t = f.txt("Tipus").lowercased()
            if t.hasPrefix("despes") || t.hasPrefix("inversi") { total += f.num("Import") }
        }
        return (total / 3 * 100).rounded() / 100
    }

    /// La que es fa servir a la previsió: la teva si l'has escrita, si no la mitjana.
    var despesaMensual: Double {
        let v = Fin.number(ajust("despesaMensual"))
        return v > 0 ? v : despesaMitjana
    }

    var liquid: Double { comptes.filter(\.liquid).reduce(0) { $0 + $1.saldo } }
    var patrimoni: Double { comptes.reduce(0) { $0 + $1.saldo } }
    var coixiObjectiu: Double { despesaMensual * coixiMesos }

    /// Patrimoni a final de cada mes: l'últim saldo conegut de cada compte.
    struct PuntPatrimoni: Identifiable {
        var mes: String
        var total: Double
        var id: String { mes }
    }

    var evolucioPatrimoni: [PuntPatrimoni] {
        let hist = saldos.sorted { $0.data < $1.data }
        guard let primer = hist.first?.data.prefix(7) else { return [] }
        var mes = String(primer)
        let actual = FinMes.actual()
        var out: [PuntPatrimoni] = []
        var ultim: [String: Double] = [:]
        var i = 0
        while mes <= actual {
            while i < hist.count, String(hist[i].data.prefix(7)) <= mes {
                ultim[hist[i].compte] = hist[i].saldo
                i += 1
            }
            out.append(PuntPatrimoni(mes: mes, total: ultim.values.reduce(0, +)))
            mes = FinMes.suma(mes, 1)
        }
        return Array(out.suffix(24))
    }

    func irpf(_ exercici: Int) -> IRPF { IRPF.calcula(exercici: exercici, contractes: contractes, bolos: bolos) }

    var previsio: Previsio {
        let c = contractes, b = bolos
        return Previsio.calcula(mesActual: FinMes.actual(), saldoInicial: liquid, despesaMensual: despesaMensual,
                                contractes: c, bolos: b, previstos: previstos) { IRPF.calcula(exercici: $0, contractes: c, bolos: b) }
    }

    // MARK: Crides

    func load() async {
        guard let client = Connection.shared.client else {
            errorMessage = "Falta configurar la connexió amb Google (engranatge de la pantalla d'inici)."
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            let r: Resposta = try await client.call("gastos.taules", ["taules": FinTaula.defs])
            set(r)
        } catch is CancellationError {
        } catch {
            errorMessage = Self.explica(error)
        }
    }

    func desa(_ taula: FinTaula, _ fila: [String: Any]) async throws {
        do {
            let r: Resposta = try await requireClient().call("gastos.desaFila",
                                                             ["taula": taula.nom, "cols": taula.cols, "fila": fila, "taules": FinTaula.defs])
            set(r)
        } catch {
            throw APIError(message: Self.explica(error))
        }
    }

    func esborra(_ taula: FinTaula, id: String) async throws {
        do {
            let r: Resposta = try await requireClient().call("gastos.esborraFila",
                                                             ["taula": taula.nom, "id": id, "taules": FinTaula.defs])
            set(r)
        } catch {
            throw APIError(message: Self.explica(error))
        }
    }

    /// Desa el saldo nou del compte i en guarda l'historial (per a l'evolució del patrimoni).
    func actualitzaSaldo(_ compte: Compte, saldo: Double) async throws {
        var c = compte
        if c.id.isEmpty { c.id = FinTaula.nouId() }
        c.saldo = saldo
        c.actualitzat = FinMes.avui()
        try await desa(.comptes, c.fila)
        try await desa(.saldos, ["Data": c.actualitzat, "Compte": c.id, "Nom": c.nom, "Saldo": saldo])
    }

    func desaAjust(_ clau: String, _ valor: String) async throws {
        try await desa(.ajustos, ["ID": clau, "Valor": valor])
    }

    private func set(_ r: Resposta) {
        taules = r.taules
        errorMessage = nil
        if let data = try? JSONEncoder().encode(r) {
            try? data.write(to: cacheURL, options: .atomic)
        }
    }

    private func requireClient() throws -> AppsScriptClient {
        guard let client = Connection.shared.client else {
            throw APIError(message: "Falta configurar la connexió amb Google.")
        }
        return client
    }

    /// Si l'script de Google encara és la versió antiga, ho diu clar.
    private static func explica(_ error: Error) -> String {
        let t = error.localizedDescription
        if t.contains("Acció desconeguda") {
            return "Cal actualitzar l'script de Google (Guasti API) amb la versió nova per fer servir aquesta pestanya."
        }
        return t
    }
}

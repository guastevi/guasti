import Foundation

/// Les dades de Gestió de casa. L'última còpia es guarda al mòbil perquè s'obri al moment
/// i es pugui consultar sense cobertura; tot es llegeix i s'escriu al full "Casa Guasti".
@MainActor
final class CasaStore: ObservableObject {
    static let shared = CasaStore()

    @Published private(set) var dades: CasaDades?
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private let dir: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()
    private var cacheURL: URL { dir.appendingPathComponent("casa.json") }
    /// Els documents ja baixats, per obrir-los sense connexió.
    private var filesDir: URL {
        let d = dir.appendingPathComponent("casa-fitxers", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    private init() {
        if let data = try? Data(contentsOf: cacheURL) {
            dades = try? JSONDecoder().decode(CasaDades.self, from: data)
        }
    }

    var registres: [CasaRegistre] { dades?.registres ?? [] }
    var avui: String { dades?.avui ?? CasaFmt.string(Date()) }

    func registres(_ tipus: CasaTipus) -> [CasaRegistre] {
        registres.filter { $0.kind == tipus }.sorted { a, b in
            if tipus == .manteniment {
                // Primer el que toca abans
                return (a.venciment.isEmpty ? "9999" : a.venciment) < (b.venciment.isEmpty ? "9999" : b.venciment)
            }
            return a.data > b.data
        }
    }

    func registre(_ id: String) -> CasaRegistre? { registres.first { $0.id == id } }

    // MARK: lloguer

    var contracte: CasaRegistre? { registres(.contracte).first }

    /// La renda d'ara: l'última actualització que ja ha començat, o la del contracte.
    var rendaActual: Double? {
        let vigents = registres(.renda).filter { $0.data <= avui && $0.importValue != nil }
        return vigents.first?.importValue ?? contracte?.importValue
    }

    /// El proper aniversari del contracte, quan normalment toca actualitzar la renda (IPC).
    var properaActualitzacio: String? {
        guard let inici = contracte?.dataDate, let avuiDate = CasaFmt.date(avui) else { return nil }
        let cal = Calendar(identifier: .gregorian)
        var d = inici
        while d <= avuiDate {
            guard let next = cal.date(byAdding: .year, value: 1, to: d) else { return nil }
            d = next
        }
        if let fi = contracte?.vencimentDate, d > fi { return nil }
        return CasaFmt.string(d)
    }

    // MARK: pendents

    struct Avis: Identifiable {
        let id: String
        let registreId: String?
        let text: String
        let quan: String
        let dies: Int
        let icon: String
    }

    /// El que cal tenir present: manteniment que toca, reparacions obertes, garanties i contracte que s'acaben.
    var avisos: [Avis] {
        var out: [Avis] = []
        for r in registres {
            switch r.kind {
            case .manteniment:
                if let d = CasaFmt.dies(fins: r.venciment, avui: avui), d <= 30 {
                    out.append(Avis(id: r.id, registreId: r.id, text: r.displayTitle, quan: d < 0 ? "Tocava \(CasaFmt.falten(d))" : "Toca \(CasaFmt.falten(d))", dies: d, icon: "checklist"))
                }
            case .reparacio where r.estat != "Fet":
                let d = CasaFmt.dies(fins: r.data, avui: avui) ?? 0
                out.append(Avis(id: r.id, registreId: r.id, text: r.displayTitle, quan: r.estat.isEmpty ? "Pendent" : r.estat, dies: min(d, 0), icon: "wrench.and.screwdriver.fill"))
            case .compra:
                if let d = CasaFmt.dies(fins: r.venciment, avui: avui), (0...60).contains(d) {
                    out.append(Avis(id: r.id, registreId: r.id, text: "Garantia: \(r.displayTitle)", quan: "S'acaba \(CasaFmt.falten(d))", dies: d, icon: "bag.fill"))
                }
            case .document:
                if let d = CasaFmt.dies(fins: r.venciment, avui: avui), d <= 60 {
                    out.append(Avis(id: r.id, registreId: r.id, text: r.displayTitle, quan: d < 0 ? "Va caducar \(CasaFmt.falten(d))" : "Caduca \(CasaFmt.falten(d))", dies: d, icon: "folder.fill"))
                }
            case .contracte:
                if r.id == contracte?.id, let d = CasaFmt.dies(fins: r.venciment, avui: avui), d <= 120 {
                    out.append(Avis(id: r.id, registreId: r.id, text: "El contracte de lloguer", quan: d < 0 ? "Va vèncer \(CasaFmt.falten(d))" : "Venç \(CasaFmt.falten(d))", dies: d, icon: "signature"))
                }
            default:
                break
            }
        }
        if let a = properaActualitzacio, let d = CasaFmt.dies(fins: a, avui: avui), d <= 45 {
            out.append(Avis(id: "renda", registreId: nil, text: "Actualització de la renda", quan: "Aniversari del contracte \(CasaFmt.falten(d))", dies: d, icon: "chart.line.uptrend.xyaxis"))
        }
        return out.sorted { $0.dies < $1.dies }
    }

    // MARK: factures

    /// Total de factures per subministrament en un any.
    func facturesAny(_ any: String) -> (total: Double, perTipus: [(String, Double)]) {
        var per: [String: Double] = [:]
        for r in registres(.factura) where r.data.hasPrefix(any) {
            per[r.displayTitle, default: 0] += r.importValue ?? 0
        }
        let sorted = per.sorted { $0.value > $1.value }.map { ($0.key, $0.value) }
        return (sorted.reduce(0) { $0 + $1.1 }, sorted)
    }

    // MARK: crides

    func load() async {
        guard let client = Connection.shared.client else {
            errorMessage = "Falta configurar la connexió amb Google (engranatge de la pantalla d'inici)."
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            let result: CasaDades = try await client.call("casa.dades")
            set(result)
        } catch is CancellationError {
        } catch {
            errorMessage = Self.explain(error)
        }
    }

    /// Desa el registre i torna'n l'ID (nou si era nou).
    @discardableResult
    func desa(_ r: CasaRegistre) async throws -> String {
        let registre: [String: Any] = ["id": r.id, "tipus": r.tipus, "data": r.data, "titol": r.titol, "import": r.imp,
                                       "qui": r.qui, "estat": r.estat, "venciment": r.venciment, "cada": r.cada, "notes": r.notes]
        let result: CasaDesaResposta = try await call("casa.desa", ["registre": registre])
        set(result.dades)
        return result.id ?? r.id
    }

    func esborra(_ r: CasaRegistre) async throws {
        let result: CasaDades = try await call("casa.esborra", ["id": r.id])
        set(result)
    }

    func fet(_ r: CasaRegistre) async throws {
        let result: CasaDades = try await call("casa.fet", ["id": r.id])
        set(result)
    }

    func pujaFitxer(_ registreId: String, nom: String, mime: String, data: Data) async throws {
        let result: CasaDades = try await call("casa.pujaFitxer", ["id": registreId, "nom": nom, "mime": mime,
                                                                    "base64": data.base64EncodedString()])
        set(result)
    }

    func treuFitxer(_ registreId: String, _ f: CasaFitxer) async throws {
        let result: CasaDades = try await call("casa.treuFitxer", ["id": registreId, "fitxerId": f.id])
        try? FileManager.default.removeItem(at: localURL(f))
        set(result)
    }

    /// El fitxer al mòbil (el baixa de Drive el primer cop).
    func obre(_ f: CasaFitxer) async throws -> URL {
        let url = localURL(f)
        if FileManager.default.fileExists(atPath: url.path) { return url }
        struct Resp: Decodable { let base64: String }
        let r: Resp = try await call("casa.fitxer", ["fitxerId": f.id])
        guard let data = Data(base64Encoded: r.base64) else { throw APIError(message: "El fitxer ha arribat malmès.") }
        try data.write(to: url, options: .atomic)
        return url
    }

    private func localURL(_ f: CasaFitxer) -> URL {
        let d = filesDir.appendingPathComponent(f.id, isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        let safe = f.nom.replacingOccurrences(of: "/", with: "-")
        return d.appendingPathComponent(safe.isEmpty ? "document" : safe)
    }

    private func call<T: Decodable>(_ action: String, _ params: [String: Any]) async throws -> T {
        guard let client = Connection.shared.client else {
            throw APIError(message: "Falta configurar la connexió amb Google.")
        }
        do {
            return try await client.call(action, params)
        } catch {
            throw APIError(message: Self.explain(error))
        }
    }

    /// Si el pont amb Google encara no té la part de Casa, ho diu clar.
    private static func explain(_ error: Error) -> String {
        let text = error.localizedDescription
        if text.contains("Acció desconeguda") {
            return "El pont amb Google (Guasti API) encara no té la part de Casa. Cal posar-hi la versió nova."
        }
        return text
    }

    private func set(_ result: CasaDades) {
        dades = result
        errorMessage = nil
        if let data = try? JSONEncoder().encode(result) {
            try? data.write(to: cacheURL, options: .atomic)
        }
    }
}

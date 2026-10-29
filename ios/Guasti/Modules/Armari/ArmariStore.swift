import Foundation

/// Les dades de l'armari. Es guarda una còpia al mòbil perquè s'obri al moment i funcioni sense cobertura;
/// els canvis s'envien sempre als fulls de Google.
@MainActor
final class ArmariStore: ObservableObject {
    static let shared = ArmariStore()

    @Published private(set) var peces: [Peca] = []
    @Published private(set) var fotos: [Foto] = []
    @Published private(set) var isLoading = false
    @Published private(set) var lastSync: Date?
    @Published var errorMessage: String?
    @Published private(set) var downloadProgress: (done: Int, total: Int)?

    private struct Snapshot: Codable {
        var peces: [Peca]
        var fotos: [Foto]
        var date: Date
    }

    private struct ListResponse: Decodable {
        let peces: [Peca]
        let fotos: [Foto]
    }

    private struct SaveResponse: Decodable {
        let piece: Peca
    }

    private struct AddPhotoResponse: Decodable {
        let foto: Foto
        let portada: String?
    }

    private struct CoverResponse: Decodable {
        let portada: String?
    }

    private let snapshotURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("armari.json")
    }()

    private init() {
        loadSnapshot()
    }

    // MARK: Lectura

    func peca(_ id: String) -> Peca? {
        peces.first { $0.id == id }
    }

    /// Fotos d'una peça, amb la portada primer.
    func photos(for peca: Peca) -> [Foto] {
        var list = fotos.filter { $0.peca == peca.id && !$0.path.isEmpty }.sorted { $0.order < $1.order }
        if !peca.portada.isEmpty {
            if let i = list.firstIndex(where: { $0.path == peca.portada }) {
                list.insert(list.remove(at: i), at: 0)
            } else {
                list.insert(Foto(id: "portada-\(peca.id)", peca: peca.id, path: peca.portada, ordre: "0"), at: 0)
            }
        }
        return list
    }

    /// Valors diferents d'un camp, per als filtres i els suggeriments.
    func values(_ keyPath: KeyPath<Peca, String>) -> [String] {
        let all: [String]
        if keyPath == \Peca.color {
            all = peces.flatMap(\.colors)
        } else {
            all = peces.map { $0[keyPath: keyPath].trimmingCharacters(in: .whitespaces) }
        }
        return Array(Set(all.filter { !$0.isEmpty })).sorted { $0.localizedCompare($1) == .orderedAscending }
    }

    // MARK: Sincronització

    func refreshIfNeeded() async {
        if let lastSync, Date().timeIntervalSince(lastSync) < 120 { return }
        await refresh()
    }

    func refresh() async {
        guard let client = Connection.shared.client else {
            errorMessage = "Falta configurar la connexió amb Google (engranatge de la pantalla d'inici)."
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            let response: ListResponse = try await client.call("armari.list")
            peces = response.peces.filter { !$0.id.isEmpty }
            fotos = response.fotos.filter { !$0.path.isEmpty }
            lastSync = Date()
            errorMessage = nil
            saveSnapshot()
        } catch is CancellationError {
            // La pantalla s'ha tancat: no és un error.
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: Canvis

    func save(_ peca: Peca) async throws {
        let response: SaveResponse = try await requireClient().call("armari.save", ["piece": try peca.jsonObject()])
        if let i = peces.firstIndex(where: { $0.id == response.piece.id }) {
            peces[i] = response.piece
        } else {
            peces.append(response.piece)
        }
        saveSnapshot()
    }

    func delete(_ peca: Peca) async throws {
        let _: Pong = try await requireClient().call("armari.delete", ["id": peca.id])
        peces.removeAll { $0.id == peca.id }
        fotos.removeAll { $0.peca == peca.id }
        saveSnapshot()
    }

    @discardableResult
    func addPhoto(_ jpeg: Data, to pecaID: String) async throws -> Foto {
        let response: AddPhotoResponse = try await requireClient().call("armari.addPhoto", [
            "pieceId": pecaID,
            "base64": jpeg.base64EncodedString(),
        ])
        fotos.append(response.foto)
        if let portada = response.portada { setLocalCover(portada, for: pecaID) }
        await PhotoLoader.shared.prime(jpeg, for: response.foto.path)
        saveSnapshot()
        return response.foto
    }

    func deletePhoto(_ foto: Foto) async throws {
        let response: CoverResponse = try await requireClient().call("armari.deletePhoto", ["photoId": foto.id])
        fotos.removeAll { $0.id == foto.id }
        if let portada = response.portada { setLocalCover(portada, for: foto.peca) }
        saveSnapshot()
    }

    /// Posa una foto com a portada i la mou al primer lloc, com l'app web.
    func setCover(_ foto: Foto) async throws {
        guard let peca = peca(foto.peca) else { return }
        let ids = [foto.id] + photos(for: peca).map(\.id).filter { $0 != foto.id && !$0.hasPrefix("portada-") }
        do {
            try await reorder(ids, for: foto.peca)
        } catch let error as APIError where error.message.hasPrefix("Acció desconeguda") {
            // Script encara sense actualitzar: almenys canvia la portada.
            let _: CoverResponse = try await requireClient().call("armari.setCover", ["pieceId": foto.peca, "path": foto.path])
            setLocalCover(foto.path, for: foto.peca)
            saveSnapshot()
        }
    }

    /// Desa l'ordre de les fotos d'una peça. La primera passa a ser la portada.
    func reorder(_ ids: [String], for pecaID: String) async throws {
        let ids = ids.filter { !$0.hasPrefix("portada-") }
        guard !ids.isEmpty else { return }
        let response: CoverResponse = try await requireClient().call("armari.reorder", ["pieceId": pecaID, "ids": ids])
        for (k, id) in ids.enumerated() {
            if let i = fotos.firstIndex(where: { $0.id == id && $0.peca == pecaID }) {
                fotos[i].ordre = String(k + 1)
            }
        }
        if let portada = response.portada, !portada.isEmpty { setLocalCover(portada, for: pecaID) }
        saveSnapshot()
    }

    /// Baixa la portada de totes les peces per poder-les veure sense connexió.
    func downloadAllCovers() async {
        let paths = peces.compactMap { photos(for: $0).first?.path }
        downloadProgress = (0, paths.count)
        await withTaskGroup(of: Void.self) { group in
            for path in paths {
                group.addTask { _ = await PhotoLoader.shared.image(path: path, size: .thumb) }
            }
            for await _ in group {
                if let p = downloadProgress { downloadProgress = (p.done + 1, p.total) }
            }
        }
        downloadProgress = nil
    }

    // MARK: Privat

    private func requireClient() throws -> AppsScriptClient {
        guard let client = Connection.shared.client else {
            throw APIError(message: "Falta configurar la connexió amb Google.")
        }
        return client
    }

    private func setLocalCover(_ path: String, for pecaID: String) {
        if let i = peces.firstIndex(where: { $0.id == pecaID }) {
            peces[i].portada = path
        }
    }

    private func loadSnapshot() {
        guard let data = try? Data(contentsOf: snapshotURL),
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) else { return }
        peces = snapshot.peces
        fotos = snapshot.fotos
    }

    private func saveSnapshot() {
        let snapshot = Snapshot(peces: peces, fotos: fotos, date: Date())
        if let data = try? JSONEncoder().encode(snapshot) {
            try? data.write(to: snapshotURL, options: .atomic)
        }
    }
}

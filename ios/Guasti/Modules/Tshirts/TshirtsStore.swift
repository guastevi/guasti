import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Un dibuix (un PNG de la carpeta "guastevitshirts" de Drive).
struct Dibuix: Codable, Identifiable, Hashable {
    let id: String
    var name: String
    let created: String
    let size: Int?

    var date: Date? { ISO8601DateFormatter.withFractions.date(from: created) ?? ISO8601DateFormatter().date(from: created) }
}

private extension ISO8601DateFormatter {
    static let withFractions: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
}

/// Els dibuixos de guastevitshirts. Es guarda una còpia de la llista al mòbil;
/// els fitxers viuen a Drive, a la carpeta "guastevitshirts".
@MainActor
final class TshirtsStore: ObservableObject {
    static let shared = TshirtsStore()

    @Published private(set) var dibuixos: [Dibuix] = []
    @Published private(set) var isLoading = false
    @Published private(set) var lastSync: Date?
    @Published var errorMessage: String?
    @Published private(set) var uploading: (done: Int, total: Int)?

    private struct ListResponse: Decodable { let dibuixos: [Dibuix] }
    private struct OneResponse: Decodable { let dibuix: Dibuix }

    private let snapshotURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("guastevitshirts.json")
    }()

    private init() {
        if let data = try? Data(contentsOf: snapshotURL),
           let list = try? JSONDecoder().decode([Dibuix].self, from: data) {
            dibuixos = list
        }
    }

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
            let response: ListResponse = try await client.call("tshirts.list")
            dibuixos = response.dibuixos
            lastSync = Date()
            errorMessage = nil
            save()
        } catch is CancellationError {
        } catch {
            errorMessage = Self.friendly(error)
        }
    }

    /// Puja dibuixos. Cada element és el fitxer i el nom (sense extensió) que tindrà a Drive.
    func upload(_ items: [(data: Data, name: String?)]) async {
        uploading = (0, items.count)
        defer { uploading = nil }
        for item in items {
            if !(await uploadOne(item.data, name: item.name)) { break }
            if let u = uploading { uploading = (u.done + 1, u.total) }
        }
    }

    /// Puja fitxers triats a Fitxers. Si és una carpeta, hi puja totes les imatges de dins;
    /// les que ja hi són (mateix nom) se salten, així es pot tornar a fer sense duplicar res.
    /// Es llegeixen d'una en una perquè una carpeta de dibuixos grans no ompli la memòria.
    func upload(urls: [URL]) async {
        var scoped: [URL] = []
        defer { scoped.forEach { $0.stopAccessingSecurityScopedResource() } }
        var files: [URL] = []
        for url in urls {
            if url.startAccessingSecurityScopedResource() { scoped.append(url) }
            if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                let items = (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? []
                files += items
                    .map { $0.pathExtension == "icloud" ? Self.iCloudOriginal($0) : $0 }
                    .filter { UTType(filenameExtension: $0.pathExtension)?.conforms(to: .image) == true }
                    .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            } else {
                files.append(url)
            }
        }
        let existing = Set(dibuixos.map { $0.name.lowercased() })
        files = files.filter { !existing.contains($0.deletingPathExtension().lastPathComponent.lowercased()) }
        guard !files.isEmpty else { return }

        uploading = (0, files.count)
        // Que la pantalla no s'apagui mentre puja una carpeta llarga.
        UIApplication.shared.isIdleTimerDisabled = true
        defer {
            uploading = nil
            UIApplication.shared.isIdleTimerDisabled = false
        }
        for file in files {
            guard let data = await Self.read(file) else {
                if let u = uploading { uploading = (u.done + 1, u.total) }
                continue
            }
            let ok = await uploadOne(data, name: file.deletingPathExtension().lastPathComponent)
            if !ok { break }
            if let u = uploading { uploading = (u.done + 1, u.total) }
        }
    }

    /// Llegeix un fitxer de Fitxers; si és a iCloud i encara no és al mòbil, el baixa primer.
    private static func read(_ url: URL) async -> Data? {
        await Task.detached {
            try? FileManager.default.startDownloadingUbiquitousItem(at: url)
            var data: Data?
            var error: NSError?
            NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &error) { data = try? Data(contentsOf: $0) }
            return data
        }.value
    }

    /// ".Dibuix.png.icloud" (encara no baixat) → "Dibuix.png".
    private static func iCloudOriginal(_ url: URL) -> URL {
        var name = url.deletingPathExtension().lastPathComponent
        if name.hasPrefix(".") { name.removeFirst() }
        return url.deletingLastPathComponent().appendingPathComponent(name)
    }

    private func uploadOne(_ data: Data, name: String?) async -> Bool {
        guard let client = Connection.shared.client else {
            errorMessage = "Falta configurar la connexió amb Google."
            return false
        }
        guard let png = Self.png(data) else { return true }
        do {
            var params: [String: Any] = ["base64": png.base64EncodedString()]
            if let name, !name.isEmpty { params["name"] = name }
            let response: OneResponse = try await client.call("tshirts.upload", params)
            dibuixos.insert(response.dibuix, at: 0)
            await TshirtLoader.shared.prime(png, id: response.dibuix.id)
            errorMessage = nil
            save()
            return true
        } catch {
            errorMessage = Self.friendly(error)
            return false
        }
    }

    func rename(_ dibuix: Dibuix, to name: String) async throws {
        let response: OneResponse = try await requireClient().call("tshirts.rename", ["id": dibuix.id, "name": name])
        if let i = dibuixos.firstIndex(where: { $0.id == dibuix.id }) { dibuixos[i] = response.dibuix }
        save()
    }

    func delete(_ dibuix: Dibuix) async throws {
        let _: Pong = try await requireClient().call("tshirts.delete", ["id": dibuix.id])
        dibuixos.removeAll { $0.id == dibuix.id }
        save()
    }

    // MARK: Privat

    private func requireClient() throws -> AppsScriptClient {
        guard let client = Connection.shared.client else {
            throw APIError(message: "Falta configurar la connexió amb Google.")
        }
        return client
    }

    private func save() {
        if let data = try? JSONEncoder().encode(dibuixos) { try? data.write(to: snapshotURL) }
    }

    /// Els PNG es pugen tal qual (amb la transparència); la resta d'imatges es converteixen a PNG.
    private static func png(_ data: Data) -> Data? {
        if data.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return data }
        return UIImage(data: data)?.pngData()
    }

    private static func friendly(_ error: Error) -> String {
        if let e = error as? APIError, e.message.hasPrefix("Acció desconeguda") {
            return "Cal actualitzar la Guasti API amb l'Api.gs nou perquè funcioni guastevitshirts."
        }
        return error.localizedDescription
    }
}

/// Baixa els dibuixos de Drive i els guarda al mòbil (un cop baixats, no es tornen a demanar).
actor TshirtLoader {
    static let shared = TshirtLoader()

    enum Size: String { case thumb, full }

    private struct ImageData: Decodable { let base64: String }

    private let memory = NSCache<NSString, UIImage>()
    private var inflight: [String: Task<UIImage?, Never>] = [:]
    private let directory: URL
    private var active = 0
    private var waiting: [CheckedContinuation<Void, Never>] = []

    init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        directory = caches.appendingPathComponent("guastevitshirts", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        memory.countLimit = 200
    }

    func image(id: String, size: Size) async -> UIImage? {
        let key = size.rawValue + "_" + id
        if let image = memory.object(forKey: key as NSString) { return image }
        if let data = try? Data(contentsOf: fileURL(key)), let image = UIImage(data: data) {
            memory.setObject(image, forKey: key as NSString)
            return image
        }
        if let task = inflight[key] { return await task.value }
        let task = Task<UIImage?, Never> { await self.download(id: id, size: size, key: key) }
        inflight[key] = task
        let image = await task.value
        inflight[key] = nil
        return image
    }

    /// El fitxer PNG original (per compartir-lo o desar-lo).
    func fileURL(id: String, name: String) async -> URL? {
        guard await image(id: id, size: .full) != nil else { return nil }
        let out = FileManager.default.temporaryDirectory.appendingPathComponent(name + ".png")
        try? FileManager.default.removeItem(at: out)
        do {
            try FileManager.default.copyItem(at: fileURL("full_" + id), to: out)
            return out
        } catch {
            return nil
        }
    }

    func prime(_ data: Data, id: String) {
        for size in [Size.thumb, .full] {
            try? data.write(to: fileURL(size.rawValue + "_" + id))
        }
    }

    private func download(id: String, size: Size, key: String) async -> UIImage? {
        await acquire()
        defer { release() }
        guard let client = await MainActor.run(body: { Connection.shared.client }) else { return nil }
        do {
            let response: ImageData = try await client.call("tshirts.image", ["id": id, "size": size.rawValue])
            guard let data = Data(base64Encoded: response.base64), let image = UIImage(data: data) else { return nil }
            try? data.write(to: fileURL(key))
            memory.setObject(image, forKey: key as NSString)
            return image
        } catch {
            return nil
        }
    }

    // Apps Script no aguanta gaires peticions alhora.
    private func acquire() async {
        if active < 4 { active += 1; return }
        await withCheckedContinuation { waiting.append($0) }
    }

    private func release() {
        if waiting.isEmpty { active -= 1 } else { waiting.removeFirst().resume() }
    }

    private func fileURL(_ key: String) -> URL { directory.appendingPathComponent(key) }
}

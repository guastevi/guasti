import Foundation

/// Manté la carpeta d'iCloud "guastevitshirts" igual que l'app: cada dibuix dins la subcarpeta
/// de la seva categoria i amb el mateix nom. La carpeta es recorda el primer cop que es tria
/// a «+ › Des de Fitxers» (o a «Connecta la carpeta d'iCloud»), i a partir d'aquí s'ordena sola
/// quan canvies una categoria o un nom.
@MainActor
final class TshirtsFolderSync: ObservableObject {
    static let shared = TshirtsFolderSync()

    @Published private(set) var connected = false
    @Published private(set) var lastMessage: String?

    private let bookmarkKey = "tshirts.icloudFolder"
    /// Id del dibuix a Drive → camí relatiu del fitxer dins la carpeta (per seguir-lo si es canvia el nom).
    private var paths: [String: String] = [:]
    private var pending: Task<Void, Never>?

    private let pathsURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("guastevitshirts-icloud.json")
    }()

    private init() {
        connected = UserDefaults.standard.data(forKey: bookmarkKey) != nil
        if let data = try? Data(contentsOf: pathsURL), let p = try? JSONDecoder().decode([String: String].self, from: data) {
            paths = p
        }
    }

    /// Recorda la carpeta (cal haver-hi fet startAccessingSecurityScopedResource).
    func remember(_ folder: URL) {
        guard let data = try? folder.bookmarkData() else { return }
        UserDefaults.standard.set(data, forKey: bookmarkKey)
        connected = true
    }

    /// Un dibuix acabat de pujar des d'un fitxer de la carpeta: així se'l pot seguir encara que canviï de nom.
    func track(id: String, file: URL) {
        guard let root = resolveRoot() else { return }
        defer { root.stopAccessingSecurityScopedResource() }
        if let rel = Self.relative(file, to: root) {
            paths[id] = rel
            savePaths()
        }
    }

    /// Ordena la carpeta d'aquí a un moment (si es fan uns quants canvis seguits, només es fa un cop).
    func scheduleSync() {
        guard connected else { return }
        pending?.cancel()
        pending = Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled else { return }
            await sync()
        }
    }

    func sync() async {
        guard let root = resolveRoot() else { return }
        defer { root.stopAccessingSecurityScopedResource() }
        let store = TshirtsStore.shared
        let cats = TshirtsCats.shared
        var plan: [(id: String, target: String)] = []
        for d in store.dibuixos {
            let folder = Self.safe(cats.categoria(d))
            let file = Self.safe(d.name) + ".png"
            plan.append((d.id, folder.isEmpty ? file : folder + "/" + file))
        }
        let known = paths
        let result = await Task.detached { Self.apply(plan: plan, root: root, known: known) }.value
        paths = result.paths
        savePaths()
        lastMessage = result.moved > 0 ? "Carpeta d'iCloud ordenada: \(result.moved) canvis." : nil
    }

    // MARK: Privat

    private func resolveRoot() -> URL? {
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else { return nil }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, bookmarkDataIsStale: &stale) else {
            UserDefaults.standard.removeObject(forKey: bookmarkKey)
            connected = false
            return nil
        }
        guard url.startAccessingSecurityScopedResource() else { return nil }
        if stale, let fresh = try? url.bookmarkData() { UserDefaults.standard.set(fresh, forKey: bookmarkKey) }
        return url
    }

    private func savePaths() {
        if let data = try? JSONEncoder().encode(paths) { try? data.write(to: pathsURL) }
    }

    /// Mou cada fitxer al lloc que li toca. Si no se sap on és, es busca pel nom (els que es van pujar
    /// abans d'existir això tenen el mateix nom a Drive i a la carpeta).
    nonisolated private static func apply(plan: [(id: String, target: String)], root: URL, known: [String: String]) -> (paths: [String: String], moved: Int) {
        let fm = FileManager.default
        var paths = known
        var moved = 0
        // Tots els PNG que hi ha ara a la carpeta i subcarpetes, pel nom.
        var byName: [String: [String]] = [:]
        var existing = Set<String>()
        if let e = fm.enumerator(at: root, includingPropertiesForKeys: nil, options: [.skipsPackageDescendants]) {
            for case let url as URL in e {
                var u = url
                if u.pathExtension == "icloud" { u = iCloudOriginal(u) }
                guard u.pathExtension.lowercased() == "png", let rel = relative(u, to: root) else { continue }
                existing.insert(rel)
                byName[key(u.deletingPathExtension().lastPathComponent), default: []].append(rel)
            }
        }
        let claimed = Set(paths.values)
        for item in plan {
            var current = paths[item.id].flatMap { existing.contains($0) ? $0 : nil }
            if current == nil {
                let name = key((item.target as NSString).lastPathComponent.replacingOccurrences(of: ".png", with: ""))
                current = byName[name]?.first { !claimed.contains($0) || paths[item.id] == $0 }
            }
            guard let from = current else { continue }
            paths[item.id] = from
            guard from != item.target, !existing.contains(item.target) else { continue }
            let src = root.appendingPathComponent(from)
            let dst = root.appendingPathComponent(item.target)
            try? fm.createDirectory(at: dst.deletingLastPathComponent(), withIntermediateDirectories: true)
            var err: NSError?
            var ok = false
            NSFileCoordinator().coordinate(writingItemAt: src, options: .forMoving, writingItemAt: dst, options: .forReplacing, error: &err) { s, d in
                ok = (try? fm.moveItem(at: s, to: d)) != nil
            }
            if ok {
                existing.remove(from)
                existing.insert(item.target)
                paths[item.id] = item.target
                moved += 1
            }
        }
        // Les subcarpetes que s'hagin quedat buides (una categoria que ja no s'usa) fora.
        if let dirs = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey]) {
            for dir in dirs where (try? dir.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                if let items = try? fm.contentsOfDirectory(atPath: dir.path), items.filter({ !$0.hasPrefix(".") }).isEmpty {
                    try? fm.removeItem(at: dir)
                }
            }
        }
        return (paths, moved)
    }

    nonisolated private static func relative(_ url: URL, to root: URL) -> String? {
        let r = root.standardizedFileURL.resolvingSymlinksInPath().path
        let p = url.standardizedFileURL.resolvingSymlinksInPath().path
        guard p.hasPrefix(r + "/") else { return nil }
        return String(p.dropFirst(r.count + 1))
    }

    nonisolated private static func key(_ s: String) -> String { s.precomposedStringWithCanonicalMapping.lowercased() }

    /// ".Dibuix.png.icloud" (encara no baixat) → "Dibuix.png".
    nonisolated private static func iCloudOriginal(_ url: URL) -> URL {
        var name = url.deletingPathExtension().lastPathComponent
        if name.hasPrefix(".") { name.removeFirst() }
        return url.deletingLastPathComponent().appendingPathComponent(name)
    }

    /// Un nom que es pugui fer servir com a fitxer o carpeta.
    nonisolated static func safe(_ s: String) -> String {
        s.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

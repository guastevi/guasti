import SwiftUI
import UIKit

/// L'arxiu de partitures: el mateix full i la mateixa carpeta del Drive que l'app web "Arxiu de Repertori".
/// Les dades es guarden al mòbil perquè s'obri al moment; les partitures ja vistes també queden guardades.
@MainActor
final class PartituresStore: ObservableObject {
    static let shared = PartituresStore()

    @Published private(set) var dades: ArxiuDades?
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?
    @Published private(set) var thumbs: [String: UIImage] = [:]
    @Published private(set) var noThumb: Set<String> = []
    @Published private(set) var offline: Set<String> = []
    @Published private(set) var saving = 0

    private let fm = FileManager.default
    private lazy var supportDir: URL = {
        let d = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("partitures")
        try? fm.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()
    private lazy var offlineDir: URL = {
        let d = supportDir.appendingPathComponent("offline")
        try? fm.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()
    private lazy var cacheDir: URL = {
        let d = fm.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("partitures")
        try? fm.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()
    private var cacheURL: URL { supportDir.appendingPathComponent("arxiu.json") }

    private init() {
        if let data = try? Data(contentsOf: cacheURL) {
            dades = try? JSONDecoder().decode(ArxiuDades.self, from: data)
        }
        let files = (try? fm.contentsOfDirectory(atPath: offlineDir.path)) ?? []
        offline = Set(files.filter { $0.hasSuffix(".pdf") }.map { String($0.dropLast(4)) })
    }

    // MARK: - Crides al Guasti API

    private func client() throws -> AppsScriptClient {
        guard let c = Connection.shared.client else {
            throw APIError(message: "Falta configurar la connexió amb Google (engranatge de la pantalla d'inici).")
        }
        return c
    }

    /// Crida una funció del Codi.gs de l'app web (getData, saveRow...).
    func call<T: Decodable>(_ fn: String, _ args: [Any] = []) async throws -> T {
        let res: PResult<T> = try await client().call("partitures", ["fn": fn, "args": args])
        return res.r
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let d: ArxiuDades = try await call("getData")
            dades = d
            errorMessage = nil
            if let data = try? JSONEncoder().encode(d) { try? data.write(to: cacheURL, options: .atomic) }
        } catch is CancellationError {
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Lectura

    func rows(_ n: String) -> [Fila] { dades?.taula(n) ?? [] }
    func llista(_ n: String) -> [String] { dades?.Llistes[n] ?? [] }

    func find(_ n: String, _ id: String) -> Fila? {
        let k = Arxiu.keys[n] ?? "ID"
        return rows(n).first { $0[k] == id }
    }

    func docsFor(_ field: String, _ id: String) -> [Fila] {
        rows("Documents").filter { field == "Concert" ? Arxiu.splitTags($0[field]).contains(id) : $0[field] == id }
    }

    /// Repertori d'un concert: documents enllaçats al concert + documents de les obres del concert.
    func concertDocs(_ cid: String) -> [Fila] {
        var seen = Set<String>(), out: [Fila] = []
        let all = docsFor("Concert", cid) + rows("Obres").filter { $0["Concert"] == cid }.flatMap { docsFor("Obra", $0["ID"] ?? "") }
        for d in all where seen.insert(d["ID"] ?? "").inserted { out.append(d) }
        // L'ordre del programa (columna «Ordre» del full Concerts): primer els ordenats, després la resta
        let ordre = Arxiu.splitTags(find("Concerts", cid)?["Ordre"])
        guard !ordre.isEmpty else { return out }
        let pos = Dictionary(ordre.enumerated().map { ($1, $0) }, uniquingKeysWith: { a, _ in a })
        return out.enumerated().sorted { a, b in
            let pa = pos[a.element["ID"] ?? ""] ?? Int.max, pb = pos[b.element["ID"] ?? ""] ?? Int.max
            return pa != pb ? pa < pb : a.offset < b.offset
        }.map(\.element)
    }

    /// El full Concerts té la columna «Ordre» per guardar l'ordre del programa?
    var hasConcertOrder: Bool { dades?.Concerts.headers.contains("Ordre") ?? false }

    func setConcertOrder(_ cid: String, _ docs: [Fila]) async throws {
        try await save("Concerts", ["ID": cid, "Ordre": docs.compactMap { $0["ID"] }.joined(separator: ", ")], original: cid)
    }

    func firstDoc(_ field: String, _ id: String) -> Fila? {
        let ds = docsFor(field, id)
        return ds.first { $0["Format"] == "PDF" || ($0["Format"] ?? "").isEmpty } ?? ds.first
    }

    func upcomingConcerts() -> [Fila] {
        let t = Arxiu.today()
        return rows("Concerts").filter { !($0["Data"] ?? "").isEmpty && String(($0["Data"] ?? "").prefix(10)) >= t }
            .sorted { ($0["Data"] ?? "") + ($0["Hora"] ?? "") < ($1["Data"] ?? "") + ($1["Hora"] ?? "") }
    }

    func obraLabel(_ o: Fila?) -> String {
        guard let o else { return "" }
        return [o["Obra"], o["Compositor"]].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " - ")
    }

    func concertLabel(_ c: Fila?) -> String {
        guard let c else { return "" }
        let t = (c["Títol"] ?? "").isEmpty ? c["Agrupació"] : c["Títol"]
        return [Arxiu.fmtDate(c["Data"]), t ?? ""].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    func refLabel(_ sheet: String, _ id: String?) -> String {
        guard let id, !id.isEmpty else { return "" }
        guard let r = find(sheet, id) else { return id }
        switch sheet {
        case "Obres": return obraLabel(r)
        case "Concerts": return concertLabel(r)
        case "Fagotades": return "Fagotada " + (r["Any"] ?? "")
        default: return id
        }
    }

    struct Compositor { var o = 0, d = 0 }

    /// Agrupa per nom sense distingir majúscules ni accents, i es queda amb la grafia més freqüent.
    func composerMap() -> [String: Compositor] {
        var byKey: [String: (names: [String: Int], c: Compositor)] = [:]
        func add(_ n: String?, obra: Bool) {
            let n = (n ?? "").trimmingCharacters(in: .whitespaces)
            guard !n.isEmpty else { return }
            let k = Arxiu.norm(n)
            var e = byKey[k] ?? (names: [:], c: Compositor())
            e.names[n, default: 0] += 1
            if obra { e.c.o += 1 } else { e.c.d += 1 }
            byKey[k] = e
        }
        rows("Obres").forEach { add($0["Compositor"], obra: true) }
        rows("Documents").forEach { add($0["Compositor"], obra: false) }
        var out: [String: Compositor] = [:]
        for e in byKey.values {
            if let best = e.names.max(by: { $0.value < $1.value })?.key { out[best] = e.c }
        }
        return out
    }

    func bookCover(_ docs: [Fila]) -> Fila? {
        docs.first { ($0["Títol"] ?? "").range(of: "full score|partitura general|general|score", options: [.regularExpression, .caseInsensitive]) != nil }
            ?? docs.sorted { Arxiu.sortNorm($0["Títol"], $1["Títol"]) }.first
    }

    func books() -> [String: [Fila]] {
        var bk: [String: [Fila]] = [:]
        for d in rows("Documents") { if let b = d["Llibre"], !b.isEmpty { bk[b, default: []].append(d) } }
        return bk
    }

    func centreGroups(_ centre: String) -> [String] {
        centre.isEmpty ? Arxiu.centreGroups.keys.sorted().flatMap { Arxiu.centreGroups[$0] ?? [] } : (Arxiu.centreGroups[centre] ?? [])
    }

    func inGroup(_ o: Fila, _ c: String) -> Bool {
        Arxiu.splitTags(o["Curs"]).contains(c) || Arxiu.splitTags(o["Etiquetes"]).contains(c)
    }

    func inCentre(_ o: Fila, _ centre: String) -> Bool {
        centre.isEmpty || o["Centre"] == centre || Arxiu.splitTags(o["Etiquetes"]).contains(centre) ||
            (Arxiu.centreGroups[centre] ?? []).contains { inGroup(o, $0) }
    }

    func courseDocs(_ curs: String, centre: String) -> [Fila] {
        var seen = Set<String>(), out: [Fila] = []
        let obres = rows("Obres").filter { inGroup($0, curs) && inCentre($0, centre) }.sorted { Arxiu.sortNorm($0["Obra"], $1["Obra"]) }
        for o in obres { for d in docsFor("Obra", o["ID"] ?? "") where seen.insert(d["ID"] ?? "").inserted { out.append(d) } }
        let docs = rows("Documents").filter { Arxiu.splitTags($0["Curs"]).contains(curs) }.sorted { Arxiu.sortNorm($0["Títol"], $1["Títol"]) }
        for d in docs where seen.insert(d["ID"] ?? "").inserted { out.append(d) }
        return out
    }

    /// Opcions dels botons d'un camp: L:llista, F:formació d'una categoria, S:full.
    func chipOptions(_ src: String) -> [String] {
        let t = src.prefix(1), n = String(src.dropFirst(2))
        if t == "F" { return n.isEmpty ? [] : llista("Formació: " + n) }
        if t == "L" { return llista(n) }
        var vals = rows(n).compactMap { $0[Arxiu.keys[n] ?? ""] }.filter { !$0.isEmpty }
        if n == "Fagotades" { vals.sort(by: >) } else if n != "Agrupacions" { vals.sort { Arxiu.sortNorm($0, $1) } }
        return vals.filter { $0 != "Desconeguda" }
    }

    // MARK: - Escriptura

    /// Desa una fila (com saveRow de la web) i torna la clau. L'app es posa al dia de seguida.
    @discardableResult
    func save(_ name: String, _ obj: Fila, original: String?) async throws -> String {
        var o: [String: Any] = obj
        if let original { o["__orig"] = original }
        let id: FlexText = try await call("saveRow", [name, o])
        applyLocal(name, obj, original: original, id: id.value)
        Task { await load() }
        return id.value
    }

    /// Desat en segon pla: la fitxa canvia al moment i el full s'actualitza darrere.
    func saveInBackground(_ name: String, _ obj: Fila, original: String) {
        applyLocal(name, obj, original: original, id: original)
        saving += 1
        Task {
            defer { saving -= 1 }
            do {
                var o: [String: Any] = obj
                o["__orig"] = original
                let _: FlexText = try await call("saveRow", [name, o])
            } catch {
                errorMessage = "No s'ha pogut desar «\(obj["Títol"] ?? obj["Obra"] ?? original)»: \(error.localizedDescription). Torna-ho a provar."
            }
        }
    }

    private func applyLocal(_ name: String, _ obj: Fila, original: String?, id: String) {
        let k = Arxiu.keys[name] ?? "ID"
        dades?.update(name) { rows in
            var o = obj
            o[k] = id
            if let original, let i = rows.firstIndex(where: { $0[k] == original }) {
                rows[i].merge(o) { _, new in new }
            } else {
                rows.append(o)
            }
        }
        // Els valors nous passen a ser un botó més, com a la web
        for camp in Arxiu.schema[name] ?? [] where camp.src.hasPrefix("L:") {
            let ln = String(camp.src.dropFirst(2))
            for v in Arxiu.splitTags(obj[camp.k]) where !(dades?.Llistes[ln] ?? []).contains(v) {
                dades?.Llistes[ln, default: []].append(v)
            }
        }
    }

    func deleteRow(_ name: String, _ id: String) async throws {
        let _: FlexText = try await call("deleteRow", [name, id])
        await load()
    }

    func deleteDocument(_ id: String) async throws -> String {
        let m: FlexText = try await call("deleteDocument", [id])
        await load()
        return m.value
    }

    func linkDocConcert(_ docId: String, _ concertId: String, add: Bool) async throws {
        let v: FlexText = try await call("linkDocConcert", [docId, concertId, add])
        dades?.update("Documents") { rows in
            if let i = rows.firstIndex(where: { $0["ID"] == docId }) { rows[i]["Concert"] = v.value }
        }
    }

    /// Puja fitxers a la carpeta de l'arxiu i en crea els documents (uploadFile de la web).
    func upload(_ files: [PickedFile], meta: Fila, progress: (String) -> Void) async throws {
        for (i, f) in files.enumerated() {
            progress("Pujant \(i + 1) de \(files.count): \(f.name)")
            let p: [String: Any] = ["name": f.name, "mimeType": Arxiu.mime(f.name), "data": f.data.base64EncodedString(), "meta": meta]
            let _: FlexText = try await call("uploadFile", [p])
        }
        await load()
    }

    // MARK: - Portades

    private var pending: [String] = []
    private var asked = Set<String>()
    private var pumping = false

    /// Miniatura de la primera pàgina que fa el Drive. Es demana quan la portada surt a la pantalla.
    func thumb(_ id: String) -> UIImage? {
        if let t = thumbs[id] { return t }
        if !asked.contains(id) {
            asked.insert(id)
            if let data = try? Data(contentsOf: cacheDir.appendingPathComponent("th_" + id)), let img = UIImage(data: data) {
                Task { self.thumbs[id] = img }
                return img
            }
            pending.append(id)
            Task { self.pump() }
        }
        return nil
    }

    private func pump() {
        guard !pumping, !pending.isEmpty else { return }
        pumping = true
        let batch = Array(pending.prefix(12))
        pending.removeFirst(batch.count)
        Task {
            defer { pumping = false; pump() }
            guard let m: [String: String] = try? await call("getThumbs", [batch]) else {
                batch.forEach { asked.remove($0) }
                return
            }
            for id in batch {
                let v = m[id] ?? ""
                if let comma = v.firstIndex(of: ","), let data = Data(base64Encoded: String(v[v.index(after: comma)...])),
                   let img = UIImage(data: data) {
                    thumbs[id] = img
                    try? data.write(to: cacheDir.appendingPathComponent("th_" + id))
                } else {
                    noThumb.insert(id)
                }
            }
        }
    }

    // MARK: - Fitxers

    /// El PDF d'un document: del mòbil si ja s'havia baixat, si no del Drive.
    func pdfData(_ fid: String) async throws -> Data {
        let off = offlineDir.appendingPathComponent(fid + ".pdf"), cached = cacheDir.appendingPathComponent(fid + ".pdf")
        if let d = try? Data(contentsOf: off) { return d }
        if let d = try? Data(contentsOf: cached) { return d }
        let fd: PPdf = try await call("getPdfForEdit", [fid])
        guard let data = Data(base64Encoded: fd.data) else { throw APIError(message: "El PDF ha arribat malament.") }
        try? data.write(to: cached, options: .atomic)
        return data
    }

    func hasLocalPdf(_ fid: String) -> Bool {
        fm.fileExists(atPath: offlineDir.appendingPathComponent(fid + ".pdf").path) ||
            fm.fileExists(atPath: cacheDir.appendingPathComponent(fid + ".pdf").path)
    }

    /// Qualsevol fitxer (àudio, vídeo, imatge...): es guarda en un fitxer temporal per obrir-lo o compartir-lo.
    func fileURL(_ fid: String) async throws -> (URL?, PFitxer) {
        let fd: PFitxer = try await call("getFileForView", [fid])
        guard fd.tooBig != true, let b64 = fd.data, let data = Data(base64Encoded: b64) else { return (nil, fd) }
        let dir = cacheDir.appendingPathComponent(fid)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(fd.name.replacingOccurrences(of: "/", with: "-"))
        try data.write(to: url, options: .atomic)
        return (url, fd)
    }

    /// Guarda els PDF al mòbil per tenir-los sense connexió.
    func downloadOffline(_ docs: [Fila], progress: (String) -> Void) async throws {
        let list = docs.filter(Arxiu.isPdf)
        for (i, d) in list.enumerated() {
            progress("Baixant \(i + 1) de \(list.count): \(d["Títol"] ?? "")")
            let fid = Arxiu.fileId(d)
            let data = try await pdfData(fid)
            try data.write(to: offlineDir.appendingPathComponent(fid + ".pdf"), options: .atomic)
            offline.insert(fid)
            if (d["Anotacions"] ?? "").isEmpty == false {
                let a = await annotations(d)
                if let j = try? JSONEncoder().encode(a) { try? j.write(to: offlineDir.appendingPathComponent(fid + ".json")) }
            }
        }
    }

    func removeOffline(_ docs: [Fila]) {
        for d in docs {
            let fid = Arxiu.fileId(d)
            try? fm.removeItem(at: offlineDir.appendingPathComponent(fid + ".pdf"))
            try? fm.removeItem(at: offlineDir.appendingPathComponent(fid + ".json"))
            offline.remove(fid)
        }
    }

    /// Un fitxer temporal amb aquest nom, per compartir-lo.
    func tempFile(_ data: Data, name: String) throws -> URL {
        let dir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(name.replacingOccurrences(of: "/", with: "-"))
        try data.write(to: url, options: .atomic)
        return url
    }

    // MARK: - Anotacions

    private var annCache: [String: Anotacions] = [:]

    func annotations(_ d: Fila) async -> Anotacions {
        let id = d["ID"] ?? ""
        if let a = annCache[id] { return a }
        guard (d["Anotacions"] ?? "").isEmpty == false else { return Anotacions() }
        var a = Anotacions()
        if let s: String = try? await call("getAnnotations", [id]), let data = s.data(using: .utf8),
           let dec = try? JSONDecoder().decode(Anotacions.self, from: data) {
            a = dec
        } else if let data = try? Data(contentsOf: offlineDir.appendingPathComponent(Arxiu.fileId(d) + ".json")),
                  let dec = try? JSONDecoder().decode(Anotacions.self, from: data) {
            a = dec
        }
        annCache[id] = a
        return a
    }

    func saveAnnotations(_ d: Fila, _ a: Anotacions) async throws {
        let id = d["ID"] ?? ""
        var clean = a
        clean.pages = clean.pages.filter { !$0.value.isEmpty }
        annCache[id] = clean
        let json = clean.pages.isEmpty ? "" : String(data: try JSONEncoder().encode(clean), encoding: .utf8) ?? ""
        let _: FlexText = try await call("saveAnnotations", [id, json])
        dades?.update("Documents") { rows in
            if let i = rows.firstIndex(where: { $0["ID"] == id }) { rows[i]["Anotacions"] = json.isEmpty ? "" : "Sí" }
        }
        if offline.contains(Arxiu.fileId(d)), let j = try? JSONEncoder().encode(clean) {
            try? j.write(to: offlineDir.appendingPathComponent(Arxiu.fileId(d) + ".json"))
        }
    }

    func clearAnnotationCache(_ id: String) { annCache[id] = nil }
}

/// Un fitxer triat al mòbil per pujar-lo.
struct PickedFile: Identifiable {
    let id = UUID()
    let name: String
    let data: Data
}

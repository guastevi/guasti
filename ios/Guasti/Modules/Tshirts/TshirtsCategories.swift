import SwiftUI

/// Categoria i instrument de cada dibuix. Es desen a la fulla de finances, a la pestanya
/// "Dibuixos" (una fila per dibuix, amb l'id del fitxer de Drive), i les categories noves a
/// "Dibuixos categories". Així no cal tocar la Guasti API.
/// Mentre un dibuix no s'ha revisat, la categoria que es mostra és la de la primera classificació.
@MainActor
final class TshirtsCats: ObservableObject {
    static let shared = TshirtsCats()

    static let defaults = ["Moon", "Claus de sol i de fa", "Instruments", "Encàrrecs", "Cançons", "Música", "No musicals", "Calendari"]
    static let instrumentsBase = ["fagot", "flauta", "flabiol", "clarinet", "oboè", "saxo", "trompa", "trompeta", "trombó", "tuba",
                                  "violí", "viola", "violoncel", "contrabaix", "guitarra", "baix", "piano", "percussió", "bateria",
                                  "arpa", "veu", "gralla", "kalimba"]

    struct Fitxa: Codable, Equatable {
        var categoria: String
        var instrument: String
        var revisat: Bool
        /// Etiquetes lliures (Sant Jordi, Nadal...), separades per comes a la fulla.
        var etiquetes: [String]?
    }

    @Published private(set) var fitxes: [String: Fitxa] = [:]
    @Published private(set) var custom: [String] = []
    @Published var errorMessage: String?
    private var lastSync: Date?

    private static let taula = "Dibuixos"
    private static let cols = ["ID", "Nom", "Categoria", "Instrument", "Revisat", "Etiquetes"]
    private static let taulaCats = "Dibuixos categories"
    private static let colsCats = ["ID", "Nom"]
    private static var defs: [String: [String]] { [taula: cols, taulaCats: colsCats] }

    private struct Resposta: Decodable { var taules: [String: [[String: String]]] }
    private struct Cache: Codable { var fitxes: [String: Fitxa]; var custom: [String] }

    private let cacheURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("guastevitshirts-categories.json")
    }()

    private init() {
        if let data = try? Data(contentsOf: cacheURL), let c = try? JSONDecoder().decode(Cache.self, from: data) {
            fitxes = c.fitxes
            custom = c.custom
        }
    }

    // MARK: Lectura

    /// Les categories en ordre: les de sempre, les noves i qualsevol altra que surti a la fulla.
    var categories: [String] {
        var out = Self.defaults
        for c in custom + fitxes.values.map(\.categoria) where !c.isEmpty && !out.contains(c) { out.append(c) }
        return out
    }

    func categoria(_ d: Dibuix) -> String {
        if let f = fitxes[d.id], !f.categoria.isEmpty { return f.categoria }
        return TshirtsPreclass.map[TshirtsPreclass.key(d.name)]?.categoria ?? ""
    }

    func instrument(_ d: Dibuix) -> String {
        if let f = fitxes[d.id] { return f.revisat || !f.instrument.isEmpty ? f.instrument : suggested(d) }
        return suggested(d)
    }

    private func suggested(_ d: Dibuix) -> String { TshirtsPreclass.map[TshirtsPreclass.key(d.name)]?.instrument ?? "" }

    func revisat(_ d: Dibuix) -> Bool { fitxes[d.id]?.revisat == true }

    func etiquetes(_ d: Dibuix) -> [String] { fitxes[d.id]?.etiquetes ?? [] }

    /// Totes les etiquetes que s'han fet servir, en ordre alfabètic.
    var allEtiquetes: [String] {
        var out = Set<String>()
        for f in fitxes.values { (f.etiquetes ?? []).forEach { out.insert($0) } }
        return out.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    /// Posa o treu una etiqueta d'un dibuix (sense tocar la categoria).
    func toggle(_ etiqueta: String, on d: Dibuix) async {
        var e = etiquetes(d)
        if let i = e.firstIndex(of: etiqueta) { e.remove(at: i) } else { e.append(etiqueta) }
        await save(d, categoria: categoria(d), instrument: instrument(d), etiquetes: e)
    }

    func instruments(in list: [Dibuix]) -> [String] {
        var out: [String] = []
        for d in list {
            let i = instrument(d)
            if !i.isEmpty && !out.contains(i) { out.append(i) }
        }
        return out.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    var allInstruments: [String] {
        var out = Self.instrumentsBase
        for f in fitxes.values where !f.instrument.isEmpty && !out.contains(f.instrument) { out.append(f.instrument) }
        return out
    }

    // MARK: Crides

    func refreshIfNeeded() async {
        if let lastSync, Date().timeIntervalSince(lastSync) < 120 { return }
        await refresh()
    }

    func refresh() async {
        guard let client = Connection.shared.client else { return }
        do {
            let r: Resposta = try await client.call("gastos.taules", ["taules": Self.defs])
            apply(r)
            lastSync = Date()
            errorMessage = nil
        } catch is CancellationError {
        } catch {
            errorMessage = "No s'han pogut carregar les categories: \(error.localizedDescription)"
        }
    }

    /// Desa la categoria i l'instrument d'un dibuix i el marca com a revisat.
    /// Es veu de seguida; si la fulla no respon, es torna enrere i surt l'error.
    func save(_ d: Dibuix, categoria: String, instrument: String, etiquetes: [String]? = nil) async {
        let before = fitxes[d.id]
        let tags = etiquetes ?? before?.etiquetes ?? []
        fitxes[d.id] = Fitxa(categoria: categoria, instrument: instrument, revisat: true, etiquetes: tags)
        saveCache()
        TshirtsFolderSync.shared.scheduleSync()
        guard let client = Connection.shared.client else {
            errorMessage = "Falta configurar la connexió amb Google."
            return
        }
        let fila: [String: Any] = ["ID": d.id, "Nom": d.name, "Categoria": categoria, "Instrument": instrument, "Revisat": "Sí", "Etiquetes": tags.joined(separator: ", ")]
        do {
            let r: Resposta = try await client.call("gastos.desaFila",
                                                    ["taula": Self.taula, "cols": Self.cols, "fila": fila, "taules": Self.defs])
            apply(r)
            errorMessage = nil
        } catch {
            fitxes[d.id] = before
            saveCache()
            errorMessage = "No s'ha pogut desar: \(error.localizedDescription)"
        }
    }

    func addCategory(_ name: String) async {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !categories.contains(name) else { return }
        custom.append(name)
        saveCache()
        guard let client = Connection.shared.client else { return }
        do {
            let r: Resposta = try await client.call("gastos.desaFila",
                                                    ["taula": Self.taulaCats, "cols": Self.colsCats, "fila": ["ID": name, "Nom": name], "taules": Self.defs])
            apply(r)
        } catch {
            errorMessage = "No s'ha pogut desar la categoria: \(error.localizedDescription)"
        }
    }

    // MARK: Privat

    private func apply(_ r: Resposta) {
        var f: [String: Fitxa] = [:]
        for row in r.taules[Self.taula] ?? [] {
            guard let id = row["ID"], !id.isEmpty else { continue }
            let rev = ["sí", "si", "true", "1", "x"].contains((row["Revisat"] ?? "").lowercased())
            let tags = (row["Etiquetes"] ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            f[id] = Fitxa(categoria: row["Categoria"] ?? "", instrument: row["Instrument"] ?? "", revisat: rev, etiquetes: tags)
        }
        fitxes = f
        custom = (r.taules[Self.taulaCats] ?? []).compactMap { ($0["Nom"] ?? $0["ID"]).flatMap { $0.isEmpty ? nil : $0 } }
        saveCache()
    }

    private func saveCache() {
        if let data = try? JSONEncoder().encode(Cache(fitxes: fitxes, custom: custom)) { try? data.write(to: cacheURL) }
    }
}

/// Un botó en forma de càpsula per triar categoria o instrument.
struct TshirtChip: View {
    let title: String
    var count: Int? = nil
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(title)
                if let count { Text("\(count)").foregroundStyle(selected ? .white.opacity(0.8) : .secondary) }
            }
            .font(Theme.body(13, weight: .semibold, relativeTo: .footnote))
            .lineLimit(1)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .foregroundStyle(selected ? .white : .primary)
            .background(selected ? Theme.tint : Color(.secondarySystemBackground), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// Revisió un per un, com a partitures: es veu el dibuix gran amb la categoria suggerida,
/// es corregeix si cal i «Desa i següent». Els semblants surten seguits.
struct TshirtsReviewView: View {
    @ObservedObject private var store = TshirtsStore.shared
    @ObservedObject private var cats = TshirtsCats.shared
    @AppStorage("tshirts.fons") private var fons: TshirtFons = .clar
    @State private var skipped = Set<String>()
    @State private var currentID: String?
    @State private var categoria = ""
    @State private var instrument = ""
    @State private var nom = ""
    @State private var etiquetes: [String] = []
    @State private var newEtiqueta = false
    @State private var newCategory = false
    @State private var newInstrument = false
    @State private var text = ""

    private var queue: [Dibuix] {
        store.dibuixos
            .filter { !cats.revisat($0) && !skipped.contains($0.id) }
            .sorted {
                let a = cats.categories.firstIndex(of: cats.categoria($0)) ?? 99
                let b = cats.categories.firstIndex(of: cats.categoria($1)) ?? 99
                if a != b { return a < b }
                return $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
    }

    private var current: Dibuix? {
        if let currentID, let d = store.dibuixos.first(where: { $0.id == currentID }), !cats.revisat(d) { return d }
        return nil
    }

    var body: some View {
        Group {
            if let d = current {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        fons.view
                            .aspectRatio(1.2, contentMode: .fit)
                            .overlay(DibuixImage(id: d.id, size: .full).padding(12))
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .onTapGesture { fons = fons.next }

                        HStack {
                            Text("Nom").font(Theme.body(13, weight: .bold, relativeTo: .footnote)).foregroundStyle(.secondary)
                            Spacer()
                            Text("En queden \(queue.count)").font(Theme.body(13, relativeTo: .footnote)).foregroundStyle(.secondary)
                        }
                        TextField(d.name, text: $nom)
                            .font(Theme.body(17, weight: .semibold, relativeTo: .headline))
                            .textFieldStyle(.roundedBorder)
                            .submitLabel(.done)

                        Text("Categoria").font(Theme.body(13, weight: .bold, relativeTo: .footnote)).foregroundStyle(.secondary)
                        chips(cats.categories, selected: categoria) { categoria = $0 }
                        Button { text = ""; newCategory = true } label: { Label("Nova categoria", systemImage: "plus") }
                            .font(Theme.body(14, relativeTo: .subheadline))

                        Text("Instrument").font(Theme.body(13, weight: .bold, relativeTo: .footnote)).foregroundStyle(.secondary)
                        chips(["Cap"] + cats.allInstruments, selected: instrument.isEmpty ? "Cap" : instrument) {
                            instrument = $0 == "Cap" ? "" : $0
                        }
                        Button { text = ""; newInstrument = true } label: { Label("Un altre instrument", systemImage: "plus") }
                            .font(Theme.body(14, relativeTo: .subheadline))

                        Text("Etiquetes").font(Theme.body(13, weight: .bold, relativeTo: .footnote)).foregroundStyle(.secondary)
                        let totes = cats.allEtiquetes + etiquetes.filter { !cats.allEtiquetes.contains($0) }
                        if !totes.isEmpty {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 6)], alignment: .leading, spacing: 6) {
                                ForEach(totes, id: \.self) { t in
                                    TshirtChip(title: t, selected: etiquetes.contains(t)) {
                                        if let i = etiquetes.firstIndex(of: t) { etiquetes.remove(at: i) } else { etiquetes.append(t) }
                                    }
                                }
                            }
                        }
                        Button { text = ""; newEtiqueta = true } label: { Label("Nova etiqueta", systemImage: "tag") }
                            .font(Theme.body(14, relativeTo: .subheadline))

                        if let e = cats.errorMessage {
                            Text(e).font(Theme.body(13, relativeTo: .footnote)).foregroundStyle(.red)
                        }

                        HStack(spacing: 12) {
                            Button { skipped.insert(d.id); next() } label: {
                                Text("Salta").frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            Button {
                                let (c, i, tags) = (categoria, instrument, etiquetes)
                                let n = nom.trimmingCharacters(in: .whitespacesAndNewlines)
                                Task {
                                    var dibuix = d
                                    if !n.isEmpty, n != d.name {
                                        do {
                                            try await store.rename(d, to: n)
                                            dibuix.name = n
                                        } catch {
                                            cats.errorMessage = "No s'ha pogut canviar el nom: \(error.localizedDescription)"
                                        }
                                    }
                                    await cats.save(dibuix, categoria: c, instrument: i, etiquetes: tags)
                                }
                                skipped.insert(d.id)
                                next()
                            } label: {
                                Text("Desa i següent").bold().frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(Theme.tint)
                            .disabled(categoria.isEmpty)
                        }
                        .controlSize(.large)
                        .padding(.top, 6)
                    }
                    .padding(16)
                }
            } else {
                ContentUnavailableView("No queda res per revisar", systemImage: "checkmark.circle",
                                       description: Text("Tots els dibuixos tenen la seva categoria."))
            }
        }
        .navigationTitle("Revisió")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { if current == nil { next() } }
        .alert("Nova categoria", isPresented: $newCategory) {
            TextField("Nom", text: $text)
            Button("Afegeix") {
                let name = text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { return }
                categoria = name
                Task { await cats.addCategory(name) }
            }
            Button("Cancel·la", role: .cancel) {}
        }
        .alert("Nova etiqueta", isPresented: $newEtiqueta) {
            TextField("Per exemple: Sant Jordi", text: $text)
            Button("Afegeix") {
                let t = text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: " ")
                if !t.isEmpty && !etiquetes.contains(t) { etiquetes.append(t) }
            }
            Button("Cancel·la", role: .cancel) {}
        }
        .alert("Un altre instrument", isPresented: $newInstrument) {
            TextField("Instrument", text: $text)
            Button("D'acord") { instrument = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            Button("Cancel·la", role: .cancel) {}
        }
    }

    private func next() {
        let d = queue.first
        currentID = d?.id
        if let d {
            categoria = cats.categoria(d)
            instrument = cats.instrument(d)
            nom = d.name
            etiquetes = cats.etiquetes(d)
        }
    }

    private func chips(_ items: [String], selected: String, pick: @escaping (String) -> Void) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 6)], alignment: .leading, spacing: 6) {
            ForEach(items, id: \.self) { item in
                TshirtChip(title: item, selected: item == selected) { pick(item) }
            }
        }
    }
}

/// Menú per canviar la categoria o l'instrument d'un dibuix (a la galeria i al detall).
struct TshirtCategoryMenu: View {
    let dibuix: Dibuix
    @ObservedObject private var cats = TshirtsCats.shared

    var body: some View {
        Menu {
            ForEach(cats.categories, id: \.self) { c in
                Button {
                    Task { await cats.save(dibuix, categoria: c, instrument: cats.instrument(dibuix)) }
                } label: {
                    if c == cats.categoria(dibuix) { Label(c, systemImage: "checkmark") } else { Text(c) }
                }
            }
        } label: {
            Label("Mou a una categoria", systemImage: "folder")
        }
        if !cats.allEtiquetes.isEmpty {
            Menu {
                ForEach(cats.allEtiquetes, id: \.self) { t in
                    Button {
                        Task { await cats.toggle(t, on: dibuix) }
                    } label: {
                        if cats.etiquetes(dibuix).contains(t) { Label(t, systemImage: "checkmark") } else { Text(t) }
                    }
                }
            } label: {
                Label("Etiquetes", systemImage: "tag")
            }
        }
    }
}

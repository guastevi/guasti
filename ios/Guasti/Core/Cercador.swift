import SwiftUI

/// El text que s'ha escrit al cercador universal, partit en paraules.
/// No distingeix majúscules ni accents: «cancons» troba «Cançons».
struct SearchQuery {
    let text: String
    let tokens: [String]

    init(_ text: String) {
        self.text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        tokens = Self.norm(self.text).split(whereSeparator: \.isWhitespace).map(String.init)
    }

    var isEmpty: Bool { tokens.isEmpty }

    /// Totes les paraules apareixen en algun dels camps.
    func matches(_ fields: [String]) -> Bool {
        let hay = Self.norm(fields.joined(separator: " "))
        return tokens.allSatisfy { hay.contains($0) }
    }

    /// Com d'amunt ha d'anar un resultat: 0 si el títol comença pel que s'ha escrit,
    /// 1 si el títol ja conté totes les paraules, 2 si les paraules són als altres camps.
    func rank(title: String) -> Int {
        let t = Self.norm(title)
        if t.hasPrefix(tokens.joined(separator: " ")) { return 0 }
        return tokens.allSatisfy { t.contains($0) } ? 1 : 2
    }

    static func norm(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "ca_ES")).lowercased()
    }
}

/// Una cosa trobada pel cercador universal i la pantalla que s'obre en tocar-la.
struct SearchResult: Identifiable {
    let id: String
    let title: String
    var subtitle = ""
    /// Text petit a la dreta (un import, una data...).
    var trailing = ""
    var trailingColor: Color?
    var systemImage: String
    /// Miniatura en lloc de la icona (p. ex. la foto d'una peça de l'armari).
    var thumbnail: AnyView?
    var rank = 2
    let destination: @MainActor () -> AnyView
}

extension GuastiModule {
    /// Per defecte una secció no surt al cercador (p. ex. Xarxes, que és feina externa).
    @MainActor func prepareSearch() async {}
    @MainActor func search(_ query: SearchQuery) -> [SearchResult] { [] }
}

/// Els resultats del cercador de la pantalla d'inici, agrupats per secció.
@MainActor
struct CercadorResultats: View {
    let query: SearchQuery

    /// Puja cada cop que una secció acaba de carregar les seves dades, per tornar a cercar.
    @State private var revision = 0
    @State private var preparing: Set<String> = []
    @State private var prepared = false
    @State private var groups: [Seccio] = []

    private struct Seccio: Identifiable {
        let module: any GuastiModule
        let results: [SearchResult]
        var id: String { module.id }
    }

    private static let perSection = 40

    var body: some View {
        List {
            if groups.isEmpty && preparing.isEmpty {
                ContentUnavailableView.search(text: query.text)
                    .listRowBackground(Color.clear)
            }
            ForEach(groups) { group in
                Section {
                    ForEach(group.results.prefix(Self.perSection)) { r in
                        NavigationLink { r.destination() } label: { row(r, tint: group.module.tint) }
                    }
                    if group.results.count > Self.perSection {
                        Text("I \(group.results.count - Self.perSection) més. Afina la cerca per veure'ls.")
                            .font(Theme.body(13, relativeTo: .footnote))
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Label(group.module.title, systemImage: group.module.systemImage)
                        .font(Theme.body(13, weight: .semibold, relativeTo: .footnote))
                        .foregroundStyle(group.module.tint)
                }
            }
            if !preparing.isEmpty {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Encara s'està carregant: " + ModuleRegistry.all.filter { preparing.contains($0.id) }.map(\.title).joined(separator: ", "))
                        .font(Theme.body(13, relativeTo: .footnote))
                        .foregroundStyle(.secondary)
                }
                .listRowBackground(Color.clear)
            }
        }
        .listStyle(.insetGrouped)
        .scrollDismissesKeyboard(.immediately)
        .task { await prepareAll() }
        .task(id: "\(query.text)#\(revision)") {
            // Petita pausa perquè no es cerqui a cada lletra mentre s'escriu.
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            groups = ModuleRegistry.all.filter(\.isAvailable).compactMap { m in
                let found = m.search(query).enumerated()
                    .sorted { ($0.element.rank, $0.offset) < ($1.element.rank, $1.offset) }
                    .map(\.element)
                return found.isEmpty ? nil : Seccio(module: m, results: found)
            }
        }
    }

    /// Cada secció es posa al dia pel seu compte; els resultats van apareixent a mesura que arriben.
    private func prepareAll() async {
        guard !prepared else { return }
        prepared = true
        await withTaskGroup(of: Void.self) { group in
            for m in ModuleRegistry.all where m.isAvailable {
                preparing.insert(m.id)
                group.addTask { @MainActor in
                    await m.prepareSearch()
                    preparing.remove(m.id)
                    revision += 1
                }
            }
        }
    }

    private func row(_ r: SearchResult, tint: Color) -> some View {
        HStack(spacing: 12) {
            Group {
                if let thumb = r.thumbnail {
                    thumb
                } else {
                    Image(systemName: r.systemImage)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(tint)
                }
            }
            .frame(width: 38, height: 38)
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(r.title.isEmpty ? "Sense nom" : r.title)
                    .font(Theme.body(16, weight: .semibold))
                    .lineLimit(2)
                if !r.subtitle.isEmpty {
                    Text(r.subtitle)
                        .font(Theme.body(13, relativeTo: .footnote))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 6)
            if !r.trailing.isEmpty {
                Text(r.trailing)
                    .font(Theme.body(14, weight: .semibold, relativeTo: .subheadline))
                    .monospacedDigit()
                    .foregroundStyle(r.trailingColor ?? .secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

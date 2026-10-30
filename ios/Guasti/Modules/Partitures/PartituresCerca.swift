import SwiftUI

/// El que l'Arxiu de Repertori aporta al cercador universal: obres, documents, concerts, compositors,
/// llibres, fagotades, agrupacions i directors. Es cerca a la còpia de l'arxiu que hi ha al mòbil.
extension PartituresModule {
    @MainActor func prepareSearch() async {
        let store = PartituresStore.shared
        if store.dades == nil { await store.load() }
    }

    @MainActor func search(_ query: SearchQuery) -> [SearchResult] {
        let store = PartituresStore.shared
        guard store.dades != nil else { return [] }
        var out: [SearchResult] = []

        // Fitxes de cada full, en l'ordre de les pestanyes de l'app
        for (sheet, icon) in [("Obres", "music.note"), ("Documents", "doc.text"), ("Concerts", "music.mic"),
                              ("Fagotades", "person.3"), ("Agrupacions", "person.3.sequence"), ("Directors", "person.wave.2")] {
            let key = Arxiu.keys[sheet] ?? "ID"
            for r in store.rows(sheet) {
                let id = r[key] ?? ""
                guard !id.isEmpty, query.matches(fields(sheet, r, store)) else { continue }
                let (title, subtitle) = labels(sheet, r, store)
                out.append(SearchResult(
                    id: "partitures-\(sheet)-\(id)",
                    title: title,
                    subtitle: subtitle,
                    systemImage: icon,
                    rank: query.rank(title: title),
                    destination: { AnyView(PDetailView(name: sheet, id: id)) }
                ))
            }
        }

        for (name, c) in store.composerMap() where query.matches([name]) {
            out.append(SearchResult(
                id: "partitures-compositor-\(name)",
                title: name,
                subtitle: "Compositor · \(c.o) obres, \(c.d) documents",
                systemImage: "person.crop.circle",
                rank: query.rank(title: name),
                destination: { AnyView(PComposerView(name: name)) }
            ))
        }

        for (name, docs) in store.books() where query.matches([name]) {
            out.append(SearchResult(
                id: "partitures-llibre-\(name)",
                title: name,
                subtitle: "Llibre · \(docs.count) documents",
                systemImage: "books.vertical",
                rank: query.rank(title: name),
                destination: { AnyView(PBookView(name: name)) }
            ))
        }
        return out
    }

    /// Els camps de la fitxa on es busca (els mateixos que es veuen a la fitxa; les referències, pel seu nom).
    @MainActor private func fields(_ sheet: String, _ r: Fila, _ store: PartituresStore) -> [String] {
        (Arxiu.schema[sheet] ?? []).compactMap { camp -> String? in
            switch camp.t {
            case .url, .files, .check: return nil
            case .ref: return store.refLabel(camp.src, r[camp.k])
            case .date: return Arxiu.fmtDate(r[camp.k]) + " " + (r[camp.k] ?? "")
            default: return r[camp.k]
            }
        }
    }

    @MainActor private func labels(_ sheet: String, _ r: Fila, _ store: PartituresStore) -> (String, String) {
        func join(_ parts: [String?]) -> String {
            parts.compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
        }
        switch sheet {
        case "Obres":
            return (r["Obra"] ?? "", join([r["Compositor"], r["Formació"] ?? r["Categoria"], r["Àmbit"]]))
        case "Documents":
            return ((r["Títol"] ?? "").isEmpty ? "Document" : r["Títol"] ?? "",
                    join([r["Compositor"], r["Instrument"], r["Llibre"], r["Format"]]))
        case "Concerts":
            return (store.concertLabel(r), join([r["Agrupació"], r["Lloc"], r["Població"]]))
        case "Fagotades":
            return ("Fagotada " + (r["Any"] ?? ""), join([r["Lloc"], r["Dates"]]))
        case "Agrupacions":
            return (r["Agrupació"] ?? "", join([r["Tipus"]]))
        default:
            return (r["Director/a"] ?? "", join([r["Agrupacions"]]))
        }
    }
}

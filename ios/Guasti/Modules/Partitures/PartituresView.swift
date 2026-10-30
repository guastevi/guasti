import SwiftUI

struct PartituresModule: GuastiModule {
    let id = "partitures"
    let title = "Partitures"
    let subtitle = "Arxiu de Repertori"
    let systemImage = "music.note.list"
    let tint = Theme.blue
    let isAvailable = true

    @MainActor func makeRootView() -> AnyView {
        AnyView(PartituresView())
    }
}

/// El que es pot obrir per sobre d'una pantalla: una fitxa per editar, pujar fitxers, el mode faristol...
enum PReq: Identifiable {
    case form(String, Fila, review: Bool = false)
    case upload(Fila)
    case tools
    case package([Fila], String, score: Bool = false, offline: Bool = false)
    case stand([Fila], String, draw: Bool = false, start: Int = 0)
    case review

    var id: String {
        switch self {
        case .form(let n, let r, let rv): return "form-\(n)-\(r["ID"] ?? r[Arxiu.keys[n] ?? ""] ?? "nou")-\(rv)"
        case .upload: return "upload"
        case .tools: return "tools"
        case .package(_, let t, _, let o): return "pkg-\(t)-\(o)"
        case .stand(_, let t, let d, let s): return "stand-\(t)-\(d)-\(s)"
        case .review: return "review"
        }
    }
}

struct PPresenter: ViewModifier {
    @Binding var req: PReq?
    var onDeleted: () -> Void = {}

    func body(content: Content) -> some View {
        content
            .sheet(item: Binding(get: { isSheet(req) ? req : nil }, set: { if $0 == nil { req = nil } })) { r in
                NavigationStack {
                    switch r {
                    case .form(let n, let row, let review):
                        PFormView(name: n, row: row, review: review, onDeleted: onDeleted)
                    case .upload(let meta): PUploadView(meta: meta)
                    case .tools: PToolsView()
                    case .package(let docs, let title, let score, let offline):
                        PPackageView(docs: docs, title: title, score: score, offline: offline)
                    case .review: PInventariReview()
                    case .stand: EmptyView()
                    }
                }
                .modifier(PToastOverlay())
            }
            .fullScreenCover(item: Binding(get: { isStand(req) ? req : nil }, set: { if $0 == nil { req = nil } })) { r in
                if case .stand(let docs, let title, let draw, let start) = r {
                    FaristolView(docs: docs, title: title, startDrawing: draw, start: start)
                }
            }
    }

    private func isStand(_ r: PReq?) -> Bool {
        if case .stand = r { return true }
        return false
    }

    private func isSheet(_ r: PReq?) -> Bool { r != nil && !isStand(r) }
}

extension View {
    func pPresenter(_ req: Binding<PReq?>, onDeleted: @escaping () -> Void = {}) -> some View {
        modifier(PPresenter(req: req, onDeleted: onDeleted))
    }
}

/// "Arxiu de Repertori": les mateixes pestanyes que l'app web.
struct PartituresView: View {
    @ObservedObject private var store = PartituresStore.shared
    @State private var tab = "Inici"
    @State private var req: PReq?
    @State private var spinning = false

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if store.dades != nil {
                        PTabContent(tab: $tab, req: $req).id(tab)
                    } else if let e = store.errorMessage {
                        PEmpty(text: "No s'ha pogut carregar: " + e)
                    } else {
                        Text("Carregant l'arxiu...").foregroundStyle(P.mute).frame(maxWidth: .infinity).padding(.vertical, 60)
                    }
                }
                .frame(maxWidth: 760)
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 110)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .refreshable { await store.load() }
        }
        .overlay(alignment: .bottomTrailing) { fab }
        .pScreen("")
        .modifier(PToastOverlay())
        .pPresenter($req)
        .task { await store.load() }
        .onChange(of: store.errorMessage) { _, e in
            if let e, store.dades != nil { toast(e) }
        }
        .overlay(alignment: .bottomLeading) {
            if store.saving > 0 {
                Text("Desant \(store.saving)...")
                    .font(.system(size: 12)).foregroundStyle(P.paper)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(P.ink.opacity(0.85), in: Capsule())
                    .padding(12)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Arxiu de Repertori").font(.system(size: 22, weight: .bold)).tracking(-0.2)
                Spacer()
                Button {
                    Task {
                        spinning = true
                        await store.load()
                        spinning = false
                        toast(store.errorMessage == nil ? "Actualitzat" : "Error: " + (store.errorMessage ?? ""))
                    }
                } label: {
                    HStack(spacing: 6) {
                        // Una animació repeatForever no s'atura mai a SwiftUI: millor un indicador només mentre carrega
                        if spinning || store.isLoading {
                            ProgressView().controlSize(.mini).tint(P.ink).frame(width: 16, height: 16)
                        } else {
                            Image(systemName: "arrow.clockwise").font(.system(size: 14, weight: .semibold)).frame(width: 16, height: 16)
                        }
                        Text("Actualitza").font(.system(size: 13, weight: .medium))
                    }
                    .foregroundStyle(P.ink)
                    .padding(.horizontal, 12).padding(.vertical, 5)
                    .background(P.card, in: Capsule())
                    .overlay(Capsule().strokeBorder(P.line))
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, 10)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(Arxiu.tabs, id: \.0) { t in
                        Button { PFilters.shared.reset(); tab = t.0 } label: {
                            Text(t.1)
                                .fontWeight(.medium)
                                .foregroundStyle(tab == t.0 ? P.ink : P.mute)
                                .padding(.horizontal, 10).padding(.top, 8).padding(.bottom, 10)
                                .overlay(alignment: .bottom) {
                                    Rectangle().fill(tab == t.0 ? P.blue : .clear).frame(height: 2)
                                }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 2)
        .background(P.paper)
        .overlay(alignment: .bottom) { Rectangle().fill(P.line).frame(height: 1) }
    }

    private var fab: some View {
        Button {
            req = PTabContent.fabRequest(tab: tab)
        } label: {
            Text("+")
                .font(.system(size: 30))
                .foregroundStyle(P.onAccent)
                .frame(width: 56, height: 56)
                .background(P.accent, in: Circle())
                .shadow(color: .black.opacity(0.25), radius: 7, y: 4)
        }
        .buttonStyle(.plain)
        .padding(.trailing, 18)
        .padding(.bottom, 22)
        .accessibilityLabel("Afegeix")
    }
}

/// Estat de filtres compartit amb el botó +, perquè sàpiga on som.
@MainActor
final class PFilters: ObservableObject {
    static let shared = PFilters()
    @Published var q = ""
    @Published var f: [String: String] = [:]
    @Published var kind = "pdf"
    @Published var centre = "Vila-seca"
    @Published var curs = ""
    @Published var limit = 60

    func reset() {
        q = ""
        f = [:]
        limit = 60
    }
}

/// El contingut de cada pestanya.
struct PTabContent: View {
    @Binding var tab: String
    @Binding var req: PReq?
    @ObservedObject private var store = PartituresStore.shared
    @ObservedObject private var s = PFilters.shared
    @AppStorage("arxiu.view") private var viewMode = "grid"

    @MainActor static func fabRequest(tab: String) -> PReq {
        let s = PFilters.shared
        switch tab {
        case "Compositors": return .form("Obres", [:])
        case "Documents", "Inici": return .tools
        case "Llibres": return .upload(["Categoria": "Llibres", "Tipus": "Llibre de música", "Formació": s.f["Formació"] ?? ""])
        case "Cursos":
            var pre: Fila = ["Àmbit": "Pedagògic", "Categoria": "Repertori fagotístic"]
            if !s.centre.isEmpty { pre["Centre"] = s.centre }
            if s.centre == "Vila-seca" { pre["Etiquetes"] = "Vila-seca" }
            if !s.curs.isEmpty { pre["Curs"] = s.curs }
            return .form("Obres", pre)
        case "Obres":
            if let c = s.f["Categoria"], !c.isEmpty { return .form("Obres", ["Categoria": c, "Formació": s.f["Formació"] ?? ""]) }
            return .form("Obres", [:])
        default: return .form(tab, [:])
        }
    }

    var body: some View {
        Group {
            switch tab {
            case "Inici": PHomeTab(tab: $tab, req: $req)
            case "Obres": obres
            case "Cursos": cursos
            case "Documents": documents
            case "Llibres": llibres
            case "Compositors": compositors
            case "Concerts": concerts
            case "Fagotades": fagotades
            default: simple
            }
        }
    }

    // MARK: filtres

    private func binding(_ k: String) -> Binding<String> {
        Binding(get: { s.f[k] ?? "" }, set: { s.f[k] = $0; s.limit = 60 })
    }

    private func matches(_ r: Fila, extra: String = "") -> Bool {
        let q = Arxiu.norm(s.q)
        if !q.isEmpty {
            let hay = Arxiu.norm(r.values.joined(separator: " ") + " " + extra)
            if q.split(separator: " ").contains(where: { !hay.contains($0) }) { return false }
        }
        for (k, v) in s.f where !v.isEmpty {
            switch k {
            case "Etiquetes", "Curs", "Tipus", "Instrument":
                if !Arxiu.splitTags(r[k]).contains(v) { return false }
            case "Categoria" where v == "__none":
                if !(r[k] ?? "").isEmpty { return false }
            case "__rev":
                if (v == "Revisats") != !(r["Revisat"] ?? "").isEmpty { return false }
            default:
                if (r[k] ?? "") != v { return false }
            }
        }
        return true
    }

    private func search(_ placeholder: String) -> some View {
        PSearch(placeholder: placeholder, text: Binding(get: { s.q }, set: { s.q = $0; s.limit = 60 })).padding(.bottom, 8)
    }

    private func catBars(_ sheet: String, cats: [(String, String)]) -> some View {
        let cur = s.f["Categoria"] ?? ""
        let forms = cur.isEmpty || cur == "__none" ? [] : Arxiu.uniq(store.rows(sheet).filter { $0["Categoria"] == cur }.map { $0["Formació"] })
        return VStack(spacing: 0) {
            PCatBar(items: cats, selected: cur) { v in s.f["Categoria"] = v; s.f["Formació"] = ""; s.limit = 60 }
            if !forms.isEmpty {
                PCatBar(items: [("Totes", "")] + forms.map { ($0, $0) }, selected: s.f["Formació"] ?? "", small: true) { s.f["Formació"] = $0 }
            }
        }
    }

    private func filterGrid(_ filters: [(String, String, [String])]) -> some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
            ForEach(filters, id: \.0) { f in
                PFilter(label: f.1, values: f.2, selection: binding(f.0))
            }
        }
        .padding(.bottom, 12)
    }

    // MARK: Obres

    private var obres: some View {
        let L = store.dades?.Llistes ?? [:]
        let items = store.rows("Obres").filter { matches($0, extra: store.refLabel("Concerts", $0["Concert"])) }
            .sorted { Arxiu.norm($0["Obra"]) == Arxiu.norm($1["Obra"]) ? Arxiu.sortNorm($0["Compositor"], $1["Compositor"]) : Arxiu.sortNorm($0["Obra"], $1["Obra"]) }
        return VStack(alignment: .leading, spacing: 0) {
            catBars("Obres", cats: [("Totes", "")] + (L["Categoria"] ?? []).map { ($0, $0) })
            search("Cerca obra, compositor, notes...")
            filterGrid([("Àmbit", "Activitat", L["Àmbit"] ?? []), ("Instrument", "Instrument", L["Instrument"] ?? []),
                        ("Agrupació", "Agrupació", Arxiu.uniq(store.rows("Agrupacions").map { $0["Agrupació"] })),
                        ("Etiquetes", "Etiqueta", L["Etiquetes"] ?? [])])
            PCount("\(items.count) obres")
            obraList(Array(items.prefix(s.limit)), total: items.count)
        }
    }

    private func obraList(_ items: [Fila], total: Int) -> some View {
        LazyVStack(spacing: 8) {
            ForEach(items, id: \.self) { o in
                NavigationLink { PDetailView(name: "Obres", id: o["ID"] ?? "") } label: { ObraCard(o: o) }.buttonStyle(.plain)
            }
            more(total > items.count)
        }
    }

    @ViewBuilder private func more(_ show: Bool) -> some View {
        if show {
            Button("Mostra'n més") { s.limit += 60 }.buttonStyle(PBtn()).frame(maxWidth: .infinity).padding(.vertical, 14)
        }
    }

    // MARK: Pedagògic

    private var cursos: some View {
        let L = store.dades?.Llistes ?? [:]
        let cursos = (L["Curs"] ?? []).filter { !Arxiu.isGroup($0) }
        let cg = store.centreGroups(s.centre)
        let short: (String) -> String = { $0.replacingOccurrences(of: "Elemental ", with: "").replacingOccurrences(of: "Professional ", with: "") }
        let items = store.rows("Obres").filter { o in
            (!(o["Curs"] ?? "").isEmpty || o["Àmbit"] == "Pedagògic" || cg.contains { store.inGroup(o, $0) }) && store.inCentre(o, s.centre) && matches(o)
        }.sorted { Arxiu.sortNorm($0["Obra"], $1["Obra"]) }
        let groups: [String] = s.curs.isEmpty ? cg + cursos + ["Sense curs"] : [s.curs]
        let grouped: [(String, [Fila])] = groups.map { c in
            (c, items.filter { o in c == "Sense curs" ? Arxiu.splitTags(o["Curs"]).isEmpty && !cg.contains { store.inGroup(o, $0) } : store.inGroup(o, c) })
        }.filter { !$0.1.isEmpty }
        let cdocs = s.curs.isEmpty ? [] : store.courseDocs(s.curs, centre: s.centre).filter(Arxiu.isPdf)
        return VStack(alignment: .leading, spacing: 0) {
            PCatBar(items: [("Tots", "")] + (L["Centre"] ?? []).map { ($0, $0) }, selected: s.centre) { s.centre = $0 }
            VStack(alignment: .leading, spacing: 8) {
                if !cg.isEmpty { cursRow("Grups", cg, label: { $0 }) }
                FlowLayout(spacing: 6) {
                    PChip(text: "Tots", on: s.curs.isEmpty, small: true) { s.curs = "" }
                    ForEach(cursos.filter { $0.hasPrefix("Iniciaci") }, id: \.self) { c in
                        PChip(text: c, on: c == s.curs, small: true) { s.curs = c }
                    }
                }
                cursRow("Elemental", cursos.filter { $0.hasPrefix("Elemental") }, label: short)
                cursRow("Professional", cursos.filter { $0.hasPrefix("Professional") }, label: short)
                cursRow("Altres", cursos.filter { !$0.hasPrefix("Iniciaci") && !$0.hasPrefix("Elemental") && !$0.hasPrefix("Professional") }, label: { $0 })
            }
            .padding(.bottom, 12)
            search("Cerca al repertori pedagògic...")
            filterGrid([("Instrument", "Instrument", L["Instrument"] ?? [])])
            if !cdocs.isEmpty {
                FlowLayout(spacing: 8) {
                    Button("Paquet de \(s.curs) (PDF únic)") {
                        req = .package(store.courseDocs(s.curs, centre: s.centre), "Repertori " + s.curs + (s.centre.isEmpty ? "" : " · " + s.centre))
                    }.buttonStyle(PBtn(kind: .primary))
                    Button("Mode faristol") { req = .stand(store.courseDocs(s.curs, centre: s.centre), s.curs) }.buttonStyle(PBtn())
                    Text("\(cdocs.count) PDF").font(.system(size: 12)).foregroundStyle(P.mute).padding(.top, 9)
                }
                .padding(.bottom, 6)
            }
            if grouped.isEmpty {
                PEmpty(text: (s.curs.isEmpty ? "Encara no hi ha repertori pedagògic." : "Encara no hi ha obres per a \(s.curs).") + "\nPrem + per afegir-ne.")
            }
            LazyVStack(alignment: .leading, spacing: 8) {
                ForEach(grouped, id: \.0) { g in
                    PGroupTitle(text: g.0, count: g.1.count).padding(.bottom, -8)
                    ForEach(g.1, id: \.self) { o in
                        NavigationLink { PDetailView(name: "Obres", id: o["ID"] ?? "") } label: { ObraCard(o: o) }.buttonStyle(.plain)
                    }
                }
            }
        }
    }

    @ViewBuilder private func cursRow(_ title: String, _ list: [String], label: @escaping (String) -> String) -> some View {
        if !list.isEmpty {
            HStack(alignment: .top, spacing: 6) {
                Text(title).font(.system(size: 12)).foregroundStyle(P.mute).frame(width: 76, alignment: .leading).padding(.top, 7)
                FlowLayout(spacing: 6) {
                    ForEach(list, id: \.self) { c in
                        PChip(text: label(c), on: c == s.curs, small: true) { s.curs = c }
                    }
                }
            }
        }
    }

    // MARK: Documents

    private struct Ent: Identifiable {
        let id: String
        let doc: Fila?
        let book: String?
        let docs: [Fila]
        let key: String
    }

    private var documents: some View {
        let L = store.dades?.Llistes ?? [:]
        let all = store.rows("Documents")
        var kn = ["pdf": 0, "ed": 0, "alt": 0]
        for d in all { kn[Arxiu.docKind(d), default: 0] += 1 }
        let items = all.filter { d in
            (s.kind == "tot" || Arxiu.docKind(d) == s.kind) &&
                matches(d, extra: store.refLabel("Obres", d["Obra"]) + " " + store.refLabel("Concerts", d["Concert"]))
        }
        var ents: [Ent] = []
        var bk: [String: Int] = [:]
        for d in items {
            if let b = d["Llibre"], !b.isEmpty {
                if let i = bk[b] {
                    let e = ents[i]
                    ents[i] = Ent(id: e.id, doc: nil, book: b, docs: e.docs + [d], key: e.key)
                } else {
                    bk[b] = ents.count
                    ents.append(Ent(id: "L|" + b, doc: nil, book: b, docs: [d], key: Arxiu.norm(b)))
                }
            } else {
                ents.append(Ent(id: d["ID"] ?? UUID().uuidString, doc: d, book: nil, docs: [], key: Arxiu.norm(d["Títol"])))
            }
        }
        ents.sort { $0.key.compare($1.key, locale: Locale(identifier: "ca_ES")) == .orderedAscending }
        let isList = viewMode == "list"
        let shown = Array(ents.prefix(s.limit * (isList ? 3 : 1)))
        let cats: [(String, String)] = [("Totes", "")] + (L["Categoria"] ?? []).map { ($0, $0) } + [("Sense classificar", "__none")]
        return VStack(alignment: .leading, spacing: 0) {
            PSeg(items: [("pdf", "PDF", kn["pdf"]), ("ed", "Editables", kn["ed"]), ("alt", "Altres", kn["alt"]), ("tot", "Tots", all.count)],
                 selected: s.kind) { s.kind = $0; s.limit = 60 }
            if s.kind == "ed" { PHint(text: "Notion, MusicXML, MuseScore, Finale, Sibelius, Dorico, MIDI...").padding(.top, -4).padding(.bottom, 10) }
            catBars("Documents", cats: cats)
            search("Cerca títol, compositor...")
            filterGrid([("Compositor", "Compositor", Arxiu.uniq(all.map { $0["Compositor"] })), ("Instrument", "Instrument", L["Instrument"] ?? []),
                        ("Tipus", "Tipus", L["Tipus document"] ?? []), ("Format", "Format", L["Format"] ?? []),
                        ("Curs", "Curs", L["Curs"] ?? []), ("__rev", "Revisió", ["Per revisar", "Revisats"])])
            PCount("\(items.count) documents") {
                PViewToggle(list: Binding(get: { viewMode == "list" }, set: { viewMode = $0 ? "list" : "grid" }))
            }
            if isList {
                LazyVStack(spacing: 0) {
                    ForEach(shown) { e in
                        if let b = e.book {
                            NavigationLink { PBookView(name: b) } label: {
                                PListRow(doc: store.bookCover(e.docs), title: b, sub: "Llibre · \(e.docs.count) fitxers")
                            }.buttonStyle(.plain)
                        } else if let d = e.doc {
                            PDocLink(doc: d) {
                                PListRow(doc: d, title: d["Títol"] ?? "",
                                         sub: [d["Compositor"], d["Instrument"], d["Tipus"], d["Format"], (d["Formació"] ?? "").isEmpty ? d["Categoria"] : d["Formació"]]
                                             .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                            }.buttonStyle(.plain)
                        }
                    }
                }
                .overlay(alignment: .top) { Rectangle().fill(P.line).frame(height: 1) }
            } else {
                LazyVGrid(columns: pGridColumns, spacing: 12) {
                    ForEach(shown) { e in
                        if let b = e.book {
                            NavigationLink { PBookView(name: b) } label: {
                                PGridItem(doc: store.bookCover(e.docs), title: b, sub: "Llibre · \(e.docs.count) fitxers")
                            }.buttonStyle(.plain)
                        } else if let d = e.doc {
                            PDocLink(doc: d) {
                                PGridItem(doc: d, title: d["Títol"] ?? "", sub: (d["Compositor"] ?? "").isEmpty ? (d["Tipus"] ?? "") : (d["Compositor"] ?? ""))
                            }.buttonStyle(.plain)
                        }
                    }
                }
            }
            more(ents.count > shown.count)
            if items.isEmpty { PEmpty(text: "No hi ha res per mostrar.") }
        }
    }

    // MARK: Llibres (categoria «Llibres»: canyes, didàctica, relaxació...)

    private var llibres: some View {
        let forms = store.llista("Formació: Llibres")
        let cur = s.f["Formació"] ?? ""
        let q = Arxiu.norm(s.q)
        let items = store.rows("Documents").filter { d in
            d["Categoria"] == "Llibres" && (cur.isEmpty || d["Formació"] == cur) &&
                (q.isEmpty || !q.split(separator: " ").contains { !Arxiu.norm(d.values.joined(separator: " ")).contains($0) })
        }.sorted { Arxiu.sortNorm($0["Títol"], $1["Títol"]) }
        return VStack(alignment: .leading, spacing: 0) {
            PCatBar(items: [("Tots", "")] + forms.map { ($0, $0) }, selected: cur) { s.f["Formació"] = $0 }
            search("Cerca llibre, autor...")
            PCount("\(items.count) llibres")
            if items.isEmpty {
                PEmpty(text: "Encara no hi ha llibres. Prem + per pujar-ne un (PDF, EPUB...).")
            }
            LazyVGrid(columns: pGridColumns, spacing: 12) {
                ForEach(items, id: \.self) { d in
                    PDocLink(doc: d) {
                        PGridItem(doc: d, title: d["Títol"] ?? "", sub: (d["Compositor"] ?? "").isEmpty ? (d["Formació"] ?? "") : (d["Compositor"] ?? ""))
                    }.buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: Compositors

    private var compositors: some View {
        let cm = store.composerMap()
        let q = Arxiu.norm(s.q)
        let names = cm.keys.filter { q.isEmpty || Arxiu.norm($0).contains(q) }.sorted { Arxiu.sortNorm($0, $1) }
        return VStack(alignment: .leading, spacing: 0) {
            search("Cerca compositor...")
            PCount("\(names.count) compositors")
            if names.isEmpty {
                PEmpty(text: q.isEmpty ? "Encara no hi ha compositors. Es van omplint quan edites les obres i els documents." : "Cap compositor coincideix amb la cerca.")
            }
            LazyVStack(alignment: .leading, spacing: 8) {
                ForEach(Array(names.enumerated()), id: \.element) { i, n in
                    let letter = String(Arxiu.norm(n).prefix(1)).uppercased()
                    if i == 0 || String(Arxiu.norm(names[i - 1]).prefix(1)).uppercased() != letter {
                        PGroupTitle(text: letter).padding(.bottom, -8)
                    }
                    let c = cm[n] ?? PartituresStore.Compositor()
                    let sub = [c.o > 0 ? "\(c.o)" + (c.o > 1 ? " obres" : " obra") : "", c.d > 0 ? "\(c.d)" + (c.d > 1 ? " documents" : " document") : ""]
                        .filter { !$0.isEmpty }.joined(separator: " · ")
                    NavigationLink { PComposerView(name: n) } label: { PSimpleCard(title: n, sub: sub) }.buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: Concerts, fagotades, agrupacions i directors

    private var concerts: some View {
        let items = store.rows("Concerts").filter { matches($0) }.sorted { ($0["Data"] ?? "") > ($1["Data"] ?? "") }
        return VStack(alignment: .leading, spacing: 0) {
            search("Cerca...")
            PCount("\(items.count) concerts")
            LazyVStack(spacing: 8) {
                ForEach(items, id: \.self) { c in
                    NavigationLink { PDetailView(name: "Concerts", id: c["ID"] ?? "") } label: {
                        PSimpleCard(title: (c["Títol"] ?? "").isEmpty ? (c["Agrupació"] ?? "") : (c["Títol"] ?? ""),
                                    sub: [Arxiu.fmtDate(c["Data"]), c["Hora"] ?? "", c["Lloc"] ?? "", c["Població"] ?? ""].filter { !$0.isEmpty }.joined(separator: " · "),
                                    tags: [(c["Agrupació"] ?? "", true), (c["Director/a"] ?? "", false)].filter { !$0.0.isEmpty })
                    }.buttonStyle(.plain)
                }
            }
            if items.isEmpty { PEmpty(text: "No hi ha res per mostrar.") }
        }
    }

    private var fagotades: some View {
        let items = store.rows("Fagotades").filter { matches($0) }.sorted { (Int($0["Any"] ?? "") ?? 0) > (Int($1["Any"] ?? "") ?? 0) }
        return VStack(alignment: .leading, spacing: 0) {
            search("Cerca...")
            LazyVStack(spacing: 8) {
                ForEach(items, id: \.self) { f in
                    let n = store.rows("Obres").filter { $0["Fagotada"] == f["Any"] }.count
                    NavigationLink { PDetailView(name: "Fagotades", id: f["Any"] ?? "") } label: {
                        PSimpleCard(title: "Fagotada " + (f["Any"] ?? ""), sub: [f["Lloc"] ?? "", f["Dates"] ?? ""].filter { !$0.isEmpty }.joined(separator: " · "),
                                    tags: [("\(n) obres", true)])
                    }.buttonStyle(.plain)
                }
            }
            if items.isEmpty { PEmpty(text: "No hi ha res per mostrar.") }
        }
    }

    private var simple: some View {
        let n = tab, k = Arxiu.keys[n] ?? ""
        let items = store.rows(n).filter { matches($0) }.sorted { Arxiu.sortNorm($0[k], $1[k]) }
        return VStack(alignment: .leading, spacing: 0) {
            search("Cerca...")
            LazyVStack(spacing: 8) {
                ForEach(items, id: \.self) { r in
                    let c = store.rows("Obres").filter { $0[k] == r[k] }.count + store.rows("Concerts").filter { $0[k] == r[k] }.count
                    NavigationLink { PDetailView(name: n, id: r[k] ?? "") } label: {
                        PSimpleCard(title: r[k] ?? "", sub: (r["Tipus"] ?? "").isEmpty ? (r["Agrupacions"] ?? "") : (r["Tipus"] ?? ""),
                                    tags: c > 0 ? [("\(c) registres", true)] : [])
                    }.buttonStyle(.plain)
                }
            }
            if items.isEmpty { PEmpty(text: "No hi ha res per mostrar.") }
        }
    }
}

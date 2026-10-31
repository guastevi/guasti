import SwiftUI
import QuickLook

struct CasaModule: GuastiModule {
    let id = "casa"
    let title = "Pis de Lloguer"
    let subtitle = "Gestió de casa"
    let systemImage = "house.fill"
    let tint = Color.white
    let tileText = Color.black
    let isAvailable = true

    @MainActor func makeRootView() -> AnyView {
        AnyView(CasaView())
    }
}

/// El llibre de la casa: el lloguer d'un cop d'ull, el que està pendent i els apartats.
struct CasaView: View {
    @ObservedObject private var store = CasaStore.shared
    @State private var query = ""
    @State private var nou: CasaTipus?
    @State private var importMsg: String?
    /// L'apartat obert. Amb botons i un sol destí: diversos NavigationLink dins d'una mateixa
    /// fila de List fan que en tornar enrere s'obri un altre cop la pantalla.
    @State private var obert: CasaTipus?
    @State private var carregat = false

    private let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

    var body: some View {
        List {
            if !query.isEmpty {
                let found = store.registres.filter { $0.matches(query) }.sorted { $0.data > $1.data }
                Section(found.isEmpty ? "No hi ha res amb «\(query)»" : "\(found.count) resultats") {
                    ForEach(found) { CasaRow(registre: $0, avui: store.avui) }
                }
            } else if store.dades == nil {
                Section {
                    if let error = store.errorMessage {
                        Text("No s'han pogut carregar les dades.\n\(error)")
                            .foregroundStyle(.secondary)
                    } else {
                        HStack { ProgressView(); Text("Carregant...").foregroundStyle(.secondary) }
                    }
                }
            } else {
                if let n = store.important {
                    Section {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text(n == 0 ? "Buscant factures i contractes al correu..." : "Portant documents del correu: \(n)")
                        }
                    }
                } else if let importMsg {
                    Section { Text(importMsg).font(Theme.body(14)).foregroundStyle(.secondary) }
                }
                pisSection
                if !store.avisos.isEmpty { avisosSection }
                Section {
                    NavigationLink { CasaConsumView() } label: {
                        Label("Consum de llum, aigua i gas", systemImage: "chart.bar.xaxis")
                    }
                }
                Section("Apartats") {
                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEach(CasaTipus.allCases) { t in
                            Button { obert = t } label: { tile(t) }
                                .buttonStyle(.plain)
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 10, leading: 0, bottom: 10, trailing: 0))
                    .listRowBackground(Color.clear)
                }
                if let error = store.errorMessage {
                    Section { Text(error).font(Theme.body(14)).foregroundStyle(CasaTheme.late) }
                }
            }
        }
        .navigationTitle("Pis de Lloguer")
        .searchable(text: $query, prompt: "Cerca factures, reparacions, documents...")
        .refreshable { await store.load() }
        .task {
            // Només en entrar a la secció, no cada cop que es torna d'un apartat
            guard !carregat else { return }
            carregat = true
            await store.load()
            if store.dades != nil, store.calImportarPrimerCop { importa() }
        }
        .tint(.primary)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if store.isLoading { ProgressView() }
                Menu {
                    ForEach(CasaTipus.allCases) { t in
                        Button { nou = t } label: { Label(t.singular, systemImage: t.icon) }
                    }
                    Divider()
                    Button { importa() } label: {
                        Label("Porta les factures del correu", systemImage: "envelope.arrow.triangle.branch")
                    }
                    .disabled(store.important != nil)
                    if let url = store.dades?.fullUrl.flatMap({ URL(string: $0) }) {
                        Divider()
                        Link(destination: url) { Label("Obre el full de Google", systemImage: "tablecells") }
                    }
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Afegeix")
            }
        }
        .sheet(item: $nou) { t in
            NavigationStack { CasaEditView(registre: .nou(t, avui: store.avui), isNew: true) }
        }
        .navigationDestination(item: $obert) { t in CasaLlistaView(tipus: t) }
    }

    private func importa() {
        importMsg = nil
        Task {
            do {
                let n = try await store.importaCorreus()
                if store.correusDeFons {
                    importMsg = "Les factures que falten s'estan portant soles, una mica cada minut. Estira cap avall d'aquí a una estona per veure-les."
                } else {
                    importMsg = n == 0 ? "Ja tens tots els documents del correu." : "S'han afegit \(n) documents del correu. A partir d'ara, els nous entren sols cada matí."
                }
            } catch {
                importMsg = error.localizedDescription
            }
        }
    }

    private var pisSection: some View {
        Section {
            if let c = store.contracte {
                NavigationLink { CasaDetallView(id: c.id) } label: {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(c.titol.isEmpty ? "El meu pis" : c.titol)
                            .font(Theme.display(20))
                            .foregroundStyle(Color.primary)
                        HStack(alignment: .top, spacing: 16) {
                            dada("Renda", store.rendaActual.map { CasaFmt.euros($0) + "/mes" } ?? "—")
                            if !c.venciment.isEmpty {
                                dada("Fi del contracte", CasaFmt.human(c.venciment))
                            }
                        }
                        if let a = store.properaActualitzacio {
                            Text("Propera actualització de renda: \(CasaFmt.human(a))")
                                .font(Theme.body(13, relativeTo: .footnote))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            } else {
                Button { nou = .contracte } label: {
                    Label("Afegeix el contracte de lloguer", systemImage: "signature")
                }
            }
        }
    }

    private func dada(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(Theme.body(12, relativeTo: .caption)).foregroundStyle(.secondary)
            Text(value).font(Theme.body(17, weight: .semibold))
        }
    }

    private var avisosSection: some View {
        Section("Pendent") {
            ForEach(store.avisos) { a in
                NavigationLink {
                    if let id = a.registreId { CasaDetallView(id: id) } else { CasaLlistaView(tipus: .renda) }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: a.icon)
                            .foregroundStyle(a.dies < 0 ? CasaTheme.late : CasaTheme.warn)
                            .frame(width: 26)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(a.text).font(Theme.body(16, weight: .medium))
                            Text(a.quan).font(Theme.body(13, relativeTo: .footnote))
                                .foregroundStyle(a.dies < 0 ? CasaTheme.late : .secondary)
                        }
                    }
                }
            }
        }
    }

    private func tile(_ t: CasaTipus) -> some View {
        let n = store.registres(t).count
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: t.icon).font(.system(size: 18, weight: .semibold))
                Spacer()
                if n > 0 { Text("\(n)").font(Theme.body(14, weight: .semibold)).opacity(0.85) }
            }
            Spacer(minLength: 0)
            Text(t.short).font(Theme.display(16)).lineLimit(1).minimumScaleFactor(0.7)
        }
        .foregroundStyle(Color.black)
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 78, alignment: .leading)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.15))
        )
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

/// Fila d'un registre a les llistes.
struct CasaRow: View {
    let registre: CasaRegistre
    let avui: String

    var body: some View {
        NavigationLink { CasaDetallView(id: registre.id) } label: {
            HStack(spacing: 12) {
                Image(systemName: registre.kind.icon)
                    .foregroundStyle(CasaTheme.green)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(registre.displayTitle).font(Theme.body(16, weight: .medium)).lineLimit(1)
                    Text(subtitle).font(Theme.body(13, relativeTo: .footnote)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 8)
                trailing
            }
        }
    }

    private var subtitle: String {
        var parts: [String] = []
        if !registre.qui.isEmpty { parts.append(registre.qui) }
        if !registre.data.isEmpty { parts.append(CasaFmt.human(registre.data)) }
        if !registre.fitxers.isEmpty { parts.append("📎 \(registre.fitxers.count)") }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder private var trailing: some View {
        switch registre.kind {
        case .manteniment:
            if let d = CasaFmt.dies(fins: registre.venciment, avui: avui) {
                chip(d < 0 ? "Tocava" : CasaFmt.falten(d), color: d < 0 ? CasaTheme.late : (d <= 30 ? CasaTheme.warn : .secondary))
            }
        case .reparacio:
            chip(registre.estat.isEmpty ? "Pendent" : registre.estat,
                 color: registre.estat == "Fet" ? CasaTheme.green : CasaTheme.warn)
        default:
            if let v = registre.importValue {
                Text(CasaFmt.euros(v)).font(Theme.body(15, weight: .semibold))
            }
        }
    }

    private func chip(_ text: String, color: Color) -> some View {
        Text(text)
            .font(Theme.body(12, weight: .semibold, relativeTo: .caption))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.12), in: Capsule())
    }
}

/// Tots els registres d'un apartat.
struct CasaLlistaView: View {
    let tipus: CasaTipus
    @ObservedObject private var store = CasaStore.shared
    @State private var nou = false
    @State private var any = String(CasaFmt.string(Date()).prefix(4))

    var body: some View {
        let items = store.registres(tipus)
        List {
            if tipus == .factura, !items.isEmpty {
                resumFactures(items)
                Section {
                    NavigationLink { CasaConsumView() } label: {
                        Label("Consum any a any", systemImage: "chart.bar.xaxis")
                    }
                }
            }
            if tipus == .renda, let r = store.rendaActual {
                Section {
                    LabeledContent("Renda d'ara", value: CasaFmt.euros(r) + "/mes")
                    if let a = store.properaActualitzacio {
                        LabeledContent("Propera actualització", value: CasaFmt.human(a))
                    }
                }
            }
            if items.isEmpty {
                Section {
                    Text(buit).foregroundStyle(.secondary)
                    Button { nou = true } label: { Label("Afegeix-ne", systemImage: "plus") }
                }
            } else if tipus == .factura {
                // Les factures de l'any triat, per subministrament: Llum, Aigua, Gas...
                let delAny = items.filter { $0.data.hasPrefix(any) }
                let grups = Dictionary(grouping: delAny, by: \.displayTitle)
                if delAny.isEmpty {
                    Section { Text("No hi ha factures del \(any).").foregroundStyle(.secondary) }
                }
                ForEach(grups.keys.sorted { (grups[$0]?.count ?? 0) > (grups[$1]?.count ?? 0) }, id: \.self) { nom in
                    Section(nom) {
                        ForEach(grups[nom] ?? []) { CasaRow(registre: $0, avui: store.avui) }
                    }
                }
            } else {
                Section {
                    ForEach(items) { CasaRow(registre: $0, avui: store.avui) }
                }
            }
        }
        .navigationTitle(tipus.short)
        .tint(.primary)
        .refreshable { await store.load() }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { nou = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Afegeix")
            }
        }
        .sheet(isPresented: $nou) {
            NavigationStack { CasaEditView(registre: .nou(tipus, avui: store.avui), isNew: true) }
        }
    }

    private var buit: String {
        switch tipus {
        case .contracte: return "Afegeix-hi el contracte: inici, final, renda i el PDF signat."
        case .renda: return "Cada cop que et pugin (o baixin) la renda, apunta-ho aquí."
        case .factura: return "Llum, aigua, gas, internet... amb la foto o el PDF de cada factura."
        case .reparacio: return "Què s'ha espatllat, qui ho arregla i quant ha costat."
        case .manteniment: return "Tasques que tornen: la revisió de la caldera, netejar filtres... T'avisa quan toquen."
        case .compra: return "Electrodomèstics i mobles, amb el tiquet i fins quan dura la garantia."
        case .document: return "Assegurança, cèdula, certificat energètic... tot a mà."
        }
    }

    @ViewBuilder private func resumFactures(_ items: [CasaRegistre]) -> some View {
        // Tots els anys seguits, del de la primera factura fins a l'actual
        let amb = items.compactMap { Int($0.data.prefix(4)) } + [Int(any), Int(CasaFmt.string(Date()).prefix(4))].compactMap { $0 }
        let anys = (amb.min()!...amb.max()!).reversed().map(String.init)
        let r = store.facturesAny(any)
        Section {
            Picker("Any", selection: $any) {
                ForEach(anys, id: \.self) { Text($0).tag($0) }
            }
            LabeledContent("Total", value: CasaFmt.euros(r.total))
                .font(Theme.body(17, weight: .semibold))
            ForEach(r.perTipus, id: \.0) { nom, total in
                LabeledContent(nom, value: CasaFmt.euros(total))
            }
        }
    }
}

/// La fitxa d'un registre, amb els seus documents.
struct CasaDetallView: View {
    let id: String
    @ObservedObject private var store = CasaStore.shared
    @State private var editing = false
    @State private var busy = false
    @State private var errorText: String?
    @State private var preview: URL?
    @State private var opening: String?

    var body: some View {
        Group {
            if let r = store.registre(id) {
                content(r)
            } else {
                ContentUnavailableView("Ja no hi és", systemImage: "trash")
            }
        }
        .tint(.primary)
        .quickLookPreview($preview)
    }

    private func content(_ r: CasaRegistre) -> some View {
        let t = r.kind
        return List {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Label(t.singular, systemImage: t.icon)
                        .font(Theme.body(13, weight: .medium, relativeTo: .footnote))
                        .foregroundStyle(Color.primary)
                    Text(r.displayTitle).font(Theme.display(24))
                }
                .padding(.vertical, 4)
            }

            Section {
                if !r.data.isEmpty { LabeledContent(t.dataLabel, value: CasaFmt.human(r.data)) }
                if let l = t.importLabel, let v = r.importValue {
                    LabeledContent(l, value: CasaFmt.euros(v) + (t == .contracte || t == .renda ? "/mes" : ""))
                }
                if let l = t.quiLabel, !r.qui.isEmpty { LabeledContent(l, value: r.qui) }
                if t == .reparacio { LabeledContent("Estat", value: r.estat.isEmpty ? "Pendent" : r.estat) }
                if let l = t.vencimentLabel, !r.venciment.isEmpty {
                    LabeledContent(l) {
                        VStack(alignment: .trailing, spacing: 1) {
                            Text(CasaFmt.human(r.venciment))
                            if let d = CasaFmt.dies(fins: r.venciment, avui: store.avui) {
                                Text(CasaFmt.falten(d)).font(Theme.body(12, relativeTo: .caption))
                                    .foregroundStyle(d < 0 ? CasaTheme.late : .secondary)
                            }
                        }
                    }
                }
                if t == .manteniment, let n = Int(r.cada), n > 0 {
                    LabeledContent("Cada", value: n == 1 ? "1 mes" : (n % 12 == 0 ? (n == 12 ? "any" : "\(n / 12) anys") : "\(n) mesos"))
                }
            }

            if t == .manteniment {
                Section {
                    Button { run { try await store.fet(r) } } label: {
                        Label("Fet avui", systemImage: "checkmark.circle.fill")
                    }
                    .disabled(busy)
                } footer: {
                    Text("Apunta que ho has fet avui i calcula la propera vegada.")
                }
            }
            if t == .reparacio, r.estat != "Fet" {
                Section {
                    Button {
                        var copy = r
                        copy.estat = "Fet"
                        run { try await store.desa(copy) }
                    } label: { Label("Marca com a arreglat", systemImage: "checkmark.circle.fill") }
                    .disabled(busy)
                }
            }

            if !r.notes.isEmpty {
                Section("Notes") { Text(r.notes).textSelection(.enabled) }
            }

            Section("Documents i fotos") {
                ForEach(r.fitxers) { f in
                    Button { obre(f) } label: {
                        HStack {
                            Image(systemName: f.isPDF ? "doc.richtext" : (f.isImage ? "photo" : "doc"))
                                .foregroundStyle(CasaTheme.green)
                            Text(f.nom).foregroundStyle(.primary).lineLimit(1)
                            Spacer()
                            if opening == f.id { ProgressView() }
                        }
                    }
                    .swipeActions {
                        Button(role: .destructive) { run { try await store.treuFitxer(r.id, f) } } label: {
                            Label("Treu", systemImage: "trash")
                        }
                    }
                }
                CasaAfegirFitxer { nom, mime, data in
                    run { try await store.pujaFitxer(r.id, nom: nom, mime: mime, data: data) }
                }
                .disabled(busy)
            }

            if let errorText {
                Section { Text(errorText).foregroundStyle(CasaTheme.late) }
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if busy { ProgressView() }
                Button("Edita") { editing = true }
            }
        }
        .sheet(isPresented: $editing) {
            NavigationStack { CasaEditView(registre: r, isNew: false) }
        }
    }

    private func obre(_ f: CasaFitxer) {
        opening = f.id
        Task {
            defer { opening = nil }
            do {
                preview = try await store.obre(f)
            } catch {
                errorText = error.localizedDescription
            }
        }
    }

    private func run(_ work: @escaping () async throws -> Void) {
        busy = true
        errorText = nil
        Task {
            defer { busy = false }
            do { try await work() } catch { errorText = error.localizedDescription }
        }
    }
}

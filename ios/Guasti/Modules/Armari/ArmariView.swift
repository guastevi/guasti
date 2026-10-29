import SwiftUI
import LocalAuthentication

struct ArmariView: View {
    @ObservedObject private var store = ArmariStore.shared

    @State private var search = ""
    @State private var tipus: String?
    @State private var temporada: String?
    @State private var ubicacio: String?
    @State private var color: String?
    @State private var showPrivate = false
    @State private var creating = false
    @AppStorage("armari.sort") private var sort: ArmariSort = .armari

    private let columns = [GridItem(.adaptive(minimum: 105), spacing: 10)]

    private var filtered: [Peca] {
        let list = store.peces.filter { p in
            (showPrivate || !p.isPrivate)
                && (tipus == nil || ArmariCatalog.group(p) == ArmariCatalog.group(Peca(id: "", tipus: tipus!)))
                && (temporada == nil || p.temporada == temporada || p.temporada == "Tot l'any")
                && (ubicacio == nil || p.ubicacio == ubicacio)
                && (color == nil || p.colors.contains(color!))
                && (search.isEmpty || p.searchText.localizedStandardContains(search))
        }
        return sorted(list)
    }

    private func sorted(_ list: [Peca]) -> [Peca] {
        let pos = Dictionary(store.peces.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { a, _ in a })
        let byNom: (Peca, Peca) -> Bool = { $0.nom.localizedCompare($1.nom) == .orderedAscending }
        switch sort {
        case .noves:
            return list.sorted { (pos[$0.id] ?? 0) > (pos[$1.id] ?? 0) }
        case .nom:
            return list.sorted { a, b in
                ArmariCatalog.group(a) != ArmariCatalog.group(b) ? ArmariCatalog.group(a) < ArmariCatalog.group(b) : byNom(a, b)
            }
        case .ubicacio:
            let idx: (Peca) -> Int = { ArmariCatalog.ubicacions.firstIndex(of: $0.ubicacio) ?? ArmariCatalog.ubicacions.count }
            return list.sorted { a, b in
                if idx(a) != idx(b) { return idx(a) < idx(b) }
                if a.ubicacio != b.ubicacio { return a.ubicacio.localizedCompare(b.ubicacio) == .orderedAscending }
                return byNom(a, b)
            }
        case .armari:
            return list.sorted { a, b in
                if ArmariCatalog.group(a) != ArmariCatalog.group(b) { return ArmariCatalog.group(a) < ArmariCatalog.group(b) }
                let ia = ArmariCatalog.orderIndex(a), ib = ArmariCatalog.orderIndex(b)
                return ia != ib ? ia < ib : byNom(a, b)
            }
        }
    }

    private var hasFilters: Bool {
        temporada != nil || ubicacio != nil || color != nil
    }

    var body: some View {
        ScrollView {
            Picker("Tipus", selection: $tipus) {
                Text("Tot").tag(String?.none)
                ForEach(ArmariCatalog.tipus, id: \.self) { Text(ArmariCatalog.tipusLabel($0)).tag(Optional($0)) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.bottom, 8)
            if hasFilters {
                activeFilters
            }
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(filtered) { peca in
                    NavigationLink(value: PecaRoute(id: peca.id)) {
                        PecaCell(peca: peca)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)

            if !store.peces.isEmpty {
                Text(footer)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding()
            }
        }
        .overlay { emptyState }
        .navigationTitle("Armari")
        .navigationDestination(for: PecaRoute.self) { route in
            PecaDetailView(pecaID: route.id)
        }
        .searchable(text: $search, prompt: "Cerca nom, marca, notes…")
        .refreshable { await store.refresh() }
        .task { await store.refreshIfNeeded() }
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                filterMenu
                Button {
                    togglePrivate()
                } label: {
                    Image(systemName: showPrivate ? "lock.open.fill" : "lock.fill")
                }
                .accessibilityLabel(showPrivate ? "Amaga les privades" : "Mostra les privades")
                Button {
                    creating = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Peça nova")
            }
        }
        .sheet(isPresented: $creating) {
            NavigationStack {
                PecaEditView(peca: Peca.nova(), isNew: true)
            }
        }
        .safeAreaInset(edge: .bottom) {
            if let progress = store.downloadProgress {
                ProgressView(value: Double(progress.done), total: Double(max(progress.total, 1))) {
                    Text("Baixant fotos \(progress.done) de \(progress.total)")
                        .font(.footnote)
                }
                .padding()
                .background(.bar)
            }
        }
    }

    private var footer: String {
        var text = "\(filtered.count) peces"
        if let lastSync = store.lastSync {
            text += " · actualitzat \(lastSync.formatted(.relative(presentation: .named)))"
        }
        return text
    }

    @ViewBuilder
    private var emptyState: some View {
        if store.peces.isEmpty {
            if store.isLoading {
                ProgressView("Carregant l'armari…")
            } else if let error = store.errorMessage {
                ContentUnavailableView {
                    Label("No s'ha pogut carregar", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(error)
                } actions: {
                    Button("Torna-ho a provar") { Task { await store.refresh() } }
                }
            }
        } else if filtered.isEmpty {
            ContentUnavailableView.search
        }
    }

    private var filterMenu: some View {
        Menu {
            Picker("Ordre", selection: $sort) {
                ForEach(ArmariSort.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.menu)
            filterPicker("Temporada", values: store.values(\.temporada), selection: $temporada)
            filterPicker("Ubicació", values: store.values(\.ubicacio), selection: $ubicacio)
            filterPicker("Color", values: store.values(\.color), selection: $color)
            if hasFilters {
                Button("Treu els filtres", role: .destructive) { clearFilters() }
            }
            Divider()
            Button {
                Task { await store.downloadAllCovers() }
            } label: {
                Label("Baixa les fotos per veure-les sense connexió", systemImage: "icloud.and.arrow.down")
            }
            .disabled(store.downloadProgress != nil)
        } label: {
            Image(systemName: hasFilters ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
        }
        .accessibilityLabel("Filtres")
    }

    private func filterPicker(_ title: String, values: [String], selection: Binding<String?>) -> some View {
        Picker(selection: selection) {
            Text("Tots").tag(String?.none)
            ForEach(values, id: \.self) { value in
                Text(value).tag(Optional(value))
            }
        } label: {
            Text(title)
            if let value = selection.wrappedValue { Text(value) }
        }
        .pickerStyle(.menu)
    }

    private var activeFilters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack {
                chip(temporada) { temporada = nil }
                chip(ubicacio) { ubicacio = nil }
                chip(color) { color = nil }
            }
            .padding(.horizontal)
        }
        .padding(.bottom, 4)
    }

    @ViewBuilder
    private func chip(_ value: String?, clear: @escaping () -> Void) -> some View {
        if let value {
            Button(action: clear) {
                HStack(spacing: 4) {
                    Text(value)
                    Image(systemName: "xmark")
                        .font(.caption2.weight(.bold))
                }
                .font(.subheadline)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.pink.opacity(0.15), in: Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    private func clearFilters() {
        temporada = nil
        ubicacio = nil
        color = nil
    }

    private func togglePrivate() {
        if showPrivate {
            showPrivate = false
            return
        }
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            showPrivate = true
            return
        }
        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Mostrar les peces privades") { ok, _ in
            DispatchQueue.main.async {
                if ok { showPrivate = true }
            }
        }
    }
}

struct PecaCell: View {
    let peca: Peca

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Color.clear
                .aspectRatio(3 / 4, contentMode: .fit)
                .overlay(DrivePhoto(path: peca.portada, size: .thumb))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(alignment: .topTrailing) {
                    if peca.isPrivate {
                        Image(systemName: "lock.fill")
                            .font(.caption2)
                            .padding(5)
                            .background(.ultraThinMaterial, in: Circle())
                            .padding(6)
                    }
                }
            Text(peca.nom.isEmpty ? "Sense nom" : peca.nom)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
            Text([peca.talla, peca.marca].filter { !$0.isEmpty }.joined(separator: " · "))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .contentShape(Rectangle())
    }
}

import SwiftUI
import LocalAuthentication

/// Pantalla d'entrada de l'Armari, com la de l'app web.
struct ArmariHomeView: View {
    @ObservedObject private var store = ArmariStore.shared
    @State private var creating = false

    private var publicPeces: [Peca] { store.peces.filter { !$0.isPrivate } }

    private var latest: [Peca] {
        Array(publicPeces.filter { !store.photos(for: $0).isEmpty }.suffix(4).reversed())
    }

    private var countText: String {
        if store.peces.isEmpty {
            if store.isLoading { return "Carregant…" }
            return store.errorMessage ?? "Encara no hi ha cap peça"
        }
        let n = publicPeces.count
        return n == 1 ? "1 peça guardada" : "\(n) peces guardades"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 4) {
                    (Text("Armari\n") + Text("Guasteví").foregroundColor(Theme.tint))
                        .font(Theme.display(44))
                    Text(countText)
                        .foregroundStyle(store.errorMessage != nil && store.peces.isEmpty ? .red : .secondary)
                }

                if !latest.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Últimes afegides")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
                        HStack(spacing: 8) {
                            ForEach(latest) { peca in
                                NavigationLink {
                                    PecaDetailView(pecaID: peca.id)
                                } label: {
                                    Color.clear
                                        .aspectRatio(3 / 4, contentMode: .fit)
                                        .overlay(DrivePhoto(path: store.photos(for: peca).first?.path ?? ""))
                                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(peca.nom)
                            }
                            ForEach(latest.count..<4, id: \.self) { _ in Color.clear.aspectRatio(3 / 4, contentMode: .fit) }
                        }
                    }
                }

                VStack(spacing: 12) {
                    Button {
                        creating = true
                    } label: {
                        choice("plus", "Afegeix una peça", "Fes fotos i guarda on la tens", primary: true)
                    }
                    .buttonStyle(.plain)
                    NavigationLink {
                        ArmariView()
                    } label: {
                        choice("square.grid.2x2", "Veure l'armari", "Galeria amb filtres i cerca", primary: false)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(20)
        }
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await store.refresh() }
        .task { await store.refreshIfNeeded() }
        .sheet(isPresented: $creating) {
            NavigationStack {
                PecaEditView(peca: Peca.nova(), isNew: true)
            }
        }
    }

    private func choice(_ icon: String, _ title: String, _ subtitle: String, primary: Bool) -> some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title2.weight(.semibold))
                .frame(width: 48, height: 48)
                .background(primary ? Color.white.opacity(0.16) : Color.gray.opacity(0.14),
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Theme.body(17, weight: .semibold, relativeTo: .headline))
                Text(subtitle).font(Theme.body(15, relativeTo: .subheadline)).opacity(0.8)
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(primary ? Color.white : Color.primary)
        .padding(.horizontal, 20)
        .padding(.vertical, 22)
        .background(primary ? Theme.accent : Color(.secondarySystemBackground),
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .contentShape(Rectangle())
    }
}

/// La galeria ("L'armari") amb els mateixos filtres que l'app web.
struct ArmariView: View {
    @ObservedObject private var store = ArmariStore.shared

    @State private var search = ""
    @State private var tipus: String?
    @State private var temporada: String?
    @State private var nom: String?
    @State private var ubicacio: String?
    @State private var color: String?
    @State private var showPrivate = false
    @State private var creating = false
    @AppStorage("armari.sort") private var sort: ArmariSort = .armari

    private static let calcat = "__calcat"
    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 14)]

    private var visible: [Peca] { store.peces.filter { showPrivate || !$0.isPrivate } }

    private var filtered: [Peca] {
        let words = search.lowercased().split(separator: " ").map(String.init)
        let list = visible.filter { p in
            if let t = temporada, !(p.temporada == t || (p.temporada == "Tot l'any" && t != "Tot l'any")) { return false }
            if let t = tipus, ArmariCatalog.group(p) != ArmariCatalog.group(Peca(id: "", tipus: t)) { return false }
            if nom == Self.calcat {
                if !ArmariCatalog.shoes.contains(ArmariCatalog.kind(of: p.nom)) { return false }
            } else if let n = nom, ArmariCatalog.kind(of: p.nom) != n { return false }
            if let u = ubicacio, p.ubicacio != u { return false }
            if let c = color, !p.colors.contains(c) { return false }
            if !words.isEmpty {
                let hay = p.searchText.lowercased()
                if !words.allSatisfy({ hay.contains($0) }) { return false }
            }
            return true
        }
        return sorted(list)
    }

    private func sorted(_ list: [Peca]) -> [Peca] {
        let pos = Dictionary(store.peces.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { a, _ in a })
        let ca = Locale(identifier: "ca")
        func cmp(_ a: String, _ b: String) -> ComparisonResult { a.compare(b, locale: ca) }
        let byNom: (Peca, Peca) -> Bool = { cmp($0.nom, $1.nom) == .orderedAscending }
        let kindCmp: (Peca, Peca) -> ComparisonResult = { cmp(ArmariCatalog.kind(of: $0.nom), ArmariCatalog.kind(of: $1.nom)) }
        let locIdx: (Peca) -> Int = { p in
            if let i = ArmariCatalog.ubicacions.firstIndex(of: p.ubicacio) { return i }
            return p.ubicacio.isEmpty ? ArmariCatalog.ubicacions.count + 1 : ArmariCatalog.ubicacions.count
        }
        let base: (Peca, Peca) -> Bool
        switch sort {
        case .noves:
            return list.sorted { (pos[$0.id] ?? 0) > (pos[$1.id] ?? 0) }
        case .nom:
            base = byNom
        case .ubicacio:
            base = { a, b in
                if locIdx(a) != locIdx(b) { return locIdx(a) < locIdx(b) }
                let c = cmp(a.ubicacio, b.ubicacio)
                return c != .orderedSame ? c == .orderedAscending : byNom(a, b)
            }
        case .peca:
            base = { a, b in
                let c = kindCmp(a, b)
                return c != .orderedSame ? c == .orderedAscending : byNom(a, b)
            }
        case .armari:
            base = { a, b in
                let ia = ArmariCatalog.orderIndex(a), ib = ArmariCatalog.orderIndex(b)
                if ia != ib { return ia < ib }
                let c = kindCmp(a, b)
                return c != .orderedSame ? c == .orderedAscending : byNom(a, b)
            }
        }
        return list.sorted { a, b in
            let ga = ArmariCatalog.group(a), gb = ArmariCatalog.group(b)
            return ga != gb ? ga < gb : base(a, b)
        }
    }

    private var usedKinds: [String] {
        Array(Set(visible.map { ArmariCatalog.kind(of: $0.nom) }.filter { !$0.isEmpty }))
            .sorted { $0.compare($1, locale: Locale(identifier: "ca")) == .orderedAscending }
    }

    private var usedLocations: [String] {
        Array(Set(visible.map(\.ubicacio).filter { !$0.isEmpty })).sorted()
    }

    private var usedColors: [String] {
        let used = Set(visible.flatMap(\.colors))
        let known = ArmariCatalog.colors.map(\.name).filter { used.contains($0) }
        return known + used.filter { u in !ArmariCatalog.colors.contains { $0.name == u } }.sorted()
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                Picker("Tipus", selection: $tipus) {
                    Text("Tot").tag(String?.none)
                    ForEach(ArmariCatalog.tipus, id: \.self) { Text(ArmariCatalog.tipusLabel($0)).tag(Optional($0)) }
                }
                .pickerStyle(.segmented)
                Picker("Temporada", selection: $temporada) {
                    Text("Totes").tag(String?.none)
                    ForEach(ArmariCatalog.temporades, id: \.self) { Text($0).tag(Optional($0)) }
                }
                .pickerStyle(.segmented)
                HStack(spacing: 10) {
                    menu(nom == Self.calcat ? "Tot el calçat" : (nom ?? "Totes les peces")) {
                        Button("Totes les peces") { nom = nil }
                        if usedKinds.contains(where: { ArmariCatalog.shoes.contains($0) }) {
                            Button("Tot el calçat") { nom = Self.calcat }
                        }
                        ForEach(usedKinds, id: \.self) { k in Button(k) { nom = k } }
                    }
                    menu(ubicacio ?? "Totes les ubicacions") {
                        Button("Totes les ubicacions") { ubicacio = nil }
                        ForEach(usedLocations, id: \.self) { l in Button(l) { ubicacio = l } }
                    }
                }
                menu(sort.title) {
                    ForEach(ArmariSort.allCases) { s in Button(s.title) { sort = s } }
                }
                if !usedColors.isEmpty {
                    colorRow
                }
            }
            .padding(.horizontal)

            HStack {
                Text(store.peces.isEmpty ? "" : "\(filtered.count) de \(visible.count) peces")
                    .font(Theme.body(13, relativeTo: .footnote))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Spacer()
            }
            .padding(.horizontal)
            .padding(.top, 8)

            LazyVGrid(columns: columns, spacing: 14) {
                ForEach(filtered) { peca in
                    NavigationLink {
                        PecaDetailView(pecaID: peca.id)
                    } label: {
                        PecaCell(peca: peca, fotos: store.photos(for: peca))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 90)
        }
        .overlay { emptyState }
        .overlay(alignment: .bottomTrailing) {
            Button {
                creating = true
            } label: {
                Image(systemName: "plus")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 58, height: 58)
                    .background(Theme.accent, in: Circle())
                    .shadow(color: .black.opacity(0.25), radius: 12, y: 6)
            }
            .padding(18)
            .accessibilityLabel("Afegeix una peça")
        }
        .navigationTitle("L'armari")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: "Cerca per nom, marca, color…")
        .refreshable { await store.refresh() }
        .task { await store.refreshIfNeeded() }
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    togglePrivate()
                } label: {
                    Image(systemName: showPrivate ? "lock.open.fill" : "lock.fill")
                }
                .tint(showPrivate ? Theme.tint : nil)
                .accessibilityLabel(showPrivate ? "Amaga l'apartat privat" : "Mostra l'apartat privat")
                Menu {
                    Button {
                        Task { await store.downloadAllCovers() }
                    } label: {
                        Label("Baixa les fotos per veure-les sense connexió", systemImage: "icloud.and.arrow.down")
                    }
                    .disabled(store.downloadProgress != nil)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
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
                        .font(Theme.body(13, relativeTo: .footnote))
                }
                .padding()
                .background(.bar)
            }
        }
    }

    private func menu<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        Menu {
            content()
        } label: {
            HStack {
                Text(title).lineLimit(1)
                Spacer(minLength: 4)
                Image(systemName: "chevron.up.chevron.down").font(Theme.body(12, relativeTo: .caption))
            }
            .font(Theme.body(15, relativeTo: .subheadline))
            .foregroundStyle(.primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    private var colorRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(usedColors, id: \.self) { c in
                    Button {
                        color = color == c ? nil : c
                    } label: {
                        ColorSwatch(name: c, size: 30)
                            .padding(2)
                            .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(color == c ? Theme.accent : .clear, lineWidth: 2))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(c)
                }
                if color != nil {
                    Button("Tots els colors") { color = nil }
                        .font(Theme.body(13, relativeTo: .footnote))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color(.secondarySystemFill), in: Capsule())
                        .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
        }
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
            } else {
                ContentUnavailableView {
                    Label("L'armari és buit", systemImage: "tshirt")
                } description: {
                    Text("Afegeix la primera peça.")
                }
            }
        } else if filtered.isEmpty {
            ContentUnavailableView {
                Label("Cap peça coincideix amb els filtres", systemImage: "line.3.horizontal.decrease.circle")
            } actions: {
                Button("Treu els filtres") { clearFilters() }
            }
        }
    }

    private func clearFilters() {
        tipus = nil
        temporada = nil
        nom = nil
        ubicacio = nil
        color = nil
        search = ""
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
        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Mostrar l'apartat privat") { ok, _ in
            DispatchQueue.main.async {
                if ok { showPrivate = true }
            }
        }
    }
}

struct PecaCell: View {
    let peca: Peca
    let fotos: [Foto]

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Color.clear
                .aspectRatio(3 / 4, contentMode: .fit)
                .overlay(PhotoStrip(fotos: fotos))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(alignment: .topLeading) {
                    if peca.isPrivate {
                        Text("Privada")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Theme.accent, in: Capsule())
                            .padding(6)
                    }
                }
            Text(peca.nom.isEmpty ? "Sense nom" : peca.nom)
                .font(Theme.body(15, weight: .semibold, relativeTo: .subheadline))
                .lineLimit(2)
            Text([peca.talla.isEmpty ? "" : "Talla \(peca.talla)", peca.ubicacio].filter { !$0.isEmpty }.joined(separator: " · "))
                .font(Theme.body(12, relativeTo: .caption))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .contentShape(Rectangle())
    }
}

/// Les fotos d'una peça a la graella: es passen lliscant (davant, darrere…), amb puntets a sota.
struct PhotoStrip: View {
    let fotos: [Foto]
    @State private var index = 0

    var body: some View {
        if fotos.count < 2 {
            DrivePhoto(path: fotos.first?.path ?? "", size: .thumb)
        } else {
            TabView(selection: $index) {
                ForEach(Array(fotos.enumerated()), id: \.element.id) { i, foto in
                    DrivePhoto(path: foto.path, size: .thumb)
                        .tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .overlay(alignment: .bottom) {
                HStack(spacing: 4) {
                    ForEach(fotos.indices, id: \.self) { i in
                        Circle()
                            .fill(i == index ? Theme.accent : Color.black.opacity(0.25))
                            .frame(width: 5, height: 5)
                    }
                }
                .padding(.bottom, 7)
                .allowsHitTesting(false)
            }
        }
    }
}

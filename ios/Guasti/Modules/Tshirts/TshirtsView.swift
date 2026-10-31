import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct TshirtsModule: GuastiModule {
    let id = "guastevitshirts"
    let title = "guastevitshirts"
    let subtitle = "Els meus dibuixos"
    let systemImage = "paintbrush.pointed.fill"
    let tint = Color(UIColor(hex: 0xF7C600)) // groc viu
    let isAvailable = true

    @MainActor func makeRootView() -> AnyView {
        AnyView(TshirtsView())
    }
}

/// Una botiga meva: la web pública i, per dins com a propietària, les vendes i la gestió.
private struct Botiga: Identifiable {
    let nom: String
    let domini: String
    let icon: String
    let visitar: String
    var vendes: String? = nil
    var gestio: String? = nil
    var id: String { nom }
}

private let botigues: [Botiga] = [
    Botiga(nom: "Redbubble", domini: "redbubble.com", icon: "bag",
           visitar: "https://www.redbubble.com/people/guastevi/shop",
           vendes: "https://www.redbubble.com/account/sales/by_sale",
           gestio: "https://www.redbubble.com/studio/dashboard"),
    Botiga(nom: "TeePublic", domini: "teepublic.com", icon: "cart",
           visitar: "https://www.teepublic.com/user/guastevi",
           vendes: "https://www.teepublic.com/account",
           gestio: "https://www.teepublic.com/design/quick_create"),
    Botiga(nom: "La Tostadora", domini: "latostadora.com", icon: "tshirt",
           visitar: "https://www.latostadora.com/guastevi/",
           vendes: "https://www.latostadora.com/login/",
           gestio: "https://www.latostadora.com/login/"),
    Botiga(nom: "Amazon Merch", domini: "merch.amazon.com", icon: "shippingbox",
           visitar: "https://www.amazon.es/s?k=guastevi",
           vendes: "https://merch.amazon.com/analyze",
           gestio: "https://merch.amazon.com/manage/products"),
    Botiga(nom: "Bandcamp", domini: "bandcamp.com", icon: "music.note",
           visitar: "https://guastevi.bandcamp.com/",
           vendes: "https://guastevi.bandcamp.com/tools",
           gestio: "https://bandcamp.com/login"),
    Botiga(nom: "Spreadshirt", domini: "spreadshirt.es", icon: "tshirt.fill",
           visitar: "https://www.spreadshirt.es/shop/user/guastevi/",
           vendes: "https://partner.spreadshirt.es/statistics",
           gestio: "https://partner.spreadshirt.es/designs"),
    Botiga(nom: "Webnode", domini: "webnode.com", icon: "globe",
           visitar: "https://guastevitshirts.webnode.es/",
           gestio: "https://www.webnode.com/login/"),
    Botiga(nom: "Instagram", domini: "instagram.com", icon: "camera",
           visitar: "https://www.instagram.com/guastevitshirts/",
           gestio: "https://business.facebook.com/latest/home"),
]

/// Quadres petits amb el logo de cada botiga. En tocar-ne un: visitar-la o entrar-hi com a propietària.
private struct BotiguesGrid: View {
    @Environment(\.openURL) private var openURL
    private let columns = [GridItem(.adaptive(minimum: 76), spacing: 8)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(botigues) { b in
                Menu {
                    obrir("Visitar la botiga", "eye", b.visitar)
                    if let v = b.vendes { obrir("Vendes", "chart.bar", v) }
                    if let g = b.gestio { obrir("Entrar a gestionar", "pencil", g) }
                } label: {
                    BotigaTile(botiga: b)
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder private func obrir(_ title: String, _ icon: String, _ url: String) -> some View {
        if let u = URL(string: url) {
            Button { openURL(u) } label: { Label(title, systemImage: icon) }
        }
    }
}

private struct BotigaTile: View {
    let botiga: Botiga

    private var logoURL: URL? {
        URL(string: "https://www.google.com/s2/favicons?sz=128&domain=\(botiga.domini)")
    }

    var body: some View {
        VStack(spacing: 6) {
            AsyncImage(url: logoURL) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFit()
                } else {
                    Image(systemName: botiga.icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Theme.tint)
                }
            }
            .frame(width: 30, height: 30)
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

            Text(botiga.nom)
                .font(Theme.body(11, weight: .semibold, relativeTo: .caption))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .padding(.horizontal, 4)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

/// Fons darrere els PNG transparents: clar, fosc o quadrícula.
enum TshirtFons: String, CaseIterable {
    case clar, fosc, quadricula

    var icon: String {
        switch self {
        case .clar: return "sun.max"
        case .fosc: return "moon"
        case .quadricula: return "checkerboard.rectangle"
        }
    }

    var next: TshirtFons {
        let all = Self.allCases
        return all[(all.firstIndex(of: self)! + 1) % all.count]
    }

    @ViewBuilder var view: some View {
        switch self {
        case .clar: Color.white
        case .fosc: Color(white: 0.08)
        case .quadricula: Checkerboard()
        }
    }
}

private struct Checkerboard: View {
    var body: some View {
        Canvas { ctx, size in
            let s: CGFloat = 10
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.white))
            for y in stride(from: 0, to: size.height, by: s) {
                for x in stride(from: 0, to: size.width, by: s) where (Int(x / s) + Int(y / s)) % 2 == 0 {
                    ctx.fill(Path(CGRect(x: x, y: y, width: s, height: s)), with: .color(Color(white: 0.88)))
                }
            }
        }
    }
}

/// La galeria de dibuixos.
struct TshirtsView: View {
    enum Ordre: String, CaseIterable {
        case recents, nom
        var title: String { self == .recents ? "Més recents" : "Per nom" }
    }

    enum Mida: String, CaseIterable {
        case petit, mitja, gran
        var title: String { ["Petits", "Mitjans", "Grans"][Self.allCases.firstIndex(of: self)!] }
        var minimum: CGFloat { [70, 110, 150][Self.allCases.firstIndex(of: self)!] }
    }

    /// Filtre de la galeria: tots, els que falten per revisar o una categoria.
    private static let tots = "__tots"
    private static let perRevisar = "__rev"

    @ObservedObject private var store = TshirtsStore.shared
    @ObservedObject private var cats = TshirtsCats.shared
    @State private var search = ""
    @State private var filtre = TshirtsView.tots
    @State private var instrumentFiltre = ""
    @State private var etiquetaFiltre = ""
    @AppStorage("tshirts.mida") private var mida: Mida = .petit
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var pickingPhotos = false
    @State private var pickingFiles = false
    @State private var confirmRepetits = false
    @State private var traientRepetits = false
    @ObservedObject private var folderSync = TshirtsFolderSync.shared
    @AppStorage("tshirts.fons") private var fons: TshirtFons = .clar
    @AppStorage("tshirts.ordre") private var ordre: Ordre = .recents

    private var columns: [GridItem] { [GridItem(.adaptive(minimum: mida.minimum), spacing: mida == .petit ? 6 : 12)] }

    /// Els dibuixos de la categoria triada (abans de filtrar per instrument i per text).
    private var inCategory: [Dibuix] {
        switch filtre {
        case Self.tots: return store.dibuixos
        case Self.perRevisar: return store.dibuixos.filter { !cats.revisat($0) }
        default: return store.dibuixos.filter { cats.categoria($0) == filtre }
        }
    }

    /// A l'inici no es veuen tots els dibuixos: només les carpetes (categories i etiquetes)
    /// i, a sota, els que encara no s'han revisat.
    private var inici: Bool {
        filtre == Self.tots && search.isEmpty && etiquetaFiltre.isEmpty && instrumentFiltre.isEmpty
    }

    private var filtered: [Dibuix] {
        let words = search.lowercased().split(separator: " ").map(String.init)
        let base = inici ? store.dibuixos.filter { !cats.revisat($0) } : inCategory
        let list = base.filter { d in
            if !instrumentFiltre.isEmpty && cats.instrument(d) != instrumentFiltre { return false }
            if !etiquetaFiltre.isEmpty && !cats.etiquetes(d).contains(etiquetaFiltre) { return false }
            guard !words.isEmpty else { return true }
            let text = ([d.name, cats.categoria(d), cats.instrument(d)] + cats.etiquetes(d)).joined(separator: " ").lowercased()
            return words.allSatisfy { text.contains($0) }
        }
        switch ordre {
        case .recents: return list.sorted { $0.created > $1.created }
        case .nom: return list.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }
    }

    private var countText: String {
        if store.dibuixos.isEmpty {
            if store.isLoading { return "Carregant…" }
            return store.errorMessage ?? "Encara no hi ha cap dibuix. Toca + per pujar-ne."
        }
        let n = store.dibuixos.count
        return n == 1 ? "1 dibuix" : "\(n) dibuixos"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    (Text("guasteví") + Text("tshirts").foregroundColor(Theme.tint))
                        .font(Theme.display(40))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text(countText)
                        .font(Theme.body(15, relativeTo: .subheadline))
                        .foregroundStyle(store.errorMessage != nil && store.dibuixos.isEmpty ? .red : .secondary)
                }

                BotiguesGrid()

                if !store.dibuixos.isEmpty { filtres }

                if let u = store.uploading {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Pujant \(min(u.done + 1, u.total)) de \(u.total)…")
                            .font(Theme.body(15, relativeTo: .subheadline))
                    }
                }
                if let error = store.errorMessage, !store.dibuixos.isEmpty {
                    Text(error)
                        .font(Theme.body(13, relativeTo: .footnote))
                        .foregroundStyle(.red)
                }

                if inici && !store.dibuixos.isEmpty {
                    carpetes
                    let n = filtered.count
                    if n > 0 {
                        Text(n == 1 ? "1 dibuix per revisar" : "\(n) dibuixos per revisar")
                            .font(Theme.body(13, weight: .bold, relativeTo: .footnote))
                            .foregroundStyle(.secondary)
                    }
                }

                LazyVGrid(columns: columns, spacing: mida == .petit ? 6 : 12) {
                    ForEach(filtered) { dibuix in
                        NavigationLink {
                            DibuixDetailView(dibuixID: dibuix.id)
                        } label: {
                            DibuixCell(dibuix: dibuix, fons: fons, showName: mida != .petit)
                        }
                        .buttonStyle(.plain)
                        .contextMenu { TshirtCategoryMenu(dibuix: dibuix) }
                    }
                }
            }
            .padding(16)
        }
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $search, prompt: "Cerca per nom")
        .refreshable {
            await store.refresh()
            await cats.refresh()
            TshirtsFolderSync.shared.scheduleSync()
        }
        .task {
            await store.refreshIfNeeded()
            await cats.refreshIfNeeded()
            TshirtsFolderSync.shared.scheduleSync()
        }
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Menu {
                    Picker("Ordre", selection: $ordre) {
                        ForEach(Ordre.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    Picker("Mida", selection: $mida) {
                        ForEach(Mida.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    Button { fons = fons.next } label: { Label("Canvia el fons", systemImage: fons.icon) }
                    Button { pickingFiles = true } label: {
                        Label(folderSync.connected ? "Carpeta d'iCloud connectada (canvia-la)" : "Connecta la carpeta d'iCloud", systemImage: "icloud")
                    }
                } label: {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                }
                .accessibilityLabel("Ordre i fons")
                Menu {
                    Button { pickingPhotos = true } label: { Label("Des de Fotos", systemImage: "photo.on.rectangle") }
                    Button { pickingFiles = true } label: { Label("Des de Fitxers (fitxers o una carpeta sencera)", systemImage: "folder") }
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Puja dibuixos")
                .disabled(store.uploading != nil)
            }
        }
        .photosPicker(isPresented: $pickingPhotos, selection: $pickerItems, matching: .images)
        .onChange(of: pickerItems) { _, items in
            guard !items.isEmpty else { return }
            pickerItems = []
            Task {
                var files: [(data: Data, name: String?)] = []
                for item in items {
                    if let data = try? await item.loadTransferable(type: Data.self) { files.append((data, nil)) }
                }
                await store.upload(files)
            }
        }
        .fileImporter(isPresented: $pickingFiles, allowedContentTypes: [.image, .folder], allowsMultipleSelection: true) { result in
            guard case .success(let urls) = result else { return }
            Task { await store.upload(urls: urls) }
        }
    }
}

extension TshirtsView {
    /// Les carpetes de l'inici: una per categoria i una per etiqueta, amb el primer dibuix de portada.
    @ViewBuilder var carpetes: some View {
        let revisats = store.dibuixos.filter { cats.revisat($0) }
        let perCat: [(String, [Dibuix])] = cats.categories.compactMap { c in
            let l = revisats.filter { cats.categoria($0) == c }
            return l.isEmpty ? nil : (c, l)
        }
        let perTag: [(String, [Dibuix])] = cats.allEtiquetes.compactMap { t in
            let l = store.dibuixos.filter { cats.etiquetes($0).contains(t) }
            return l.isEmpty ? nil : (t, l)
        }
        if !perCat.isEmpty || !perTag.isEmpty {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 10)], spacing: 10) {
                ForEach(perCat, id: \.0) { c, l in
                    Button { tria(c) } label: { TshirtCarpeta(nom: c, icona: "folder.fill", dibuixos: l, fons: fons) }
                        .buttonStyle(.plain)
                }
                ForEach(perTag, id: \.0) { t, l in
                    Button { etiquetaFiltre = t } label: { TshirtCarpeta(nom: t, icona: "tag.fill", dibuixos: l, fons: fons) }
                        .buttonStyle(.plain)
                }
            }
        }
    }

    /// Categories (amb quants n'hi ha), instruments de la categoria triada i la revisió un per un.
    @ViewBuilder var filtres: some View {
        let pendents = store.dibuixos.filter { !cats.revisat($0) }.count
        let repetits = store.repetits.count
        VStack(alignment: .leading, spacing: 8) {
            if repetits > 0 {
                Button { confirmRepetits = true } label: {
                    HStack {
                        Image(systemName: "square.on.square")
                        Text(traientRepetits ? "Traient els repetits…" : "Hi ha \(repetits) dibuixos repetits. Treu-los")
                        Spacer()
                        if traientRepetits { ProgressView() }
                    }
                    .font(Theme.body(15, weight: .semibold, relativeTo: .subheadline))
                    .padding(12)
                    .background(Color.orange.opacity(0.18), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(traientRepetits)
                .confirmationDialog("S'han pujat dos cops (mateix nom i mateixa mida). Es queda el primer i els altres van a la paperera de Drive (s'hi poden recuperar 30 dies).",
                                    isPresented: $confirmRepetits, titleVisibility: .visible) {
                    Button("Treu-ne \(repetits)", role: .destructive) {
                        traientRepetits = true
                        Task { await store.treuRepetits(); traientRepetits = false }
                    }
                }
            }
            if let m = folderSync.lastMessage {
                Label(m, systemImage: "icloud").font(.footnote).foregroundStyle(.secondary)
            }
            if pendents > 0 {
                NavigationLink { TshirtsReviewView() } label: {
                    HStack {
                        Image(systemName: "checklist")
                        Text("Revisa les categories un per un")
                        Spacer()
                        Text("\(pendents)").bold()
                        Image(systemName: "chevron.right").font(.footnote)
                    }
                    .font(Theme.body(15, weight: .semibold, relativeTo: .subheadline))
                    .padding(12)
                    .background(Theme.tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    TshirtChip(title: "Inici", selected: filtre == Self.tots && etiquetaFiltre.isEmpty) { tria(Self.tots) }
                    ForEach(cats.categories, id: \.self) { c in
                        let n = store.dibuixos.filter { cats.categoria($0) == c }.count
                        if n > 0 { TshirtChip(title: c, count: n, selected: filtre == c) { tria(c) } }
                    }
                    if pendents > 0 {
                        TshirtChip(title: "Per revisar", count: pendents, selected: filtre == Self.perRevisar) { tria(Self.perRevisar) }
                    }
                }
            }
            let instruments = cats.instruments(in: inCategory)
            if filtre != Self.tots && instruments.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        TshirtChip(title: "Tots els instruments", selected: instrumentFiltre.isEmpty) { instrumentFiltre = "" }
                        ForEach(instruments, id: \.self) { i in
                            TshirtChip(title: i, selected: instrumentFiltre == i) { instrumentFiltre = i }
                        }
                    }
                }
            }
            let etiquetes = cats.allEtiquetes
            if !etiquetes.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        Image(systemName: "tag").foregroundStyle(.secondary)
                        ForEach(etiquetes, id: \.self) { t in
                            let n = inCategory.filter { cats.etiquetes($0).contains(t) }.count
                            TshirtChip(title: t, count: n, selected: etiquetaFiltre == t) {
                                etiquetaFiltre = etiquetaFiltre == t ? "" : t
                            }
                        }
                    }
                }
            }
        }
    }

    private func tria(_ f: String) {
        filtre = f
        instrumentFiltre = ""
        etiquetaFiltre = ""
    }
}

/// Una carpeta de l'inici: portada (el primer dibuix), nom i quants n'hi ha.
private struct TshirtCarpeta: View {
    let nom: String
    let icona: String
    let dibuixos: [Dibuix]
    let fons: TshirtFons

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            fons.view
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    if let d = dibuixos.first { DibuixImage(id: d.id, size: .thumb).padding(8) }
                }
                .overlay(alignment: .topLeading) {
                    Image(systemName: icona)
                        .font(.caption)
                        .foregroundStyle(Theme.tint)
                        .padding(6)
                }
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.primary.opacity(0.08)))
            HStack(spacing: 4) {
                Text(nom).lineLimit(1)
                Spacer(minLength: 0)
                Text("\(dibuixos.count)").foregroundStyle(.secondary)
            }
            .font(Theme.body(13, weight: .semibold, relativeTo: .footnote))
        }
        .contentShape(Rectangle())
    }
}

private struct DibuixCell: View {
    let dibuix: Dibuix
    let fons: TshirtFons
    var showName = true

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            fons.view
                .aspectRatio(1, contentMode: .fit)
                .overlay(DibuixImage(id: dibuix.id, size: .thumb).padding(showName ? 8 : 4))
                .clipShape(RoundedRectangle(cornerRadius: showName ? 14 : 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: showName ? 14 : 8, style: .continuous).stroke(Color.primary.opacity(0.08)))
            if showName {
                Text(dibuix.name)
                    .font(Theme.body(14, weight: .medium, relativeTo: .subheadline))
                    .lineLimit(1)
            }
        }
        .contentShape(Rectangle())
    }
}

/// Un dibuix de Drive (ajustat, sense retallar).
struct DibuixImage: View {
    let id: String
    var size: TshirtLoader.Size = .thumb

    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image).resizable().scaledToFit()
            } else if failed {
                Image(systemName: "photo").font(.title).foregroundStyle(.tertiary)
            } else {
                ProgressView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: id + size.rawValue) {
            failed = false
            if size != .thumb, image == nil {
                image = await TshirtLoader.shared.image(id: id, size: .thumb)
            }
            if let better = await TshirtLoader.shared.image(id: id, size: size) {
                image = better
            } else if image == nil {
                failed = true
            }
        }
    }
}

/// Un dibuix a pantalla completa: zoom, fons, compartir, canviar el nom i eliminar.
struct DibuixDetailView: View {
    let dibuixID: String

    @ObservedObject private var store = TshirtsStore.shared
    @ObservedObject private var cats = TshirtsCats.shared
    @Environment(\.dismiss) private var dismiss
    @AppStorage("tshirts.fons") private var fons: TshirtFons = .clar
    @State private var shareURL: URL?
    @State private var renaming = false
    @State private var newName = ""
    @State private var confirmDelete = false
    @State private var working = false
    @State private var error: String?
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1

    private var dibuix: Dibuix? { store.dibuixos.first { $0.id == dibuixID } }

    var body: some View {
        Group {
            if let dibuix {
                VStack(spacing: 0) {
                    fons.view
                        .overlay(
                            DibuixImage(id: dibuix.id, size: .full)
                                .padding(16)
                                .scaleEffect(scale)
                                .gesture(
                                    MagnificationGesture()
                                        .onChanged { scale = max(1, min(lastScale * $0, 6)) }
                                        .onEnded { _ in lastScale = scale }
                                )
                                .onTapGesture(count: 2) {
                                    withAnimation { scale = scale > 1 ? 1 : 2.5 }
                                    lastScale = scale
                                }
                        )
                        .clipped()

                    VStack(alignment: .leading, spacing: 4) {
                        Text(dibuix.name)
                            .font(Theme.display(22))
                        Menu {
                            TshirtCategoryMenu(dibuix: dibuix)
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "folder")
                                Text([cats.categoria(dibuix), cats.instrument(dibuix)].filter { !$0.isEmpty }.joined(separator: " · ")
                                    .ifEmpty("Sense categoria"))
                                if !cats.revisat(dibuix) { Text("(suggeriment)").foregroundStyle(.secondary) }
                            }
                            .font(Theme.body(14, weight: .semibold, relativeTo: .subheadline))
                        }
                        if let date = dibuix.date {
                            Text(date.formatted(date: .long, time: .shortened))
                                .font(Theme.body(14, relativeTo: .subheadline))
                                .foregroundStyle(.secondary)
                        }
                        if let error {
                            Text(error).font(Theme.body(13, relativeTo: .footnote)).foregroundStyle(.red)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                }
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        Button { fons = fons.next } label: { Image(systemName: fons.icon) }
                            .accessibilityLabel("Canvia el fons")
                        if let shareURL {
                            ShareLink(item: shareURL) { Image(systemName: "square.and.arrow.up") }
                        } else {
                            ProgressView()
                        }
                        Menu {
                            Button {
                                newName = dibuix.name
                                renaming = true
                            } label: { Label("Canvia el nom", systemImage: "pencil") }
                            Button(role: .destructive) { confirmDelete = true } label: { Label("Elimina", systemImage: "trash") }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                        .disabled(working)
                    }
                }
                .task(id: dibuix.name) {
                    shareURL = await TshirtLoader.shared.fileURL(id: dibuix.id, name: dibuix.name)
                }
                .alert("Canvia el nom", isPresented: $renaming) {
                    TextField("Nom", text: $newName)
                    Button("Desa") { Task { await rename(dibuix) } }
                    Button("Cancel·la", role: .cancel) {}
                }
                .alert("Eliminar «\(dibuix.name)»?", isPresented: $confirmDelete) {
                    Button("Elimina", role: .destructive) { Task { await delete(dibuix) } }
                    Button("Cancel·la", role: .cancel) {}
                } message: {
                    Text("Anirà a la paperera del Drive i el podràs recuperar durant 30 dies.")
                }
            } else {
                ContentUnavailableView("Aquest dibuix ja no hi és", systemImage: "photo")
            }
        }
    }

    private func rename(_ dibuix: Dibuix) async {
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name != dibuix.name else { return }
        working = true
        defer { working = false }
        do {
            try await store.rename(dibuix, to: name)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func delete(_ dibuix: Dibuix) async {
        working = true
        defer { working = false }
        do {
            try await store.delete(dibuix)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

private extension String {
    func ifEmpty(_ other: String) -> String { isEmpty ? other : self }
}

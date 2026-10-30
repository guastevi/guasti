import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct TshirtsModule: GuastiModule {
    let id = "guastevitshirts"
    let title = "guastevitshirts"
    let subtitle = "Els meus dibuixos"
    let systemImage = "paintbrush.pointed.fill"
    let tint = Theme.accent
    let isAvailable = true

    @MainActor func makeRootView() -> AnyView {
        AnyView(TshirtsView())
    }
}

/// Les botigues i webs on hi ha els dissenys.
private let botigues: [(nom: String, icon: String, url: String)] = [
    ("Webnode", "globe", "https://guastevitshirts.webnode.es/"),
    ("Bandcamp", "music.note", "https://guastevi.bandcamp.com/"),
    ("La Tostadora", "tshirt", "https://www.latostadora.com/guastevi/"),
    ("Redbubble", "bag", "https://www.redbubble.com/people/guastevi/shop"),
    ("TeePublic", "cart", "https://www.teepublic.com/user/guastevi"),
    ("Instagram", "camera", "https://www.instagram.com/guastevitshirts/"),
]

private struct BotiguesRow: View {
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(botigues, id: \.nom) { b in
                    if let url = URL(string: b.url) {
                        Link(destination: url) {
                            Label(b.nom, systemImage: b.icon)
                                .font(Theme.body(14, weight: .semibold, relativeTo: .subheadline))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Color(.secondarySystemBackground), in: Capsule())
                        }
                        .foregroundStyle(Theme.tint)
                    }
                }
            }
        }
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

    @ObservedObject private var store = TshirtsStore.shared
    @State private var search = ""
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var pickingPhotos = false
    @State private var pickingFiles = false
    @AppStorage("tshirts.fons") private var fons: TshirtFons = .clar
    @AppStorage("tshirts.ordre") private var ordre: Ordre = .recents

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 12)]

    private var filtered: [Dibuix] {
        let words = search.lowercased().split(separator: " ").map(String.init)
        let list = store.dibuixos.filter { d in
            words.isEmpty || words.allSatisfy { d.name.lowercased().contains($0) }
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

                BotiguesRow()

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

                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(filtered) { dibuix in
                        NavigationLink {
                            DibuixDetailView(dibuixID: dibuix.id)
                        } label: {
                            DibuixCell(dibuix: dibuix, fons: fons)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(16)
        }
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $search, prompt: "Cerca per nom")
        .refreshable { await store.refresh() }
        .task { await store.refreshIfNeeded() }
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Menu {
                    Picker("Ordre", selection: $ordre) {
                        ForEach(Ordre.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    Button { fons = fons.next } label: { Label("Canvia el fons", systemImage: fons.icon) }
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

private struct DibuixCell: View {
    let dibuix: Dibuix
    let fons: TshirtFons

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            fons.view
                .aspectRatio(1, contentMode: .fit)
                .overlay(DibuixImage(id: dibuix.id, size: .thumb).padding(8))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.primary.opacity(0.08)))
            Text(dibuix.name)
                .font(Theme.body(14, weight: .medium, relativeTo: .subheadline))
                .lineLimit(1)
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

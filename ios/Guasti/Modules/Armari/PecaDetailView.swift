import SwiftUI

struct PecaDetailView: View {
    let pecaID: String

    @ObservedObject private var store = ArmariStore.shared
    @Environment(\.dismiss) private var dismiss

    @State private var editing = false
    @State private var busy = false
    @State private var errorText: String?
    @State private var viewing: Foto?
    @State private var confirmDelete = false

    var body: some View {
        if let peca = store.peca(pecaID) {
            content(peca)
        } else {
            ContentUnavailableView("Aquesta peça ja no hi és", systemImage: "tshirt")
        }
    }

    private func content(_ peca: Peca) -> some View {
        let fotos = store.photos(for: peca)
        return List {
            Section {
                gallery(fotos, cover: peca.portada)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }

            Section {
                chips(peca)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
            }

            if !peca.ubicacio.isEmpty || !peca.talla.isEmpty || !peca.marca.isEmpty || !peca.colors.isEmpty {
                Section {
                    if !peca.ubicacio.isEmpty {
                        LabeledContent {
                            Text(peca.ubicacio)
                                .font(Theme.body(17, weight: .semibold))
                                .foregroundStyle(.primary)
                        } label: {
                            Label("Ubicació", systemImage: "mappin.and.ellipse")
                        }
                    }
                    row("Talla", peca.talla)
                    row("Marca", peca.marca)
                    if !peca.colors.isEmpty {
                        LabeledContent("Color") {
                            HStack(spacing: 6) {
                                ForEach(peca.colors, id: \.self) { c in
                                    ColorSwatch(name: c, size: 18)
                                    Text(c)
                                }
                            }
                        }
                    }
                }
            }

            if !peca.notes.isEmpty {
                Section("Notes") {
                    Text(peca.notes)
                }
            }

            Section {
                Button {
                    editing = true
                } label: {
                    Label("Edita", systemImage: "pencil")
                }
                Button(role: .destructive) {
                    confirmDelete = true
                } label: {
                    Label("Elimina", systemImage: "trash")
                }
            }
            .disabled(busy)
        }
        .navigationTitle(peca.nom.isEmpty ? "Peça" : peca.nom)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if busy {
                    ProgressView()
                } else {
                    Button("Edita") { editing = true }
                }
            }
        }
        .sheet(isPresented: $editing) {
            NavigationStack {
                PecaEditView(peca: peca, isNew: false) {
                    dismiss()
                }
            }
        }
        .confirmationDialog("Vols eliminar «\(peca.nom)» i les seves fotos?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Elimina", role: .destructive) {
                run {
                    try await store.delete(peca)
                    dismiss()
                }
            }
        } message: {
            Text("Les fotos aniran a la paperera de Drive.")
        }
        .fullScreenCover(item: $viewing) { foto in
            PhotoViewer(fotos: fotos, start: foto.id, title: peca.nom)
        }
        .alert("No s'ha pogut fer", isPresented: Binding(get: { errorText != nil }, set: { if !$0 { errorText = nil } })) {
            Button("D'acord", role: .cancel) {}
        } message: {
            Text(errorText ?? "")
        }
    }

    @ViewBuilder
    private func gallery(_ fotos: [Foto], cover: String) -> some View {
        if fotos.isEmpty {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color(.secondarySystemFill))
                Text("Sense fotos").foregroundStyle(.secondary)
            }
            .aspectRatio(4 / 3, contentMode: .fit)
        } else {
            // Totes les fotos de cop (davant, darrere…), petites. Tocant-ne una s'obre en gran.
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8),
                                GridItem(.flexible(), spacing: 8)], spacing: 8) {
                ForEach(Array(fotos.enumerated()), id: \.element.id) { i, foto in
                    Color.clear
                        .aspectRatio(3 / 4, contentMode: .fit)
                        .overlay(DrivePhoto(path: foto.path, size: .medium))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .contentShape(Rectangle())
                        .onTapGesture { viewing = foto }
                        .overlay(alignment: .bottomLeading) { tag(foto, isCover: i == 0) }
                }
            }
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private func tag(_ foto: Foto, isCover: Bool) -> some View {
        Group {
            if isCover {
                Text("Portada")
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Theme.accent, in: Capsule())
            } else if !foto.id.hasPrefix("portada-") {
                Button {
                    run {
                        try await store.setCover(foto)
                    }
                } label: {
                    Text("Portada?")
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.black.opacity(0.6), in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(busy)
            }
        }
        .font(Theme.body(10, relativeTo: .caption2))
        .padding(6)
    }

    private func chips(_ peca: Peca) -> some View {
        HStack(spacing: 6) {
            ForEach([peca.tipus.isEmpty ? "" : ArmariCatalog.tipusLabel(peca.tipus), peca.temporada,
                     peca.isPrivate ? "Privada" : ""].filter { !$0.isEmpty }, id: \.self) { chip in
                Text(chip)
                    .font(Theme.body(15, relativeTo: .subheadline))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color(.secondarySystemFill), in: Capsule())
            }
        }
    }

    @ViewBuilder
    private func row(_ title: String, _ value: String) -> some View {
        if !value.isEmpty {
            LabeledContent(title, value: value)
        }
    }

    private func run(_ action: @escaping () async throws -> Void) {
        Task {
            busy = true
            defer { busy = false }
            do {
                try await action()
            } catch {
                errorText = error.localizedDescription
            }
        }
    }
}

/// Foto a pantalla completa, amb zoom.
/// Fotos a pantalla sencera: es passen lliscant de costat, es tanquen amb la creu o lliscant cap avall,
/// i amb dos dits (o doble toc) s'amplien.
struct PhotoViewer: View {
    let fotos: [Foto]
    let start: String
    var title = ""
    @Environment(\.dismiss) private var dismiss
    @State private var current: String?
    @State private var sharing = false
    @State private var drag: CGFloat = 0
    @State private var zoomed = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.opacity(1 - min(Double(abs(drag)) / 400, 0.6)).ignoresSafeArea()
            ScrollView(.horizontal) {
                LazyHStack(spacing: 0) {
                    ForEach(fotos) { foto in
                        ZoomablePhoto(path: foto.path, zoomed: $zoomed)
                            .containerRelativeFrame([.horizontal, .vertical])
                            .id(foto.id)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollIndicators(.hidden)
            .scrollDisabled(zoomed)
            .scrollPosition(id: $current)
            .offset(y: drag)
            .simultaneousGesture(
                DragGesture(minimumDistance: 20)
                    .onChanged { v in
                        guard !zoomed, abs(v.translation.height) > abs(v.translation.width) else { return }
                        drag = max(0, v.translation.height)
                    }
                    .onEnded { v in
                        if !zoomed, v.translation.height > 120 { dismiss() } else { withAnimation { drag = 0 } }
                    }
            )
            .ignoresSafeArea()

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(Color.black.opacity(0.6), in: Circle())
                    .padding(16)
            }
            .zIndex(1)
            .accessibilityLabel("Tanca")

            ShareCircleButton(busy: sharing) { share() }
                .padding(16)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .zIndex(1)

            if fotos.count > 1 {
                HStack(spacing: 6) {
                    ForEach(fotos) { f in
                        Circle()
                            .fill(f.id == (current ?? start) ? Color.white : Color.white.opacity(0.35))
                            .frame(width: 7, height: 7)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, 24)
                .allowsHitTesting(false)
            }
        }
        .onAppear { current = start }
    }

    /// Comparteix o desa la foto que es veu ara, a la mida més gran.
    private func share() {
        guard let foto = fotos.first(where: { $0.id == (current ?? start) }) ?? fotos.first else { return }
        let n = (fotos.firstIndex(of: foto) ?? 0) + 1
        let name = (title.isEmpty ? "Foto" : title) + (fotos.count > 1 ? " \(n)" : "")
        sharing = true
        Task {
            defer { sharing = false }
            guard let image = await PhotoLoader.shared.image(path: foto.path, size: .full),
                  let url = ShareSheet.imageFile(image, name: name) else { return }
            ShareSheet.present([url])
        }
    }
}

private struct ZoomablePhoto: View {
    let path: String
    @Binding var zoomed: Bool
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1

    var body: some View {
        DrivePhoto(path: path, size: .full, contentMode: .fit)
            .scaleEffect(scale)
            .clipped()
            .contentShape(Rectangle())
            .onTapGesture(count: 2) {
                withAnimation { scale = scale > 1 ? 1 : 2.5 }
                lastScale = scale
                zoomed = scale > 1
            }
            .gesture(
                MagnificationGesture()
                    .onChanged { scale = max(1, lastScale * $0) }
                    .onEnded { _ in
                        lastScale = scale
                        zoomed = scale > 1
                    }
            )
    }
}

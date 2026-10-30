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
            PhotoViewer(path: foto.path)
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
struct PhotoViewer: View {
    let path: String
    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            DrivePhoto(path: path, size: .full, contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .scaleEffect(scale)
                .clipped()
                .gesture(
                    MagnificationGesture()
                        .onChanged { scale = max(1, lastScale * $0) }
                        .onEnded { _ in lastScale = scale }
                )
                .onTapGesture(count: 2) {
                    withAnimation { scale = scale > 1 ? 1 : 2.5 }
                    lastScale = scale
                }
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
        }
    }
}

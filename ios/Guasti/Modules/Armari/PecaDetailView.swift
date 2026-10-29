import SwiftUI
import PhotosUI

struct PecaDetailView: View {
    let pecaID: String

    @ObservedObject private var store = ArmariStore.shared
    @Environment(\.dismiss) private var dismiss

    @State private var editing = false
    @State private var pickerItem: PhotosPickerItem?
    @State private var showCamera = false
    @State private var uploading = false
    @State private var errorText: String?
    @State private var viewing: Foto?
    @State private var page: String?

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
                gallery(fotos)
                    .listRowInsets(EdgeInsets())
                HStack {
                    PhotosPicker(selection: $pickerItem, matching: .images) {
                        Label("Galeria", systemImage: "photo.on.rectangle")
                    }
                    Spacer()
                    if uploading {
                        ProgressView()
                        Spacer()
                    }
                    Button {
                        showCamera = true
                    } label: {
                        Label("Càmera", systemImage: "camera")
                    }
                }
                .buttonStyle(.borderless)
                .disabled(uploading)
            }

            Section {
                chips(peca)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
            }

            Section {
                if !peca.ubicacio.isEmpty {
                    LabeledContent {
                        Text(peca.ubicacio)
                            .font(.body.weight(.semibold))
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

            if !peca.notes.isEmpty {
                Section("Notes") {
                    Text(peca.notes)
                }
            }
        }
        .navigationTitle(peca.nom.isEmpty ? "Peça" : peca.nom)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edita") { editing = true }
            }
        }
        .sheet(isPresented: $editing) {
            NavigationStack {
                PecaEditView(peca: peca, isNew: false) {
                    dismiss()
                }
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { image in upload(image, to: peca.id) }
                .ignoresSafeArea()
        }
        .fullScreenCover(item: $viewing) { foto in
            PhotoViewer(path: foto.path)
        }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                    upload(image, to: peca.id)
                }
                pickerItem = nil
            }
        }
        .alert("No s'ha pogut fer", isPresented: Binding(get: { errorText != nil }, set: { if !$0 { errorText = nil } })) {
            Button("D'acord", role: .cancel) {}
        } message: {
            Text(errorText ?? "")
        }
    }

    @ViewBuilder
    private func gallery(_ fotos: [Foto]) -> some View {
        if fotos.isEmpty {
            DrivePhoto(path: "")
                .frame(height: 260)
        } else {
            TabView(selection: $page) {
                ForEach(fotos) { foto in
                    DrivePhoto(path: foto.path, size: .medium, contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color(.secondarySystemBackground))
                        .tag(Optional(foto.id))
                        .onTapGesture { viewing = foto }
                        .contextMenu { photoActions(foto) }
                }
            }
            .tabViewStyle(.page(indexDisplayMode: fotos.count > 1 ? .always : .never))
            .frame(height: 440)
        }
    }

    @ViewBuilder
    private func photoActions(_ foto: Foto) -> some View {
        if !foto.id.hasPrefix("portada-") {
            Button {
                run { try await store.setCover(foto) }
            } label: {
                Label("Fes-la portada", systemImage: "star")
            }
            Button(role: .destructive) {
                run { try await store.deletePhoto(foto) }
            } label: {
                Label("Elimina la foto", systemImage: "trash")
            }
        }
    }

    private func chips(_ peca: Peca) -> some View {
        HStack(spacing: 6) {
            ForEach([peca.tipus.isEmpty ? "" : ArmariCatalog.tipusLabel(peca.tipus), peca.temporada,
                     peca.isPrivate ? "Privada" : ""].filter { !$0.isEmpty }, id: \.self) { chip in
                Text(chip)
                    .font(.subheadline)
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

    private func upload(_ image: UIImage, to pecaID: String) {
        guard let jpeg = ImageUtil.jpegForUpload(image) else { return }
        run { try await store.addPhoto(jpeg, to: pecaID) }
    }

    private func run(_ action: @escaping () async throws -> Void) {
        Task {
            uploading = true
            defer { uploading = false }
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
                .scaleEffect(scale)
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
                Image(systemName: "xmark.circle.fill")
                    .font(.largeTitle)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.white)
                    .padding()
            }
            .accessibilityLabel("Tanca")
        }
    }
}

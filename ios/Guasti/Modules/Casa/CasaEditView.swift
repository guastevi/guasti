import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

/// Formulari d'un registre nou o d'edició. Els camps canvien segons l'apartat.
struct CasaEditView: View {
    @State var registre: CasaRegistre
    let isNew: Bool

    @ObservedObject private var store = CasaStore.shared
    @Environment(\.dismiss) private var dismiss

    @State private var saving = false
    @State private var errorText: String?
    @State private var pendents: [Pendent] = []
    @State private var confirmDelete = false

    struct Pendent: Identifiable {
        let id = UUID()
        let nom: String
        let mime: String
        let data: Data
    }

    private var t: CasaTipus { registre.kind }

    private var titolSuggeriments: [String] {
        var seen = Set<String>()
        let used = store.registres(t).map(\.titol)
        return (t.titolSuggeriments + used).filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    private var quiSuggeriments: [String] {
        var seen = Set<String>()
        return store.registres(t).map(\.qui).filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    var body: some View {
        Form {
            Section(t.titolLabel) {
                TextField(t.titolLabel, text: $registre.titol)
                if !titolSuggeriments.isEmpty {
                    suggeriments(titolSuggeriments) { registre.titol = $0 }
                }
            }

            Section {
                DatePicker(t.dataLabel, selection: dateBinding(\.data), displayedComponents: .date)
                if let l = t.importLabel {
                    LabeledContent(l) {
                        TextField("0,00 €", text: $registre.imp)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                }
                if let l = t.quiLabel {
                    LabeledContent(l) {
                        TextField(l, text: $registre.qui).multilineTextAlignment(.trailing)
                    }
                }
            } footer: {
                if !quiSuggeriments.isEmpty, t.quiLabel != nil {
                    suggeriments(quiSuggeriments) { registre.qui = $0 }
                }
            }

            if t == .reparacio {
                Section("Estat") {
                    Picker("Estat", selection: $registre.estat) {
                        ForEach(CasaFmt.estatsReparacio, id: \.self) { Text($0).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
            }

            if t == .manteniment {
                Section {
                    Picker("Cada quant", selection: $registre.cada) {
                        Text("Cada mes").tag("1")
                        Text("Cada 3 mesos").tag("3")
                        Text("Cada 6 mesos").tag("6")
                        Text("Cada any").tag("12")
                        Text("Cada 2 anys").tag("24")
                        Text("Cada 5 anys").tag("60")
                        Text("Un sol cop").tag("")
                    }
                    .onChange(of: registre.cada) { _, _ in recalculaPropera() }
                    .onChange(of: registre.data) { _, _ in recalculaPropera() }
                }
            }

            if let l = t.vencimentLabel {
                Section {
                    Toggle(l, isOn: Binding(
                        get: { !registre.venciment.isEmpty },
                        set: { on in registre.venciment = on ? defaultVenciment() : "" }
                    ))
                    if !registre.venciment.isEmpty {
                        DatePicker(l, selection: dateBinding(\.venciment), displayedComponents: .date)
                    }
                }
            }

            Section("Notes") {
                TextField(t.notesPlaceholder, text: $registre.notes, axis: .vertical)
                    .lineLimit(2...10)
            }

            if isNew {
                Section("Documents i fotos") {
                    ForEach(pendents) { p in
                        Label(p.nom, systemImage: p.mime.hasPrefix("image/") ? "photo" : "doc")
                    }
                    .onDelete { pendents.remove(atOffsets: $0) }
                    CasaAfegirFitxer { nom, mime, data in
                        pendents.append(Pendent(nom: nom, mime: mime, data: data))
                    }
                }
            }

            if let errorText {
                Section { Text(errorText).foregroundStyle(CasaTheme.late) }
            }

            if !isNew {
                Section {
                    Button("Esborra", role: .destructive) { confirmDelete = true }
                }
            }
        }
        .tint(CasaTheme.green)
        .navigationTitle(isNew ? t.singular : "Edita")
        .navigationBarTitleDisplayMode(.inline)
        .interactiveDismissDisabled(saving)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel·la") { dismiss() }.disabled(saving)
            }
            ToolbarItem(placement: .confirmationAction) {
                if saving { ProgressView() } else { Button("Desa", action: save).bold() }
            }
        }
        .confirmationDialog("Segur que vols esborrar-ho? Els documents aniran a la paperera de Drive.",
                            isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Esborra", role: .destructive, action: delete)
        }
    }

    private func suggeriments(_ items: [String], pick: @escaping (String) -> Void) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(items, id: \.self) { s in
                    Button(s) { pick(s) }
                        .font(Theme.body(13, relativeTo: .footnote))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(CasaTheme.green.opacity(0.12), in: Capsule())
                        .foregroundStyle(CasaTheme.green)
                        .buttonStyle(.plain)
                }
            }
        }
    }

    private func dateBinding(_ key: WritableKeyPath<CasaRegistre, String>) -> Binding<Date> {
        Binding(
            get: { CasaFmt.date(registre[keyPath: key]) ?? Date() },
            set: { registre[keyPath: key] = CasaFmt.string($0) }
        )
    }

    private func defaultVenciment() -> String {
        let base = CasaFmt.date(registre.data) ?? Date()
        let months: Int
        switch t {
        case .contracte: months = 60
        case .compra: months = 36
        case .manteniment: months = Int(registre.cada) ?? 12
        default: months = 12
        }
        let d = Calendar(identifier: .gregorian).date(byAdding: .month, value: months, to: base) ?? base
        return CasaFmt.string(d)
    }

    private func recalculaPropera() {
        guard t == .manteniment else { return }
        registre.venciment = (Int(registre.cada) ?? 0) > 0 ? defaultVenciment() : ""
    }

    private func save() {
        saving = true
        errorText = nil
        Task {
            defer { saving = false }
            do {
                let id = try await store.desa(registre)
                registre.id = id
                for (i, p) in pendents.enumerated() {
                    do {
                        try await store.pujaFitxer(id, nom: p.nom, mime: p.mime, data: p.data)
                    } catch {
                        pendents.removeFirst(i)
                        throw APIError(message: "S'ha desat, però no s'ha pogut pujar «\(p.nom)»: \(error.localizedDescription)")
                    }
                }
                dismiss()
            } catch {
                errorText = error.localizedDescription
            }
        }
    }

    private func delete() {
        saving = true
        Task {
            defer { saving = false }
            do {
                try await store.esborra(registre)
                dismiss()
            } catch {
                errorText = error.localizedDescription
            }
        }
    }
}

/// Botó per afegir un document: foto amb la càmera, de la galeria o un fitxer (PDF...).
struct CasaAfegirFitxer: View {
    let onFile: (String, String, Data) -> Void

    @State private var showCamera = false
    @State private var showPhotos = false
    @State private var showFiles = false
    @State private var photoItem: PhotosPickerItem?

    var body: some View {
        Menu {
            Button { showCamera = true } label: { Label("Fes una foto", systemImage: "camera") }
            Button { showPhotos = true } label: { Label("Tria de la galeria", systemImage: "photo.on.rectangle") }
            Button { showFiles = true } label: { Label("Tria un fitxer (PDF...)", systemImage: "folder") }
        } label: {
            Label("Afegeix un document", systemImage: "paperclip")
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { image in addImage(image) }.ignoresSafeArea()
        }
        .photosPicker(isPresented: $showPhotos, selection: $photoItem, matching: .images)
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                    addImage(image)
                }
                photoItem = nil
            }
        }
        .fileImporter(isPresented: $showFiles, allowedContentTypes: [.item]) { result in
            guard case .success(let url) = result else { return }
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url) else { return }
            let mime = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
            onFile(url.lastPathComponent, mime, data)
        }
    }

    private func addImage(_ image: UIImage) {
        guard let data = ImageUtil.jpegForUpload(image, maxSide: 2200) else { return }
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH.mm.ss"
        onFile("Foto \(f.string(from: Date())).jpg", "image/jpeg", data)
    }
}

import SwiftUI
import PhotosUI

/// Formulari de peça nova o d'edició, amb els mateixos camps i ordre que l'app web.
struct PecaEditView: View {
    @State var peca: Peca
    let isNew: Bool
    var onDeleted: () -> Void = {}

    @ObservedObject private var store = ArmariStore.shared
    @Environment(\.dismiss) private var dismiss

    @State private var saving = false
    @State private var status: String?
    @State private var errorText: String?
    @State private var addingLocation = false
    @State private var newLocation = ""
    @State private var otherNom = false
    @State private var items: [EditPhoto] = []
    @State private var removed: [Foto] = []
    @State private var reordered = false
    @State private var loaded = false
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var showPicker = false
    @State private var showCamera = false
    @State private var choosingSource = false

    private var nomOptions: [String] {
        var seen = Set<String>()
        let existing = store.peces.map { $0.nom.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        return (ArmariCatalog.kinds + existing).filter { seen.insert($0).inserted }
    }

    private var ubicacions: [String] {
        var seen = Set<String>()
        return (ArmariCatalog.ubicacions + store.peces.map(\.ubicacio) + [peca.ubicacio])
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    var body: some View {
        Form {
            photosSection

            Section("Peça") {
                Picker("Peça", selection: nomSelection) {
                    Text("Tria la peça").tag("")
                    ForEach(nomOptions, id: \.self) { Text($0).tag($0) }
                    Text("Una altra…").tag("__other")
                }
                if otherNom {
                    TextField("Escriu quina peça és", text: $peca.nom)
                }
            }

            Section("Tipus") {
                Picker("Tipus", selection: $peca.tipus) {
                    ForEach(ArmariCatalog.tipus, id: \.self) { Text(ArmariCatalog.tipusLabel($0)).tag($0) }
                }
                .pickerStyle(.segmented)
            }

            Section("Temporada") {
                Picker("Temporada", selection: $peca.temporada) {
                    ForEach(ArmariCatalog.temporades, id: \.self) { Text($0).tag($0) }
                }
                .pickerStyle(.segmented)
            }

            Section {
                LabeledContent("Talla") {
                    TextField("M, 38, 40…", text: $peca.talla).multilineTextAlignment(.trailing)
                }
                LabeledContent("Marca") {
                    TextField("Marca", text: $peca.marca).multilineTextAlignment(.trailing)
                }
            }

            Section {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 38), spacing: 10)], spacing: 10) {
                    ForEach(ArmariCatalog.colors, id: \.name) { c in
                        let on = peca.colors.contains(c.name)
                        Button {
                            toggleColor(c.name)
                        } label: {
                            ColorSwatch(name: c.name, size: 34)
                                .overlay {
                                    if on {
                                        Image(systemName: "checkmark")
                                            .font(.caption.weight(.bold))
                                            .foregroundStyle(.white)
                                            .shadow(radius: 2)
                                    }
                                }
                                .padding(2)
                                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(on ? Color.pink : .clear, lineWidth: 2))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(c.name)
                        .accessibilityAddTraits(on ? .isSelected : [])
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text(peca.color.isEmpty ? "Color · toca'n un o més" : "Color · \(peca.color)")
            }

            Section("Ubicació") {
                FlowLayout(spacing: 8) {
                    ForEach(ubicacions, id: \.self) { l in
                        pill(l, on: peca.ubicacio == l) { peca.ubicacio = peca.ubicacio == l ? "" : l }
                    }
                    pill("+ Un altre lloc", on: false, dashed: true) { addingLocation = true }
                }
                .padding(.vertical, 4)
                if addingLocation {
                    HStack {
                        TextField("Nom del lloc nou", text: $newLocation)
                            .onSubmit(addLocation)
                        Button("Afegeix", action: addLocation)
                    }
                }
            }

            Section {
                Toggle(isOn: Binding(get: { peca.isPrivate }, set: { peca.privada = $0 ? "Sí" : "" })) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Peça privada")
                        Text("No surt a la galeria ni a la cerca si no obres l'apartat privat")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Notes") {
                TextField("Per a quin concert, si cal planxar…", text: $peca.notes, axis: .vertical)
                    .lineLimit(2...8)
            }

            Section {
                Button {
                    Task { await save() }
                } label: {
                    HStack {
                        Spacer()
                        if saving { ProgressView().padding(.trailing, 6) }
                        Text(saving ? (status ?? "Desant…") : (isNew ? "Desa la peça" : "Desa els canvis"))
                            .font(.headline)
                        Spacer()
                    }
                }
                .disabled(saving)
            }
        }
        .navigationTitle(isNew ? "Nova peça" : "Edita la peça")
        .navigationBarTitleDisplayMode(.inline)
        .interactiveDismissDisabled(saving)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel·la") { dismiss() }
                    .disabled(saving)
            }
        }
        .onAppear(perform: load)
        .confirmationDialog("Afegeix fotos", isPresented: $choosingSource) {
            Button("Fes una foto") { showCamera = true }
            Button("Tria de la galeria") { showPicker = true }
        }
        .photosPicker(isPresented: $showPicker, selection: $pickerItems, maxSelectionCount: 10, matching: .images)
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { image in addNew(image) }
                .ignoresSafeArea()
        }
        .onChange(of: pickerItems) { _, picked in
            guard !picked.isEmpty else { return }
            Task {
                for item in picked {
                    if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                        addNew(image)
                    }
                }
                pickerItems = []
            }
        }
        .alert("No s'ha pogut desar", isPresented: Binding(get: { errorText != nil }, set: { if !$0 { errorText = nil } })) {
            Button("D'acord", role: .cancel) {}
        } message: {
            Text(errorText ?? "")
        }
    }

    // MARK: Fotos

    private var photosSection: some View {
        Section {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { i, item in
                        thumb(item, index: i)
                    }
                    Button {
                        choosingSource = true
                    } label: {
                        VStack(spacing: 6) {
                            Image(systemName: "plus").font(.title3)
                            Text("Afegeix fotos").font(.caption)
                        }
                        .foregroundStyle(.secondary)
                        .frame(width: 96, height: 128)
                        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [5])).foregroundStyle(.secondary))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical, 4)
            }
        } header: {
            Text("Fotos · la primera és la portada. Fes servir les fletxes per canviar l'ordre")
                .textCase(nil)
        }
    }

    private func thumb(_ item: EditPhoto, index i: Int) -> some View {
        Group {
            switch item.kind {
            case .existing(let foto):
                DrivePhoto(path: foto.path, size: .thumb)
            case .new(let photo):
                Image(uiImage: photo.preview).resizable().aspectRatio(contentMode: .fill)
            }
        }
        .frame(width: 96, height: 128)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(alignment: .topTrailing) {
            Button {
                remove(at: i)
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 26, height: 26)
                    .background(Color.black.opacity(0.6), in: Circle())
            }
            .buttonStyle(.plain)
            .padding(6)
            .accessibilityLabel("Treu la foto")
        }
        .overlay(alignment: .bottom) {
            HStack {
                if i == 0 {
                    Text("Portada")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Color.pink, in: Capsule())
                }
                Spacer(minLength: 0)
                if items.count > 1 {
                    arrow("chevron.left", enabled: i > 0) { move(i, i - 1) }
                        .accessibilityLabel("Mou a l'esquerra")
                    arrow("chevron.right", enabled: i < items.count - 1) { move(i, i + 1) }
                        .accessibilityLabel("Mou a la dreta")
                }
            }
            .padding(6)
        }
    }

    private func arrow(_ icon: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(Color.black.opacity(0.45), in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.35)
    }

    private func move(_ from: Int, _ to: Int) {
        guard items.indices.contains(from), items.indices.contains(to), from != to else { return }
        withAnimation { items.insert(items.remove(at: from), at: to) }
        reordered = true
    }

    private func remove(at i: Int) {
        let item = items.remove(at: i)
        if case .existing(let foto) = item.kind, !foto.id.hasPrefix("portada-") { removed.append(foto) }
        reordered = true
    }

    private func addNew(_ image: UIImage) {
        guard let jpeg = ImageUtil.jpegForUpload(image) else { return }
        items.append(EditPhoto(kind: .new(PendingPhoto(jpeg: jpeg, preview: UIImage(data: jpeg) ?? image))))
    }

    // MARK: Camps

    private var nomSelection: Binding<String> {
        Binding(
            get: { otherNom ? "__other" : (nomOptions.contains(peca.nom) ? peca.nom : (peca.nom.isEmpty ? "" : "__other")) },
            set: { v in
                if v == "__other" {
                    otherNom = true
                    if nomOptions.contains(peca.nom) { peca.nom = "" }
                    return
                }
                otherNom = false
                peca.nom = v
                if ArmariCatalog.intimate.contains(v) { peca.privada = "Sí" }
                if ArmariCatalog.home.contains(v) { peca.tipus = "Roba de casa" }
            }
        )
    }

    private func pill(_ title: String, on: Bool, dashed: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(on ? Color.white : (dashed ? Color.pink : Color.primary))
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(on ? Color.pink : Color.clear, in: Capsule())
                .overlay(Capsule().strokeBorder(on ? Color.pink : Color.gray.opacity(0.4),
                                                style: StrokeStyle(lineWidth: 1, dash: dashed ? [4] : [])))
        }
        .buttonStyle(.plain)
    }

    private func toggleColor(_ name: String) {
        var list = peca.colors
        if let i = list.firstIndex(of: name) { list.remove(at: i) } else { list.append(name) }
        peca.color = list.joined(separator: ", ")
    }

    private func addLocation() {
        let v = newLocation.trimmingCharacters(in: .whitespaces)
        if !v.isEmpty { peca.ubicacio = v }
        newLocation = ""
        addingLocation = false
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        if !peca.nom.isEmpty && !nomOptions.contains(peca.nom) { otherNom = true }
        if !isNew {
            items = store.photos(for: peca).map { EditPhoto(kind: .existing($0)) }
        }
    }

    // MARK: Desar

    private func save() async {
        peca.nom = peca.nom.trimmingCharacters(in: .whitespaces)
        peca.talla = peca.talla.trimmingCharacters(in: .whitespaces)
        peca.marca = peca.marca.trimmingCharacters(in: .whitespaces)
        peca.notes = peca.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if addingLocation { addLocation() }
        guard !peca.nom.isEmpty else {
            errorText = "Tria quina peça és."
            return
        }
        saving = true
        defer {
            saving = false
            status = nil
        }
        do {
            status = "Desant…"
            try await store.save(peca)
            for foto in removed {
                try await store.deletePhoto(foto)
            }
            removed = []
            let added = items.indices.filter { if case .new = items[$0].kind { return true } else { return false } }
            for (n, i) in added.enumerated() {
                status = "Pujant fotos \(n + 1) de \(added.count)…"
                if case .new(let photo) = items[i].kind {
                    let foto = try await store.addPhoto(photo.jpeg, to: peca.id)
                    items[i] = EditPhoto(kind: .existing(foto))
                }
            }
            if !items.isEmpty && (reordered || !added.isEmpty) {
                status = "Desant l'ordre…"
                let ids = items.compactMap { item -> String? in
                    if case .existing(let foto) = item.kind { return foto.id }
                    return nil
                }
                do {
                    try await store.reorder(ids, for: peca.id)
                } catch let error as APIError where error.message.hasPrefix("Acció desconeguda") {
                    if reordered {
                        errorText = "La peça s'ha desat, però per desar l'ordre de les fotos cal actualitzar l'script Guasti API."
                        return
                    }
                }
            }
            dismiss()
        } catch {
            errorText = error.localizedDescription
        }
    }
}

/// Una foto del formulari: una que ja és al Drive o una de nova que encara s'ha de pujar.
struct EditPhoto: Identifiable {
    enum Kind {
        case existing(Foto)
        case new(PendingPhoto)
    }
    let id = UUID()
    let kind: Kind
}

/// Col·loca els botons en files, com les "pastilles" d'ubicació de l'app web.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxX: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            maxX = max(maxX, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: min(maxX, width), height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

/// Camp de text amb un menú dels valors que ja fas servir, perquè no calgui escriure'ls.
struct SuggestField: View {
    let title: String
    @Binding var text: String
    let options: [String]
    /// Per al color: afegeix el valor ("Negre, Granat") en lloc de substituir-lo.
    var appends = false

    var body: some View {
        HStack {
            Text(title)
            TextField("—", text: $text)
                .multilineTextAlignment(.trailing)
                .foregroundStyle(.secondary)
            if !options.isEmpty {
                Menu {
                    ForEach(options, id: \.self) { option in
                        Button(option) { pick(option) }
                    }
                } label: {
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.footnote)
                }
            }
        }
    }

    private func pick(_ option: String) {
        let current = text.trimmingCharacters(in: .whitespaces)
        if appends, !current.isEmpty, !current.localizedCaseInsensitiveContains(option) {
            text = current + ", " + option
        } else {
            text = option
        }
    }
}

/// Una foto triada o feta abans de desar la peça.
struct PendingPhoto: Identifiable {
    let id = UUID()
    let jpeg: Data
    let preview: UIImage
}

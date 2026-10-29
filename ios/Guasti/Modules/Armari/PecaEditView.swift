import SwiftUI

struct PecaEditView: View {
    @State var peca: Peca
    let isNew: Bool
    var onDeleted: () -> Void = {}

    @ObservedObject private var store = ArmariStore.shared
    @Environment(\.dismiss) private var dismiss

    @State private var saving = false
    @State private var errorText: String?
    @State private var confirmDelete = false
    @State private var addingLocation = false
    @State private var newLocation = ""

    private var nomOptions: [String] {
        var seen = Set<String>()
        return (ArmariCatalog.ordre + store.values(\.nom)).filter { seen.insert($0).inserted }
    }

    private var ubicacions: [String] {
        var seen = Set<String>()
        return (ArmariCatalog.ubicacions + store.values(\.ubicacio) + [peca.ubicacio])
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    private func toggleColor(_ name: String) {
        var list = peca.colors
        if let i = list.firstIndex(of: name) { list.remove(at: i) } else { list.append(name) }
        peca.color = list.joined(separator: ", ")
    }

    var body: some View {
        Form {
            Section {
                SuggestField(title: "Peça", text: $peca.nom, options: nomOptions)
            }

            Section {
                Picker("Tipus", selection: $peca.tipus) {
                    ForEach(ArmariCatalog.tipus, id: \.self) { Text(ArmariCatalog.tipusLabel($0)).tag($0) }
                }
                .pickerStyle(.segmented)
                Picker("Temporada", selection: $peca.temporada) {
                    ForEach(ArmariCatalog.temporades, id: \.self) { Text($0).tag($0) }
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Tipus i temporada")
            }

            Section {
                SuggestField(title: "Talla", text: $peca.talla, options: store.values(\.talla))
                SuggestField(title: "Marca", text: $peca.marca, options: store.values(\.marca))
                Picker("Ubicació", selection: $peca.ubicacio) {
                    Text("—").tag("")
                    ForEach(ubicacions, id: \.self) { Text($0).tag($0) }
                }
                if addingLocation {
                    HStack {
                        TextField("Nom del lloc nou", text: $newLocation)
                        Button("Afegeix") {
                            let v = newLocation.trimmingCharacters(in: .whitespaces)
                            if !v.isEmpty { peca.ubicacio = v }
                            newLocation = ""
                            addingLocation = false
                        }
                    }
                } else {
                    Button("+ Un altre lloc") { addingLocation = true }
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
                                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(on ? Color.accentColor : .clear, lineWidth: 2))
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

            Section("Notes") {
                TextField("Notes", text: $peca.notes, axis: .vertical)
                    .lineLimit(3...8)
            }

            Section {
                Toggle("Privada", isOn: Binding(
                    get: { peca.isPrivate },
                    set: { peca.privada = $0 ? "Sí" : "" }
                ))
            } footer: {
                Text("Les peces privades només es veuen després de Face ID.")
            }

            if !isNew {
                Section {
                    Button("Elimina la peça", role: .destructive) { confirmDelete = true }
                }
            }
        }
        .navigationTitle(isNew ? "Peça nova" : "Edita")
        .navigationBarTitleDisplayMode(.inline)
        .disabled(saving)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel·la") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                if saving {
                    ProgressView()
                } else {
                    Button("Desa") { Task { await save() } }
                        .disabled(peca.nom.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .confirmationDialog("Segur que vols eliminar aquesta peça i les seves fotos?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Elimina", role: .destructive) { Task { await delete() } }
        } message: {
            Text("Les fotos van a la paperera de Drive i es poden recuperar durant 30 dies.")
        }
        .alert("No s'ha pogut desar", isPresented: Binding(get: { errorText != nil }, set: { if !$0 { errorText = nil } })) {
            Button("D'acord", role: .cancel) {}
        } message: {
            Text(errorText ?? "")
        }
    }

    private func save() async {
        saving = true
        defer { saving = false }
        do {
            try await store.save(peca)
            dismiss()
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func delete() async {
        saving = true
        defer { saving = false }
        do {
            try await store.delete(peca)
            dismiss()
            onDeleted()
        } catch {
            errorText = error.localizedDescription
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

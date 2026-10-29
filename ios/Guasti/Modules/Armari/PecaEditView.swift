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

    var body: some View {
        Form {
            Section {
                TextField("Nom de la peça", text: $peca.nom)
                    .font(.headline)
            }

            Section {
                SuggestField(title: "Tipus", text: $peca.tipus, options: store.values(\.tipus))
                SuggestField(title: "Temporada", text: $peca.temporada, options: store.values(\.temporada))
                SuggestField(title: "Ubicació", text: $peca.ubicacio, options: store.values(\.ubicacio))
                SuggestField(title: "Color", text: $peca.color, options: store.values(\.color), appends: true)
                SuggestField(title: "Talla", text: $peca.talla, options: store.values(\.talla))
                SuggestField(title: "Marca", text: $peca.marca, options: store.values(\.marca))
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

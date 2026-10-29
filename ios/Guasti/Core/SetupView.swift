import SwiftUI

struct SetupView: View {
    @ObservedObject private var connection = Connection.shared
    @Environment(\.dismiss) private var dismiss

    @State private var url = ""
    @State private var key = ""
    @State private var testing = false
    @State private var result: String?

    var body: some View {
        Form {
            Section {
                TextField("https://script.google.com/macros/s/…/exec", text: $url)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField("Clau (API_KEY)", text: $key)
            } header: {
                Text("Connexió amb Google")
            } footer: {
                Text("És l'URL de l'script Guasti API i la clau que hi vas posar a Propietats de l'script. Només cal fer-ho un cop.")
            }

            Section {
                Button {
                    Task { await test() }
                } label: {
                    HStack {
                        Text("Prova i desa")
                        if testing {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(testing || url.isEmpty || key.isEmpty)

                if let result {
                    Text(result)
                        .font(Theme.body(13, relativeTo: .footnote))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Configuració")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Tanca") { dismiss() }
            }
        }
        .onAppear {
            url = connection.baseURL
            key = connection.apiKey
        }
    }

    private func test() async {
        testing = true
        defer { testing = false }
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let parsed = URL(string: trimmed), parsed.scheme == "https" else {
            result = "L'URL no és vàlida."
            return
        }
        do {
            let _: Pong = try await AppsScriptClient(baseURL: parsed, key: key).call("ping")
            connection.baseURL = trimmed
            connection.apiKey = key
            result = "Connectat ✓"
            await ArmariStore.shared.refresh()
            dismiss()
        } catch {
            result = error.localizedDescription
        }
    }
}

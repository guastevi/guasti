import SwiftUI
import UIKit

struct XarxesModule: GuastiModule {
    let id = "xarxes"
    let title = "Xarxes"
    let subtitle = "Instagram i Facebook"
    let systemImage = "paperplane.fill"
    let tint = Xar.lila
    let isAvailable = true
    let logo: String? = "LogoAuditori"

    @MainActor func makeRootView() -> AnyView {
        AnyView(XarxesView())
    }
}

/// El publicador de l'Auditori: publicar alhora a Instagram i a la pàgina de Facebook.
/// Fa servir el mateix Apps Script que la web, a través d'ApiGuasti.gs.
struct XarxesView: View {
    enum Vista: String, CaseIterable {
        case nova, historial

        var title: String { self == .nova ? "Nova" : "Historial" }
        var icon: String { self == .nova ? "square.and.pencil" : "clock" }
    }

    @ObservedObject private var publicador = Publicador.shared
    @ObservedObject private var store = XarxesStore.shared
    @State private var vista: Vista = .nova
    @State private var connectant = false

    var body: some View {
        VStack(spacing: 0) {
            header
            if publicador.client == nil {
                senseConnexio
            } else {
                ScrollView {
                    Group {
                        switch vista {
                        case .nova: XarxesNova()
                        case .historial: XarxesHistorial()
                        }
                    }
                    .frame(maxWidth: 560)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                    .frame(maxWidth: .infinity)
                }
                .scrollDismissesKeyboard(.interactively)
                .refreshable {
                    if vista == .historial { await store.carregarHistorial() } else { await store.carregarFragments() }
                }
                nav
            }
        }
        .background(Xar.bg.ignoresSafeArea())
        .foregroundStyle(Xar.text)
        .tint(Xar.accent)
        .environment(\.colorScheme, .dark)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Xar.bg, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { connectant = true } label: { Image(systemName: "gearshape") }
                    .accessibilityLabel("Connexió amb el publicador")
            }
        }
        .sheet(isPresented: $connectant) {
            NavigationStack { PublicadorSetupView() }
        }
        .task { if store.fragments.isEmpty { await store.carregarFragments() } }
        .onChange(of: vista) { _, v in
            if v == .historial { Task { await store.carregarHistorial() } }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image("LogoAuditori")
                .resizable()
                .scaledToFit()
                .frame(height: 34)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(.white, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .accessibilityLabel("Auditori Josep Carreras")
            VStack(alignment: .leading, spacing: 1) {
                Text("Publicar a xarxes")
                    .font(.system(size: 20, weight: .heavy))
                Text("Instagram i Facebook de l'Auditori")
                    .font(.system(size: 13))
                    .foregroundStyle(Xar.muted)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 10)
    }

    private var senseConnexio: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "link")
                .font(.system(size: 36, weight: .semibold))
                .foregroundStyle(Xar.accent)
            Text("Connecta el publicador")
                .font(.system(size: 20, weight: .bold))
            Text("Només cal fer-ho un cop: enganxa l'enllaç de l'app del publicador, el que acaba en ?k=…")
                .font(.system(size: 15))
                .foregroundStyle(Xar.muted)
                .multilineTextAlignment(.center)
            Button("Connecta") { connectant = true }
                .buttonStyle(XarBoto())
                .frame(maxWidth: 260)
            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity)
    }

    private var nav: some View {
        HStack {
            ForEach(Vista.allCases, id: \.self) { v in
                Button {
                    vista = v
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: v.icon).font(.system(size: 22))
                        Text(v.title).font(.system(size: 13, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(6)
                    .foregroundStyle(vista == v ? Xar.accent : Xar.muted)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 8)
        .background(Xar.card.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) { Rectangle().fill(Xar.line).frame(height: 1) }
    }
}

/// Enganxar l'enllaç del publicador i comprovar que respon.
struct PublicadorSetupView: View {
    @ObservedObject private var publicador = Publicador.shared
    @Environment(\.dismiss) private var dismiss
    @State private var link = ""
    @State private var provant = false
    @State private var resultat: String?

    var body: some View {
        Form {
            Section {
                TextField("https://script.google.com/macros/s/…/exec?k=…", text: $link, axis: .vertical)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("Enganxa") { link = UIPasteboard.general.string ?? link }
            } header: {
                Text("Enllaç del publicador")
            } footer: {
                Text("És l'enllaç de l'app que fa servir l'equip, amb la clau ?k= al final. Es desa només en aquest iPhone.")
            }

            Section {
                Button {
                    Task { await provar() }
                } label: {
                    HStack {
                        Text("Prova i desa")
                        if provant {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(provant || link.isEmpty)

                if let resultat {
                    Text(resultat)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Publicador")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Tanca") { dismiss() }
            }
        }
        .onAppear { link = publicador.link }
    }

    private func provar() async {
        provant = true
        defer { provant = false }
        // Si l'enllaç nou no porta ?k=, hi posem la clau de l'enllaç que ja hi havia desat
        if Publicador.client(for: link) == nil, let antic = publicador.client,
           var parts = URLComponents(string: link.trimmingCharacters(in: .whitespacesAndNewlines)),
           parts.queryItems?.contains(where: { $0.name == "k" }) != true {
            parts.queryItems = (parts.queryItems ?? []) + [URLQueryItem(name: "k", value: antic.clau)]
            if let complet = parts.string { link = complet }
        }
        guard let client = Publicador.client(for: link) else {
            resultat = "L'enllaç no és vàlid. Ha de començar per https://script.google.com i acabar en ?k=…"
            return
        }
        do {
            let estat: EstatConnexio = try await client.call("estat")
            publicador.link = link.trimmingCharacters(in: .whitespacesAndNewlines)
            resultat = "Connectat ✓"
                + (estat.facebook ? " Facebook" + (estat.pagina.map { $0.isEmpty ? "" : " (\($0))" } ?? "") : "")
                + (estat.instagram ? " · Instagram" + (estat.compteIg.map { $0.isEmpty ? "" : " (@\($0))" } ?? "") : "")
            await XarxesStore.shared.carregarFragments()
            try? await Task.sleep(for: .seconds(1))
            dismiss()
        } catch {
            resultat = error.localizedDescription
        }
    }
}

/// El botó groc de la web.
struct XarBoto: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        XarBotoCos(configuration: configuration)
    }

    private struct XarBotoCos: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .font(.system(size: 17, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .foregroundStyle(isEnabled ? Xar.onAccent : Xar.text)
                .background(isEnabled ? Xar.accent : Color(UIColor(hex: 0x7A6A1A)), in: RoundedRectangle(cornerRadius: 12))
                .opacity(configuration.isPressed ? 0.85 : 1)
        }
    }
}

/// Targeta fosca amb vora, com les .targeta de la web.
struct XarCard<Content: View>: View {
    var title: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let title {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .padding(.bottom, 10)
            }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Xar.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Xar.line))
        .padding(.bottom, 14)
    }
}

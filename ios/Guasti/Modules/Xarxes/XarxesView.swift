import SwiftUI
import WebKit

struct XarxesModule: GuastiModule {
    let id = "xarxes"
    let title = "Xarxes"
    let subtitle = "Publicador Auditori"
    let systemImage = "paperplane.fill"
    let tint = Color(UIColor(hex: 0x9A7400))
    let isAvailable = true

    @MainActor func makeRootView() -> AnyView {
        AnyView(XarxesView())
    }
}

/// L'enllaç de l'app web del publicador (Apps Script). Porta la clau ?k=, per això va al Keychain.
@MainActor
final class Publicador: ObservableObject {
    static let shared = Publicador()

    @Published var link: String {
        didSet { Keychain.set(link, for: "publicadorURL") }
    }

    private init() {
        link = Keychain.get("publicadorURL") ?? ""
    }

    var url: URL? { Self.parse(link) }

    static func parse(_ text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), url.scheme == "https",
              let host = url.host, host == "script.google.com" || host.hasSuffix(".google.com") else { return nil }
        return url
    }
}

/// El publicador de l'Auditori (Instagram i Facebook) dins de Guasti: és la mateixa app web, en una vista web.
struct XarxesView: View {
    @ObservedObject private var publicador = Publicador.shared
    @Environment(\.openURL) private var openURL
    @State private var editing = false
    @State private var reload = 0
    @State private var loading = true
    @State private var needsLogin = false

    var body: some View {
        Group {
            if let url = publicador.url {
                PublicadorWebView(url: url, reload: reload, loading: $loading, needsLogin: $needsLogin)
                    .ignoresSafeArea(edges: .bottom)
                    .overlay {
                        if loading { ProgressView().tint(.yellow).controlSize(.large) }
                    }
            } else {
                ContentUnavailableView {
                    Label("Publicador de l'Auditori", systemImage: "paperplane")
                } description: {
                    Text("Enganxa l'enllaç de l'app del publicador (el que acaba en ?k=…) i ja el tindràs aquí.")
                } actions: {
                    Button("Afegeix l'enllaç") { editing = true }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .background(Color.black)
        .navigationTitle("Xarxes")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    if let url = publicador.url {
                        Button { reload += 1 } label: { Label("Refresca", systemImage: "arrow.clockwise") }
                        Button { openURL(url) } label: { Label("Obre a Safari", systemImage: "safari") }
                    }
                    Button { editing = true } label: { Label("Canvia l'enllaç", systemImage: "link") }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("Opcions")
            }
        }
        .sheet(isPresented: $editing) {
            NavigationStack { PublicadorSetupView() }
        }
        .alert("Cal un compte de Google", isPresented: $needsLogin) {
            if let url = publicador.url {
                Button("Obre a Safari") { openURL(url) }
            }
            Button("D'acord", role: .cancel) {}
        } message: {
            Text("El publicador demana iniciar sessió, i Google no ho deixa fer dins d'altres apps. A l'editor d'Apps Script, a Gestiona les implementacions, posa «Qui hi té accés: Qualsevol usuari». Mentrestant, obre'l a Safari.")
        }
    }
}

private struct PublicadorSetupView: View {
    @ObservedObject private var publicador = Publicador.shared
    @Environment(\.dismiss) private var dismiss
    @State private var link = ""

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
        }
        .navigationTitle("Publicador")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Tanca") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Desa") {
                    publicador.link = link.trimmingCharacters(in: .whitespacesAndNewlines)
                    dismiss()
                }
                .disabled(!link.isEmpty && Publicador.parse(link) == nil)
            }
        }
        .onAppear { link = publicador.link }
    }
}

struct PublicadorWebView: UIViewRepresentable {
    let url: URL
    let reload: Int
    @Binding var loading: Bool
    @Binding var needsLogin: Bool

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()  // perquè recordi el nom de qui publica
        config.allowsInlineMediaPlayback = true
        // Google tracta millor la vista web si s'anuncia com a Safari
        config.applicationNameForUserAgent = "Version/17.0 Mobile/15E148 Safari/604.1"
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.backgroundColor = .black
        context.coordinator.load(url, reload: reload, in: webView)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.load(url, reload: reload, in: webView)
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        var parent: PublicadorWebView
        private var loadedURL: URL?
        private var loadedReload = -1

        init(_ parent: PublicadorWebView) { self.parent = parent }

        /// Torna a carregar l'enllaç sencer (com el botó ↻ Refrescar de la web), no només el marc de dins.
        func load(_ url: URL, reload: Int, in webView: WKWebView) {
            guard url != loadedURL || reload != loadedReload else { return }
            loadedURL = url
            loadedReload = reload
            webView.load(URLRequest(url: url))
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = navigationAction.request.url else { return decisionHandler(.allow) }
            if url.host == "accounts.google.com" {
                parent.loading = false
                parent.needsLogin = true
                return decisionHandler(.cancel)
            }
            if let scheme = url.scheme, !["https", "http", "about", "blob", "data"].contains(scheme) {
                UIApplication.shared.open(url)
                return decisionHandler(.cancel)
            }
            decisionHandler(.allow)
        }

        /// Els enllaços «Veure a Instagram / Facebook» (target=_blank) s'obren fora, a l'app o a Safari.
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if let url = navigationAction.request.url { UIApplication.shared.open(url) }
            return nil
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            parent.loading = true
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            parent.loading = false
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            parent.loading = false
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            parent.loading = false
        }
    }
}

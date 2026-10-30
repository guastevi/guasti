import SwiftUI
import UIKit
import PhotosUI
import UniformTypeIdentifiers

/// L'estat de la secció Xarxes. Es queda en memòria mentre l'app és oberta, així que
/// si surts a mitja publicació a una altra secció, quan tornes ho trobes igual.
@MainActor
final class XarxesStore: ObservableObject {
    static let shared = XarxesStore()

    struct Linia: Identifiable {
        enum Tipus { case normal, be, malament }
        let id = UUID()
        var text: String
        var tipus: Tipus = .normal
    }

    // Nova publicació
    @Published var elements: [Element] = []
    @Published var format: Format = .publicacio
    @Published var text = ""
    @Published var collab = ""
    @Published var ig = true
    @Published var fb = true
    @Published var programar = false
    @Published var quan = XarxesStore.properaHora()
    @Published var autor: String {
        didSet { UserDefaults.standard.set(autor, forKey: "xarxes.autor") }
    }
    @Published var carregant = false

    // Publicant
    @Published var publicant = false
    @Published var progres: Double = 0
    @Published var registre: [Linia] = []
    @Published var enllacIg = ""
    @Published var enllacosFb: [String] = []

    // Dades compartides de l'equip
    @Published var fragments: [Fragment] = []
    @Published var historial: [Entrada]?
    @Published var errorHistorial: String?

    private init() {
        autor = UserDefaults.standard.string(forKey: "xarxes.autor") ?? ""
    }

    private var client: PublicadorClient? { Publicador.shared.client }

    nonisolated static func properaHora() -> Date {
        let d = Date().addingTimeInterval(3600)
        return Calendar.current.date(bySetting: .minute, value: 0, of: d) ?? d
    }

    // MARK: Fotos i vídeos

    func afegir(_ items: [PhotosPickerItem]) async {
        carregant = true
        defer { carregant = false }
        for item in items {
            guard elements.count < Xar.maxElements else { break }
            if item.supportedContentTypes.contains(where: { $0.conforms(to: .movie) }) {
                if let p = try? await item.loadTransferable(type: Pellicula.self) {
                    elements.append(await Element.deVideo(p.url))
                }
            } else if let data = try? await item.loadTransferable(type: Data.self), let el = Element.deFoto(data) {
                elements.append(el)
            }
        }
    }

    func treure(_ el: Element) {
        if let url = el.fitxer { try? FileManager.default.removeItem(at: url) }
        elements.removeAll { $0.id == el.id }
    }

    func mouEsquerra(_ el: Element) {
        guard let i = elements.firstIndex(where: { $0.id == el.id }), i > 0 else { return }
        elements.swapAt(i, i - 1)
    }

    var fotosForaDeProporcio: Int {
        format == .publicacio ? elements.filter(\.foraDeProporcio).count : 0
    }

    var collaboradors: [String] {
        collab.split(whereSeparator: { $0 == " " || $0 == "," || $0.isNewline })
            .map { $0.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "@", with: "") }
            .filter { !$0.isEmpty }
    }

    var hashtags: Int {
        let re = try? NSRegularExpression(pattern: "#[\\p{L}\\p{N}_]+")
        return re?.numberOfMatches(in: text, range: NSRange(text.startIndex..., in: text)) ?? 0
    }

    // MARK: Textos habituals

    func carregarFragments() async {
        guard let client else { return }
        if let l: [Fragment] = try? await client.call("llistarFragments") { fragments = l }
    }

    func afegirFragment(_ f: Fragment) {
        let net = text.replacingOccurrences(of: "\\s+$", with: "", options: .regularExpression)
        text = net + (net.isEmpty ? "" : "\n\n") + f.text
    }

    func desarFragment(nom: String, text: String) async throws {
        guard let client else { return }
        fragments = try await client.call("desarFragment", [nom, text])
    }

    func esborrarFragment(_ f: Fragment) async throws {
        guard let client else { return }
        fragments = try await client.call("esborrarFragment", [f.nom])
    }

    // MARK: Historial

    func carregarHistorial() async {
        guard let client else { return }
        do {
            historial = try await client.call("llistarHistorial")
            errorHistorial = nil
        } catch {
            errorHistorial = error.localizedDescription
        }
    }

    func cancellar(_ e: Entrada) async throws {
        guard let client else { return }
        let _: Qualsevol = try await client.call("cancellar", [e.id])
        await carregarHistorial()
    }

    // MARK: Publicar

    /// Què falta abans de publicar, amb les mateixes comprovacions que la web.
    var problema: String? {
        let t = format == .story ? "" : text.trimmingCharacters(in: .whitespacesAndNewlines)
        if elements.isEmpty { return "Afegeix com a mínim una foto o un vídeo." }
        if format == .reel && (elements.count != 1 || !elements[0].video) { return "Un Reel ha de ser un sol vídeo." }
        if format == .story && elements.count > 10 { return "Com a màxim 10 stories alhora." }
        if !ig && !fb { return "Marca com a mínim una xarxa." }
        if ig && t.count > 2200 { return "El text és massa llarg per a Instagram (màxim 2.200 caràcters)." }
        if format != .story && collaboradors.count > 3 { return "Instagram permet com a màxim 3 col·laboradors." }
        if programar && quan < Date() { return "Tria una data i hora futures." }
        return nil
    }

    var resum: String {
        let xarxes = [ig ? "Instagram" : nil, fb ? "Facebook" : nil].compactMap { $0 }.joined(separator: " i ")
        let que = format == .reel ? "un Reel" : format == .story ? "\(elements.count) story(s)" : "\(elements.count) element(s)"
        return programar
            ? "Es programarà \(que) a \(xarxes) per al \(Xar.dataCurta(quan)). Endavant?"
            : "Es publicarà \(que) a \(xarxes). Endavant?"
    }

    @discardableResult
    private func anotar(_ text: String, _ tipus: Linia.Tipus = .normal) -> UUID {
        let l = Linia(text: text, tipus: tipus)
        registre.append(l)
        return l.id
    }

    private func canviar(_ id: UUID, _ text: String) {
        if let i = registre.firstIndex(where: { $0.id == id }) { registre[i].text = text }
    }

    private func netejar() {
        for el in elements { if let url = el.fitxer { try? FileManager.default.removeItem(at: url) } }
        elements = []
        text = ""
        collab = ""
    }

    /// Els mateixos passos que la web: pujar al Drive, preparar les fotos a Facebook,
    /// crear i esperar els elements d'Instagram, publicar i anotar-ho a l'historial.
    func publicar() async {
        guard let client, !publicant else { return }
        let fmt = format
        let text = fmt == .story ? "" : self.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let collaboradors = fmt == .story ? [] : self.collaboradors
        let ig = self.ig, fb = self.fb, programat = self.programar, quan = self.quan
        let autor = self.autor.trimmingCharacters(in: .whitespacesAndNewlines)
        let elements = self.elements
        let total = elements.count

        publicant = true
        registre = []
        progres = 0
        enllacIg = ""
        enllacosFb = []
        UIApplication.shared.isIdleTimerDisabled = true
        defer {
            publicant = false
            UIApplication.shared.isIdleTimerDisabled = false
        }

        let passos = Double(programat ? total + 1 : total * (ig ? 4 : 2) + (ig ? 1 : 0) + (fb ? 1 : 0))
        var fets = 0.0
        func avanca() {
            fets += 1
            progres = min(1, fets / passos)
        }

        // El nom de la carpeta del Drive, com el de la web: «2026-10-30 15:20 Primera línia del text»
        let ara = DateFormatter()
        ara.locale = Locale(identifier: "en_US_POSIX")
        ara.timeZone = TimeZone(identifier: "UTC")
        ara.dateFormat = "yyyy-MM-dd HH:mm"
        let primera = text.split(separator: "\n", omittingEmptySubsequences: false).first.map(String.init) ?? ""
        let carpeta = ara.string(from: Date()) + " " + String(primera.prefix(40))

        var igFet = false
        var enllacIg = ""
        var enllacosFb: [String] = []
        do {
            // 1. Pujar cada fitxer al Drive de l'Auditori
            var pujats: [Pujat] = []
            for (i, el) in elements.enumerated() {
                let l = anotar("Pujant \(i + 1) de \(total)…")
                let (nom, tipus, base64) = try await Self.preparar(el, numero: i + 1, retallar: fmt == .publicacio)
                let p: Pujat = try await client.call("pujarFitxer", [nom, tipus, base64, carpeta], timeout: 300)
                pujats.append(p)
                canviar(l, "Pujat \(i + 1) de \(total)")
                avanca()
            }

            if programat {
                let feina: [String: Any] = [
                    "quan": ISO8601DateFormatter().string(from: quan), "format": fmt.rawValue, "text": text,
                    "ig": ig, "fb": fb, "collaboradors": collaboradors, "autor": autor, "carpeta": carpeta,
                    "elements": pujats.map(\.dict),
                ]
                let _: Qualsevol = try await client.call("programar", [feina])
                avanca()
                anotar("✓ Programat per al \(Xar.dataCurta(quan)). El trobaràs a l'Historial, on també el pots cancel·lar.", .be)
                netejar()
                return
            }

            // 2. Preparar les fotos a Facebook (també serveixen d'origen per a Instagram)
            for i in pujats.indices {
                if !pujats[i].video {
                    let f: FotoPreparada = try await client.call("prepararFoto", [pujats[i].id], timeout: 180)
                    pujats[i].fbPhotoId = f.fbPhotoId
                    pujats[i].url = f.url
                }
                avanca()
            }

            // 3. Instagram
            if ig {
                let carrusel = fmt == .publicacio && pujats.count > 1
                var ids: [String] = []
                for (i, p) in pujats.enumerated() {
                    let l = anotar("Preparant \(i + 1) per a Instagram…")
                    let r: IdResposta = try await client.call(
                        "crearElementInstagram", [p.dict, carrusel, text, collaboradors, fmt.rawValue], timeout: 360)
                    ids.append(r.id)
                    avanca()
                    // Instagram ha de processar cada element (sobretot els vídeos) abans de publicar
                    var intent = 0
                    while true {
                        let e: EstatElement = try await client.call("estatElementInstagram", [r.id])
                        let estat = e.estat ?? ""
                        if estat.isEmpty || estat == "FINISHED" { break }
                        if estat == "ERROR" || estat == "EXPIRED" {
                            throw APIError(message: "Instagram no ha acceptat l'element \(i + 1): \(e.detall ?? "")")
                        }
                        if intent > 100 { throw APIError(message: "Instagram triga massa a processar el vídeo \(i + 1).") }
                        canviar(l, "Instagram està processant el \(i + 1)…")
                        try await Task.sleep(for: .seconds(4))
                        intent += 1
                    }
                    canviar(l, "Llest per a Instagram: \(i + 1)")
                    avanca()
                    if fmt == .story {
                        let s: EnllacIg = try await client.call("publicarInstagram", [[r.id], "", [String]()])
                        if let e = s.enllac, !e.isEmpty { enllacIg = e }
                        igFet = true
                        canviar(l, "Story \(i + 1) publicada a Instagram")
                    }
                }
                if fmt != .story {
                    anotar("Publicant a Instagram…")
                    let r: EnllacIg = try await client.call("publicarInstagram", [ids, text, collaboradors], timeout: 300)
                    enllacIg = r.enllac ?? ""
                    igFet = true
                }
                avanca()
                anotar("✓ Publicat a Instagram", .be)
            }

            // 4. Facebook
            if fb {
                anotar("Publicant a Facebook…")
                let r: EnllacosFb = try await client.call("publicarFacebook", [
                    pujats.filter { !$0.video }.compactMap(\.fbPhotoId),
                    pujats.filter(\.video).map(\.id), text, fmt.rawValue,
                ], timeout: 360)
                enllacosFb = r.enllacos
                avanca()
                anotar("✓ Publicat a Facebook", .be)
            }

            progres = 1
            self.enllacIg = enllacIg
            self.enllacosFb = enllacosFb
            anotar("Fet!", .be)
            registrar(client, ["autor": autor, "format": fmt.rawValue, "ig": ig, "fb": fb, "elements": total, "text": text,
                               "collaboradors": collaboradors, "enllacIg": enllacIg, "enllacosFb": enllacosFb, "carpeta": carpeta])
            netejar()
        } catch {
            let missatge = error.localizedDescription
            anotar("✗ " + missatge, .malament)
            self.enllacIg = enllacIg
            self.enllacosFb = enllacosFb
            if !programat {
                registrar(client, ["autor": autor, "ig": ig, "fb": fb, "elements": total, "text": text,
                                   "collaboradors": collaboradors, "enllacIg": enllacIg, "enllacosFb": enllacosFb,
                                   "carpeta": carpeta, "error": missatge, "igFet": igFet])
            }
            if igFet {
                self.ig = false
                anotar("Instagram ja està publicat. He desmarcat Instagram perquè, si ho tornes a provar, no surti dues vegades.")
            } else {
                anotar("No s'ha completat. Revisa el missatge i torna-ho a provar; les fotos continuen seleccionades.")
            }
        }
    }

    private func registrar(_ client: PublicadorClient, _ r: [String: Any]) {
        Task {
            let _: Qualsevol? = try? await client.call("registrar", [r])
        }
    }

    /// Convertir les fotos i llegir els vídeos fora del fil principal, perquè la pantalla no es congeli.
    private nonisolated static func preparar(_ el: Element, numero: Int, retallar: Bool) async throws -> (String, String, String) {
        try el.perPujar(numero: numero, retallar: retallar)
    }
}

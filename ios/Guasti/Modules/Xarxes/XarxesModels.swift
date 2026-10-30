import SwiftUI
import UIKit
import ImageIO
import AVFoundation
import CoreTransferable
import UniformTypeIdentifiers

/// Els colors del publicador web: fons negre i botons grocs.
enum Xar {
    static let bg = Color(UIColor(hex: 0x0B0B0B))
    static let card = Color(UIColor(hex: 0x161616))
    static let field = Color(UIColor(hex: 0x0F0F0F))
    static let text = Color(UIColor(hex: 0xF2F2F0))
    static let muted = Color(UIColor(hex: 0x9A9A96))
    static let line = Color(UIColor(hex: 0x2A2A2A))
    static let accent = Color(UIColor(hex: 0xFFD60A))
    static let onAccent = Color(UIColor(hex: 0x111111))
    static let be = Color(UIColor(hex: 0x7BD88F))
    static let malament = Color(UIColor(hex: 0xFF6B6B))
    /// Lila del logo de l'Auditori, per a la rajola de la pantalla d'inici.
    static let lila = Color(UIColor(hex: 0x682081))

    static let maxElements = 20
    static let midaMaxima = 45 * 1024 * 1024

    static func dataCurta(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.abbreviated).hour().minute().locale(Locale(identifier: "ca")))
    }

    static func dataCurta(iso: String) -> String {
        guard !iso.isEmpty else { return "" }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let d = f.date(from: iso) ?? ISO8601DateFormatter().date(from: iso) else { return "" }
        return dataCurta(d)
    }
}

enum Format: String, CaseIterable {
    case publicacio, reel, story

    var title: String {
        switch self {
        case .publicacio: return "Publicació"
        case .reel: return "Reel"
        case .story: return "Story"
        }
    }

    var ajuda: String {
        switch self {
        case .publicacio: return "Una foto o vídeo, o un carrusel de fins a 20. A Facebook, les fotos surten juntes en un post."
        case .reel: return "Un sol vídeo vertical (9:16). Surt com a Reel a Instagram i a Facebook."
        case .story: return "Fins a 10 fotos o vídeos verticals; cadascun és una story. Les stories no porten text ni col·laboradors i desapareixen al cap de 24 hores."
        }
    }
}

// MARK: - Connexió amb el publicador

/// L'enllaç de l'app del publicador (Apps Script «Publicador Auditori»), amb la clau ?k=.
/// Va al Keychain perquè porta la clau, i el repositori és públic.
@MainActor
final class Publicador: ObservableObject {
    static let shared = Publicador()

    @Published var link: String {
        didSet { Keychain.set(link, for: "publicadorURL") }
    }

    private init() {
        link = Keychain.get("publicadorURL") ?? ""
    }

    var client: PublicadorClient? { Self.client(for: link) }

    /// De «https://script.google.com/macros/s/…/exec?k=CLAU» en treu l'adreça i la clau.
    static func client(for text: String) -> PublicadorClient? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var parts = URLComponents(string: trimmed), parts.scheme == "https",
              let host = parts.host, host.hasSuffix("google.com"),
              let clau = parts.queryItems?.first(where: { $0.name == "k" })?.value, !clau.isEmpty else { return nil }
        parts.query = nil
        parts.fragment = nil
        guard let url = parts.url else { return nil }
        return PublicadorClient(url: url, clau: clau)
    }
}

/// Parla amb ApiGuasti.gs, el fitxer que hi ha al projecte del publicador. Són les mateixes
/// funcions que fa servir la web: { action, k, args } → { ok, r } o { ok: false, error }.
struct PublicadorClient {
    let url: URL
    let clau: String

    private struct Resposta<T: Decodable>: Decodable {
        let ok: Bool
        let error: String?
        let r: T?
    }

    func call<T: Decodable>(_ accio: String, _ args: [Any] = [], timeout: TimeInterval = 120) async throws -> T {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("text/plain;charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["action": accio, "k": clau, "args": args])

        let data: Data
        do {
            data = try await URLSession.shared.data(for: request).0
        } catch let error as URLError where error.code == .timedOut {
            throw APIError(message: "Google ha tardat massa a respondre. Torna-ho a provar.")
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            throw APIError(message: "No hi ha connexió amb Google (\(error.localizedDescription)).")
        }

        guard let resposta = try? JSONDecoder().decode(Resposta<T>.self, from: data) else {
            if let envelope = try? JSONDecoder().decode(Resposta<Qualsevol>.self, from: data), !envelope.ok {
                throw APIError(message: envelope.error ?? "Error desconegut")
            }
            throw APIError(message: "Resposta inesperada de Google. Revisa que el publicador tingui el fitxer ApiGuasti i que la implementació sigui «Qualsevol usuari».")
        }
        guard resposta.ok else { throw APIError(message: resposta.error ?? "Error desconegut") }
        guard let r = resposta.r else {
            if let buit = Qualsevol() as? T { return buit }
            throw APIError(message: "Google no ha retornat res (\(accio)).")
        }
        return r
    }
}

/// Per a les respostes que no ens interessen.
struct Qualsevol: Decodable {
    init() {}
    init(from decoder: Decoder) throws {}
}

/// Un text, un número o res: el full de càlcul ho pot tornar de qualsevol manera.
struct Flex: Decodable {
    let text: String

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let s = try? c.decode(String.self) { text = s }
        else if let i = try? c.decode(Int.self) { text = String(i) }
        else if let d = try? c.decode(Double.self) { text = String(d) }
        else if let b = try? c.decode(Bool.self) { text = b ? "sí" : "no" }
        else { text = "" }
    }
}

struct EstatConnexio: Decodable {
    let facebook: Bool
    let instagram: Bool
    let pagina: String?
    let compteIg: String?
}

struct Fragment: Decodable, Hashable {
    let nom: String
    let text: String
}

struct Pujat: Decodable {
    let id: String
    let nom: String
    let video: Bool
    var fbPhotoId: String?
    var url: String?

    var dict: [String: Any] {
        var d: [String: Any] = ["id": id, "nom": nom, "video": video]
        if let fbPhotoId { d["fbPhotoId"] = fbPhotoId }
        if let url { d["url"] = url }
        return d
    }
}

struct FotoPreparada: Decodable {
    let fbPhotoId: String
    let url: String
}

struct IdResposta: Decodable { let id: String }
struct EstatElement: Decodable { let estat: String?; let detall: String? }
struct EnllacIg: Decodable { let enllac: String? }
struct EnllacosFb: Decodable { let enllacos: [String] }

struct Entrada: Decodable, Identifiable {
    let id: String
    let estat: String
    let autor: String
    let text: String
    let xarxes: String
    let elements: String
    let enllacIg: String
    let enllacosFb: [String]
    let error: String
    let creat: String
    let programat: String
    let publicat: String

    private enum K: String, CodingKey {
        case id, estat, autor, text, xarxes, elements, enllacIg, enllacosFb, error, creat, programat, publicat
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        func s(_ k: K) -> String { (try? c.decodeIfPresent(Flex.self, forKey: k))?.text ?? "" }
        id = s(.id)
        estat = s(.estat)
        autor = s(.autor)
        text = s(.text)
        xarxes = s(.xarxes)
        elements = s(.elements)
        enllacIg = s(.enllacIg)
        enllacosFb = (try? c.decodeIfPresent([String].self, forKey: .enllacosFb)) ?? []
        error = s(.error)
        creat = s(.creat)
        programat = s(.programat)
        publicat = s(.publicat)
    }

    var etiqueta: String {
        ["publicat": "Publicat", "programat": "Programat", "publicant": "Publicant", "error": "Error", "cancel·lat": "Cancel·lat"][estat] ?? estat
    }

    var color: Color {
        switch estat {
        case "publicat": return Xar.be
        case "error": return Xar.malament
        case "programat", "publicant": return Xar.accent
        default: return Xar.muted
        }
    }
}

// MARK: - Fotos i vídeos triats

struct Element: Identifiable {
    let id = UUID()
    let video: Bool
    /// La foto tal com ve de la Fototeca (HEIC o JPG). Es converteix just abans de pujar-la.
    let dades: Data?
    /// El vídeo, copiat a la carpeta temporal.
    let fitxer: URL?
    let miniatura: UIImage?
    let proporcio: CGFloat?

    /// Instagram només accepta fotos entre 4:5 (vertical) i 1,91:1 (horitzontal).
    var foraDeProporcio: Bool {
        guard !video, let p = proporcio else { return false }
        return p < 0.8 - 0.01 || p > 1.91 + 0.01
    }

    var tipusVideo: String {
        switch fitxer?.pathExtension.lowercased() {
        case "mp4", "m4v": return "video/mp4"
        default: return "video/quicktime"
        }
    }

    static func deFoto(_ data: Data) -> Element? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 400,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
        return Element(video: false, dades: data, fitxer: nil, miniatura: UIImage(cgImage: cg),
                       proporcio: CGFloat(cg.width) / CGFloat(max(cg.height, 1)))
    }

    static func deVideo(_ url: URL) async -> Element {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 400, height: 400)
        let cg = try? await generator.image(at: .zero).image
        return Element(video: true, dades: nil, fitxer: url, miniatura: cg.map { UIImage(cgImage: $0) },
                       proporcio: cg.map { CGFloat($0.width) / CGFloat(max($0.height, 1)) })
    }

    /// Nom, tipus i contingut en base64 per a pujarFitxer, com fa la web.
    func perPujar(numero: Int, retallar: Bool) throws -> (String, String, String) {
        if video, let fitxer {
            let data = try Data(contentsOf: fitxer)
            if data.count > Xar.midaMaxima { throw APIError(message: "El vídeo \(numero) és massa gran (màxim ~45 MB per fitxer).") }
            return ("video-\(numero).\(fitxer.pathExtension.lowercased())", tipusVideo, data.base64EncodedString())
        }
        guard let dades, let jpeg = Self.jpeg(dades, retallar: retallar) else {
            throw APIError(message: "No s'ha pogut llegir la foto \(numero).")
        }
        return ("foto-\(numero).jpg", "image/jpeg", jpeg.base64EncodedString())
    }

    /// JPEG d'una mida raonable i, per a les publicacions, retallada pel centre a una proporció que Instagram accepti.
    static func jpeg(_ data: Data, retallar: Bool) -> Data? {
        autoreleasepool {
            guard let img = UIImage(data: data) else { return nil }
            let w = img.size.width, h = img.size.height
            guard w > 0, h > 0 else { return nil }
            var crop = CGRect(x: 0, y: 0, width: w, height: h)
            let r = w / h
            if retallar && r < 0.8 {
                crop.size.height = (w / 0.8).rounded()
                crop.origin.y = ((h - crop.height) / 2).rounded()
            }
            if retallar && r > 1.91 {
                crop.size.width = (h * 1.91).rounded()
                crop.origin.x = ((w - crop.width) / 2).rounded()
            }
            let escala = min(1, (retallar ? 1440 : 1080) / crop.width)
            let target = CGSize(width: (crop.width * escala).rounded(), height: (crop.height * escala).rounded())
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            format.opaque = true
            let out = UIGraphicsImageRenderer(size: target, format: format).image { _ in
                img.draw(in: CGRect(x: -crop.minX * escala, y: -crop.minY * escala, width: w * escala, height: h * escala))
            }
            return out.jpegData(compressionQuality: 0.9)
        }
    }
}

/// Un vídeo de la Fototeca, copiat a una carpeta temporal.
struct Pellicula: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { p in
            SentTransferredFile(p.url)
        } importing: { rebut in
            let ext = rebut.file.pathExtension.isEmpty ? "mov" : rebut.file.pathExtension
            let desti = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "." + ext)
            try FileManager.default.copyItem(at: rebut.file, to: desti)
            return Pellicula(url: desti)
        }
    }
}

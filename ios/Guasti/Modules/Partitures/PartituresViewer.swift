import SwiftUI
import PDFKit
import AVKit
import UIKit

// MARK: - PDF: primera pàgina, pàgines per al faristol i anotacions dibuixades

enum PDFTools {
    /// Dibuixa una pàgina (amb el gir que tingui) a la mida que es demana.
    static func render(_ page: PDFPage, fitting size: CGSize, scale: CGFloat) -> UIImage {
        let b = page.bounds(for: .cropBox)
        let rotated = page.rotation % 180 != 0
        let w = rotated ? b.height : b.width, h = rotated ? b.width : b.height
        let k = min(size.width / w, size.height / h)
        let target = CGSize(width: max(1, w * k * scale), height: max(1, h * k * scale))
        return page.thumbnail(of: target, for: .cropBox)
    }

    /// Un PDF nou amb les anotacions dibuixades a sobre (l'original no es toca).
    static func burn(_ data: Data, _ a: Anotacions) -> Data {
        guard !a.isEmpty, let doc = PDFDocument(data: data) else { return data }
        let out = PDFDocument()
        for i in 0..<doc.pageCount {
            guard let page = doc.page(at: i) else { continue }
            let strokes = a.pages[String(i + 1)] ?? []
            if strokes.isEmpty {
                if let copy = page.copy() as? PDFPage { out.insert(copy, at: out.pageCount) }
                continue
            }
            let b = page.bounds(for: .cropBox)
            let rotated = page.rotation % 180 != 0
            let size = CGSize(width: rotated ? b.height : b.width, height: rotated ? b.width : b.height)
            let pdf = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: size)).pdfData { ctx in
                ctx.beginPage()
                let cg = ctx.cgContext
                cg.saveGState()
                cg.translateBy(x: 0, y: size.height)
                cg.scaleBy(x: 1, y: -1)
                page.draw(with: .cropBox, to: cg)
                cg.restoreGState()
                for s in strokes { stroke(s, in: cg, size: size) }
            }
            if let one = PDFDocument(data: pdf), let p = one.page(at: 0)?.copy() as? PDFPage { out.insert(p, at: out.pageCount) }
        }
        return out.dataRepresentation() ?? data
    }

    static func stroke(_ s: Anotacions.Traç, in cg: CGContext, size: CGSize) {
        let p = s.p
        guard p.count >= 2 else { return }
        cg.setStrokeColor(UIColor(Color(hexString: s.c)).cgColor)
        cg.setLineWidth(max(1, s.w * size.width))
        cg.setLineCap(.round)
        cg.setLineJoin(.round)
        cg.beginPath()
        cg.move(to: CGPoint(x: p[0] * size.width, y: p[1] * size.height))
        if p.count == 2 { cg.addLine(to: CGPoint(x: p[0] * size.width + 0.1, y: p[1] * size.height)) }
        var k = 2
        while k + 1 < p.count {
            cg.addLine(to: CGPoint(x: p[k] * size.width, y: p[k + 1] * size.height))
            k += 2
        }
        cg.strokePath()
    }
}

// MARK: - Vista prèvia d'un document a la seva fitxa

/// PDF: la primera pàgina (toca per veure-la sencera al faristol). Àudio, vídeo i imatges: es poden reproduir o veure.
/// La resta de formats: es poden enviar o obrir al Drive.
struct PDocPreview: View {
    let doc: Fila
    @Binding var req: PReq?
    @ObservedObject private var store = PartituresStore.shared
    @State private var image: UIImage?
    @State private var pages = 0
    @State private var fileURL: URL?
    @State private var player: AVPlayer?
    @State private var info: PFitxer?
    @State private var error: String?
    @State private var loading = true

    var body: some View {
        let kind = Arxiu.viewKind(doc, name: info?.name)
        VStack(spacing: 0) {
            if let error {
                infoCard(message: "No s'ha pogut mostrar: " + error)
            } else if kind == .pdf {
                pdfPreview
            } else if loading {
                PRing(label: doc["Títol"]).frame(height: 160)
            } else if let player, kind == .audio || kind == .video {
                VStack(alignment: .leading, spacing: 8) {
                    if kind == .audio { Text(info?.name ?? "").fontWeight(.semibold).foregroundStyle(Color(white: 0.07)) }
                    VideoPlayer(player: player).frame(height: kind == .audio ? 60 : 260)
                }
                .padding(kind == .audio ? 14 : 0)
            } else if let fileURL, kind == .image, let img = UIImage(contentsOfFile: fileURL.path) {
                Image(uiImage: img).resizable().scaledToFit()
                    .overlay(alignment: .topTrailing) {
                        ShareLink(item: fileURL) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                                .frame(width: 38, height: 38)
                                .background(Color.black.opacity(0.6), in: Circle())
                        }
                        .padding(8)
                        .accessibilityLabel("Comparteix o desa")
                    }
            } else {
                infoCard(message: info?.tooBig == true ? "El fitxer fa més de 30 MB i no es pot obrir dins l'app. Obre'l al Drive." : nil)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 120)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(P.line))
        .task(id: doc["ID"]) { await load() }
    }

    private var pdfPreview: some View {
        Group {
            if let image {
                VStack(spacing: 0) {
                    Image(uiImage: image).resizable().scaledToFit()
                    Text((pages > 1 ? "Pàgina 1 de \(pages) · " : "") + "Toca per veure-la sencera")
                        .font(.system(size: 12)).foregroundStyle(Color(white: 0.33))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                }
                .contentShape(Rectangle())
                .onTapGesture { req = .stand([doc], doc["Títol"] ?? "") }
            } else {
                PRing(label: nil, dark: false).frame(height: 220)
            }
        }
    }

    private func infoCard(message: String?) -> some View {
        let e = Arxiu.fileExt(info?.name ?? doc["Títol"] ?? "")
        let app = Arxiu.fmtNames[e] ?? ((doc["Format"] ?? "").isEmpty ? "aquest programa" : (doc["Format"] ?? ""))
        let u = info?.url ?? Arxiu.docUrl(doc)
        return VStack(spacing: 6) {
            Text(info?.name ?? doc["Títol"] ?? "").font(.system(size: 15, weight: .semibold)).multilineTextAlignment(.center)
            Text(message ?? "Fitxer de \(app). Aquest format només s'obre amb \(app) i no es pot mostrar aquí. Si n'exportes un PDF o un MusicXML, l'app el podrà mostrar.")
                .font(.system(size: 12)).foregroundStyle(P.mute).multilineTextAlignment(.center)
                .padding(.bottom, 6)
            HStack(spacing: 8) {
                if let fileURL {
                    ShareLink(item: fileURL) { Text("Descarrega") }.buttonStyle(PBtn(kind: .primary))
                }
                if let url = URL(string: u), !u.isEmpty {
                    Link(destination: url) { Text("Obre al Drive") }.buttonStyle(PBtn())
                }
            }
        }
        .foregroundStyle(Color(white: 0.07))
        .padding(16)
        .frame(maxWidth: .infinity)
    }

    private func load() async {
        let fid = Arxiu.fileId(doc)
        loading = true
        defer { loading = false }
        do {
            if Arxiu.viewKind(doc) == .pdf {
                let data = try await store.pdfData(fid)
                guard let pdf = PDFDocument(data: data), let page = pdf.page(at: 0) else { throw APIError(message: "El PDF no es pot llegir.") }
                pages = pdf.pageCount
                image = PDFTools.render(page, fitting: CGSize(width: 700, height: 2000), scale: 2)
            } else {
                let (url, fd) = try await store.fileURL(fid)
                info = fd
                fileURL = url
                if let url, [.audio, .video].contains(Arxiu.viewKind(doc, name: fd.name)) { player = AVPlayer(url: url) }
                if Arxiu.viewKind(doc, name: fd.name) == .pdf, let url, let data = try? Data(contentsOf: url),
                   let pdf = PDFDocument(data: data), let page = pdf.page(at: 0) {
                    pages = pdf.pageCount
                    image = PDFTools.render(page, fitting: CGSize(width: 700, height: 2000), scale: 2)
                }
            }
        } catch is CancellationError {
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// La rodeta de càrrega vermella de la web: un cercle que es va omplint mentre es carrega.
struct PRing: View {
    var label: String?
    var dark = false
    @State private var progress = 0.04
    @State private var spin = false

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle().stroke(dark ? Color.white.opacity(0.14) : Color.black.opacity(0.08), lineWidth: 5.5)
                Circle().trim(from: 0, to: progress)
                    .stroke(Color(UIColor(hex: 0xe53935)), style: StrokeStyle(lineWidth: 5.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 60, height: 60)
            .rotationEffect(.degrees(spin ? 360 : 0))
            .animation(.linear(duration: 1.2).repeatForever(autoreverses: false), value: spin)
            if let label, !label.isEmpty {
                Text(label).font(.system(size: 14)).foregroundStyle(dark ? Color(white: 0.67) : Color(white: 0.47)).lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity)
        .onAppear { spin = true }
        .task {
            while !Task.isCancelled && progress < 0.9 {
                try? await Task.sleep(for: .milliseconds(120))
                progress += (0.92 - progress) * 0.045
            }
        }
    }
}

// MARK: - Compartir

/// Comparteix: enviar el PDF (amb les anotacions o sense) o un enllaç per obrir-lo.
struct PShareBox: View {
    let doc: Fila
    @ObservedObject private var store = PartituresStore.shared
    @State private var info: PShareInfo?
    @State private var error: String?
    @State private var file: URL?
    @State private var annFile: URL?
    @State private var withAnn = false
    @State private var preparing = true
    @State private var publicURL: String?
    @State private var activating = false
    @State private var annLink: String?
    @State private var annLinkBusy = false

    private var title: String { (doc["Títol"] ?? "").isEmpty ? (info?.name ?? "") : (doc["Títol"] ?? "") }
    private var hasAnn: Bool { !(doc["Anotacions"] ?? "").isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Comparteix").font(.system(size: 15, weight: .bold)).padding(.bottom, 2)
            if let error {
                PHint(text: "Error: " + error)
            } else if let info {
                if info.size <= 20 * 1024 * 1024 {
                    PHint(text: "Envia el PDF directament (WhatsApp, Telegram, Correu, AirDrop...):")
                    if let f = (withAnn ? annFile : file) {
                        ShareLink(item: f) { Text("Envia el PDF") }.buttonStyle(PBtn(kind: .primary))
                    } else {
                        Button(withAnn ? "Afegint anotacions..." : "Preparant el fitxer...") {}.buttonStyle(PBtn(kind: .primary)).disabled(true)
                    }
                    if hasAnn {
                        Toggle("Envia el PDF amb les meves anotacions", isOn: $withAnn).tint(P.blue).padding(.top, 4)
                    }
                }
                PHint(text: "O envia un enllaç per obrir-lo:").padding(.top, 8)
                if let url = publicURL ?? (info.isPublic ? info.url : nil) {
                    PShareLinks(title: title, url: url, copy: true)
                } else if info.canLink {
                    Button(activating ? "Activant..." : "Activa l'enllaç per compartir") { activate() }.buttonStyle(PBtn()).disabled(activating)
                    PHint(text: "Qualsevol persona amb l'enllaç podrà veure aquest fitxer (no editar-lo).")
                } else {
                    PHint(text: "Aquest fitxer és d'una altra persona: només el pots enviar com a fitxer.")
                }
                if hasAnn {
                    PHint(text: "Aquesta partitura té anotacions teves. L'enllaç és sempre sense anotacions.").padding(.top, 10)
                    if let annLink {
                        PHint(text: "Còpia desada a Arxiu de Repertori / Paquets")
                        PShareLinks(title: title + " (anotat)", url: annLink, copy: true)
                    } else {
                        Button(annLinkBusy ? "Preparant..." : "Fes una còpia amb anotacions i comparteix-la") { annotatedCopy() }
                            .buttonStyle(PBtn()).disabled(annLinkBusy)
                    }
                }
            } else {
                PHint(text: "Preparant...")
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(P.line))
        .padding(.bottom, 12)
        .task { await prepare() }
        .onChange(of: withAnn) { _, on in if on && annFile == nil { Task { await prepareAnnotated() } } }
    }

    private func fileName(_ suffix: String = "") -> String {
        var n = info?.name ?? title
        if Arxiu.fileExt(n).isEmpty { n += ".pdf" }
        if suffix.isEmpty { return n }
        return n.replacingOccurrences(of: #"\.pdf$"#, with: "", options: [.regularExpression, .caseInsensitive]) + suffix + ".pdf"
    }

    private func prepare() async {
        let fid = Arxiu.fileId(doc)
        do {
            info = try await store.call("getShareInfo", [fid])
            guard let info, info.size <= 20 * 1024 * 1024 else { return }
            if Arxiu.isPdf(doc) {
                file = try store.tempFile(try await store.pdfData(fid), name: fileName())
            } else {
                file = try await store.fileURL(fid).0
            }
        } catch is CancellationError {
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func prepareAnnotated() async {
        do {
            let data = try await store.pdfData(Arxiu.fileId(doc))
            let a = await store.annotations(doc)
            annFile = try store.tempFile(PDFTools.burn(data, a), name: fileName(" (anotat)"))
        } catch {
            toast("Error: " + error.localizedDescription)
            withAnn = false
        }
    }

    private func activate() {
        activating = true
        Task {
            do { publicURL = try await store.call("makePublicLink", [Arxiu.fileId(doc)]) } catch { toast("Error: " + error.localizedDescription) }
            activating = false
        }
    }

    private func annotatedCopy() {
        annLinkBusy = true
        Task {
            do {
                let data = try await store.pdfData(Arxiu.fileId(doc))
                let burned = PDFTools.burn(data, await store.annotations(doc))
                let r: PPaquet = try await store.call("savePackage", [burned.base64EncodedString(), title + " (anotat).pdf"])
                annLink = try await store.call("makePublicLink", [r.id])
            } catch { toast("Error: " + error.localizedDescription) }
            annLinkBusy = false
        }
    }
}

/// WhatsApp, Telegram, Correu i Copia l'enllaç.
struct PShareLinks: View {
    let title: String
    let url: String
    var copy = false

    var body: some View {
        let txt = title + " – " + url
        FlowLayout(spacing: 8) {
            link("WhatsApp", "https://wa.me/?text=" + enc(txt))
            link("Telegram", "https://t.me/share/url?url=" + enc(url) + "&text=" + enc(title))
            link("Correu", "mailto:?subject=" + enc(title) + "&body=" + enc(txt))
            if copy {
                Button("Copia l'enllaç") {
                    UIPasteboard.general.string = url
                    toast("Enllaç copiat")
                }.buttonStyle(PBtn())
            }
        }
        .padding(.top, 2)
    }

    private func enc(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: "-._~"))) ?? s
    }

    @ViewBuilder private func link(_ t: String, _ u: String) -> some View {
        if let url = URL(string: u) { Link(destination: url) { Text(t) }.buttonStyle(PBtn()) }
    }
}

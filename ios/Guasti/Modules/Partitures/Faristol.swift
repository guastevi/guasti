import SwiftUI
import PDFKit
import UIKit

/// Mode faristol: les partitures a pantalla sencera, una pàgina rere l'altra, amb el llapis per anotar.
/// Toca a la dreta o a l'esquerra (o llisca) per passar pàgina; al mig, mostra o amaga la barra.
struct FaristolView: View {
    let docs: [Fila]
    let title: String
    var startDrawing = false
    @ObservedObject private var store = PartituresStore.shared
    @Environment(\.dismiss) private var dismiss

    @State private var i = 0
    @State private var p = 1
    @State private var pdfs: [Int: PDFDocument] = [:]
    @State private var image: UIImage?
    @State private var shownKey = ""
    @State private var error: String?
    @State private var bar = true
    @State private var drawing = false
    @State private var showAnn = true
    @State private var color = "#111111"
    @State private var width = 0.0025
    @State private var erase = false
    @State private var ann: [String: Anotacions] = [:]
    @State private var dirty = Set<String>()
    @State private var confirmClear = false
    @State private var redraw = 0

    init(docs: [Fila], title: String, startDrawing: Bool = false, start: Int = 0) {
        let pdfs = docs.filter(Arxiu.isPdf)
        self.docs = pdfs
        let first = start < docs.count ? docs[start]["ID"] : nil
        _i = State(initialValue: pdfs.firstIndex { $0["ID"] == first } ?? 0)
        self.title = title
        self.startDrawing = startDrawing
    }

    private static let colors = ["#111111", "#d0021b", "#1e6fd9", "#1a9b3c"]

    var body: some View {
        GeometryReader { geo in
            let area = CGSize(width: geo.size.width, height: geo.size.height - (drawing ? 112 : 0))
            ZStack(alignment: drawing ? .top : .center) {
                Color.black.ignoresSafeArea()
                if docs.isEmpty {
                    Text("No hi ha cap PDF per mostrar").foregroundStyle(Color(white: 0.67))
                } else if let image, shownKey.hasPrefix("\(i)-\(p)-") {
                    let fit = fitSize(image.size, in: area)
                    Image(uiImage: image)
                        .resizable()
                        .frame(width: fit.width, height: fit.height)
                        .background(Color.white)
                        .overlay {
                            InkCanvas(strokes: showAnn ? strokes : [], enabled: drawing, color: color, width: width, erase: erase,
                                      redraw: redraw) { setStrokes($0) }
                        }
                        .padding(.top, drawing ? 56 : 0)
                } else if let error {
                    Text("No s'ha pogut obrir: " + error).foregroundStyle(Color(white: 0.67)).multilineTextAlignment(.center).padding()
                } else {
                    PRing(label: docs[i]["Títol"], dark: true)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onEnded { g in
                guard !drawing else { return }
                let dx = g.translation.width
                if abs(dx) > 50 { dx < 0 ? next() : prev(); return }
                guard abs(g.translation.height) < 30 else { return }
                let x = g.location.x / max(geo.size.width, 1)
                if x < 0.3 { prev() } else if x > 0.7 { next() } else { withAnimation(.easeOut(duration: 0.2)) { bar.toggle() } }
            })
            .task(id: "\(i)-\(p)-\(Int(area.width))x\(Int(area.height))") { await show(area: area) }
        }
        .ignoresSafeArea(edges: drawing ? [] : .all)
        .overlay(alignment: .top) { if bar || drawing { topBar.transition(.move(edge: .top)) } }
        .overlay(alignment: .bottom) { if drawing { tools } }
        .statusBarHidden(!bar)
        .persistentSystemOverlays(.hidden)
        .preferredColorScheme(.dark)
        .modifier(PToastOverlay())
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            drawing = startDrawing
            if !startDrawing {
                Task {
                    try? await Task.sleep(for: .seconds(2.5))
                    if !drawing { withAnimation { bar = false } }
                }
            }
        }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        .alert("Esborrar totes les anotacions d'aquesta pàgina?", isPresented: $confirmClear) {
            Button("Esborra", role: .destructive) { setStrokes([]); redraw += 1 }
            Button("Cancel·la", role: .cancel) {}
        }
    }

    // MARK: barres

    private var pageCount: Int { pdfs[i]?.pageCount ?? 0 }

    private var topBar: some View {
        HStack(spacing: 8) {
            Button("Tanca") { close() }.buttonStyle(PBtn(small: true))
            if !docs.isEmpty {
                Menu {
                    Picker("", selection: Binding(get: { i }, set: { v in saveAnn(i); i = v; p = 1 })) {
                        ForEach(docs.indices, id: \.self) { k in Text("\(k + 1). " + (docs[k]["Títol"] ?? "")).tag(k) }
                    }
                } label: {
                    HStack {
                        Text("\(i + 1). " + (docs[i]["Títol"] ?? "")).lineLimit(1)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.down").font(.system(size: 11))
                    }
                    .font(.system(size: 14))
                    .foregroundStyle(.black)
                    .padding(7)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 8))
                }
                if pageCount > 0 { Text("Pàg. \(p) / \(pageCount)").font(.system(size: 13)).foregroundStyle(.white).fixedSize() }
                Button(drawing ? "Fet" : "Llapis") { setDrawing(!drawing) }.buttonStyle(PBtn(small: true))
                Button("Anot.: " + (showAnn ? "Sí" : "No")) { showAnn.toggle(); redraw += 1 }.buttonStyle(PBtn(small: true))
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(Color.black.opacity(0.78))
    }

    private var tools: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Self.colors, id: \.self) { c in
                    Button { color = c; erase = false } label: {
                        Circle().fill(Color(hexString: c)).frame(width: 28, height: 28)
                            .overlay(Circle().strokeBorder(color == c && !erase ? Color.white : Color(white: 0.33), lineWidth: 2))
                            .overlay(Circle().stroke(color == c && !erase ? P.blue : .clear, lineWidth: 2).padding(-3))
                    }
                    .buttonStyle(.plain)
                }
                Button(width < 0.003 ? "Fi" : "Gruixut") { width = width < 0.003 ? 0.006 : 0.0025 }.buttonStyle(PBtn(small: true))
                Button("Goma") { erase.toggle() }.buttonStyle(PBtn(kind: erase ? .primary : .normal, small: true))
                Button("Desfés") {
                    var s = strokes
                    if !s.isEmpty { s.removeLast(); setStrokes(s); redraw += 1 }
                }.buttonStyle(PBtn(small: true))
                Button("Esborra pàgina") { confirmClear = true }.buttonStyle(PBtn(small: true))
                Button("Fet") { setDrawing(false) }.buttonStyle(PBtn(kind: .primary, small: true))
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
        }
        .background(Color.black.opacity(0.85))
    }

    // MARK: pàgines

    private func fitSize(_ s: CGSize, in area: CGSize) -> CGSize {
        guard s.width > 0, s.height > 0 else { return area }
        let k = min(area.width / s.width, area.height / s.height)
        return CGSize(width: s.width * k, height: s.height * k)
    }

    private func pdf(_ k: Int) async throws -> PDFDocument {
        if let d = pdfs[k] { return d }
        let data = try await store.pdfData(Arxiu.fileId(docs[k]))
        guard let d = PDFDocument(data: data) else { throw APIError(message: "El PDF no es pot llegir.") }
        pdfs[k] = d
        return d
    }

    private func show(area: CGSize) async {
        guard !docs.isEmpty else { return }
        let k = i
        do {
            error = nil
            let d = try await pdf(k)
            if p < 0 { p = d.pageCount }
            p = max(1, min(p, d.pageCount))
            if ann[docs[k]["ID"] ?? ""] == nil { ann[docs[k]["ID"] ?? ""] = await store.annotations(docs[k]) }
            guard let page = d.page(at: p - 1) else { return }
            let scale = min(UIScreen.main.scale, 3)
            image = PDFTools.render(page, fitting: area, scale: scale)
            shownKey = "\(k)-\(p)-"
            redraw += 1
            if p == d.pageCount, k + 1 < docs.count { _ = try? await pdf(k + 1) }
        } catch is CancellationError {
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func next() {
        guard pageCount > 0 else { return }
        if p < pageCount { p += 1 } else if i < docs.count - 1 { saveAnn(i); i += 1; p = 1 } else { toast("Final del programa") }
    }

    private func prev() {
        if p > 1 { p -= 1 } else if i > 0 { saveAnn(i); i -= 1; p = -1 }
    }

    // MARK: anotacions

    private var strokes: [Anotacions.Traç] {
        guard !docs.isEmpty else { return [] }
        return ann[docs[i]["ID"] ?? ""]?.pages[String(p)] ?? []
    }

    private func setStrokes(_ s: [Anotacions.Traç]) {
        let id = docs[i]["ID"] ?? ""
        var a = ann[id] ?? Anotacions()
        a.pages[String(p)] = s
        ann[id] = a
        dirty.insert(id)
    }

    private func setDrawing(_ on: Bool) {
        drawing = on
        if on { showAnn = true; bar = true } else { saveAnn(i) }
        redraw += 1
    }

    private func saveAnn(_ k: Int) {
        guard k < docs.count else { return }
        let d = docs[k], id = d["ID"] ?? ""
        guard dirty.contains(id), let a = ann[id] else { return }
        dirty.remove(id)
        Task {
            do {
                try await store.saveAnnotations(d, a)
                toast(a.isEmpty ? "Anotacions esborrades" : "Anotacions desades")
            } catch {
                dirty.insert(id)
                toast("No s'han pogut desar les anotacions: " + error.localizedDescription)
            }
        }
    }

    private func close() {
        saveAnn(i)
        dismiss()
    }
}

/// La capa transparent on es dibuixa. Amb l'Apple Pencil, el dit i el palmell no dibuixen.
struct InkCanvas: UIViewRepresentable {
    let strokes: [Anotacions.Traç]
    let enabled: Bool
    let color: String
    let width: Double
    let erase: Bool
    let redraw: Int
    let onChange: ([Anotacions.Traç]) -> Void

    func makeUIView(context: Context) -> InkUIView {
        let v = InkUIView()
        v.backgroundColor = .clear
        v.isOpaque = false
        v.isMultipleTouchEnabled = false
        return v
    }

    func updateUIView(_ v: InkUIView, context: Context) {
        if !v.isTouching { v.strokes = strokes }
        v.isUserInteractionEnabled = enabled
        v.color = color
        v.width = width
        v.erase = erase
        v.onChange = onChange
        v.setNeedsDisplay()
    }
}

final class InkUIView: UIView {
    var strokes: [Anotacions.Traç] = []
    var color = "#111111"
    var width = 0.0025
    var erase = false
    var onChange: ([Anotacions.Traç]) -> Void = { _ in }
    private(set) var isTouching = false
    private var pencilSeen = false
    private var current: Int?

    override func draw(_ rect: CGRect) {
        guard let cg = UIGraphicsGetCurrentContext() else { return }
        for s in strokes { PDFTools.stroke(s, in: cg, size: bounds.size) }
    }

    private func point(_ t: UITouch) -> (Double, Double) {
        let l = t.location(in: self)
        let x = max(0, min(1, l.x / max(bounds.width, 1))), y = max(0, min(1, l.y / max(bounds.height, 1)))
        return ((x * 10000).rounded() / 10000, (y * 10000).rounded() / 10000)
    }

    private func accepts(_ t: UITouch) -> Bool {
        if t.type == .pencil { pencilSeen = true }
        return !(pencilSeen && t.type != .pencil)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = touches.first, accepts(t) else { return }
        isTouching = true
        let q = point(t)
        if erase { eraseAt(q); return }
        strokes.append(Anotacions.Traç(c: color, w: width, p: [q.0, q.1]))
        current = strokes.count - 1
        setNeedsDisplay()
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = touches.first, accepts(t) else { return }
        let all = event?.coalescedTouches(for: t) ?? [t]
        for ct in all {
            let q = point(ct)
            if erase { eraseAt(q); continue }
            guard let c = current else { continue }
            let p = strokes[c].p, n = p.count
            if abs(q.0 - p[n - 2]) + abs(q.1 - p[n - 1]) < 0.0015 { continue }
            strokes[c].p += [q.0, q.1]
        }
        setNeedsDisplay()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) { finish() }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { finish() }

    private func finish() {
        guard isTouching else { return }
        isTouching = false
        current = nil
        onChange(strokes)
    }

    private func eraseAt(_ q: (Double, Double)) {
        let r = 0.015, before = strokes.count
        strokes.removeAll { s in
            stride(from: 0, to: s.p.count - 1, by: 2).contains { abs(s.p[$0] - q.0) < r && abs(s.p[$0 + 1] - q.1) < r }
        }
        if strokes.count != before { setNeedsDisplay() }
    }
}

// MARK: - PDF únic

/// Ajunta diverses partitures en un sol PDF per enviar-lo, desar-lo al Drive o tenir-lo sense connexió.
struct PPackageView: View {
    let title: String
    let score: Bool
    let offline: Bool
    @ObservedObject private var store = PartituresStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var docs: [Fila]
    @State private var off: Set<String> = []
    @State private var name: String
    @State private var withAnn: Bool
    @State private var msg = ""
    @State private var busy = false
    @State private var result: URL?
    @State private var link: String?
    @State private var saving = false

    init(docs: [Fila], title: String, score: Bool = false, offline: Bool = false) {
        let pdfs = docs.filter(Arxiu.isPdf)
        _docs = State(initialValue: score ? Arxiu.sortScore(pdfs) : pdfs)
        self.title = title
        self.score = score
        self.offline = offline
        _name = State(initialValue: title)
        _withAnn = State(initialValue: offline)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if docs.isEmpty { PEmpty(text: "No hi ha cap PDF per ajuntar") }
                if offline {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Per tenir el programa sense connexió").fontWeight(.bold)
                        PHint(text: "Toca «Sense connexió» i les partitures es guarden dins de Guasti: el mode faristol funcionarà encara que no hi hagi cobertura, amb les teves anotacions. També pots crear el PDF i desar-lo a Fitxers o a Llibres.")
                        POfflineButton(docs: docs, small: false)
                    }
                    .padding(14)
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(P.line))
                } else {
                    PHint(text: score ? "Ordenat com un guió de director: primer la partitura general i després les particel·les (vent fusta, vent metall, percussió, corda). Pots canviar l'ordre amb les fletxes o treure'n alguna."
                        : "Tria les partitures i l'ordre. Es crearà un sol PDF per enviar als alumnes o companys.")
                    if docs.count > 1 {
                        Button("Ordena com un guió de director") {
                            docs = Arxiu.sortScore(docs)
                            toast("Ordenat com un guió")
                        }.buttonStyle(PBtn()).padding(.top, 8)
                    }
                }
                Text("Nom del PDF").font(.system(size: 13)).foregroundStyle(P.mute).padding(.top, 12).padding(.bottom, 4)
                TextField("", text: $name).pInput()
                if docs.contains(where: { !($0["Anotacions"] ?? "").isEmpty }) {
                    Toggle("Amb les meves anotacions", isOn: $withAnn).tint(P.blue).padding(.top, 12)
                }
                VStack(spacing: 0) {
                    ForEach(Array(docs.enumerated()), id: \.offset) { k, d in
                        let id = d["ID"] ?? ""
                        HStack(spacing: 10) {
                            Button {
                                if off.contains(id) { off.remove(id) } else { off.insert(id) }
                            } label: {
                                Image(systemName: off.contains(id) ? "square" : "checkmark.square.fill")
                                    .font(.system(size: 20)).foregroundStyle(off.contains(id) ? P.mute : P.blue)
                            }
                            .buttonStyle(.plain)
                            PCover(doc: d, label: " ", showFormat: false, placeholderSize: 7).frame(width: 34)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(d["Títol"] ?? "").font(.system(size: 14, weight: .medium)).lineLimit(2)
                                Text([d["Tipus"] ?? "", (d["Anotacions"] ?? "").isEmpty ? "" : "amb anotacions"].filter { !$0.isEmpty }.joined(separator: " · "))
                                    .font(.system(size: 12)).foregroundStyle(P.mute)
                            }
                            Spacer(minLength: 0)
                            Button("↑") { move(k, k - 1) }.buttonStyle(PBtn(small: true))
                            Button("↓") { move(k, k + 1) }.buttonStyle(PBtn(small: true))
                        }
                        .padding(.vertical, 6)
                        .overlay(alignment: .bottom) { Rectangle().fill(P.line).frame(height: 1) }
                    }
                }
                .padding(.top, 12)
                Button(busy ? "Creant..." : "Crea el PDF") { create() }.buttonStyle(PBtn(kind: .primary)).disabled(busy || docs.isEmpty)
                    .padding(.vertical, 14)
                if !msg.isEmpty { PHint(text: msg) }
                if let result { shareBox(result) }
            }
            .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 60)
        }
        .pScreen(offline ? "Sense connexió" : "PDF únic")
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Tanca") { dismiss() }.foregroundStyle(P.ink) } }
    }

    private func shareBox(_ url: URL) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Envia-ho").font(.system(size: 15, weight: .bold))
            FlowLayout(spacing: 8) {
                ShareLink(item: url) { Text("Envia el PDF") }.buttonStyle(PBtn(kind: .primary))
                if link == nil {
                    Button(saving ? "Desant..." : "Desa al Drive i comparteix un enllaç") { saveToDrive(url) }.buttonStyle(PBtn()).disabled(saving)
                }
            }
            if let link {
                PHint(text: "Desat a Arxiu de Repertori / Paquets. Qualsevol persona amb l'enllaç el podrà veure i descarregar:")
                PShareLinks(title: name, url: link, copy: true)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(P.line))
    }

    private func move(_ a: Int, _ b: Int) {
        guard b >= 0, b < docs.count else { return }
        docs.swapAt(a, b)
    }

    private func create() {
        let list = docs.filter { !off.contains($0["ID"] ?? "") }
        guard !list.isEmpty else { toast("Tria almenys una partitura"); return }
        busy = true
        result = nil
        link = nil
        Task {
            let out = PDFDocument()
            for (n, d) in list.enumerated() {
                msg = "Afegint \(n + 1) de \(list.count): " + (d["Títol"] ?? "")
                do {
                    var data = try await store.pdfData(Arxiu.fileId(d))
                    if withAnn && !(d["Anotacions"] ?? "").isEmpty { data = PDFTools.burn(data, await store.annotations(d)) }
                    guard let src = PDFDocument(data: data) else { throw APIError(message: "") }
                    for k in 0..<src.pageCount { if let pg = src.page(at: k)?.copy() as? PDFPage { out.insert(pg, at: out.pageCount) } }
                } catch {
                    toast("No s'ha pogut afegir " + (d["Títol"] ?? ""))
                }
            }
            let nm = (name.isEmpty ? title : name).trimmingCharacters(in: .whitespaces)
            out.documentAttributes = [PDFDocumentAttribute.titleAttribute: nm]
            if let data = out.dataRepresentation() {
                let fname = nm.replacingOccurrences(of: #"[\\/:*?"<>|]+"#, with: "-", options: .regularExpression) + ".pdf"
                result = try? store.tempFile(data, name: fname)
                msg = "Fet: \(out.pageCount) pàgines · " + String(format: "%.1f MB", Double(data.count) / 1_048_576)
            } else {
                msg = "Error: no s'ha pogut crear el PDF"
            }
            busy = false
        }
    }

    private func saveToDrive(_ url: URL) {
        saving = true
        Task {
            do {
                let data = try Data(contentsOf: url)
                let r: PPaquet = try await store.call("savePackage", [data.base64EncodedString(), url.lastPathComponent])
                link = try await store.call("makePublicLink", [r.id])
            } catch { toast("Error: " + error.localizedDescription) }
            saving = false
        }
    }
}

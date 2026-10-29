import SwiftUI
import PDFKit
import UniformTypeIdentifiers

/// Editor de pàgines d'un PDF (showPages de la web): girar, moure, treure i afegir pàgines.
/// En desar, el fitxer es canvia al Drive amb el mateix enllaç (el Drive guarda la versió anterior).
/// Si el PDF és d'una altra persona, se'n fa una còpia teva i el document passa a apuntar-hi.
struct PPagesView: View {
    let doc: Fila
    @ObservedObject private var store = PartituresStore.shared
    @Environment(\.dismiss) private var dismiss

    private struct Pg: Identifiable {
        let src: Int
        let idx: Int
        var rot = 0
        var id: String { "\(src)-\(idx)" }
    }

    @State private var srcs: [PDFDocument] = []
    @State private var pages: [Pg] = []
    @State private var sel = Set<String>()
    @State private var thumbs: [String: UIImage] = [:]
    @State private var dirty = false
    @State private var msg = "Carregant el PDF..."
    @State private var mine = true
    @State private var owner = ""
    @State private var saving = false
    @State private var adding = false
    @State private var pickingFile = false
    @State private var q = ""
    @State private var confirmExit = false

    private let columns = [GridItem(.adaptive(minimum: 104), spacing: 10, alignment: .top)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                PHint(text: msg)
                if adding { addBox }
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(Array(pages.enumerated()), id: \.element.id) { n, pg in
                        pageCell(n, pg)
                    }
                }
            }
            .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 140)
        }
        .overlay(alignment: .bottom) { if !srcs.isEmpty { bar } }
        .pScreen("Pàgines · " + (doc["Títol"] ?? ""))
        .navigationBarBackButtonHidden(dirty)
        .toolbar {
            if dirty {
                ToolbarItem(placement: .topBarLeading) { Button("Enrere") { confirmExit = true }.foregroundStyle(P.ink) }
            }
        }
        .alert("Sortir sense desar els canvis?", isPresented: $confirmExit) {
            Button("Surt sense desar", role: .destructive) { dismiss() }
            Button("Cancel·la", role: .cancel) {}
        }
        .fileImporter(isPresented: $pickingFile, allowedContentTypes: [.pdf]) { result in
            if case .success(let url) = result, let f = PickedFile.read([url]).first, let d = PDFDocument(data: f.data) {
                insert(d)
            }
        }
        .task { await load() }
    }

    private func pageCell(_ n: Int, _ pg: Pg) -> some View {
        let on = sel.contains(pg.id)
        return Button {
            if on { sel.remove(pg.id) } else { sel.insert(pg.id) }
        } label: {
            VStack(spacing: 3) {
                ZStack {
                    Color.white
                    if let img = thumbs[pg.id] {
                        Image(uiImage: img).resizable().scaledToFit()
                            .rotationEffect(.degrees(Double(pg.rot)))
                            .scaleEffect(pg.rot % 180 != 0 ? 0.72 : 1)
                            .animation(.easeOut(duration: 0.15), value: pg.rot)
                    } else {
                        ProgressView().task { thumb(pg) }
                    }
                }
                .aspectRatio(3 / 4, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(P.line))
                Text("\(n + 1)" + (pg.rot != 0 ? " · \(pg.rot)°" : "") + (pg.src > 0 ? " · nova" : ""))
                    .font(.system(size: 12)).foregroundStyle(pg.src > 0 ? P.blueInk : P.mute)
            }
            .padding(2)
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(on ? P.blue : .clear, lineWidth: 2))
        }
        .buttonStyle(.plain)
    }

    private var bar: some View {
        let ns = sel.count
        return VStack(alignment: .leading, spacing: 8) {
            Text("\(pages.count) pàgines" + (ns > 0 ? " · \(ns) seleccionades" : " · toca les pàgines per seleccionar-les") + (dirty ? " · canvis sense desar" : ""))
                .font(.system(size: 13)).foregroundStyle(P.mute)
            FlowLayout(spacing: 8) {
                Button("Gira") { rotate() }.buttonStyle(PBtn()).disabled(ns == 0).opacity(ns == 0 ? 0.4 : 1)
                Button("‹ Mou") { move(-1) }.buttonStyle(PBtn()).disabled(ns == 0).opacity(ns == 0 ? 0.4 : 1)
                Button("Mou ›") { move(1) }.buttonStyle(PBtn()).disabled(ns == 0).opacity(ns == 0 ? 0.4 : 1)
                Button("Treu") { remove() }.buttonStyle(PBtn(kind: .danger)).disabled(ns == 0).opacity(ns == 0 ? 0.4 : 1)
                Button("+ Afegeix") { withAnimation { adding.toggle() } }.buttonStyle(PBtn())
                Button(saving ? "Desant..." : "Desa") { save() }.buttonStyle(PBtn(kind: .primary))
                    .disabled(!dirty || saving).opacity(!dirty || saving ? 0.4 : 1)
            }
        }
        .padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(P.paper)
        .overlay(alignment: .top) { Rectangle().fill(P.line).frame(height: 1) }
    }

    private var addBox: some View {
        let nq = Arxiu.norm(q)
        let res = nq.count < 2 ? [] : Array(store.rows("Documents").filter { Arxiu.isPdf($0) && Arxiu.norm($0["Títol"]).contains(nq) }.prefix(30))
        return VStack(alignment: .leading, spacing: 8) {
            Text("Afegeix pàgines").font(.system(size: 15, weight: .bold))
            PHint(text: "S'afegeixen darrere de la pàgina seleccionada (o al final).")
            Button("Un PDF del mòbil o del Drive") { pickingFile = true }.buttonStyle(PBtn())
            Text("O un document de l'arxiu").font(.system(size: 13)).foregroundStyle(P.mute).padding(.top, 4)
            PSearch(placeholder: "Cerca pel nom...", text: $q)
            ForEach(res, id: \.self) { d in
                Button {
                    Task {
                        do {
                            let data = try await store.pdfData(Arxiu.fileId(d))
                            if let pdf = PDFDocument(data: data) { insert(pdf) }
                        } catch { toast("Error: " + error.localizedDescription) }
                    }
                } label: {
                    Text(d["Títol"] ?? "").frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 8).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .overlay(alignment: .bottom) { Rectangle().fill(P.line).frame(height: 1) }
            }
            Button("Tanca") { withAnimation { adding = false } }.buttonStyle(PBtn())
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(P.line))
    }

    // MARK: accions

    private func selIdx() -> [Int] { pages.indices.filter { sel.contains(pages[$0].id) } }

    private func rotate() {
        for k in selIdx() { pages[k].rot = (pages[k].rot + 90) % 360 }
        dirty = true
    }

    private func move(_ dir: Int) {
        let ix = selIdx()
        guard let first = ix.first, let last = ix.last else { return }
        if dir < 0 && first == 0 { return }
        if dir > 0 && last == pages.count - 1 { return }
        for k in (dir < 0 ? ix : ix.reversed()) { pages.swapAt(k, k + dir) }
        dirty = true
    }

    private func remove() {
        guard !sel.isEmpty else { return }
        if sel.count >= pages.count { toast("Ha de quedar almenys una pàgina"); return }
        pages.removeAll { sel.contains($0.id) }
        sel = []
        dirty = true
    }

    private func insert(_ pdf: PDFDocument) {
        let si = srcs.count
        srcs.append(pdf)
        let list = (0..<pdf.pageCount).map { Pg(src: si, idx: $0) }
        let at = (selIdx().last.map { $0 + 1 }) ?? pages.count
        pages.insert(contentsOf: list, at: at)
        sel = Set(list.map(\.id))
        dirty = true
        adding = false
        toast("\(list.count)" + (list.count > 1 ? " pàgines afegides" : " pàgina afegida"))
    }

    private func thumb(_ pg: Pg) {
        guard thumbs[pg.id] == nil, pg.src < srcs.count, let page = srcs[pg.src].page(at: pg.idx) else { return }
        thumbs[pg.id] = PDFTools.render(page, fitting: CGSize(width: 220, height: 220), scale: 2)
    }

    private func load() async {
        do {
            let fd: PPdf = try await store.call("getPdfForEdit", [Arxiu.fileId(doc)])
            guard let data = Data(base64Encoded: fd.data), let pdf = PDFDocument(data: data) else {
                throw APIError(message: "El PDF no es pot llegir.")
            }
            mine = fd.mine ?? true
            owner = fd.owner ?? ""
            srcs = [pdf]
            pages = (0..<pdf.pageCount).map { Pg(src: 0, idx: $0) }
            msg = mine ? "Toca les pàgines per seleccionar-les i fes servir els botons de sota. En desar, el fitxer es canvia al Drive (mateix enllaç; el Drive guarda la versió anterior)."
                : "Aquest PDF és de \(owner): en desar se'n farà una còpia teva editada i el document passarà a apuntar-hi."
        } catch is CancellationError {
        } catch {
            msg = "Error: " + error.localizedDescription
        }
    }

    private func save() {
        saving = true
        let order = pages
        Task {
            do {
                let out = PDFDocument()
                for pg in order {
                    guard let page = srcs[pg.src].page(at: pg.idx)?.copy() as? PDFPage else { continue }
                    if pg.rot != 0 { page.rotation = (page.rotation + pg.rot) % 360 }
                    out.insert(page, at: out.pageCount)
                }
                guard let data = out.dataRepresentation() else { throw APIError(message: "No s'ha pogut crear el PDF.") }
                let r: PSavedPdf = try await store.call("savePdf", [Arxiu.fileId(doc), data.base64EncodedString(), doc["ID"] ?? ""])
                store.replacePdf(old: Arxiu.fileId(doc), new: r.id, data: data)
                // Les anotacions segueixen les seves pàgines (les girades o esborrades es perden), com a la web
                if !(doc["Anotacions"] ?? "").isEmpty {
                    let a = await store.annotations(doc)
                    var na = Anotacions()
                    for (k, pg) in order.enumerated() where pg.src == 0 && pg.rot == 0 {
                        if let s = a.pages[String(pg.idx + 1)], !s.isEmpty { na.pages[String(k + 1)] = s }
                    }
                    try await store.saveAnnotations(doc, na)
                }
                dirty = false
                await store.load()
                toast(r.copy == true ? "Desat com a còpia teva" : "PDF desat")
                dismiss()
            } catch {
                let e = error.localizedDescription
                toast(e.contains("Drive is not defined") || e.contains("Drive no està definit")
                      ? "Falta activar el servei «Drive API» al Guasti API (Serveis +) i tornar-lo a implementar."
                      : "Error: " + e)
            }
            saving = false
        }
    }
}

struct PSavedPdf: Decodable {
    var id: String
    var url: String?
    var copy: Bool?
}

import SwiftUI

/// La fitxa d'una obra, document, concert, fagotada, agrupació o director/a (showDetail de la web).
struct PDetailView: View {
    let name: String
    let id: String
    @ObservedObject private var store = PartituresStore.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var req: PReq?
    @State private var showShare = false
    @State private var showPicker = false
    @State private var confirmDelete = false
    @State private var confirmClearAnn = false
    @State private var bookPrompt = false
    @State private var bookName = ""

    var body: some View {
        Group {
            if let r = store.find(name, id) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        PFieldList(name: name, r: r)
                        FlowLayout(spacing: 8) { actions(r) }.padding(.vertical, 14)
                        extra(r)
                    }
                    .frame(maxWidth: 760, alignment: .leading)
                    .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 60)
                    .frame(maxWidth: .infinity)
                }
                .pScreen(title(r))
            } else {
                PEmpty(text: "Aquest registre ja no hi és.").pScreen("")
            }
        }
        .modifier(PToastOverlay())
        .pPresenter($req, onDeleted: { dismiss() })
        .alert("Esborrar aquest document?", isPresented: $confirmDelete) {
            Button("Esborra", role: .destructive) { deleteDoc() }
            Button("Cancel·la", role: .cancel) {}
        } message: {
            Text("S'esborrarà de l'arxiu i del Drive. El fitxer anirà a la paperera del Drive i el podràs recuperar durant 30 dies.")
        }
        .alert("Esborrar totes les teves anotacions d'aquesta partitura?", isPresented: $confirmClearAnn) {
            Button("Esborra-les", role: .destructive) { clearAnnotations() }
            Button("Cancel·la", role: .cancel) {}
        } message: { Text("La partitura no es toca.") }
        .alert("Agrupa la carpeta com a llibre", isPresented: $bookPrompt) {
            TextField("Nom del llibre", text: $bookName)
            Button("Agrupa") { makeBook() }
            Button("Cancel·la", role: .cancel) {}
        } message: { Text("Tots els fitxers de la carpeta s'hi agruparan.") }
    }

    private func title(_ r: Fila) -> String {
        switch name {
        case "Obres": return store.obraLabel(r)
        case "Documents": return (r["Títol"] ?? "").isEmpty ? "Document" : (r["Títol"] ?? "")
        case "Concerts": return store.concertLabel(r)
        case "Fagotades": return "Fagotada " + (r["Any"] ?? "")
        default: return r[Arxiu.keys[name] ?? ""] ?? ""
        }
    }

    private var folder: String? {
        guard let r = store.find(name, id), let notes = r["Notes"],
              let m = notes.range(of: #"^Carpeta: [^·]+?\s*(·|$)"#, options: .regularExpression) else { return nil }
        var f = String(notes[m].dropFirst(9))
        if f.hasSuffix("·") { f.removeLast() }
        return f.trimmingCharacters(in: .whitespaces)
    }

    @ViewBuilder private func actions(_ r: Fila) -> some View {
        let edit = Button("Edita") { req = .form(name, r) }
        switch name {
        case "Obres":
            edit.buttonStyle(PBtn(kind: .primary))
            Button("Puja PDF o partitures") { req = .upload(["Obra": id]) }.buttonStyle(PBtn())
            Button("Enllaça fitxer del Drive") { req = .form("Documents", ["Obra": id]) }.buttonStyle(PBtn())
        case "Documents":
            let u = Arxiu.docUrl(r)
            if !u.isEmpty {
                Button("Comparteix") { withAnimation { showShare.toggle() } }.buttonStyle(PBtn(kind: .primary))
                if Arxiu.isPdf(r) {
                    Button("Anota") { req = .stand([r], title(r), draw: true) }.buttonStyle(PBtn())
                }
                if let url = URL(string: u) { Button("Obre al Drive") { openURL(url) }.buttonStyle(PBtn()) }
                edit.buttonStyle(PBtn())
                Button("Esborra") { confirmDelete = true }.buttonStyle(PBtn(kind: .danger))
            } else {
                edit.buttonStyle(PBtn(kind: .primary))
            }
            if let b = r["Llibre"], !b.isEmpty {
                NavigationLink { PBookView(name: b) } label: { Text("Obre el llibre") }.buttonStyle(PBtn())
            } else if let f = folder, f != "(arrel)" {
                Button("Agrupa la carpeta com a llibre") {
                    bookName = f.replacingOccurrences(of: #"\s*parts?$"#, with: "", options: [.regularExpression, .caseInsensitive])
                    bookPrompt = true
                }.buttonStyle(PBtn())
            }
        case "Concerts":
            edit.buttonStyle(PBtn())
            Button("Mode faristol") { req = .stand(store.concertDocs(id), title(r)) }.buttonStyle(PBtn(kind: .primary))
            Button("PDF únic") { req = .package(store.concertDocs(id), title(r)) }.buttonStyle(PBtn())
            POfflineButton(docs: store.concertDocs(id), small: false)
            Button("Afegeix partitures de l'arxiu") { withAnimation { showPicker.toggle() } }.buttonStyle(PBtn())
            Button("Puja fitxers") { req = .upload(["Concert": id]) }.buttonStyle(PBtn())
            Button("Afegeix obra") {
                req = .form("Obres", ["Concert": id, "Agrupació": r["Agrupació"] ?? "", "Director/a": r["Director/a"] ?? "", "Àmbit": "Concert"])
            }.buttonStyle(PBtn())
        case "Fagotades":
            edit.buttonStyle(PBtn(kind: .primary))
            Button("Afegeix obra") { req = .form("Obres", ["Fagotada": id, "Àmbit": "Fagotada", "Agrupació": "Fagotada"]) }.buttonStyle(PBtn())
        default:
            edit.buttonStyle(PBtn(kind: .primary))
        }
    }

    @ViewBuilder private func extra(_ r: Fila) -> some View {
        switch name {
        case "Obres":
            h3("Documents")
            PDocList(docs: store.docsFor("Obra", id), req: $req)
        case "Documents":
            if !(r["Anotacions"] ?? "").isEmpty {
                HStack(spacing: 4) {
                    Text("Aquesta partitura té anotacions teves (es veuen al mode faristol).")
                    Button("Esborra-les") { confirmClearAnn = true }.foregroundStyle(P.blueInk)
                }
                .font(.system(size: 12)).foregroundStyle(P.mute).padding(.top, -4).padding(.bottom, 10)
            }
            let cs = Arxiu.splitTags(r["Concert"]).compactMap { store.find("Concerts", $0) }
            if !cs.isEmpty {
                h3("Concerts")
                VStack(spacing: 8) {
                    ForEach(cs, id: \.self) { c in
                        NavigationLink { PDetailView(name: "Concerts", id: c["ID"] ?? "") } label: {
                            PSimpleCard(title: store.concertLabel(c), sub: [c["Lloc"] ?? "", c["Població"] ?? ""].filter { !$0.isEmpty }.joined(separator: " · "))
                        }.buttonStyle(.plain)
                    }
                }
            }
            if showShare { PShareBox(doc: r).padding(.top, 6) }
            if !Arxiu.fileId(r).isEmpty { PDocPreview(doc: r, req: $req).padding(.top, 12) }
        case "Concerts":
            if showPicker { PConcertPicker(concertId: id) { withAnimation { showPicker = false } } }
            let cds = store.docsFor("Concert", id)
            HStack(spacing: 6) {
                h3("Repertori i partitures")
                Text("\(cds.count)").font(.system(size: 13)).foregroundStyle(P.mute).padding(.top, 14)
            }
            if cds.isEmpty {
                Text("Encara no hi ha partitures. Toca «Afegeix partitures de l'arxiu».").foregroundStyle(P.mute).font(.system(size: 13))
            } else {
                LazyVGrid(columns: pGridColumns, spacing: 12) {
                    ForEach(cds, id: \.self) { d in
                        VStack(spacing: 4) {
                            NavigationLink { PDetailView(name: "Documents", id: d["ID"] ?? "") } label: {
                                PGridItem(doc: d, title: d["Títol"] ?? "", sub: d["Tipus"] ?? "")
                            }.buttonStyle(.plain)
                            PUnlinkButton(docId: d["ID"] ?? "", concertId: id)
                        }
                    }
                }
            }
            h3("Obres")
            PObraList(obres: store.rows("Obres").filter { $0["Concert"] == id })
        case "Fagotades":
            h3("Repertori")
            PObraList(obres: store.rows("Obres").filter { $0["Fagotada"] == id })
        default:
            h3("Obres")
            PObraList(obres: store.rows("Obres").filter { $0[Arxiu.keys[name] ?? ""] == id })
        }
    }

    private func h3(_ t: String) -> some View {
        Text(t).font(.system(size: 15, weight: .bold)).padding(.top, 22).padding(.bottom, 8)
    }

    private func deleteDoc() {
        Task {
            do {
                let m = try await store.deleteDocument(id)
                toast(m)
                dismiss()
            } catch { toast("Error: " + error.localizedDescription) }
        }
    }

    private func clearAnnotations() {
        guard let r = store.find(name, id) else { return }
        Task {
            do {
                try await store.saveAnnotations(r, Anotacions())
                toast("Anotacions esborrades")
            } catch { toast("Error: " + error.localizedDescription) }
        }
    }

    private func makeBook() {
        let nn = bookName.trimmingCharacters(in: .whitespaces)
        guard !nn.isEmpty, let f = folder else { return }
        Task {
            do {
                let n: FlexText = try await store.call("setLlibre", [[String](), f, nn])
                await store.load()
                toast("\(n.value) fitxers agrupats")
            } catch { toast("Error: " + error.localizedDescription) }
        }
    }
}

/// Els camps omplerts d'una fitxa (fieldView de la web).
struct PFieldList: View {
    let name: String
    let r: Fila
    @ObservedObject private var store = PartituresStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Arxiu.schema[name] ?? [], id: \.k) { f in
                if let v = r[f.k], !v.isEmpty, f.t != .files {
                    Text(Arxiu.lbl(f.k)).font(.system(size: 12)).foregroundStyle(P.mute).padding(.top, 10)
                    switch f.t {
                    case .url:
                        if let u = URL(string: v) { Link("Obre l'enllaç", destination: u).foregroundStyle(P.blueInk) } else { Text(v) }
                    case .ref: Text(store.refLabel(f.src, v))
                    case .date: Text(Arxiu.fmtDate(v))
                    default: Text(v).textSelection(.enabled)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct PObraList: View {
    let obres: [Fila]

    var body: some View {
        if obres.isEmpty {
            Text("Cap obra encara.").foregroundStyle(P.mute).font(.system(size: 13))
        } else {
            VStack(spacing: 8) {
                ForEach(obres, id: \.self) { o in
                    NavigationLink { PDetailView(name: "Obres", id: o["ID"] ?? "") } label: { ObraCard(o: o) }.buttonStyle(.plain)
                }
            }
        }
    }
}

/// Llista de documents d'una obra (.doc): portada, títol, format i Edita.
struct PDocList: View {
    let docs: [Fila]
    @Binding var req: PReq?

    var body: some View {
        if docs.isEmpty {
            Text("Cap document encara.").foregroundStyle(P.mute).font(.system(size: 13))
        } else {
            VStack(spacing: 6) {
                ForEach(docs, id: \.self) { d in
                    HStack(spacing: 10) {
                        NavigationLink { PDetailView(name: "Documents", id: d["ID"] ?? "") } label: {
                            HStack(spacing: 10) {
                                PCover(doc: d, label: " ", showFormat: false, placeholderSize: 8).frame(width: 40)
                                Text((d["Títol"] ?? "").isEmpty ? "Document" : (d["Títol"] ?? "")).fontWeight(.medium)
                                    .multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        if let f = d["Format"], !f.isEmpty {
                            Text(f).font(.system(size: 11)).foregroundStyle(P.mute)
                                .padding(.horizontal, 5).padding(.vertical, 1)
                                .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(P.line))
                        }
                        Button("Edita") { req = .form("Documents", d) }.buttonStyle(PBtn())
                    }
                    .padding(.horizontal, 12).padding(.vertical, 10)
                    .background(P.card, in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(P.line))
                }
            }
        }
    }
}

struct PUnlinkButton: View {
    let docId: String
    let concertId: String
    @State private var busy = false

    var body: some View {
        Button("Treu del concert") {
            busy = true
            Task {
                do { try await PartituresStore.shared.linkDocConcert(docId, concertId, add: false) } catch { toast("Error: " + error.localizedDescription) }
                busy = false
            }
        }
        .buttonStyle(PBtn(small: true))
        .font(.system(size: 12))
        .disabled(busy)
    }
}

/// "Afegeix partitures al concert": cerca a l'arxiu i toca per afegir.
struct PConcertPicker: View {
    let concertId: String
    let done: () -> Void
    @ObservedObject private var store = PartituresStore.shared
    @State private var q = ""
    @State private var busy = Set<String>()

    var body: some View {
        let nq = Arxiu.norm(q)
        let res = nq.count < 2 ? [] : Array(store.rows("Documents").filter { Arxiu.norm(($0["Títol"] ?? "") + " " + ($0["Llibre"] ?? "")).contains(nq) }.prefix(40))
        return VStack(alignment: .leading, spacing: 8) {
            Text("Afegeix partitures al concert").font(.system(size: 15, weight: .bold))
            PSearch(placeholder: "Cerca pel nom de l'obra o del fitxer...", text: $q)
            if !res.isEmpty {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(res, id: \.self) { d in
                            let did = d["ID"] ?? ""
                            let on = Arxiu.splitTags(d["Concert"]).contains(concertId)
                            Button {
                                guard !on, !busy.contains(did) else { return }
                                busy.insert(did)
                                Task {
                                    do { try await store.linkDocConcert(did, concertId, add: true) } catch { toast("Error: " + error.localizedDescription) }
                                    busy.remove(did)
                                }
                            } label: {
                                HStack(spacing: 10) {
                                    PCover(doc: d, label: " ", showFormat: false, placeholderSize: 6).frame(width: 30)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(d["Títol"] ?? "").multilineTextAlignment(.leading)
                                        Text([d["Tipus"] ?? "", d["Format"] ?? "", d["Llibre"] ?? ""].filter { !$0.isEmpty }.joined(separator: " · "))
                                            .font(.system(size: 12)).foregroundStyle(P.mute)
                                    }
                                    Spacer()
                                    Text(busy.contains(did) ? "..." : on ? "✓" : "+").fontWeight(.bold).foregroundStyle(P.blueInk)
                                }
                                .padding(.horizontal, 12).padding(.vertical, 10)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            Rectangle().fill(P.line).frame(height: 1)
                        }
                    }
                }
                .frame(maxHeight: 360)
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(P.line))
            }
            Button("Fet", action: done).buttonStyle(PBtn(kind: .primary))
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(P.line))
        .padding(.bottom, 12)
    }
}

// MARK: - Compositors i llibres

struct PComposerView: View {
    let name: String
    @ObservedObject private var store = PartituresStore.shared
    @State private var req: PReq?

    var body: some View {
        let k = Arxiu.norm(name)
        let obres = store.rows("Obres").filter { Arxiu.norm($0["Compositor"]) == k }.sorted { Arxiu.sortNorm($0["Obra"], $1["Obra"]) }
        let docs = store.rows("Documents").filter { Arxiu.norm($0["Compositor"]) == k }.sorted { Arxiu.sortNorm($0["Títol"], $1["Títol"]) }
        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if docs.contains(where: Arxiu.isPdf) {
                    HStack(spacing: 8) {
                        Button("Mode faristol") { req = .stand(docs, name) }.buttonStyle(PBtn(kind: .primary))
                        Button("PDF únic") { req = .package(docs, name) }.buttonStyle(PBtn())
                    }
                }
                if !obres.isEmpty {
                    countTitle("Obres", obres.count)
                    PObraList(obres: obres)
                }
                if !docs.isEmpty {
                    countTitle("Documents", docs.count)
                    LazyVGrid(columns: pGridColumns, spacing: 12) {
                        ForEach(docs, id: \.self) { d in
                            NavigationLink { PDetailView(name: "Documents", id: d["ID"] ?? "") } label: {
                                PGridItem(doc: d, title: d["Títol"] ?? "", sub: d["Tipus"] ?? "")
                            }.buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 60)
        }
        .pScreen(name)
        .modifier(PToastOverlay())
        .pPresenter($req)
    }

    private func countTitle(_ t: String, _ n: Int) -> some View {
        HStack(spacing: 6) {
            Text(t).font(.system(size: 15, weight: .bold))
            Text("\(n)").font(.system(size: 13)).foregroundStyle(P.mute)
        }
        .padding(.top, 22).padding(.bottom, 8)
    }
}

struct PBooksView: View {
    @ObservedObject private var store = PartituresStore.shared

    var body: some View {
        let bk = store.books()
        let names = bk.keys.sorted { Arxiu.sortNorm($0, $1) }
        return ScrollView {
            if names.isEmpty {
                PEmpty(text: "Encara no hi ha cap llibre.")
            } else {
                LazyVGrid(columns: pGridColumns, spacing: 12) {
                    ForEach(names, id: \.self) { n in
                        NavigationLink { PBookView(name: n) } label: {
                            PGridItem(doc: store.bookCover(bk[n] ?? []), title: n, sub: "\(bk[n]?.count ?? 0) fitxers")
                        }.buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 60)
            }
        }
        .pScreen("Llibres")
    }
}

struct PBookView: View {
    let name: String
    @ObservedObject private var store = PartituresStore.shared
    @AppStorage("arxiu.view") private var viewMode = "grid"
    @Environment(\.dismiss) private var dismiss
    @State private var req: PReq?
    @State private var busy: String?
    @State private var renaming = false
    @State private var newName = ""
    @State private var confirmUndo = false

    var body: some View {
        let docs = store.rows("Documents").filter { $0["Llibre"] == name }.sorted { Arxiu.sortNorm($0["Títol"], $1["Títol"]) }
        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                PCount("\(docs.count) fitxers en aquest llibre") {
                    PViewToggle(list: Binding(get: { viewMode == "list" }, set: { viewMode = $0 ? "list" : "grid" }))
                }
                if viewMode == "list" {
                    VStack(spacing: 0) {
                        ForEach(docs, id: \.self) { d in
                            NavigationLink { PDetailView(name: "Documents", id: d["ID"] ?? "") } label: {
                                PListRow(doc: d, title: short(d), sub: [d["Tipus"] ?? "", d["Format"] ?? ""].filter { !$0.isEmpty }.joined(separator: " · "))
                            }.buttonStyle(.plain)
                        }
                    }
                    .overlay(alignment: .top) { Rectangle().fill(P.line).frame(height: 1) }
                } else {
                    LazyVGrid(columns: pGridColumns, spacing: 12) {
                        ForEach(docs, id: \.self) { d in
                            NavigationLink { PDetailView(name: "Documents", id: d["ID"] ?? "") } label: {
                                PGridItem(doc: d, title: short(d), sub: d["Tipus"] ?? "")
                            }.buttonStyle(.plain)
                        }
                    }
                }
                FlowLayout(spacing: 8) {
                    Button("Mode faristol") { req = .stand(docs, name) }.buttonStyle(PBtn(kind: .primary))
                    Button("PDF únic (guió + particel·les)") { req = .package(docs, name, score: true) }.buttonStyle(PBtn())
                    Button(busy ?? "Ajunta-ho en una carpeta del Drive") { moveBook(docs.count) }.buttonStyle(PBtn()).disabled(busy != nil)
                    Button("Canvia el nom") { newName = name; renaming = true }.buttonStyle(PBtn())
                    Button("Desfes el llibre") { confirmUndo = true }.buttonStyle(PBtn(kind: .danger))
                }
                .padding(.top, 20)
            }
            .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 60)
        }
        .pScreen(name)
        .modifier(PToastOverlay())
        .pPresenter($req)
        .alert("Nom del llibre", isPresented: $renaming) {
            TextField("Nom del llibre", text: $newName)
            Button("Desa") { setBook(docs, newName.trimmingCharacters(in: .whitespaces), "Nom canviat") }
            Button("Cancel·la", role: .cancel) {}
        }
        .alert("Tornar a mostrar aquests fitxers per separat?", isPresented: $confirmUndo) {
            Button("Desfes el llibre", role: .destructive) { setBook(docs, "", "Llibre desfet") }
            Button("Cancel·la", role: .cancel) {}
        } message: { Text("No s'esborra res.") }
    }

    private func short(_ d: Fila) -> String {
        let tt = d["Títol"] ?? "", sx = " - " + name
        return tt.lowercased().hasSuffix(sx.lowercased()) ? String(tt.dropLast(sx.count)) : tt
    }

    private func moveBook(_ n: Int) {
        busy = "Movent \(n) fitxers..."
        Task {
            do {
                let m: String = try await store.call("moveBook", [name])
                await store.load()
                toast(m)
            } catch { toast("Error: " + error.localizedDescription) }
            busy = nil
        }
    }

    private func setBook(_ docs: [Fila], _ nn: String, _ msg: String) {
        guard nn != name else { return }
        Task {
            do {
                let _: FlexText = try await store.call("setLlibre", [docs.map { $0["ID"] ?? "" }, "", nn])
                await store.load()
                toast(msg)
                dismiss()
            } catch { toast("Error: " + error.localizedDescription) }
        }
    }
}

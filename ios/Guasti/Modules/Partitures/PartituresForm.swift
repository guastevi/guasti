import SwiftUI
import UniformTypeIdentifiers

/// Nova fitxa o Edita (showForm de la web), també per a la revisió dels documents un per un.
struct PFormView: View {
    let name: String
    @State var row: Fila
    var review = false
    var onDeleted: () -> Void = {}
    @Environment(\.dismiss) private var dismiss

    init(name: String, row: Fila, review: Bool = false, onDeleted: @escaping () -> Void = {}) {
        self.name = name
        _row = State(initialValue: row)
        self.review = review
        self.onDeleted = onDeleted
    }

    var body: some View {
        PFormBody(name: name, row: row, review: review, onDeleted: onDeleted) {
            if review, let n = PReview.shared.next() { row = n } else {
                if review { toast("No queda res per revisar") }
                dismiss()
            }
        }
        .id(row["ID"] ?? row[Arxiu.keys[name] ?? ""] ?? "nou")
    }
}

private struct PFormBody: View {
    let name: String
    let row: Fila
    let review: Bool
    let onDeleted: () -> Void
    let next: () -> Void
    @ObservedObject private var store = PartituresStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var vals: Fila = [:]
    @State private var files: [PickedFile] = []
    @State private var picking = false
    @State private var saving = false
    @State private var progress = ""
    @State private var confirmDelete = false

    init(name: String, row: Fila, review: Bool, onDeleted: @escaping () -> Void, next: @escaping () -> Void) {
        self.name = name
        self.row = row
        self.review = review
        self.onDeleted = onDeleted
        self.next = next
        var v: Fila = [:]
        for f in Arxiu.schema[name] ?? [] {
            if f.t == .files { v["__tipus"] = f.src } else { v[f.k] = row[f.k] ?? "" }
        }
        _vals = State(initialValue: v)
    }

    private var key: String { Arxiu.keys[name] ?? "ID" }

    private var isNew: Bool {
        if ["Agrupacions", "Directors", "Fagotades"].contains(name) { return store.find(name, row[key] ?? "") == nil }
        return (row[key] ?? "").isEmpty
    }

    private var title: String {
        if review { return "Revisió" }
        if !isNew { return "Edita" }
        let fem = ["Obres", "Agrupacions", "Fagotades"].contains(name)
        return (fem ? "Nova " : "Nou ") + (Arxiu.singular[name] ?? "")
    }

    private var previewDoc: Fila? {
        if name == "Documents" { return Arxiu.fileId(row).isEmpty ? nil : row }
        if name == "Obres", let id = row["ID"], !id.isEmpty, let d = store.firstDoc("Obra", id), !Arxiu.fileId(d).isEmpty { return d }
        return nil
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if review { reviewHint }
                if let pd = previewDoc {
                    DisclosureGroup {
                        PDocPreview(doc: pd, req: .constant(nil)).frame(maxHeight: 260).clipped().padding(.top, 8)
                        if let t = pd["Títol"], !t.isEmpty { PHint(text: "Nom del fitxer: " + t).padding(.top, 6) }
                    } label: {
                        Text("Portada del PDF").font(.system(size: 13)).foregroundStyle(P.mute)
                    }
                    .tint(P.mute)
                    .padding(.bottom, 6)
                }
                ForEach(Arxiu.schema[name] ?? [], id: \.k) { f in
                    if visible(f) { field(f) }
                }
                FlowLayout(spacing: 8) {
                    Button(saving ? "Desant..." : review ? "Desa i següent" : "Desa") { save() }
                        .buttonStyle(PBtn(kind: .primary)).disabled(saving)
                    if review { Button("Salta") { PReview.shared.skip.insert(row["ID"] ?? ""); next() }.buttonStyle(PBtn()) }
                    if !isNew { Button("Elimina") { confirmDelete = true }.buttonStyle(PBtn(kind: .danger)) }
                }
                .padding(.vertical, 14)
                if !progress.isEmpty { PHint(text: progress) }
            }
            .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 60)
        }
        .scrollDismissesKeyboard(.interactively)
        .pScreen(title)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Tanca") { dismiss() }.foregroundStyle(P.ink) }
        }
        .alert(name == "Documents" ? "Esborrar «\(row["Títol"] ?? "aquest document")» de l'arxiu i del Drive?" : "Eliminar aquest registre?",
               isPresented: $confirmDelete) {
            Button(name == "Documents" ? "Esborra" : "Elimina", role: .destructive) { delete() }
            Button("Cancel·la", role: .cancel) {}
        } message: {
            if name == "Documents" { Text("El fitxer anirà a la paperera del Drive i el podràs recuperar durant 30 dies.") }
        }
        .fileImporter(isPresented: $picking, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
            if case .success(let urls) = result { files += PickedFile.read(urls).filter { f in !files.contains { $0.name == f.name && $0.data.count == f.data.count } } }
        }
    }

    private var reviewHint: some View {
        let notes = row["Notes"] ?? ""
        var folder = ""
        if notes.hasPrefix("Carpeta:"), let r = notes.range(of: #"Carpeta: [^·]*"#, options: .regularExpression) { folder = String(notes[r].dropFirst(9)) }
        return VStack(alignment: .leading, spacing: 2) {
            (Text("Revisió: en queden ") + Text("\(PReview.shared.remaining)").bold() + Text(". Omple el que falti i toca «Desa i següent»."))
            if !folder.isEmpty { Text(folder) }
        }
        .font(.system(size: 12)).foregroundStyle(P.mute).padding(.bottom, 8)
    }

    // MARK: visibilitat (updateVis de la web)

    private func visible(_ f: Arxiu.Camp) -> Bool {
        if f.k == "Formació" {
            let cat = vals["Categoria"] ?? ""
            return cat.isEmpty || !store.chipOptions("F:" + cat).isEmpty || !(vals["Formació"] ?? "").isEmpty
        }
        guard !f.showIf.isEmpty else { return true }
        if !(vals[f.k] ?? "").isEmpty { return true }
        return f.showIf.split(separator: ";").contains { rule in
            let r = String(rule)
            guard let op = r.firstIndex(where: { $0 == "=" || $0 == "~" }) else { return false }
            let k = String(r[..<op]), allowed = r[r.index(after: op)...].split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            let cur = vals[k] ?? ""
            if r[op] == "~" { return allowed.contains { Arxiu.splitTags(cur).contains($0) } }
            return allowed.contains(cur)
        }
    }

    private func bind(_ k: String) -> Binding<String> {
        Binding(get: { vals[k] ?? "" }, set: { v in
            if k == "Categoria", v != vals[k] { vals["Formació"] = "" }
            vals[k] = v
        })
    }

    @ViewBuilder private func label(_ k: String, star: Bool = false) -> some View {
        HStack(spacing: 3) {
            Text(Arxiu.lbl(k))
            if star { Text("*").bold().foregroundStyle(P.blueInk) }
        }
        .font(.system(size: 13)).foregroundStyle(P.mute).padding(.top, 12).padding(.bottom, 4)
        if let h = Arxiu.hints[k] { Text(h).font(.system(size: 12)).foregroundStyle(P.mute).padding(.top, -2).padding(.bottom, 6) }
    }

    @ViewBuilder private func field(_ f: Arxiu.Camp) -> some View {
        switch f.t {
        case .multi:
            label(f.k)
            PChipsField(options: store.chipOptions(f.src), value: bind(f.k), multi: true)
        case .chips:
            label(f.k)
            if f.src == "F:" && (vals["Categoria"] ?? "").isEmpty && (vals[f.k] ?? "").isEmpty {
                PHint(text: "Tria primer la categoria.")
            } else {
                PChipsField(options: store.chipOptions(f.src == "F:" ? "F:" + (vals["Categoria"] ?? "") : f.src), value: bind(f.k), multi: false)
            }
        case .files:
            filesSection
        case .ref:
            label(f.k)
            PRefPicker(sheet: f.src, value: bind(f.k))
        case .comp:
            label(f.k, star: true)
            PSuggestField(placeholder: "Ex.: Mozart, Weissenborn, Popular...", text: bind(f.k),
                          options: Arxiu.uniq(store.rows("Obres").map { $0["Compositor"] } + store.rows("Documents").map { $0["Compositor"] }))
        case .book:
            label(f.k)
            PSuggestField(placeholder: "Sense llibre", text: bind(f.k), options: Arxiu.uniq(store.rows("Documents").map { $0["Llibre"] }))
        case .area:
            label(f.k)
            TextEditor(text: bind(f.k))
                .scrollContentBackground(.hidden)
                .frame(minHeight: 80)
                .padding(6)
                .background(P.card, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(P.line))
        case .check:
            Button {
                vals[f.k] = (vals[f.k] ?? "").isEmpty ? "Sí" : ""
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: (vals[f.k] ?? "").isEmpty ? "square" : "checkmark.square.fill")
                        .font(.system(size: 20)).foregroundStyle((vals[f.k] ?? "").isEmpty ? P.mute : P.blue)
                    Text(f.k)
                }
            }
            .buttonStyle(.plain)
            .padding(.top, 12)
        case .date:
            label(f.k)
            PDateField(value: bind(f.k), time: false)
        case .time:
            label(f.k)
            PDateField(value: bind(f.k), time: true)
        case .number, .url, .text:
            label(f.k)
            TextField("", text: bind(f.k))
                .keyboardType(f.t == .number ? .decimalPad : f.t == .url ? .URL : .default)
                .textInputAutocapitalization(f.t == .url ? .never : .sentences)
                .autocorrectionDisabled(f.t == .url)
                .pInput()
        }
    }

    private var filesSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle().fill(P.line).frame(height: 1).padding(.top, 26)
            Text("Partitures i fitxers").font(.system(size: 15, weight: .bold)).padding(.top, 22).padding(.bottom, 2)
            label("__tipus")
            PChipsField(options: store.llista("Tipus document"), value: bind("__tipus"), multi: true)
            PFilePickerBox(files: $files, picking: $picking,
                           text: "Afegeix els PDF, MusicXML, MuseScore, Notion o àudios")
                .padding(.top, 10)
        }
    }

    // MARK: desar i eliminar

    private func save() {
        var o: Fila = [:]
        for f in Arxiu.schema[name] ?? [] where f.t != .files {
            o[f.k] = (vals[f.k] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let tipus = vals["__tipus"] ?? ""
        if name == "Concerts" && (o["Data"] ?? "").isEmpty { toast("Posa la data del concert perquè surti a Inici"); return }
        if name == "Obres" && (o["Obra"] ?? "").isEmpty && (o["Compositor"] ?? "").isEmpty {
            toast("Posa almenys el títol de l'obra o el compositor"); return
        }
        if name == "Documents" { o["Revisat"] = "Sí" }
        let original = isNew ? nil : row[key]
        // Les dades que ja venien de fora (p. ex. l'obra d'un document nou) es conserven
        for (k, v) in row where o[k] == nil && !k.hasPrefix("__") && isNew { o[k] = v }
        if let original, files.isEmpty {
            store.saveInBackground(name, o, original: original)
            if review { PReview.shared.skip.insert(row["ID"] ?? "") }
            next()
            return
        }
        saving = true
        Task {
            do {
                let newId = try await store.save(name, o, original: original)
                if !files.isEmpty {
                    var meta: Fila = ["Tipus": tipus]
                    meta[name == "Concerts" ? "Concert" : "Obra"] = newId
                    try await store.upload(files, meta: meta) { progress = $0 }
                }
                toast(files.isEmpty ? "Desat" : "Desat amb \(files.count)" + (files.count > 1 ? " fitxers" : " fitxer"))
                if review { PReview.shared.skip.insert(row["ID"] ?? "") }
                next()
            } catch {
                toast("Error: " + error.localizedDescription)
            }
            saving = false
        }
    }

    private func delete() {
        Task {
            do {
                if name == "Documents" { toast(try await store.deleteDocument(row["ID"] ?? "")) } else {
                    try await store.deleteRow(name, row[key] ?? "")
                    toast("Eliminat")
                }
                dismiss()
                onDeleted()
            } catch { toast("Error: " + error.localizedDescription) }
        }
    }
}

extension View {
    func pInput() -> some View {
        self.padding(10)
            .background(P.card, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(P.line))
    }
}

// MARK: - Camps

/// Botons per triar (un o diversos) i "+ Afegeix" per escriure'n un de nou.
struct PChipsField: View {
    let options: [String]
    @Binding var value: String
    let multi: Bool
    @State private var adding = false
    @State private var newValue = ""
    @State private var extra: [String] = []
    @FocusState private var focused: Bool

    var body: some View {
        let sel = multi ? Arxiu.splitTags(value) : (value.isEmpty ? [] : [value])
        var all = options
        for x in sel + extra where !all.contains(x) { all.append(x) }
        return FlowLayout(spacing: 8) {
            ForEach(all, id: \.self) { o in
                PChip(text: o, on: sel.contains(o)) { toggle(o) }
            }
            if adding {
                HStack(spacing: 6) {
                    TextField("Nou valor...", text: $newValue)
                        .focused($focused)
                        .onSubmit(add)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .frame(minWidth: 160)
                        .overlay(Capsule().strokeBorder(P.line))
                    PChip(text: "Afegeix", on: true, action: add)
                }
            } else {
                Button {
                    adding = true
                    focused = true
                } label: {
                    Text("+ Afegeix").font(.system(size: 14)).foregroundStyle(P.mute)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .overlay(Capsule().strokeBorder(P.line, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func toggle(_ v: String) {
        if !multi { value = value == v ? "" : v; return }
        var sel = Arxiu.splitTags(value)
        if let i = sel.firstIndex(of: v) { sel.remove(at: i) } else { sel.append(v) }
        value = sel.joined(separator: ", ")
    }

    private func add() {
        let v = newValue.trimmingCharacters(in: .whitespaces)
        if !v.isEmpty {
            if !options.contains(v) && !extra.contains(v) { extra.append(v) }
            if multi {
                var sel = Arxiu.splitTags(value)
                if !sel.contains(v) { sel.append(v) }
                value = sel.joined(separator: ", ")
            } else {
                value = v
            }
        }
        newValue = ""
        adding = false
    }
}

/// Desplegable per triar una obra o un concert de l'arxiu.
struct PRefPicker: View {
    let sheet: String
    @Binding var value: String
    @ObservedObject private var store = PartituresStore.shared

    var body: some View {
        var rs = store.rows(sheet)
        if sheet == "Concerts" { rs.sort { ($0["Data"] ?? "") > ($1["Data"] ?? "") } }
        let k = Arxiu.keys[sheet] ?? "ID"
        return Menu {
            Picker("", selection: $value) {
                Text("—").tag("")
                ForEach(rs, id: \.self) { r in Text(store.refLabel(sheet, r[k])).tag(r[k] ?? "") }
            }
        } label: {
            HStack {
                Text(value.isEmpty ? " " : store.refLabel(sheet, value)).foregroundStyle(P.ink).multilineTextAlignment(.leading)
                Spacer()
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 11)).foregroundStyle(P.mute)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .pInput()
        }
    }
}

/// Camp de text amb suggeriments (datalist de la web).
struct PSuggestField: View {
    let placeholder: String
    @Binding var text: String
    let options: [String]
    @FocusState private var focused: Bool

    var body: some View {
        let q = Arxiu.norm(text)
        let sug = focused && !q.isEmpty ? Array(options.filter { Arxiu.norm($0).contains(q) && $0 != text }.prefix(8)) : []
        return VStack(alignment: .leading, spacing: 6) {
            TextField(placeholder, text: $text).focused($focused).autocorrectionDisabled().pInput()
            if !sug.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(sug, id: \.self) { s in PChip(text: s, small: true) { text = s; focused = false } }
                }
            }
        }
    }
}

/// Data (AAAA-MM-DD) o hora (HH:MM), com els camps date/time de la web.
struct PDateField: View {
    @Binding var value: String
    let time: Bool

    private var fmt: DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = time ? "HH:mm" : "yyyy-MM-dd"
        return f
    }

    var body: some View {
        HStack {
            if let d = fmt.date(from: String(value.prefix(time ? 5 : 10))) {
                DatePicker("", selection: Binding(get: { d }, set: { value = fmt.string(from: $0) }),
                           displayedComponents: time ? .hourAndMinute : .date)
                    .labelsHidden()
                    .environment(\.locale, Locale(identifier: "ca_ES"))
                Spacer()
                Button("Treu") { value = "" }.buttonStyle(PBtn(small: true))
            } else {
                Button(time ? "Posa l'hora" : "Posa la data") {
                    value = time ? "20:00" : fmt.string(from: Date())
                }
                .buttonStyle(PBtn())
                if !value.isEmpty { Text(value).foregroundStyle(P.mute) }
                Spacer()
            }
        }
    }
}

/// La caixa per afegir fitxers i la llista dels triats, amb "Treu".
struct PFilePickerBox: View {
    @Binding var files: [PickedFile]
    @Binding var picking: Bool
    let text: String

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                Text(text + ", o").font(.system(size: 14)).foregroundStyle(P.mute).multilineTextAlignment(.center)
                Button("Afegeix fitxers") { picking = true }.buttonStyle(PBtn())
                Text("Pots tornar a tocar «Afegeix fitxers» per afegir-ne d'altres carpetes.")
                    .font(.system(size: 12)).foregroundStyle(P.mute).multilineTextAlignment(.center)
            }
            .padding(16)
            .frame(maxWidth: .infinity)
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(P.line, style: StrokeStyle(lineWidth: 2, dash: [6, 4])))
            .padding(.bottom, 8)
            ForEach(files) { f in
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(f.name).font(.system(size: 14, weight: .medium)).lineLimit(1)
                        Text(String(format: "%.1f MB", Double(f.data.count) / 1_048_576)).font(.system(size: 12)).foregroundStyle(P.mute)
                    }
                    Spacer()
                    Button("Treu") { files.removeAll { $0.id == f.id } }.buttonStyle(PBtn(small: true))
                }
                .padding(.vertical, 6)
                .overlay(alignment: .bottom) { Rectangle().fill(P.line).frame(height: 1) }
            }
        }
    }
}

extension PickedFile {
    static func read(_ urls: [URL]) -> [PickedFile] {
        urls.compactMap { url in
            let ok = url.startAccessingSecurityScopedResource()
            defer { if ok { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url) else { return nil }
            return PickedFile(name: url.lastPathComponent, data: data)
        }
    }
}

// MARK: - Pujar fitxers, eines i inventari

struct PUploadView: View {
    let meta: Fila
    @ObservedObject private var store = PartituresStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var tipus: String
    @State private var obra = ""
    @State private var tema: String
    @State private var files: [PickedFile] = []
    @State private var picking = false
    @State private var busy = false
    @State private var progress = ""

    init(meta: Fila) {
        self.meta = meta
        _tipus = State(initialValue: meta["Tipus"] ?? "Particel·la")
        _tema = State(initialValue: meta["Formació"] ?? "")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                fieldLabel("Tipus")
                PChipsField(options: store.llista("Tipus document"), value: $tipus, multi: true)
                if meta["Categoria"] == "Llibres" {
                    fieldLabel("Tema")
                    PChipsField(options: store.llista("Formació: Llibres"), value: $tema, multi: false)
                } else if meta["Obra"] == nil && meta["Concert"] == nil {
                    fieldLabel("Obra")
                    PRefPicker(sheet: "Obres", value: $obra)
                }
                fieldLabel("Fitxers (PDF, MusicXML, MuseScore, Notion, àudio...)")
                PFilePickerBox(files: $files, picking: $picking, text: "Tria els fitxers del mòbil o del Drive")
                Button(busy ? "Pujant..." : files.isEmpty ? "Puja" : "Puja \(files.count)" + (files.count > 1 ? " fitxers" : " fitxer")) { upload() }
                    .buttonStyle(PBtn(kind: .primary)).disabled(busy).padding(.vertical, 14)
                if !progress.isEmpty { PHint(text: progress) }
            }
            .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 60)
        }
        .pScreen("Puja fitxers")
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Tanca") { dismiss() }.foregroundStyle(P.ink) } }
        .fileImporter(isPresented: $picking, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
            if case .success(let urls) = result { files += PickedFile.read(urls) }
        }
    }

    private func fieldLabel(_ k: String) -> some View {
        Text(Arxiu.lbl(k)).font(.system(size: 13)).foregroundStyle(P.mute).padding(.top, 12).padding(.bottom, 4)
    }

    private func upload() {
        guard !files.isEmpty else { toast("Tria algun fitxer"); return }
        var m = meta
        if !tipus.isEmpty { m["Tipus"] = tipus }
        if !obra.isEmpty { m["Obra"] = obra }
        if meta["Categoria"] == "Llibres" { m["Formació"] = tema }
        if m["Formació"] == "" { m["Formació"] = nil }
        busy = true
        Task {
            do {
                try await store.upload(files, meta: m) { progress = $0 }
                toast("\(files.count) fitxers pujats")
                dismiss()
            } catch { toast("Error: " + error.localizedDescription) }
            busy = false
        }
    }
}

/// "Afegeix document" i les eines de l'inventari del Drive.
struct PToolsView: View {
    @ObservedObject private var store = PartituresStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var msg = ""
    @State private var running = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                FlowLayout(spacing: 8) {
                    NavigationLink { PUploadView(meta: [:]) } label: { Text("Puja fitxers") }.buttonStyle(PBtn(kind: .primary))
                    NavigationLink { PFormView(name: "Documents", row: [:]) } label: { Text("Enllaça un fitxer del Drive") }.buttonStyle(PBtn())
                }
                .padding(.vertical, 14)
                Text("Inventari del Drive").font(.system(size: 15, weight: .bold)).padding(.top, 8).padding(.bottom, 8)
                Text("Busca al teu Drive tots els PDFs i fitxers de partitura nous i els afegeix a l'arxiu amb el seu enllaç. No mou cap fitxer.")
                    .font(.system(size: 13)).foregroundStyle(P.mute)
                FlowLayout(spacing: 8) {
                    Button("Fes l'inventari") { inventari() }.buttonStyle(PBtn()).disabled(running)
                    NavigationLink { PInventariReview() } label: { Text("Revisa els pendents") }.buttonStyle(PBtn())
                    Button("Classifica automàticament") { classifica() }.buttonStyle(PBtn()).disabled(running)
                }
                .padding(.vertical, 14)
                if !msg.isEmpty { Text(msg).font(.system(size: 13)).foregroundStyle(P.mute) }
            }
            .padding(.horizontal, 16).padding(.top, 4).padding(.bottom, 60)
        }
        .pScreen("Afegeix document")
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Tanca") { dismiss() }.foregroundStyle(P.ink) } }
    }

    private func inventari() {
        running = true
        Task {
            do {
                while true {
                    msg = "Revisant el Drive..."
                    let m: String = try await store.call("inventari")
                    msg = m
                    if !m.contains("parcial") { break }
                }
                await store.load()
            } catch { msg = "Error: " + error.localizedDescription }
            running = false
        }
    }

    private func classifica() {
        running = true
        msg = "Classificant..."
        Task {
            do {
                msg = try await store.call("classificaDocuments")
                await store.load()
            } catch { msg = "Error: " + error.localizedDescription }
            running = false
        }
    }
}

/// Fitxers del Drive que pel nom no semblaven música: Sí per afegir-los, No per descartar-los.
struct PInventariReview: View {
    @ObservedObject private var store = PartituresStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var list: [PInventari]?
    @State private var busy = Set<String>()
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                if let error {
                    PEmpty(text: "Error: " + error)
                } else if let list {
                    if list.isEmpty {
                        PEmpty(text: "No queda res per revisar.")
                    } else {
                        (Text("\(list.count) fitxers que pel nom no semblaven música. Toca ") + Text("Sí").bold() +
                            Text(" per afegir-los a l'arxiu o ") + Text("No").bold() + Text(" per descartar-los (es queden al Drive igualment)."))
                            .font(.system(size: 12)).foregroundStyle(P.mute).padding(.bottom, 6)
                        ForEach(list) { r in row(r) }
                    }
                } else {
                    Text("Carregant...").foregroundStyle(P.mute).frame(maxWidth: .infinity).padding(.vertical, 60)
                }
            }
            .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 60)
        }
        .pScreen("Revisa els pendents")
        .task {
            do { list = try await store.call("getInventariRows") } catch { self.error = error.localizedDescription }
        }
    }

    private func row(_ r: PInventari) -> some View {
        let d: Fila = ["Enllaç Drive": r.url?.value ?? "", "Format": r.fmt?.value ?? "", "Títol": r.t.value]
        return HStack(spacing: 10) {
            PCover(doc: d, label: " ", showFormat: false, placeholderSize: 8).frame(width: 40)
            VStack(alignment: .leading, spacing: 2) {
                if let u = URL(string: r.url?.value ?? "") { Link(r.t.value, destination: u).foregroundStyle(P.ink).fontWeight(.medium) } else { Text(r.t.value) }
                if let f = r.folder?.value, !f.isEmpty { Text(f).font(.system(size: 12)).foregroundStyle(P.mute) }
            }
            Spacer(minLength: 0)
            Button("Sí") { decide(r, true) }.buttonStyle(PBtn(kind: .primary)).disabled(busy.contains(r.id))
            Button("No") { decide(r, false) }.buttonStyle(PBtn()).disabled(busy.contains(r.id))
        }
        .opacity(busy.contains(r.id) ? 0.4 : 1)
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(P.card, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(P.line))
    }

    private func decide(_ r: PInventari, _ include: Bool) {
        busy.insert(r.id)
        Task {
            do {
                let _: FlexText = try await store.call("decideInventari", [r.id, include])
                list?.removeAll { $0.id == r.id }
                toast(include ? "Afegit a l'arxiu" : "Descartat")
                if include { await store.load() }
            } catch { toast("Error: " + error.localizedDescription) }
            busy.remove(r.id)
        }
    }
}

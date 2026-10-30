import SwiftUI

// Les peces de la interfície de l'app web (Index.html): targetes, etiquetes, botons, xips i portades.

/// Portada: la miniatura de la primera pàgina que fa el Drive, amb el títol a sota mentre no arriba.
struct PCover: View {
    let doc: Fila?
    var label: String? = nil
    var showFormat = true
    var placeholderSize: CGFloat = 12
    @ObservedObject private var store = PartituresStore.shared

    var body: some View {
        let id = doc.map(Arxiu.fileId) ?? ""
        let fmt = doc?["Format"] ?? ""
        RoundedRectangle(cornerRadius: 8)
            .fill(P.chip)
            .aspectRatio(3 / 4, contentMode: .fit)
            .overlay {
                Text(label ?? doc?["Títol"] ?? "")
                    .font(.system(size: placeholderSize, weight: .semibold))
                    .foregroundStyle(P.mute)
                    .multilineTextAlignment(.center)
                    .padding(placeholderSize < 10 ? 2 : 8)
            }
            .overlay {
                if !id.isEmpty, let img = store.thumbs[id] ?? store.thumb(id) {
                    Color.white.overlay(alignment: .top) {
                        Image(uiImage: img).resizable().scaledToFill()
                    }
                    .clipped()
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if showFormat, !fmt.isEmpty, fmt != "PDF" {
                    Text(fmt)
                        .font(.system(size: 10))
                        .foregroundStyle(P.mute)
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(P.card, in: RoundedRectangle(cornerRadius: 4))
                        .padding(6)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(P.line))
    }
}

struct PTag: View {
    let text: String
    var accent = false

    var body: some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(accent ? P.blueInk : P.ink)
            .padding(.horizontal, 7).padding(.vertical, 1)
            .background(accent ? P.accentSoft : P.chip, in: RoundedRectangle(cornerRadius: 6))
    }
}

/// Etiquetes en files que salten de línia.
struct PTags: View {
    let tags: [(String, Bool)]

    var body: some View {
        if !tags.isEmpty {
            FlowLayout(spacing: 4) {
                ForEach(Array(tags.enumerated()), id: \.offset) { PTag(text: $0.element.0, accent: $0.element.1) }
            }
            .padding(.top, 6)
        }
    }
}

extension View {
    /// La targeta .card de la web: blanca, vora fina i cantonades de 12.
    func pCard(padding: Bool = true) -> some View {
        self.padding(.horizontal, padding ? 14 : 0)
            .padding(.vertical, padding ? 12 : 0)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(P.card, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(P.line))
            .contentShape(RoundedRectangle(cornerRadius: 12))
    }

    /// Pantalla de l'arxiu: fons, lletra del sistema i títol en negreta com els h2 de la web.
    func pScreen(_ title: String) -> some View {
        self.background(P.paper.ignoresSafeArea())
            .foregroundStyle(P.ink)
            .font(.system(size: 15))
            .tint(P.ink)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(P.paper, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(title).font(.system(size: 18, weight: .bold)).lineLimit(1)
                }
            }
    }
}

/// Els botons .btn de la web: normal, principal (negre) i perill (vermell).
struct PBtn: ButtonStyle {
    enum Kind { case normal, primary, danger }
    var kind: Kind = .normal
    var small = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: small ? 13 : 15))
            .foregroundStyle(kind == .primary ? P.onAccent : kind == .danger ? P.danger : P.ink)
            .padding(.horizontal, small ? 10 : 12)
            .padding(.vertical, small ? 5 : 8)
            .background(kind == .primary ? P.accent : P.card, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(kind == .primary ? P.accent : P.line))
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

/// Xip arrodonit: blau quan està triat.
struct PChip: View {
    let text: String
    var on = false
    var small = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(text)
                .font(.system(size: small ? 13 : 14))
                .lineLimit(1)
                .foregroundStyle(on ? .white : P.ink)
                .padding(.horizontal, small ? 10 : 14)
                .padding(.vertical, small ? 6 : 8)
                .background(on ? P.blue : P.card, in: Capsule())
                .overlay(Capsule().strokeBorder(on ? P.blue : P.line))
        }
        .buttonStyle(.plain)
    }
}

/// Fila de xips que es desplaça de costat (.catbar).
struct PCatBar: View {
    /// (nom que es veu, valor)
    let items: [(String, String)]
    let selected: String
    var small = false
    let pick: (String) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(items, id: \.1) { it in
                    PChip(text: it.0, on: it.1 == selected, small: small) { pick(it.1) }
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.horizontal, -16)
        .padding(.bottom, 10)
    }
}

/// El desplegable de filtres de la web (select): el primer valor és el nom del filtre.
struct PFilter: View {
    let label: String
    let values: [String]
    @Binding var selection: String
    var display: (String) -> String = { $0 }

    var body: some View {
        Menu {
            Picker(label, selection: $selection) {
                Text(label).tag("")
                ForEach(values, id: \.self) { Text(display($0)).tag($0) }
            }
        } label: {
            HStack(spacing: 4) {
                Text(selection.isEmpty ? label : display(selection)).lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "chevron.down").font(.system(size: 10, weight: .semibold)).foregroundStyle(P.mute)
            }
            .font(.system(size: 14))
            .foregroundStyle(P.ink)
            .padding(8)
            .frame(maxWidth: .infinity)
            .background(P.card, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(selection.isEmpty ? P.line : P.blue))
        }
    }
}

struct PSearch: View {
    let placeholder: String
    @Binding var text: String
    var onSubmit: () -> Void = {}

    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.plain)
            .submitLabel(.search)
            .onSubmit(onSubmit)
            .autocorrectionDisabled()
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(P.card, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(P.line))
    }
}

/// Selector de segments (.seg): PDF / Editables / Altres / Tots.
struct PSeg: View {
    /// (valor, nom, comptador)
    let items: [(String, String, Int?)]
    let selected: String
    let pick: (String) -> Void

    var body: some View {
        HStack(spacing: 2) {
            ForEach(items, id: \.0) { it in
                Button { pick(it.0) } label: {
                    HStack(spacing: 3) {
                        Text(it.1).fontWeight(it.0 == selected ? .semibold : .regular)
                        if let c = it.2 { Text("\(c)").font(.system(size: 12)).foregroundStyle(P.mute) }
                    }
                    .font(.system(size: 13))
                    .lineLimit(1)
                    .foregroundStyle(P.ink)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .background {
                        if it.0 == selected {
                            RoundedRectangle(cornerRadius: 8).fill(P.card).shadow(color: .black.opacity(0.15), radius: 1.5, y: 1)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(P.chip, in: RoundedRectangle(cornerRadius: 10))
        .padding(.bottom, 10)
    }
}

/// "Portades / Llista" al costat del comptador.
struct PViewToggle: View {
    @Binding var list: Bool

    var body: some View {
        HStack(spacing: 0) {
            ForEach([false, true], id: \.self) { l in
                Button { list = l } label: {
                    Text(l ? "Llista" : "Portades")
                        .font(.system(size: 12))
                        .foregroundStyle(list == l ? P.ink : P.mute)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background {
                            if list == l { RoundedRectangle(cornerRadius: 6).fill(P.card).shadow(color: .black.opacity(0.15), radius: 1, y: 1) }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(P.chip, in: RoundedRectangle(cornerRadius: 8))
    }
}

struct PCount<Trailing: View>: View {
    let text: String
    let trailing: () -> Trailing

    init(_ text: String, @ViewBuilder trailing: @escaping () -> Trailing) {
        self.text = text
        self.trailing = trailing
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(text).font(.system(size: 13)).foregroundStyle(P.mute)
            Spacer(minLength: 0)
            trailing()
        }
        .padding(.horizontal, 2)
        .padding(.top, 4)
        .padding(.bottom, 8)
    }
}

extension PCount where Trailing == EmptyView {
    init(_ text: String) {
        self.text = text
        self.trailing = { EmptyView() }
    }
}

/// Títol de grup (.group): "Elemental 1r  12".
struct PGroupTitle: View {
    let text: String
    var count: Int? = nil

    var body: some View {
        HStack(spacing: 6) {
            Text(text).font(.system(size: 15, weight: .bold))
            if let count { Text("\(count)").font(.system(size: 13)).foregroundStyle(P.mute) }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 2)
        .padding(.top, 18)
        .padding(.bottom, 8)
    }
}

struct PHint: View {
    let text: String
    var body: some View {
        Text(text).font(.system(size: 12)).foregroundStyle(P.mute).frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct PEmpty: View {
    let text: String
    var body: some View {
        Text(text).foregroundStyle(P.mute).multilineTextAlignment(.center).frame(maxWidth: .infinity).padding(.vertical, 40).padding(.horizontal, 10)
    }
}

/// Targeta simple: títol, subtítol i etiquetes.
struct PSimpleCard: View {
    let title: String
    var sub: String = ""
    var tags: [(String, Bool)] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title.isEmpty ? "(sense títol)" : title).fontWeight(.semibold)
            if !sub.isEmpty { Text(sub).font(.system(size: 13)).foregroundStyle(P.mute).padding(.top, 2) }
            PTags(tags: tags)
        }
        .pCard()
    }
}

/// La targeta d'una obra, amb la portada de la primera partitura si en té.
struct ObraCard: View {
    let o: Fila
    @ObservedObject private var store = PartituresStore.shared

    var body: some View {
        let id = o["ID"] ?? ""
        let nd = store.docsFor("Obra", id).count
        let sub = [o["Instrument"], o["Paper"], o["Agrupació"], o["Any aproximat"]].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
        var tags: [(String, Bool)] = []
        let fc = (o["Formació"] ?? "").isEmpty ? (o["Categoria"] ?? "") : (o["Formació"] ?? "")
        if !fc.isEmpty { tags.append((fc, true)) }
        if let a = o["Àmbit"], !a.isEmpty { tags.append((a, false)) }
        tags += Arxiu.splitTags(o["Curs"]).map { ($0, false) }
        if let f = o["Fagotada"], !f.isEmpty { tags.append(("Fagotada " + f, false)) }
        tags += Arxiu.splitTags(o["Etiquetes"]).map { ($0, false) }
        if !(o["Fragment orquestral"] ?? "").isEmpty { tags.append(("Fragment orquestral", false)) }
        if nd > 0 { tags.append(("\(nd)" + (nd > 1 ? " documents" : " document"), false)) }
        let title = store.obraLabel(o)
        return HStack(alignment: .top, spacing: 12) {
            if let fd = store.firstDoc("Obra", id) {
                PCover(doc: fd, label: o["Obra"], placeholderSize: 9).frame(width: 54)
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(title.isEmpty ? "(sense títol)" : title).fontWeight(.semibold).multilineTextAlignment(.leading)
                if !sub.isEmpty { Text(sub).font(.system(size: 13)).foregroundStyle(P.mute).padding(.top, 2) }
                PTags(tags: tags)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .pCard()
    }
}

/// Element de la graella de portades (.gi): portada, títol i subtítol centrats.
struct PGridItem: View {
    let doc: Fila?
    let title: String
    var sub: String = ""
    var coverLabel: String? = nil

    var body: some View {
        VStack(spacing: 0) {
            PCover(doc: doc, label: coverLabel ?? title)
            Text(title).font(.system(size: 12, weight: .semibold)).multilineTextAlignment(.center).lineLimit(3).padding(.top, 6)
            if !sub.isEmpty { Text(sub).font(.system(size: 12)).foregroundStyle(P.mute).lineLimit(1) }
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .contentShape(Rectangle())
    }
}

/// Fila de la vista en llista (.lrow).
struct PListRow: View {
    let doc: Fila?
    let title: String
    var sub: String = ""

    var body: some View {
        HStack(spacing: 10) {
            PCover(doc: doc, label: " ", showFormat: false, placeholderSize: 7).frame(width: 34)
            VStack(alignment: .leading, spacing: 1) {
                Text(title.isEmpty ? "(sense títol)" : title).font(.system(size: 14, weight: .medium)).lineLimit(1)
                if !sub.isEmpty { Text(sub).font(.system(size: 12)).foregroundStyle(P.mute).lineLimit(1) }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 2)
        .overlay(alignment: .bottom) { Rectangle().fill(P.line).frame(height: 1) }
        .contentShape(Rectangle())
    }
}

let pGridColumns = [GridItem(.flexible(), spacing: 10, alignment: .top), GridItem(.flexible(), spacing: 10, alignment: .top),
                    GridItem(.flexible(), spacing: 10, alignment: .top)]

/// Avís petit a baix de tot (#toast).
struct PToastView: View {
    let text: String?

    var body: some View {
        if let text {
            Text(text)
                .font(.system(size: 14))
                .foregroundStyle(P.paper)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(P.ink, in: RoundedRectangle(cornerRadius: 8))
                .padding(.bottom, 90)
                .padding(.horizontal, 20)
                .transition(.opacity)
        }
    }
}

/// Avisos que es poden mostrar des de qualsevol pantalla de l'arxiu.
@MainActor
final class PToast: ObservableObject {
    static let shared = PToast()
    @Published var text: String?
    private var task: Task<Void, Never>?

    func show(_ t: String) {
        withAnimation { text = t }
        task?.cancel()
        task = Task {
            try? await Task.sleep(for: .seconds(2.6))
            if !Task.isCancelled { withAnimation { text = nil } }
        }
    }
}

@MainActor func toast(_ t: String) { PToast.shared.show(t) }

struct PToastOverlay: ViewModifier {
    @ObservedObject private var toastState = PToast.shared
    func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) { PToastView(text: toastState.text).allowsHitTesting(false) }
    }
}

/// Enllaç a un document. A l'iPad, un PDF s'obre directament a pantalla sencera (faristol);
/// mantenint-lo premut hi ha «Fitxa del document». A l'iPhone obre la fitxa com sempre.
struct PDocLink<Label: View>: View {
    let doc: Fila
    @ViewBuilder var label: () -> Label
    @State private var stand = false
    @State private var detail = false

    private var direct: Bool { UIDevice.current.userInterfaceIdiom == .pad && Arxiu.isPdf(doc) }

    var body: some View {
        if direct {
            Button { stand = true } label: { label() }
                .buttonStyle(.plain)
                .contextMenu {
                    Button { detail = true } label: { SwiftUI.Label("Fitxa del document", systemImage: "info.circle") }
                    Button { stand = true } label: { SwiftUI.Label("Obre a pantalla sencera", systemImage: "arrow.up.left.and.arrow.down.right") }
                }
                .sheet(isPresented: $detail) {
                    NavigationStack { PDetailView(name: "Documents", id: doc["ID"] ?? "") }.modifier(PToastOverlay())
                }
                .fullScreenCover(isPresented: $stand) {
                    FaristolView(docs: [doc], title: doc["Títol"] ?? "")
                }
        } else {
            NavigationLink { PDetailView(name: "Documents", id: doc["ID"] ?? "") } label: { label() }
        }
    }
}

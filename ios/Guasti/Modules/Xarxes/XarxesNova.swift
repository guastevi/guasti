import SwiftUI
import PhotosUI

/// Nova publicació: fotos i vídeos, text, xarxes, quan i qui.
struct XarxesNova: View {
    @ObservedObject private var store = XarxesStore.shared
    @Environment(\.openURL) private var openURL
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var confirmant = false
    @State private var avis: String?
    @State private var nouFragment = false
    @State private var nomFragment = ""
    @State private var esborrant: Fragment?

    private let columnes = [GridItem(.adaptive(minimum: 96), spacing: 10)]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            formatCard
            fotosCard
            if store.format != .story { textCard }
            xarxesCard
            quanCard

            Button(store.publicant ? (store.programar ? "Programant…" : "Publicant…") : (store.programar ? "Programar" : "Publicar")) {
                if let p = store.problema { avis = p } else { confirmant = true }
            }
            .buttonStyle(XarBoto())
            .disabled(store.publicant || store.carregant)

            if !store.registre.isEmpty { progresCard.padding(.top, 14) }
        }
        .alert(store.resum, isPresented: $confirmant) {
            Button("Cancel·la", role: .cancel) {}
            Button(store.programar ? "Programa" : "Publica") { Task { await store.publicar() } }
        }
        .alert(avis ?? "", isPresented: Binding(get: { avis != nil }, set: { if !$0 { avis = nil } })) {
            Button("D'acord", role: .cancel) {}
        }
        .alert("Desar com a text habitual", isPresented: $nouFragment) {
            TextField("Nom curt (p. ex. Hashtags)", text: $nomFragment)
            Button("Cancel·la", role: .cancel) {}
            Button("Desa") {
                let nom = nomFragment.trimmingCharacters(in: .whitespaces)
                let text = store.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !nom.isEmpty else { return }
                Task {
                    do { try await store.desarFragment(nom: nom, text: text) } catch { avis = error.localizedDescription }
                }
            }
        } message: {
            Text("Es desarà tot el text que has escrit, per a tot l'equip.")
        }
        .alert("Esborrar «\(esborrant?.nom ?? "")» per a tothom?",
               isPresented: Binding(get: { esborrant != nil }, set: { if !$0 { esborrant = nil } })) {
            Button("Cancel·la", role: .cancel) {}
            Button("Esborra", role: .destructive) {
                guard let f = esborrant else { return }
                Task {
                    do { try await store.esborrarFragment(f) } catch { avis = error.localizedDescription }
                }
            }
        }
        .onChange(of: pickerItems) { _, items in
            guard !items.isEmpty else { return }
            Task {
                await store.afegir(items)
                pickerItems = []
            }
        }
    }

    // MARK: Format

    private var formatCard: some View {
        XarCard {
            Picker("Format", selection: $store.format) {
                ForEach(Format.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            Text(store.format.ajuda)
                .font(.system(size: 13))
                .foregroundStyle(Xar.muted)
                .padding(.top, 10)
        }
    }

    // MARK: Fotos i vídeos

    private var fotosCard: some View {
        XarCard(title: "Fotos i vídeos") {
            PhotosPicker(selection: $pickerItems,
                         maxSelectionCount: max(1, Xar.maxElements - store.elements.count),
                         selectionBehavior: .ordered,
                         matching: .any(of: [.images, .videos])) {
                HStack(spacing: 8) {
                    if store.carregant {
                        ProgressView()
                    } else {
                        Image(systemName: "photo.on.rectangle.angled")
                    }
                    Text(store.elements.isEmpty ? "Tria fotos o vídeos" : "Afegeix-ne més")
                }
                .font(.system(size: 15, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 22)
                .foregroundStyle(Xar.muted)
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Xar.line, style: StrokeStyle(lineWidth: 2, dash: [6, 5])))
            }
            .disabled(store.elements.count >= Xar.maxElements || store.publicant)

            if !store.elements.isEmpty {
                LazyVGrid(columns: columnes, spacing: 10) {
                    ForEach(Array(store.elements.enumerated()), id: \.element.id) { i, el in
                        peca(el, numero: i + 1)
                    }
                }
                .padding(.top, 14)
                Text("\(store.elements.count) de \(Xar.maxElements)")
                    .font(.system(size: 13))
                    .foregroundStyle(Xar.muted)
                    .padding(.top, 8)
            }

            if store.fotosForaDeProporcio > 0 {
                Text("Atenció: \(store.fotosForaDeProporcio) foto(s) són més allargades del que Instagram accepta (entre 4:5 vertical i 1,91:1 horitzontal). L'app les retallarà pel centre.")
                    .font(.system(size: 13))
                    .foregroundStyle(Xar.accent)
                    .padding(.top, 8)
            }
        }
    }

    private func peca(_ el: Element, numero: Int) -> some View {
        Color(UIColor(hex: 0x222222))
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let m = el.miniatura {
                    Image(uiImage: m).resizable().scaledToFill()
                } else {
                    Image(systemName: el.video ? "video" : "photo").foregroundStyle(Xar.muted)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(alignment: .topLeading) {
                Text("\(numero)\(el.video ? " ▶" : "")\(el.foraDeProporcio && store.format == .publicacio ? " ⚠" : "")")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 6))
                    .padding(4)
            }
            .overlay(alignment: .bottomTrailing) {
                if !store.publicant {
                    HStack(spacing: 4) {
                        if numero > 1 {
                            botoPeca("chevron.left", "Mou a l'esquerra") { store.mouEsquerra(el) }
                        }
                        botoPeca("xmark", "Treu") { store.treure(el) }
                    }
                    .padding(4)
                }
            }
    }

    private func botoPeca(_ icona: String, _ etiqueta: String, accio: @escaping () -> Void) -> some View {
        Button(action: accio) {
            Image(systemName: icona)
                .font(.system(size: 12, weight: .bold))
                .frame(width: 28, height: 28)
                .foregroundStyle(Xar.accent)
                .background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(etiqueta)
    }

    // MARK: Text

    private var textCard: some View {
        XarCard(title: "Text") {
            TextEditor(text: $store.text)
                .scrollContentBackground(.hidden)
                .font(.system(size: 16))
                .frame(minHeight: 160)
                .padding(8)
                .background(Xar.field, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Xar.line))
            let massa = store.text.count > 2200 || store.hashtags > 30
            Text("\(store.text.count.formatted(.number.locale(Locale(identifier: "ca")))) / 2.200 · \(store.hashtags) hashtags\(store.hashtags > 30 ? " (Instagram en permet 30)" : "")")
                .font(.system(size: 13))
                .foregroundStyle(massa ? Xar.malament : Xar.muted)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.top, 4)

            Text("Textos habituals")
                .font(.system(size: 14, weight: .semibold))
                .padding(.top, 12)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(store.fragments, id: \.self) { f in
                        Button { store.afegirFragment(f) } label: { xip(f.nom) }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button(role: .destructive) { esborrant = f } label: { Label("Esborra per a tothom", systemImage: "trash") }
                            }
                    }
                    Button {
                        if store.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            avis = "Escriu el text que vols desar, per exemple els hashtags de sempre."
                        } else {
                            nomFragment = ""
                            nouFragment = true
                        }
                    } label: { xip("+ Desa", nou: true) }
                        .buttonStyle(.plain)
                }
            }
            .padding(.top, 8)
            Text("Toca'n un per afegir-lo al final del text. Mantén-lo premut per esborrar-lo.")
                .font(.system(size: 12))
                .foregroundStyle(Xar.muted)
                .padding(.top, 6)

            if store.format != .story {
                Text("Col·laboradors d'Instagram")
                    .font(.system(size: 14, weight: .semibold))
                    .padding(.top, 14)
                TextField("@artista @companyia (fins a 3)", text: $store.collab)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(11)
                    .background(Xar.field, in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Xar.line))
                    .padding(.top, 8)
                Text("Reben una invitació i, si l'accepten, el post surt també al seu perfil.")
                    .font(.system(size: 12))
                    .foregroundStyle(Xar.muted)
                    .padding(.top, 6)
            }
        }
    }

    private func xip(_ text: String, nou: Bool = false) -> some View {
        Text(text)
            .font(.system(size: 14))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .foregroundStyle(nou ? Xar.accent : Xar.text)
            .background(Xar.field, in: Capsule())
            .overlay(Capsule().strokeBorder(nou ? Xar.accent.opacity(0.6) : Xar.line))
    }

    // MARK: Xarxes i quan

    private var xarxesCard: some View {
        XarCard(title: "On") {
            Toggle("Instagram", isOn: $store.ig)
            Toggle("Facebook", isOn: $store.fb)
                .padding(.top, 6)
        }
    }

    private var quanCard: some View {
        XarCard(title: "Quan") {
            Picker("Quan", selection: $store.programar) {
                Text("Ara mateix").tag(false)
                Text("Programar").tag(true)
            }
            .pickerStyle(.segmented)
            if store.programar {
                DatePicker("Dia i hora", selection: $store.quan, in: Date()..., displayedComponents: [.date, .hourAndMinute])
                    .padding(.top, 10)
                Text("Es publica sola des de Google, amb un marge de fins a 5 minuts, encara que ningú tingui l'app oberta.")
                    .font(.system(size: 12))
                    .foregroundStyle(Xar.muted)
                    .padding(.top, 6)
            }
            Text("El teu nom")
                .font(.system(size: 14, weight: .semibold))
                .padding(.top, 14)
            TextField("Perquè l'equip sàpiga qui ho ha publicat", text: $store.autor)
                .textContentType(.givenName)
                .padding(11)
                .background(Xar.field, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Xar.line))
                .padding(.top, 8)
        }
    }

    // MARK: Progrés

    private var progresCard: some View {
        XarCard {
            ProgressView(value: store.progres)
                .tint(Xar.accent)
                .padding(.bottom, 10)
            ForEach(store.registre) { l in
                Text(l.text)
                    .font(.system(size: 14))
                    .foregroundStyle(l.tipus == .be ? Xar.be : l.tipus == .malament ? Xar.malament : Xar.text)
                    .padding(.vertical, 2)
            }
            if !store.publicant && (!store.enllacIg.isEmpty || !store.enllacosFb.isEmpty) {
                HStack(spacing: 10) {
                    if let u = URL(string: store.enllacIg), !store.enllacIg.isEmpty {
                        Button("Veure a Instagram") { openURL(u) }
                    }
                    ForEach(Array(store.enllacosFb.enumerated()), id: \.offset) { i, s in
                        if let u = URL(string: s) {
                            Button("Veure a Facebook\(store.enllacosFb.count > 1 ? " \(i + 1)" : "")") { openURL(u) }
                        }
                    }
                }
                .font(.system(size: 14, weight: .semibold))
                .padding(.top, 8)
            }
        }
    }
}

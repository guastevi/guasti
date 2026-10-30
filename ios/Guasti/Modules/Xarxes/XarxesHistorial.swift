import SwiftUI

/// Què s'ha publicat, qui ho ha fet, els enllaços, els errors i les programades (que es poden cancel·lar).
struct XarxesHistorial: View {
    @ObservedObject private var store = XarxesStore.shared
    @Environment(\.openURL) private var openURL
    @State private var cancellant: Entrada?
    @State private var avis: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let llista = store.historial {
                if llista.isEmpty {
                    estat("Encara no hi ha cap publicació.")
                }
                ForEach(llista) { e in entrada(e) }
            } else if let error = store.errorHistorial {
                estat("No s'ha pogut carregar l'historial.\n\(error)")
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 60)
            }
        }
        .task { if store.historial == nil { await store.carregarHistorial() } }
        .alert("Cancel·lar aquesta publicació programada?",
               isPresented: Binding(get: { cancellant != nil }, set: { if !$0 { cancellant = nil } })) {
            Button("No", role: .cancel) {}
            Button("Cancel·la-la", role: .destructive) {
                guard let e = cancellant else { return }
                Task {
                    do { try await store.cancellar(e) } catch { avis = error.localizedDescription }
                }
            }
        }
        .alert(avis ?? "", isPresented: Binding(get: { avis != nil }, set: { if !$0 { avis = nil } })) {
            Button("D'acord", role: .cancel) {}
        }
    }

    private func estat(_ text: String) -> some View {
        Text(text)
            .foregroundStyle(Xar.muted)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 60)
    }

    private func entrada(_ e: Entrada) -> some View {
        XarCard {
            HStack {
                Text(e.etiqueta)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Xar.onAccent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(e.color, in: Capsule())
                Text(e.estat == "programat" ? "Per al " + Xar.dataCurta(iso: e.programat)
                     : Xar.dataCurta(iso: e.publicat.isEmpty ? e.creat : e.publicat))
                    .font(.system(size: 13))
                    .foregroundStyle(Xar.muted)
                Spacer()
                Text(e.autor)
                    .font(.system(size: 13))
                    .foregroundStyle(Xar.muted)
            }
            Text(e.text.isEmpty ? "(sense text)" : e.text)
                .font(.system(size: 15))
                .lineLimit(4)
                .padding(.top, 8)
            Text("\(e.xarxes) · \(e.elements) element(s)")
                .font(.system(size: 13))
                .foregroundStyle(Xar.muted)
                .padding(.top, 6)
            if !e.error.isEmpty {
                Text(e.error)
                    .font(.system(size: 13))
                    .foregroundStyle(Xar.malament)
                    .padding(.top, 6)
            }
            HStack(spacing: 14) {
                if let u = URL(string: e.enllacIg), !e.enllacIg.isEmpty {
                    Button("Instagram") { openURL(u) }
                }
                ForEach(Array(e.enllacosFb.enumerated()), id: \.offset) { i, s in
                    if let u = URL(string: s) {
                        Button("Facebook\(e.enllacosFb.count > 1 ? " \(i + 1)" : "")") { openURL(u) }
                    }
                }
                if e.estat == "programat" {
                    Spacer()
                    Button("Cancel·lar") { cancellant = e }
                        .foregroundStyle(Xar.malament)
                }
            }
            .font(.system(size: 14, weight: .semibold))
            .padding(.top, 8)
        }
    }
}

import SwiftUI

/// Pestanya Inici: repertori per estudiar (concerts d'aquest mes i del següent), comptadors i obres noves.
struct PHomeTab: View {
    @Binding var tab: String
    @Binding var req: PReq?
    @ObservedObject private var store = PartituresStore.shared
    @State private var q = ""

    var body: some View {
        let docs = store.rows("Documents")
        let none = docs.filter { ($0["Categoria"] ?? "").isEmpty }.count
        let books = Arxiu.uniq(docs.map { $0["Llibre"] }).count
        let obres = Array(store.rows("Obres").suffix(6).reversed())
        let lim = limitDate()
        let up = store.upcomingConcerts().filter { String(($0["Data"] ?? "").prefix(10)) < lim }
        let nodate = store.rows("Concerts").filter { ($0["Data"] ?? "").isEmpty && !(($0["Títol"] ?? "") + ($0["Agrupació"] ?? "")).isEmpty }
        let pend = store.dades?.pendents ?? 0
        return VStack(alignment: .leading, spacing: 0) {
            PSearch(placeholder: "Cerca a tot l'arxiu...", text: $q) {
                let f = PFilters.shared
                f.reset()
                f.kind = "tot"
                f.q = q
                tab = "Documents"
            }
            .padding(.bottom, 4)
            HStack {
                Text("Repertori per estudiar").font(.system(size: 15, weight: .bold))
                Spacer()
                Button("+ Nou concert") { req = .form("Concerts", [:]) }.buttonStyle(PBtn(small: true))
            }
            .padding(.top, 18).padding(.bottom, 8).padding(.horizontal, 2)
            if up.isEmpty && nodate.isEmpty {
                PHint(text: "No tens cap concert programat aquest mes ni el següent. Toca «+ Nou concert» per afegir-ne un i posar-hi les partitures.")
            }
            ForEach(Array(up.enumerated()), id: \.offset) { i, c in
                let mo = String((c["Data"] ?? "").prefix(7))
                if i == 0 || String((up[i - 1]["Data"] ?? "").prefix(7)) != mo {
                    monthHeader(Arxiu.monthName(c["Data"]))
                }
                PConcertRow(c: c, req: $req)
            }
            ForEach(Array(nodate.enumerated()), id: \.offset) { i, c in
                if i == 0 { monthHeader("Sense data") }
                PConcertRow(c: c, req: $req, missingDate: true)
            }
            if pend > 0 {
                Button("\(pend) fitxers nous del Drive per acceptar") { req = .review }
                    .font(.system(size: 12)).foregroundStyle(P.blueInk).padding(.top, 14).padding(.horizontal, 2)
            }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                tile("\(docs.filter { ($0["Revisat"] ?? "").isEmpty }.count)", "Documents per revisar") { reviewNext() }
                tile("\(none)", "Sense classificar") { goDocs(category: "__none") }
                tile("\(docs.count)", "Documents") { goDocs(category: nil) }
                NavigationLink { PBooksView() } label: { tileLabel("\(books)", "Llibres") }.buttonStyle(.plain)
            }
            .padding(.top, 14)
            if !obres.isEmpty {
                PGroupTitle(text: "Obres afegides fa poc")
                VStack(spacing: 8) {
                    ForEach(obres, id: \.self) { o in
                        NavigationLink { PDetailView(name: "Obres", id: o["ID"] ?? "") } label: { ObraCard(o: o) }.buttonStyle(.plain)
                    }
                }
            }
            PGroupTitle(text: "Eines")
            Button("Inventari, revisió i classificació") { req = .tools }.buttonStyle(PBtn())
        }
    }

    private func limitDate() -> String {
        let c = Calendar.current.dateComponents([.year, .month], from: Date())
        var y = c.year ?? 2026, m = (c.month ?? 1) + 2
        if m > 12 { m -= 12; y += 1 }
        return String(format: "%04d-%02d-01", y, m)
    }

    private func monthHeader(_ t: String) -> some View {
        Text(t.uppercased())
            .font(.system(size: 13, weight: .semibold)).tracking(0.4).foregroundStyle(P.mute)
            .padding(.horizontal, 2).padding(.top, 12).padding(.bottom, 6)
    }

    private func tileLabel(_ n: String, _ t: String, blue: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(n).font(.system(size: 22, weight: .bold)).foregroundStyle(blue ? P.blueInk : P.ink)
            Text(t).font(.system(size: 13)).foregroundStyle(P.mute)
        }
        .pCard()
    }

    private func tile(_ n: String, _ t: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { tileLabel(n, t) }.buttonStyle(.plain)
    }

    private func goDocs(category: String?) {
        let f = PFilters.shared
        f.reset()
        f.kind = "tot"
        if let category { f.f["Categoria"] = category }
        tab = "Documents"
    }

    /// Revisió sistemàtica: va obrint un per un els documents que encara no s'han revisat.
    private func reviewNext() {
        PReview.shared.skip = []
        if let d = PReview.shared.next() { req = .form("Documents", d, review: true) } else { toast("No queda res per revisar") }
    }
}

/// Els documents per revisar, agrupats per carpeta com a la web.
@MainActor
final class PReview {
    static let shared = PReview()
    var skip = Set<String>()

    var remaining: Int {
        PartituresStore.shared.rows("Documents").filter { ($0["Revisat"] ?? "").isEmpty && !skip.contains($0["ID"] ?? "") }.count
    }

    func next() -> Fila? {
        let q = PartituresStore.shared.rows("Documents").filter { ($0["Revisat"] ?? "").isEmpty && !skip.contains($0["ID"] ?? "") }
        func key(_ d: Fila) -> String {
            let notes = d["Notes"] ?? ""
            var folder = ""
            if let r = notes.range(of: #"Carpeta: [^·]*"#, options: .regularExpression) { folder = String(notes[r].dropFirst(9)) }
            return Arxiu.norm(folder + " " + (d["Llibre"] ?? "") + " " + (d["Títol"] ?? ""))
        }
        return q.min { key($0) < key($1) }
    }
}

/// Un concert a Inici: data, títol, lloc i la tira de portades de les partitures.
struct PConcertRow: View {
    let c: Fila
    @Binding var req: PReq?
    var missingDate = false
    @ObservedObject private var store = PartituresStore.shared

    var body: some View {
        let cid = c["ID"] ?? ""
        let ds = store.concertDocs(cid)
        let title = (c["Títol"] ?? "").isEmpty ? ((c["Agrupació"] ?? "").isEmpty ? "Concert" : (c["Agrupació"] ?? "")) : (c["Títol"] ?? "")
        let sub = [c["Agrupació"], c["Lloc"], c["Població"]].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 12) {
                NavigationLink { PDetailView(name: "Concerts", id: cid) } label: {
                    VStack(alignment: .leading, spacing: 0) {
                        if missingDate {
                            Text("Falta la data: toca per posar-la").font(.system(size: 12, weight: .semibold)).foregroundStyle(P.red)
                        } else {
                            Text(Arxiu.dayLabel(c["Data"]) + ((c["Hora"] ?? "").isEmpty ? "" : " · " + (c["Hora"] ?? "")))
                                .font(.system(size: 12, weight: .semibold)).foregroundStyle(P.blueInk)
                        }
                        Text(title).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                        if !sub.isEmpty { Text(sub).font(.system(size: 12)).foregroundStyle(P.mute).lineLimit(1) }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if !ds.isEmpty && !missingDate { POfflineButton(docs: ds) }
            }
            if !missingDate {
                if ds.isEmpty {
                    Text("Sense partitures: toca el concert per afegir-n'hi.").font(.system(size: 12)).foregroundStyle(P.mute)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(ds, id: \.self) { d in
                                NavigationLink { PDetailView(name: "Documents", id: d["ID"] ?? "") } label: {
                                    PCover(doc: d, label: " ", showFormat: false, placeholderSize: 6).frame(width: 44)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(1)
                    }
                }
            }
        }
        .padding(.leading, 12).padding(.trailing, 10).padding(.vertical, 8)
        .background(P.card, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(P.line))
        .padding(.bottom, 6)
    }
}

/// "Sense connexió": guarda les partitures al mòbil perquè el faristol funcioni sense cobertura.
struct POfflineButton: View {
    let docs: [Fila]
    var small = true
    @ObservedObject private var store = PartituresStore.shared
    @State private var busy: String?
    @State private var askRemove = false

    var body: some View {
        let pdfs = docs.filter(Arxiu.isPdf)
        let done = !pdfs.isEmpty && pdfs.allSatisfy { store.offline.contains(Arxiu.fileId($0)) }
        Button {
            if done { askRemove = true; return }
            Task {
                busy = "Baixant..."
                do {
                    try await store.downloadOffline(pdfs) { busy = $0.components(separatedBy: ":").first }
                    toast("Les partitures ja són al mòbil: el faristol funcionarà sense connexió")
                } catch {
                    toast("Error: " + error.localizedDescription)
                }
                busy = nil
            }
        } label: {
            HStack(spacing: 4) {
                if busy != nil { ProgressView().controlSize(.mini) }
                Text(busy ?? (done ? "✓ Al mòbil" : "Sense connexió"))
            }
        }
        .buttonStyle(PBtn(small: true))
        .font(.system(size: small ? 11 : 13))
        .disabled(busy != nil)
        .confirmationDialog("Aquestes partitures ja són al mòbil", isPresented: $askRemove, titleVisibility: .visible) {
            Button("Treu-les del mòbil", role: .destructive) { store.removeOffline(pdfs) }
        } message: {
            Text("Si les treus, el faristol les tornarà a baixar quan hi hagi connexió.")
        }
    }
}

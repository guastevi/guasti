import SwiftUI
import Charts

/// Pestanya "Futur" de Gastos: previsió de saldo a 12 mesos, comptes i coixí, bolos i IRPF.
struct GastosFutur: View {
    enum Seccio: String, CaseIterable {
        case previsio = "Previsió"
        case comptes = "Comptes"
        case bolos = "Bolos"
        case irpf = "IRPF"
    }

    let showToast: (String, Bool) -> Void

    @ObservedObject private var store = FuturStore.shared
    @AppStorage("gastos.futur.seccio") private var seccio: Seccio = .previsio

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Picker("Secció", selection: $seccio) {
                ForEach(Seccio.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.bottom, 14)

            if !store.carregat {
                Group {
                    if let error = store.errorMessage {
                        Text(error)
                    } else {
                        Text("Carregant...")
                    }
                }
                .font(.system(size: 15))
                .foregroundStyle(Fin.muted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 60)
            } else {
                switch seccio {
                case .previsio: FuturPrevisio(showToast: showToast)
                case .comptes: FuturComptes(showToast: showToast)
                case .bolos: FuturBolos(showToast: showToast)
                case .irpf: FuturIRPF()
                }
            }
        }
        .task { await store.load() }
        .onChange(of: store.errorMessage) { _, error in
            if let error, store.carregat { showToast(error, true) }
        }
    }
}

// MARK: - Peces comunes

/// Requadre petit amb un títol i una xifra, com els de Resum.
struct FinKPI: View {
    let title: String
    let value: String
    var color: Color = Fin.text
    var note: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.55)
                .foregroundStyle(Fin.muted)
            Text(value)
                .font(.system(size: 22, weight: .heavy))
                .tracking(-0.22)
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if let note {
                Text(note)
                    .font(.system(size: 12))
                    .foregroundStyle(Fin.muted)
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Fin.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Fin.line))
    }
}

struct FinKPIGrid<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            content
        }
        .padding(.bottom, 12)
    }
}

/// Fila d'una llista: títol, subtítol i import a la dreta.
struct FinFilaView: View {
    let title: String
    var subtitle: String = ""
    let value: String
    var color: Color = Fin.text

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 16, weight: .semibold)).lineLimit(1)
                if !subtitle.isEmpty {
                    Text(subtitle).font(.system(size: 13)).foregroundStyle(Fin.muted).lineLimit(2)
                }
            }
            Spacer(minLength: 8)
            Text(value)
                .font(.system(size: 16, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(color)
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}

struct FinBotoAfegir: View {
    let text: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Label(text, systemImage: "plus")
                .font(.system(size: 15, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .foregroundStyle(Fin.text)
                .background(Fin.bg, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Fin.line))
        }
        .buttonStyle(.plain)
        .padding(.top, 10)
    }
}

struct FinBuit: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 15))
            .foregroundStyle(Fin.muted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 6)
    }
}

struct FinSeparador: View {
    var body: some View { Rectangle().fill(Fin.line).frame(height: 1) }
}

struct FinBarra: View {
    let fraction: Double
    let color: Color
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Fin.line)
                Capsule().fill(color).frame(width: geo.size.width * Swift.min(1, Swift.max(0, fraction)))
            }
        }
        .frame(height: 8)
    }
}

extension Fin {
    /// 1234.5 → "1234,5" per editar-lo en un camp de text.
    static func editable(_ n: Double) -> String {
        guard n != 0 else { return "" }
        let v = (n * 100).rounded() / 100
        let s = v == v.rounded() ? String(Int(v)) : String(v)
        return s.replacingOccurrences(of: ".", with: ",")
    }

    static func signe(_ n: Double) -> String { (n >= 0 ? "+" : "−") + eur(abs(n)) }
}

// MARK: - Previsió

struct FuturPrevisio: View {
    let showToast: (String, Bool) -> Void

    @ObservedObject private var store = FuturStore.shared
    @State private var obert: String?
    @State private var editContracte: Contracte?
    @State private var editPrevist: Previst?
    @State private var editDespesa = false

    var body: some View {
        let p = store.previsio
        VStack(spacing: 0) {
            FinKPIGrid {
                FinKPI(title: "Ara (comptes)", value: Fin.eur0(p.saldoInicial),
                       note: store.comptes.isEmpty ? "Afegeix els comptes a Comptes" : "Corrent i estalvi")
                FinKPI(title: "D'aquí a 12 mesos", value: Fin.eur0(p.mesos.last?.saldo ?? 0),
                       color: (p.mesos.last?.saldo ?? 0) < 0 ? Fin.sortida : Fin.entrada,
                       note: Fin.signe((p.mesos.last?.saldo ?? 0) - p.saldoInicial))
            }

            if let m = p.minim {
                let justet = m.saldo < store.coixiObjectiu
                Text(justet
                     ? "Mes més just: \(Fin.nomMes(m.mes)), amb \(Fin.eur0(m.saldo)). Quedaria per sota del coixí (\(Fin.eur0(store.coixiObjectiu)))."
                     : "Mes més just: \(Fin.nomMes(m.mes)), amb \(Fin.eur0(m.saldo)). Sempre per sobre del coixí.")
                    .font(.system(size: 14))
                    .foregroundStyle(justet ? Fin.sortida : Fin.muted)
                    .padding(.horizontal, 2)
                    .padding(.bottom, 12)
            }

            FinCard(title: "Saldo previst") {
                chart(p)
            }

            FinCard(title: "Mes a mes") {
                VStack(spacing: 0) {
                    ForEach(Array(p.mesos.enumerated()), id: \.element.id) { i, m in
                        Button {
                            withAnimation(.easeOut(duration: 0.2)) { obert = obert == m.mes ? nil : m.mes }
                        } label: {
                            HStack {
                                Text(Fin.nomMes(m.mes)).font(.system(size: 16, weight: .semibold))
                                Spacer()
                                Text(Fin.signe(m.net))
                                    .font(.system(size: 13))
                                    .foregroundStyle(m.net < 0 ? Fin.sortida : Fin.entrada)
                                Text(Fin.eur0(m.saldo))
                                    .font(.system(size: 16, weight: .semibold))
                                    .monospacedDigit()
                                    .foregroundStyle(m.saldo < 0 ? Fin.sortida : Fin.text)
                                    .frame(minWidth: 86, alignment: .trailing)
                            }
                            .padding(.vertical, 10)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        if obert == m.mes {
                            VStack(spacing: 6) {
                                ForEach(m.linies) { l in
                                    HStack {
                                        Text(l.nom).lineLimit(1)
                                        Spacer()
                                        Text(Fin.signe(l.imp)).monospacedDigit()
                                            .foregroundStyle(l.imp < 0 ? Fin.sortida : Fin.entrada)
                                    }
                                    .font(.system(size: 14))
                                }
                            }
                            .padding(.leading, 12)
                            .padding(.bottom, 10)
                        }
                        if i < p.mesos.count - 1 { FinSeparador() }
                    }
                }
            }

            FinCard(title: "Nòmines") {
                if store.contractes.isEmpty {
                    FinBuit(text: "Afegeix els contractes fixos: el sou brut i la retenció que surten a la nòmina.")
                }
                ForEach(store.contractes) { c in
                    Button { editContracte = c } label: {
                        FinFilaView(title: c.nom,
                                    subtitle: "\(Fin.eur0(c.brut)) bruts × \(c.pagues) · IRPF \(Fin.pct(c.irpf))" + periode(c),
                                    value: Fin.eur(c.netMensual) + "/mes", color: Fin.entrada)
                    }
                    .buttonStyle(.plain)
                    FinSeparador()
                }
                FinBotoAfegir(text: "Afegir contracte") { editContracte = Contracte() }
            }

            FinCard(title: "Despeses i ingressos previstos") {
                if store.previstos.isEmpty {
                    FinBuit(text: "Assegurances, IBI, quotes, la renda... el que saps que vindrà i en quin mes.")
                }
                ForEach(store.previstos) { pv in
                    Button { editPrevist = pv } label: {
                        FinFilaView(title: pv.nom,
                                    subtitle: Fin.mesos[pv.mes - 1].capitalized + (pv.anyFix == 0 ? " · cada any" : " \(pv.anyFix)"),
                                    value: (pv.tipus == "Ingrés" ? "+" : "−") + Fin.eur(pv.imp),
                                    color: Fin.color(pv.tipus))
                    }
                    .buttonStyle(.plain)
                    FinSeparador()
                }
                FinBotoAfegir(text: "Afegir previst") { editPrevist = Previst() }
            }

            FinCard(title: "Despesa habitual") {
                Button { editDespesa = true } label: {
                    FinFilaView(title: Fin.eur(store.despesaMensual) + " al mes",
                                subtitle: Fin.number(store.ajust("despesaMensual")) > 0
                                    ? "L'has posada tu. La mitjana dels 3 últims mesos és \(Fin.eur0(store.despesaMitjana))."
                                    : "Mitjana de despeses i inversió dels 3 últims mesos. Toca per canviar-la.",
                                value: "")
                }
                .buttonStyle(.plain)
            }
        }
        .sheet(item: $editContracte) { ContracteForm(contracte: $0, showToast: showToast) }
        .sheet(item: $editPrevist) { PrevistForm(previst: $0, showToast: showToast) }
        .sheet(isPresented: $editDespesa) { DespesaForm(showToast: showToast) }
    }

    private func periode(_ c: Contracte) -> String {
        if c.finsA.isEmpty { return "" }
        return " · fins a \(Fin.nomMes(c.finsA).lowercased())"
    }

    private func chart(_ p: Previsio) -> some View {
        let coixi = store.coixiObjectiu
        return Chart {
            ForEach(p.mesos) { m in
                AreaMark(x: .value("Mes", Fin.mesCurt(m.mes)), y: .value("Saldo", m.saldo))
                    .foregroundStyle(Fin.estalvi.opacity(0.12))
                LineMark(x: .value("Mes", Fin.mesCurt(m.mes)), y: .value("Saldo", m.saldo))
                    .foregroundStyle(Fin.estalvi)
                    .lineStyle(StrokeStyle(lineWidth: 2.5))
                PointMark(x: .value("Mes", Fin.mesCurt(m.mes)), y: .value("Saldo", m.saldo))
                    .foregroundStyle(m.saldo < coixi ? Fin.sortida : Fin.estalvi)
                    .symbolSize(28)
            }
            if coixi > 0 {
                RuleMark(y: .value("Coixí", coixi))
                    .foregroundStyle(Fin.muted)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .annotation(position: .top, alignment: .leading) {
                        Text("coixí").font(.system(size: 11)).foregroundStyle(Fin.muted)
                    }
            }
        }
        .chartXAxis {
            AxisMarks { _ in AxisValueLabel().foregroundStyle(Fin.muted) }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine().foregroundStyle(Fin.line)
                AxisValueLabel {
                    if let v = value.as(Double.self) { Text(Fin.eur0(v)).foregroundStyle(Fin.muted) }
                }
            }
        }
        .frame(height: 220)
    }
}

// MARK: - Comptes

struct FuturComptes: View {
    let showToast: (String, Bool) -> Void

    @ObservedObject private var store = FuturStore.shared
    @State private var edit: Compte?
    @State private var editCoixi = false

    var body: some View {
        VStack(spacing: 0) {
            FinKPIGrid {
                FinKPI(title: "Patrimoni", value: Fin.eur0(store.patrimoni), note: "Tots els comptes")
                FinKPI(title: "Disponible", value: Fin.eur0(store.liquid), color: Fin.estalvi, note: "Corrent i estalvi")
            }

            FinCard(title: "Coixí de seguretat") {
                let obj = store.coixiObjectiu
                let frac = obj > 0 ? store.liquid / obj : 0
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(Fin.eur0(store.liquid)).font(.system(size: 20, weight: .bold))
                        Text("de \(Fin.eur0(obj))").foregroundStyle(Fin.muted)
                        Spacer()
                        Text(Fin.pct(frac * 100)).font(.system(size: 14, weight: .semibold))
                    }
                    FinBarra(fraction: frac, color: frac >= 1 ? Fin.entrada : Fin.estalvi)
                    Button { editCoixi = true } label: {
                        Text("\(Fin.editable(store.coixiMesos)) mesos de despesa habitual (\(Fin.eur0(store.despesaMensual))/mes). "
                             + (frac >= 1 ? "Coixí complet." : "Et falten \(Fin.eur0(obj - store.liquid))."))
                            .font(.system(size: 13))
                            .foregroundStyle(Fin.muted)
                            .multilineTextAlignment(.leading)
                    }
                    .buttonStyle(.plain)
                }
            }

            FinCard(title: "Comptes") {
                if store.comptes.isEmpty {
                    FinBuit(text: "Afegeix els comptes (banc, Trade Republic...) i n'actualitzes el saldo de tant en tant.")
                }
                ForEach(store.comptes) { c in
                    Button { edit = c } label: {
                        FinFilaView(title: c.nom,
                                    subtitle: c.tipus + (c.actualitzat.isEmpty ? "" : " · " + Fin.nomDia(c.actualitzat)),
                                    value: Fin.eur(c.saldo),
                                    color: c.tipus == "Inversió" ? Fin.inversio : Fin.text)
                    }
                    .buttonStyle(.plain)
                    FinSeparador()
                }
                FinBotoAfegir(text: "Afegir compte") { edit = Compte() }
            }

            FinCard(title: "Evolució del patrimoni") {
                let punts = store.evolucioPatrimoni
                if punts.count < 2 {
                    FinBuit(text: "Cada vegada que actualitzis un saldo quedarà guardat aquí. Amb uns quants mesos en veuràs la corba.")
                } else {
                    Chart(punts) { pt in
                        AreaMark(x: .value("Mes", etiqueta(pt.mes)), y: .value("Total", pt.total))
                            .foregroundStyle(Fin.inversio.opacity(0.12))
                        LineMark(x: .value("Mes", etiqueta(pt.mes)), y: .value("Total", pt.total))
                            .foregroundStyle(Fin.inversio)
                            .lineStyle(StrokeStyle(lineWidth: 2.5))
                    }
                    .chartXAxis {
                        AxisMarks { _ in AxisValueLabel().foregroundStyle(Fin.muted) }
                    }
                    .chartYAxis {
                        AxisMarks(position: .leading) { value in
                            AxisGridLine().foregroundStyle(Fin.line)
                            AxisValueLabel {
                                if let v = value.as(Double.self) { Text(Fin.eur0(v)).foregroundStyle(Fin.muted) }
                            }
                        }
                    }
                    .frame(height: 200)
                }
            }
        }
        .sheet(item: $edit) { CompteForm(compte: $0, showToast: showToast) }
        .sheet(isPresented: $editCoixi) { CoixiForm(showToast: showToast) }
    }

    /// "2026-10" → "oct 26"
    private func etiqueta(_ mes: String) -> String {
        Fin.mesCurt(mes) + " " + String(mes.prefix(4).suffix(2))
    }
}

// MARK: - Bolos

struct FuturBolos: View {
    let showToast: (String, Bool) -> Void

    @ObservedObject private var store = FuturStore.shared
    @State private var edit: Bolo?
    @State private var anyVist = Int(FinMes.actual().prefix(4)) ?? 2026

    var body: some View {
        let bolos = store.bolos.filter { $0.anyData == anyVist }
        let brut = bolos.reduce(0) { $0 + $1.brut }
        let pendent = bolos.filter { !$0.cobrat }.reduce(0) { $0 + $1.net }
        VStack(spacing: 0) {
            HStack {
                Button { anyVist -= 1 } label: { Image(systemName: "chevron.left") }
                Text(String(anyVist)).font(.system(size: 18, weight: .bold)).frame(minWidth: 70)
                Button { anyVist += 1 } label: { Image(systemName: "chevron.right") }
                Spacer()
                Button { edit = Bolo(data: FinMes.avui()) } label: {
                    Label("Bolo", systemImage: "plus")
                        .font(.system(size: 15, weight: .semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .foregroundStyle(.white)
                        .background(Fin.entrada, in: Capsule())
                }
            }
            .buttonStyle(.plain)
            .padding(.bottom, 12)

            FinKPIGrid {
                FinKPI(title: "Brut \(String(anyVist))", value: Fin.eur0(brut), color: Fin.entrada,
                       note: "\(bolos.count) bolo\(bolos.count == 1 ? "" : "s")")
                FinKPI(title: "Pendent de cobrar", value: Fin.eur0(pendent),
                       note: "Retingut: \(Fin.eur0(bolos.reduce(0) { $0 + $1.retingut }))")
            }

            FinCard {
                if bolos.isEmpty {
                    FinBuit(text: "Cap bolo apuntat aquest any. Apunta'ls amb l'import brut i la retenció de la factura.")
                }
                ForEach(Array(bolos.enumerated()), id: \.element.id) { i, b in
                    HStack(spacing: 8) {
                        Button { edit = b } label: {
                            FinFilaView(title: b.titol,
                                        subtitle: Fin.nomDia(b.data) + (b.pagador.isEmpty || b.concepte.isEmpty ? "" : " · " + b.pagador)
                                            + " · \(Fin.eur0(b.brut)) bruts, \(Fin.pct(b.retencio))",
                                        value: Fin.eur(b.net), color: b.cobrat ? Fin.entrada : Fin.muted)
                        }
                        .buttonStyle(.plain)
                        Button {
                            Task { await marcaCobrat(b) }
                        } label: {
                            Image(systemName: b.cobrat ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 22))
                                .foregroundStyle(b.cobrat ? Fin.entrada : Fin.muted)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(b.cobrat ? "Cobrat" : "Marcar com a cobrat")
                    }
                    if i < bolos.count - 1 { FinSeparador() }
                }
            }
            Text("El cercle marca si ja l'has cobrat. En marcar-lo, el net s'apunta sol a Moviments com a ingrés (categoria Bolos).")
                .font(.system(size: 13))
                .foregroundStyle(Fin.muted)
                .padding(.horizontal, 2)
        }
        .sheet(item: $edit) { BoloForm(bolo: $0, showToast: showToast) }
    }

    private func marcaCobrat(_ b: Bolo) async {
        var n = b
        n.cobrat.toggle()
        do {
            try await FuturStore.shared.desa(.bolos, n.fila)
            if n.cobrat {
                _ = try await GastosStore.shared.afegir(tipus: "Ingrés", imp: Fin.editable(n.net), categoria: "Bolos",
                                                         concepte: [n.pagador, n.concepte].filter { !$0.isEmpty }.joined(separator: " · "),
                                                         data: FinMes.avui())
                showToast("Cobrat: \(Fin.eur(n.net)) apuntat a Moviments", false)
            } else {
                showToast("Marcat com a pendent (el moviment, si cal, esborra'l a Moviments)", false)
            }
        } catch {
            showToast(error.localizedDescription, true)
        }
    }
}

// MARK: - IRPF

struct FuturIRPF: View {
    @ObservedObject private var store = FuturStore.shared
    @State private var anyVist = Int(FinMes.actual().prefix(4)) ?? 2026

    var body: some View {
        let r = store.irpf(anyVist)
        VStack(spacing: 0) {
            HStack {
                Button { anyVist -= 1 } label: { Image(systemName: "chevron.left") }
                Text("Renda \(String(anyVist))").font(.system(size: 18, weight: .bold)).frame(minWidth: 120)
                Button { anyVist += 1 } label: { Image(systemName: "chevron.right") }
                Spacer()
            }
            .buttonStyle(.plain)
            .padding(.bottom, 12)

            FinKPIGrid {
                FinKPI(title: r.resultat >= 0 ? "A pagar" : "Et tornen", value: Fin.eur0(abs(r.resultat)),
                       color: r.resultat > 0 ? Fin.sortida : Fin.entrada,
                       note: "Es declara la primavera de \(String(anyVist + 1))")
                FinKPI(title: "Tipus efectiu", value: Fin.pct(r.tipusEfectiu),
                       note: "Cada 100 € de bolo: \(Fin.eur0(r.tipusMarginal)) d'IRPF")
            }

            if r.brut == 0 {
                FinCard {
                    FinBuit(text: "Afegeix les nòmines a Previsió i els bolos a Bolos: el càlcul es fa sol.")
                }
            }

            if let ideal = r.retencioIdealBolos {
                FinCard(title: "Bolos") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(r.resultat > 0
                             ? "Amb el que t'han retingut et quedaria \(Fin.eur0(r.resultat)) per pagar. Guarda't aquests diners, o demana una retenció del \(Fin.pct(ideal.rounded())) als bolos."
                             : "Les retencions ja cobreixen el que toca pagar. Amb un \(Fin.pct(ideal.rounded())) als bolos quedaries a zero.")
                            .font(.system(size: 15))
                        Text("\(r.nBolos) bolos · \(Fin.eur0(r.brutBolos)) bruts · \(Fin.eur0(r.retencionsBolos)) retinguts")
                            .font(.system(size: 13))
                            .foregroundStyle(Fin.muted)
                    }
                }
            }

            FinCard(title: "Com surt") {
                VStack(spacing: 7) {
                    linia("Nòmines (brut)", r.brutNomines)
                    linia("Bolos (brut)", r.brutBolos)
                    linia("Seguretat Social", -r.seguretatSocial)
                    linia("Altres despeses (fix)", -IRPF.altresDespeses)
                    if r.reduccio > 0 { linia("Reducció per treball", -r.reduccio) }
                    FinSeparador()
                    linia("Base liquidable", r.base, bold: true)
                }
            }

            FinCard(title: "Per trams (estatal + català)") {
                VStack(spacing: 7) {
                    HStack {
                        Text("Tram").frame(maxWidth: .infinity, alignment: .leading)
                        Text("Tipus").frame(width: 54, alignment: .trailing)
                        Text("Base").frame(width: 80, alignment: .trailing)
                        Text("Quota").frame(width: 74, alignment: .trailing)
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Fin.muted)
                    ForEach(r.trams.filter { $0.base > 0 || $0.desDe <= r.base }) { t in
                        HStack {
                            Text(t.finsA.map { "\(Fin.eur0(t.desDe)) – \(Fin.eur0($0))" } ?? "més de \(Fin.eur0(t.desDe))")
                                .lineLimit(1).minimumScaleFactor(0.7)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text(Fin.pct(t.tipus)).frame(width: 54, alignment: .trailing)
                            Text(Fin.eur0(t.base)).frame(width: 80, alignment: .trailing)
                            Text(Fin.eur0(t.quota)).frame(width: 74, alignment: .trailing)
                        }
                        .font(.system(size: 14))
                        .monospacedDigit()
                    }
                    FinSeparador()
                    linia("Mínim personal", -r.descompteMinim)
                    linia("Quota", r.quota, bold: true)
                    linia("Retencions nòmines", -r.retencionsNomines)
                    linia("Retencions bolos", -r.retencionsBolos)
                    FinSeparador()
                    linia(r.resultat >= 0 ? "A pagar" : "Et tornen", abs(r.resultat), bold: true,
                          color: r.resultat > 0 ? Fin.sortida : Fin.entrada)
                }
            }

            Text("És una estimació: compta els bolos com a rendiments del treball i no inclou deduccions (lloguer, plans de pensions, donatius...). Serveix per saber per on vas, no substitueix la declaració.")
                .font(.system(size: 13))
                .foregroundStyle(Fin.muted)
                .padding(.horizontal, 2)
        }
    }

    private func linia(_ t: String, _ v: Double, bold: Bool = false, color: Color = Fin.text) -> some View {
        HStack {
            Text(t)
            Spacer()
            Text(Fin.eur(v)).monospacedDigit().foregroundStyle(color)
        }
        .font(.system(size: 15, weight: bold ? .bold : .regular))
    }
}

// MARK: - Formularis

/// Esquelet comú dels formularis: títol, Cancel·la / Desa i, si ja existia, Esborrar.
struct FinForm<Content: View>: View {
    let title: String
    let saving: Bool
    var error: String?
    var onDelete: (() -> Void)?
    let onSave: () -> Void
    @ViewBuilder var content: Content

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                content
                if let error {
                    Section { Text(error).foregroundStyle(Fin.sortida) }
                }
                if let onDelete {
                    Section {
                        Button("Esborrar", role: .destructive, action: onDelete)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Fin.bg)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel·la") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if saving { ProgressView() } else { Button("Desa", action: onSave).bold() }
                }
            }
            .disabled(saving)
        }
        .presentationDetents([.large])
    }
}

struct FinCampNum: View {
    let label: String
    @Binding var text: String
    var unit = "€"

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            TextField("0", text: $text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 140)
            Text(unit).foregroundStyle(Fin.muted)
        }
    }
}

private let isoDia: DateFormatter = {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.timeZone = TimeZone(identifier: "Europe/Madrid")
    f.dateFormat = "yyyy-MM-dd"
    return f
}()

private func dataDe(_ s: String) -> Date {
    isoDia.date(from: s.count == 7 ? s + "-01" : s) ?? Date()
}

/// Comú a tots els formularis: desa, tanca i avisa.
@MainActor
private func executa(_ saving: Binding<Bool>, _ errorText: Binding<String?>, dismiss: DismissAction,
                     toast: (String, Bool) -> Void, missatge: String, _ op: () async throws -> Void) async {
    saving.wrappedValue = true
    defer { saving.wrappedValue = false }
    do {
        try await op()
        toast(missatge, false)
        dismiss()
    } catch {
        errorText.wrappedValue = error.localizedDescription
    }
}

struct CompteForm: View {
    let compte: Compte
    let showToast: (String, Bool) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var nom = ""
    @State private var tipus = "Corrent"
    @State private var saldo = ""
    @State private var saving = false
    @State private var error: String?

    var body: some View {
        FinForm(title: compte.id.isEmpty ? "Compte nou" : compte.nom, saving: saving, error: error,
                onDelete: compte.id.isEmpty ? nil : { Task { await esborra() } }, onSave: { Task { await desa() } }) {
            Section {
                TextField("Nom (p. ex. Trade Republic)", text: $nom)
                Picker("Tipus", selection: $tipus) {
                    ForEach(Compte.tipus, id: \.self) { Text($0) }
                }
            } footer: {
                Text("Corrent i estalvi compten com a diners disponibles (coixí i previsió). Inversió només suma al patrimoni.")
            }
            Section("Saldo d'avui") {
                FinCampNum(label: "Saldo", text: $saldo)
            }
        }
        .onAppear {
            nom = compte.nom
            tipus = compte.tipus
            saldo = Fin.editable(compte.saldo)
        }
    }

    private func desa() async {
        let n = nom.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else { error = "Posa-li un nom"; return }
        var c = compte
        c.nom = n
        c.tipus = tipus
        let s = Fin.number(saldo)
        await executa($saving, $error, dismiss: dismiss, toast: showToast, missatge: "Saldo desat") {
            if c.id.isEmpty || s != compte.saldo {
                try await FuturStore.shared.actualitzaSaldo(c, saldo: s)
            } else {
                try await FuturStore.shared.desa(.comptes, c.fila)
            }
        }
    }

    private func esborra() async {
        await executa($saving, $error, dismiss: dismiss, toast: showToast, missatge: "Compte esborrat") {
            try await FuturStore.shared.esborra(.comptes, id: compte.id)
        }
    }
}

struct ContracteForm: View {
    let contracte: Contracte
    let showToast: (String, Bool) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var nom = ""
    @State private var brut = ""
    @State private var pagues = 14
    @State private var irpf = ""
    @State private var ss = ""
    @State private var teInici = false
    @State private var inici = Date()
    @State private var teFi = false
    @State private var fi = Date()
    @State private var saving = false
    @State private var error: String?

    var body: some View {
        FinForm(title: contracte.id.isEmpty ? "Contracte nou" : contracte.nom, saving: saving, error: error,
                onDelete: contracte.id.isEmpty ? nil : { Task { await esborra() } }, onSave: { Task { await desa() } }) {
            Section {
                TextField("Nom (p. ex. EMMCA)", text: $nom)
                FinCampNum(label: "Sou brut mensual", text: $brut)
                Picker("Pagues", selection: $pagues) {
                    Text("12 (prorratejades)").tag(12)
                    Text("14 (juny i desembre)").tag(14)
                }
            }
            Section {
                FinCampNum(label: "Retenció IRPF", text: $irpf, unit: "%")
                FinCampNum(label: "Seguretat Social", text: $ss, unit: "%")
            } footer: {
                Text("Tots dos surten a la nòmina. La Seguretat Social d'un contracte normal és un 6,5 % aproximadament.")
            }
            Section {
                Toggle("Comença més endavant", isOn: $teInici)
                if teInici {
                    DatePicker("Des de", selection: $inici, displayedComponents: .date)
                }
                Toggle("Té data de fi", isOn: $teFi)
                if teFi {
                    DatePicker("Fins a", selection: $fi, displayedComponents: .date)
                }
            } footer: {
                Text("Només compta el mes. Per exemple, un contracte de curs escolar que acaba al juny.")
            }
        }
        .environment(\.locale, Locale(identifier: "ca_ES"))
        .onAppear {
            nom = contracte.nom
            brut = Fin.editable(contracte.brut)
            pagues = contracte.pagues
            irpf = Fin.editable(contracte.irpf)
            ss = Fin.editable(contracte.ss)
            teInici = !contracte.desDe.isEmpty
            inici = dataDe(contracte.desDe)
            teFi = !contracte.finsA.isEmpty
            fi = dataDe(contracte.finsA)
        }
    }

    private func desa() async {
        let n = nom.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else { error = "Posa-li un nom"; return }
        guard Fin.number(brut) > 0 else { error = "Escriu el sou brut mensual"; return }
        var c = contracte
        if c.id.isEmpty { c.id = FinTaula.nouId() }
        c.nom = n
        c.brut = Fin.number(brut)
        c.pagues = pagues
        c.irpf = Fin.number(irpf)
        c.ss = Fin.number(ss)
        c.desDe = teInici ? String(isoDia.string(from: inici).prefix(7)) : ""
        c.finsA = teFi ? String(isoDia.string(from: fi).prefix(7)) : ""
        await executa($saving, $error, dismiss: dismiss, toast: showToast, missatge: "Contracte desat") {
            try await FuturStore.shared.desa(.contractes, c.fila)
        }
    }

    private func esborra() async {
        await executa($saving, $error, dismiss: dismiss, toast: showToast, missatge: "Contracte esborrat") {
            try await FuturStore.shared.esborra(.contractes, id: contracte.id)
        }
    }
}

struct BoloForm: View {
    let bolo: Bolo
    let showToast: (String, Bool) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var data = Date()
    @State private var concepte = ""
    @State private var pagador = ""
    @State private var brut = ""
    @State private var retencio = ""
    @State private var cobrat = false
    @State private var apunta = true
    @State private var saving = false
    @State private var error: String?

    var body: some View {
        FinForm(title: bolo.id.isEmpty ? "Bolo nou" : bolo.titol, saving: saving, error: error,
                onDelete: bolo.id.isEmpty ? nil : { Task { await esborra() } }, onSave: { Task { await desa() } }) {
            Section {
                TextField("Concert (p. ex. Nadal Sant Cugat)", text: $concepte)
                TextField("Qui paga (p. ex. OSV)", text: $pagador)
                DatePicker("Data", selection: $data, displayedComponents: .date)
            }
            Section {
                FinCampNum(label: "Import brut", text: $brut)
                FinCampNum(label: "Retenció IRPF", text: $retencio, unit: "%")
                Picker("Retencions habituals", selection: $retencio) {
                    ForEach(["15", "7", "2", "0"], id: \.self) { Text($0 + " %").tag($0) }
                }
                .pickerStyle(.segmented)
                if Fin.number(brut) > 0 {
                    let net = Fin.number(brut) * (1 - Fin.number(retencio) / 100)
                    HStack {
                        Text("Cobraràs")
                        Spacer()
                        Text(Fin.eur(net)).bold()
                    }
                }
            } footer: {
                Text("Factura com a autònom: 15 % (7 % els primers anys). Contracte artístic curt: sovint 2 %.")
            }
            Section {
                Toggle("Ja l'he cobrat", isOn: $cobrat)
                if cobrat && !bolo.cobrat {
                    Toggle("Apunta'l a Moviments", isOn: $apunta)
                }
            }
        }
        .environment(\.locale, Locale(identifier: "ca_ES"))
        .onAppear {
            data = dataDe(bolo.data)
            concepte = bolo.concepte
            pagador = bolo.pagador
            brut = Fin.editable(bolo.brut)
            retencio = Fin.editable(bolo.retencio).isEmpty ? "0" : Fin.editable(bolo.retencio)
            cobrat = bolo.cobrat
        }
    }

    private func desa() async {
        guard Fin.number(brut) > 0 else { error = "Escriu l'import brut"; return }
        var b = bolo
        if b.id.isEmpty { b.id = FinTaula.nouId() }
        b.data = isoDia.string(from: data)
        b.concepte = concepte.trimmingCharacters(in: .whitespaces)
        b.pagador = pagador.trimmingCharacters(in: .whitespaces)
        b.brut = Fin.number(brut)
        b.retencio = Fin.number(retencio)
        b.cobrat = cobrat
        let nouCobrament = cobrat && !bolo.cobrat && apunta
        await executa($saving, $error, dismiss: dismiss, toast: showToast,
                      missatge: nouCobrament ? "Bolo desat i apuntat a Moviments" : "Bolo desat") {
            try await FuturStore.shared.desa(.bolos, b.fila)
            if nouCobrament {
                _ = try await GastosStore.shared.afegir(tipus: "Ingrés", imp: Fin.editable(b.net), categoria: "Bolos",
                                                         concepte: [b.pagador, b.concepte].filter { !$0.isEmpty }.joined(separator: " · "),
                                                         data: FinMes.avui())
            }
        }
    }

    private func esborra() async {
        await executa($saving, $error, dismiss: dismiss, toast: showToast, missatge: "Bolo esborrat") {
            try await FuturStore.shared.esborra(.bolos, id: bolo.id)
        }
    }
}

struct PrevistForm: View {
    let previst: Previst
    let showToast: (String, Bool) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var nom = ""
    @State private var tipus = "Despesa"
    @State private var imp = ""
    @State private var mes = 1
    @State private var cadaAny = true
    @State private var anyFix = Int(FinMes.actual().prefix(4)) ?? 2026
    @State private var saving = false
    @State private var error: String?

    var body: some View {
        FinForm(title: previst.id.isEmpty ? "Previst nou" : previst.nom, saving: saving, error: error,
                onDelete: previst.id.isEmpty ? nil : { Task { await esborra() } }, onSave: { Task { await desa() } }) {
            Section {
                Picker("Tipus", selection: $tipus) {
                    Text("Despesa").tag("Despesa")
                    Text("Ingrés").tag("Ingrés")
                }
                .pickerStyle(.segmented)
                TextField("Nom (p. ex. Assegurança de la moto)", text: $nom)
                FinCampNum(label: "Import", text: $imp)
            }
            Section {
                Picker("Mes", selection: $mes) {
                    ForEach(1...12, id: \.self) { Text(Fin.mesos[$0 - 1].capitalized).tag($0) }
                }
                Toggle("Cada any", isOn: $cadaAny)
                if !cadaAny {
                    Stepper("Any \(String(anyFix))", value: $anyFix, in: 2020...2100)
                }
            }
        }
        .onAppear {
            nom = previst.nom
            tipus = previst.tipus
            imp = Fin.editable(previst.imp)
            mes = previst.mes
            cadaAny = previst.anyFix == 0
            if previst.anyFix != 0 { anyFix = previst.anyFix }
        }
    }

    private func desa() async {
        let n = nom.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else { error = "Posa-li un nom"; return }
        guard Fin.number(imp) > 0 else { error = "Escriu l'import"; return }
        var p = previst
        if p.id.isEmpty { p.id = FinTaula.nouId() }
        p.nom = n
        p.tipus = tipus
        p.imp = Fin.number(imp)
        p.mes = mes
        p.anyFix = cadaAny ? 0 : anyFix
        await executa($saving, $error, dismiss: dismiss, toast: showToast, missatge: "Desat") {
            try await FuturStore.shared.desa(.previstos, p.fila)
        }
    }

    private func esborra() async {
        await executa($saving, $error, dismiss: dismiss, toast: showToast, missatge: "Esborrat") {
            try await FuturStore.shared.esborra(.previstos, id: previst.id)
        }
    }
}

struct DespesaForm: View {
    let showToast: (String, Bool) -> Void

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = FuturStore.shared
    @State private var valor = ""
    @State private var saving = false
    @State private var error: String?

    var body: some View {
        FinForm(title: "Despesa habitual", saving: saving, error: error, onSave: { Task { await desa() } }) {
            Section {
                FinCampNum(label: "Al mes", text: $valor)
            } footer: {
                Text("Deixa-ho en blanc per fer servir la mitjana dels 3 últims mesos (\(Fin.eur(store.despesaMitjana))). No hi comptis el que ja has posat a previstos.")
            }
        }
        .onAppear { valor = store.ajust("despesaMensual") }
    }

    private func desa() async {
        let v = Fin.number(valor)
        await executa($saving, $error, dismiss: dismiss, toast: showToast, missatge: "Desat") {
            try await FuturStore.shared.desaAjust("despesaMensual", v > 0 ? Fin.editable(v) : "")
        }
    }
}

struct CoixiForm: View {
    let showToast: (String, Bool) -> Void

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = FuturStore.shared
    @State private var mesos = 6
    @State private var saving = false
    @State private var error: String?

    var body: some View {
        FinForm(title: "Coixí de seguretat", saving: saving, error: error, onSave: { Task { await desa() } }) {
            Section {
                Stepper("\(mesos) mesos", value: $mesos, in: 1...24)
                HStack {
                    Text("Objectiu")
                    Spacer()
                    Text(Fin.eur0(Double(mesos) * store.despesaMensual)).bold()
                }
            } footer: {
                Text("Quants mesos de despesa habitual vols tenir sempre disponibles. El més habitual és entre 3 i 6.")
            }
        }
        .onAppear { mesos = Int(store.coixiMesos) }
    }

    private func desa() async {
        await executa($saving, $error, dismiss: dismiss, toast: showToast, missatge: "Desat") {
            try await FuturStore.shared.desaAjust("coixiMesos", String(mesos))
        }
    }
}

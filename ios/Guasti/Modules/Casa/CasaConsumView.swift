import SwiftUI
import Charts

/// Llum, aigua i gas: quant se n'ha gastat, quant ha costat i a quin preu, tot junt o cada cosa per separat.
/// Es calcula amb les factures que hi ha a Casa, així que s'actualitza sola quan n'arriben de noves.
enum CasaServei: String, CaseIterable, Identifiable {
    case llum = "Llum", aigua = "Aigua", gas = "Gas"

    var id: String { rawValue }
    var icon: String {
        switch self {
        case .llum: return "bolt.fill"
        case .aigua: return "drop.fill"
        case .gas: return "flame.fill"
        }
    }
    var unitat: String { self == .aigua ? "m³" : "kWh" }
    /// Aigua en blau, llum en groc i gas en vermell.
    var color: Color {
        switch self {
        case .llum: return Color(red: 0.96, green: 0.74, blue: 0.05)
        case .aigua: return Color(red: 0.13, green: 0.47, blue: 0.86)
        case .gas: return Color(red: 0.86, green: 0.20, blue: 0.18)
        }
    }

    static let colors: [Color] = allCases.map(\.color)
    static let noms: [String] = allCases.map(\.rawValue)
}

/// Un tros d'una factura que cau dins d'un mes concret.
struct CasaTram {
    let servei: CasaServei
    let any: Int
    let mes: Int
    let consum: Double
    let cost: Double
    let dies: Double
}

/// Un any d'un subministrament. Les factures que passen d'un any a l'altre es reparteixen pels dies.
struct CasaConsumAny: Identifiable {
    let any: Int
    var consum: Double = 0
    var cost: Double = 0
    /// Dies de l'any que tenen factura (per saber si l'any és sencer).
    var dies: Double = 0

    var id: Int { any }
    /// Preu mitjà de cada kWh o m³, amb tot inclòs (impostos, quotes fixes...).
    var preu: Double? { consum > 0 ? cost / consum : nil }
    /// Mitjanes al mes: serveixen per comparar anys que no estan sencers.
    var consumMes: Double? { dies >= 20 ? consum / dies * 30.44 : nil }
    var costMes: Double? { dies >= 20 ? cost / dies * 30.44 : nil }
    var mesos: Int { Int((dies / 30.44).rounded()) }
}

/// Una factura amb el seu període.
struct CasaFacturaConsum: Identifiable {
    let id: String
    let inici: Date
    let fi: Date
    let consum: Double
    let cost: Double
    let dies: Double
}

struct CasaFacturaRara: Identifiable {
    let factura: CasaFacturaConsum
    let vegades: Double
    var id: String { factura.id }
}

/// Un mes d'un subministrament (per als gràfics mes a mes).
struct CasaConsumMes: Identifiable {
    let servei: CasaServei
    let mes: Date
    var consum: Double = 0
    var cost: Double = 0
    var id: String { servei.rawValue + "\(mes.timeIntervalSince1970)" }
}

enum CasaConsumCalcul {
    static let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Madrid") ?? .current
        return c
    }()

    /// Cada factura partida pels mesos que cobreix, en proporció als dies.
    static func trams(_ registres: [CasaRegistre], servei: CasaServei) -> [CasaTram] {
        var out: [CasaTram] = []
        var vistes = Set<String>()
        for r in registres where r.kind == .factura && r.displayTitle == servei.rawValue {
            guard let consum = r.consumValue else { continue }
            // La propietària de vegades envia el mateix PDF dues vegades
            let clau = "\(r.inici ?? "")|\(r.venciment)|\(consum)|\(r.imp)" + ((r.inici ?? "").isEmpty ? "|\(r.data)" : "")
            guard vistes.insert(clau).inserted else { continue }
            let cost = r.importValue ?? 0

            if let a = (r.inici).flatMap(CasaFmt.date), let b = CasaFmt.date(r.venciment), b > a {
                let total = b.timeIntervalSince(a) / 86400
                var d = a
                while d < b {
                    let c = cal.dateComponents([.year, .month], from: d)
                    let inici = cal.date(from: c) ?? d
                    let seguent = cal.date(byAdding: .month, value: 1, to: inici) ?? b
                    let next = min(seguent, b)
                    let dies = next.timeIntervalSince(d) / 86400
                    let f = dies / total
                    out.append(CasaTram(servei: servei, any: c.year ?? 0, mes: c.month ?? 1,
                                        consum: consum * f, cost: cost * f, dies: dies))
                    d = next
                }
            } else if let data = CasaFmt.date(r.data) {
                // Sense període: una factura normal (dos mesos l'aigua, un mes la resta)
                let c = cal.dateComponents([.year, .month], from: data)
                out.append(CasaTram(servei: servei, any: c.year ?? 0, mes: c.month ?? 1,
                                    consum: consum, cost: cost, dies: servei == .aigua ? 61 : 30.44))
            }
        }
        return out
    }

    /// Les factures amb període, sense repetides, per buscar-ne de rares.
    static func factures(_ registres: [CasaRegistre], servei: CasaServei) -> [CasaFacturaConsum] {
        var out: [CasaFacturaConsum] = []
        var vistes = Set<String>()
        for r in registres where r.kind == .factura && r.displayTitle == servei.rawValue {
            guard let consum = r.consumValue, let a = (r.inici).flatMap(CasaFmt.date),
                  let b = CasaFmt.date(r.venciment), b > a else { continue }
            guard vistes.insert("\(r.inici ?? "")|\(r.venciment)|\(consum)").inserted else { continue }
            out.append(CasaFacturaConsum(id: r.id, inici: a, fi: b, consum: consum, cost: r.importValue ?? 0,
                                         dies: b.timeIntervalSince(a) / 86400))
        }
        return out.sorted { $0.inici < $1.inici }
    }

    /// Factures que gasten (per dia) molt més que la mitjana de les altres de la mateixa època de l'any.
    static func rares(_ fs: [CasaFacturaConsum]) -> [CasaFacturaRara] {
        let perDia = fs.filter { $0.dies >= 10 }.map { $0.consum / $0.dies }.sorted()
        guard perDia.count >= 6 else { return [] }
        return fs.compactMap { f in
            guard f.dies >= 10 else { return nil }
            let mes = cal.component(.month, from: f.inici)
            // Mateixa època: factures que comencen com a molt un mes abans o després
            let semblants = fs.filter { g in
                g.id != f.id && g.dies >= 10 && {
                    let d = abs(cal.component(.month, from: g.inici) - mes)
                    return min(d, 12 - d) <= 1
                }()
            }.map { $0.consum / $0.dies }.sorted()
            guard semblants.count >= 2 else { return nil }
            let mitjana = semblants[semblants.count / 2]
            let x = (f.consum / f.dies) / max(mitjana, 0.0001)
            return x >= 1.8 ? CasaFacturaRara(factura: f, vegades: x) : nil
        }
    }

    /// Gener fins a l'últim mes amb factura d'enguany, comparat amb els mateixos mesos de l'any anterior.
    static func mateixosMesos(_ trams: [CasaTram]) -> (any: Int, finsMes: Int, ara: (Double, Double), abans: (Double, Double))? {
        guard let any = trams.map(\.any).max() else { return nil }
        let finsMes = trams.filter { $0.any == any }.map(\.mes).max() ?? 0
        guard finsMes >= 2, trams.contains(where: { $0.any == any - 1 }) else { return nil }
        func suma(_ a: Int) -> (Double, Double) {
            trams.filter { $0.any == a && $0.mes <= finsMes }.reduce((0, 0)) { ($0.0 + $1.consum, $0.1 + $1.cost) }
        }
        return (any, finsMes, suma(any), suma(any - 1))
    }

    static func anys(_ registres: [CasaRegistre], servei: CasaServei) -> [CasaConsumAny] {
        var per: [Int: CasaConsumAny] = [:]
        for t in trams(registres, servei: servei) {
            var y = per[t.any] ?? CasaConsumAny(any: t.any)
            y.consum += t.consum
            y.cost += t.cost
            y.dies += t.dies
            per[t.any] = y
        }
        return per.values.map { var y = $0; y.dies = min(y.dies, 366); return y }.sorted { $0.any < $1.any }
    }

    static func mesos(_ registres: [CasaRegistre], servei: CasaServei) -> [CasaConsumMes] {
        var per: [Date: CasaConsumMes] = [:]
        for t in trams(registres, servei: servei) {
            guard let d = cal.date(from: DateComponents(year: t.any, month: t.mes, day: 1)) else { continue }
            var m = per[d] ?? CasaConsumMes(servei: servei, mes: d)
            m.consum += t.consum
            m.cost += t.cost
            per[d] = m
        }
        return per.values.sorted { $0.mes < $1.mes }
    }
}

/// Un punt dels gràfics conjunts: un any i un subministrament.
private struct CasaPunt: Identifiable {
    let servei: CasaServei
    let any: Int
    let valor: Double
    let complet: Bool
    var id: String { servei.rawValue + String(any) }
}

struct CasaConsumView: View {
    @ObservedObject private var store = CasaStore.shared
    /// nil = tot junt
    @State private var servei: CasaServei? = nil
    @State private var variable: Variable = .cost
    @State private var periode: Periode = .anys

    static func nomMes(_ m: Int) -> String {
        let noms = ["gener", "febrer", "març", "abril", "maig", "juny", "juliol", "agost", "setembre", "octubre", "novembre", "desembre"]
        return noms[max(0, min(11, m - 1))]
    }

    enum Variable: String, CaseIterable, Identifiable {
        case cost = "Cost", consum = "Consum", preu = "Preu"
        var id: String { rawValue }
    }

    enum Periode: String, CaseIterable, Identifiable {
        case anys = "Any a any", mesos = "Mes a mes"
        var id: String { rawValue }
    }

    var body: some View {
        List {
            Section {
                Picker("Què vols veure", selection: $servei) {
                    Text("Tot").tag(CasaServei?.none)
                    ForEach(CasaServei.allCases) { s in Text(s.rawValue).tag(Optional(s)) }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }

            let perLlegir = store.registres(.factura).filter {
                (servei.map { [$0.rawValue] } ?? CasaServei.noms).contains($0.displayTitle) && $0.consum == nil
            }.count
            if perLlegir > 0 {
                Section {
                    Label("Encara s'estan llegint \(perLlegir) factures. Això s'anirà completant sol.", systemImage: "hourglass")
                        .font(Theme.body(14))
                        .foregroundStyle(.secondary)
                }
            }

            if let servei {
                VistaServei(servei: servei, registres: store.registres, variable: $variable, periode: $periode)
            } else {
                VistaTot(registres: store.registres, periode: $periode)
            }
        }
        .navigationTitle("Llum, aigua i gas")
        .tint(.primary)
        .refreshable { await store.load() }
    }
}

// MARK: - Tot junt

private struct VistaTot: View {
    let registres: [CasaRegistre]
    @Binding var periode: CasaConsumView.Periode

    var body: some View {
        let anys = Dictionary(uniqueKeysWithValues: CasaServei.allCases.map { ($0, CasaConsumCalcul.anys(registres, servei: $0)) })
        let tots = Set(anys.values.flatMap { $0.map(\.any) }).sorted()
        // Només anys amb prou factures de tot per comparar
        let bons = tots.filter { a in CasaServei.allCases.allSatisfy { s in (anys[s]?.first { $0.any == a }?.mesos ?? 0) >= 3 } }

        if bons.isEmpty {
            Section { Text("Encara no hi ha prou factures amb el consum llegit.").foregroundStyle(.secondary) }
        } else {
            resum(anys, bons)
            mateixosMesos()
            total(anys)

            Section {
                Picker("Període", selection: $periode) {
                    ForEach(CasaConsumView.Periode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }

            if periode == .anys {
                costAnys(anys, bons)
                preusAnys(anys, bons)
            } else {
                costMesos()
            }
            taula(anys, bons)
        }
    }

    private func costMes(_ anys: [CasaServei: [CasaConsumAny]], _ s: CasaServei, _ a: Int) -> Double {
        anys[s]?.first { $0.any == a }?.costMes ?? 0
    }

    @ViewBuilder private func resum(_ anys: [CasaServei: [CasaConsumAny]], _ bons: [Int]) -> some View {
        if let a = bons.first, let b = bons.last, a != b {
            let ta = CasaServei.allCases.reduce(0) { $0 + costMes(anys, $1, a) }
            let tb = CasaServei.allCases.reduce(0) { $0 + costMes(anys, $1, b) }
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Del \(String(a)) al \(String(b))").font(Theme.display(18))
                    FilaCanvi(nom: "Tot junt, al mes", color: .primary, a: ta, b: tb,
                              detall: "\(CasaFmt.euros(ta)) → \(CasaFmt.euros(tb))")
                    ForEach(CasaServei.allCases) { s in
                        let x = costMes(anys, s, a), y = costMes(anys, s, b)
                        FilaCanvi(nom: s.rawValue, color: s.color, a: x, b: y,
                                  detall: "\(CasaFmt.euros(x)) → \(CasaFmt.euros(y))")
                    }
                }
                .padding(.vertical, 4)
            } footer: {
                Text("Factura mitjana al mes de cada any.")
            }
        }
    }

    @ViewBuilder private func mateixosMesos() -> some View {
        let trams = CasaServei.allCases.flatMap { CasaConsumCalcul.trams(registres, servei: $0) }
        if let m = CasaConsumCalcul.mateixosMesos(trams) {
            Section {
                FilaCanvi(nom: "Tot junt", color: .primary, a: m.abans.1, b: m.ara.1,
                          detall: "\(CasaFmt.euros(m.abans.1)) → \(CasaFmt.euros(m.ara.1))")
                ForEach(CasaServei.allCases) { s in
                    do {
                        let a = trams.filter { $0.servei == s && $0.any == m.any - 1 && $0.mes <= m.finsMes }.reduce(0) { $0 + $1.cost }
                        let b = trams.filter { $0.servei == s && $0.any == m.any && $0.mes <= m.finsMes }.reduce(0) { $0 + $1.cost }
                        FilaCanvi(nom: s.rawValue, color: s.color, a: a, b: b,
                                  detall: "\(CasaFmt.euros(a)) → \(CasaFmt.euros(b))")
                    }
                }
            } header: {
                Text("\(String(m.any)) contra \(String(m.any - 1))")
            } footer: {
                Text("El que has pagat de gener a \(CasaConsumView.nomMes(m.finsMes)) d'aquest any, comparat amb els mateixos mesos de l'any anterior.")
            }
        }
    }

    @ViewBuilder private func total(_ anys: [CasaServei: [CasaConsumAny]]) -> some View {
        let primer = anys.values.compactMap { $0.first?.any }.min()
        let total = anys.values.flatMap { $0 }.reduce(0) { $0 + $1.cost }
        if let primer {
            Section {
                HStack {
                    Text("Total pagat des del \(String(primer))").font(Theme.body(15))
                    Spacer()
                    Text(CasaFmt.euros(total)).font(Theme.body(17, weight: .semibold))
                }
                HStack(spacing: 14) {
                    ForEach(CasaServei.allCases) { s in
                        HStack(spacing: 4) {
                            Circle().fill(s.color).frame(width: 8, height: 8)
                            Text("\(s.rawValue) \(CasaFmt.euros((anys[s] ?? []).reduce(0) { $0 + $1.cost }))")
                        }
                    }
                }
                .font(Theme.body(13, relativeTo: .footnote))
                .foregroundStyle(.secondary)
            }
        }
    }

    private func costAnys(_ anys: [CasaServei: [CasaConsumAny]], _ bons: [Int]) -> some View {
        let punts = bons.flatMap { a in CasaServei.allCases.map { s in
            CasaPunt(servei: s, any: a, valor: costMes(anys, s, a), complet: true)
        } }
        return Section {
            Chart(punts) { p in
                BarMark(x: .value("Any", String(p.any)), y: .value("€", p.valor))
                    .foregroundStyle(by: .value("Servei", p.servei.rawValue))
            }
            .chartForegroundStyleScale(domain: CasaServei.noms, range: CasaServei.colors)
            .chartLegend(position: .bottom)
            .frame(height: 220)
            .padding(.vertical, 6)
        } header: {
            Text("Quant pagues al mes")
        } footer: {
            Text("Mitjana de cada any: cada color és un subministrament, i l'alçada total és tot junt.")
        }
    }

    /// Com han pujat els preus: el primer any és 100 per a cada subministrament.
    private func preusAnys(_ anys: [CasaServei: [CasaConsumAny]], _ bons: [Int]) -> some View {
        let punts: [CasaPunt] = CasaServei.allCases.flatMap { s -> [CasaPunt] in
            let ys = (anys[s] ?? []).filter { bons.contains($0.any) && $0.preu != nil }
            guard let base = ys.first?.preu, base > 0 else { return [] }
            return ys.map { CasaPunt(servei: s, any: $0.any, valor: ($0.preu ?? 0) / base * 100, complet: true) }
        }
        return Section {
            Chart(punts) { p in
                LineMark(x: .value("Any", String(p.any)), y: .value("Preu", p.valor))
                    .foregroundStyle(by: .value("Servei", p.servei.rawValue))
                    .symbol(by: .value("Servei", p.servei.rawValue))
                RuleMark(y: .value("Inici", 100))
                    .foregroundStyle(.secondary.opacity(0.4))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
            }
            .chartForegroundStyleScale(domain: CasaServei.noms, range: CasaServei.colors)
            .chartLegend(position: .bottom)
            .frame(height: 200)
            .padding(.vertical, 6)
        } header: {
            Text("Com han canviat els preus")
        } footer: {
            Text("El primer any és 100. Si una línia arriba a 120, aquell preu ha pujat un 20 %.")
        }
    }

    private func costMesos() -> some View {
        let tots = CasaServei.allCases.flatMap { CasaConsumCalcul.mesos(registres, servei: $0) }
        let desDe = CasaConsumCalcul.cal.date(byAdding: .month, value: -24, to: Date()) ?? .distantPast
        let punts = tots.filter { $0.mes >= desDe }
        return Section {
            Chart(punts) { m in
                BarMark(x: .value("Mes", m.mes, unit: .month), y: .value("€", m.cost))
                    .foregroundStyle(by: .value("Servei", m.servei.rawValue))
            }
            .chartForegroundStyleScale(domain: CasaServei.noms, range: CasaServei.colors)
            .chartLegend(position: .bottom)
            .chartXAxis {
                AxisMarks(values: .stride(by: .month, count: 3)) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.month(.abbreviated).year(.twoDigits))
                }
            }
            .frame(height: 220)
            .padding(.vertical, 6)
        } header: {
            Text("Quant has pagat cada mes")
        } footer: {
            Text("Els últims dos anys. Les factures de dos mesos es reparteixen entre els dos.")
        }
    }

    private func taula(_ anys: [CasaServei: [CasaConsumAny]], _ bons: [Int]) -> some View {
        Section("Any per any") {
            ForEach(bons.reversed(), id: \.self) { a in
                let cost: (CasaServei) -> Double = { s in anys[s]?.first { $0.any == a }?.cost ?? 0 }
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(String(a)).font(Theme.body(17, weight: .semibold))
                        Spacer()
                        Text(CasaFmt.euros(CasaServei.allCases.reduce(0) { $0 + cost($1) })).font(Theme.body(17, weight: .semibold))
                    }
                    HStack(spacing: 14) {
                        ForEach(CasaServei.allCases) { s in
                            HStack(spacing: 4) {
                                Circle().fill(s.color).frame(width: 8, height: 8)
                                Text("\(s.rawValue) \(CasaFmt.euros(cost(s)))")
                            }
                        }
                    }
                    .font(Theme.body(13, relativeTo: .footnote))
                    .foregroundStyle(.secondary)
                    let mesos = CasaServei.allCases.map { s in anys[s]?.first { $0.any == a }?.mesos ?? 0 }.min() ?? 0
                    if mesos < 12 {
                        Text("Any incomplet: \(mesos) mesos amb factura")
                            .font(Theme.body(12, relativeTo: .caption))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }
}

// MARK: - Un subministrament

private struct VistaServei: View {
    let servei: CasaServei
    let registres: [CasaRegistre]
    @Binding var variable: CasaConsumView.Variable
    @Binding var periode: CasaConsumView.Periode

    var body: some View {
        let anys = CasaConsumCalcul.anys(registres, servei: servei)
        if anys.isEmpty {
            Section {
                Text("Encara no hi ha factures de \(servei.rawValue.lowercased()) amb el consum llegit.")
                    .foregroundStyle(.secondary)
            }
        } else {
            resum(anys)
            Section {
                VStack(spacing: 10) {
                    Picker("Variable", selection: $variable) {
                        ForEach(CasaConsumView.Variable.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Picker("Període", selection: $periode) {
                        ForEach(CasaConsumView.Periode.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }
            if periode == .anys { graficAnys(anys) } else { graficMesos() }
            mateixosMesos()
            rares()
            taula(anys)
        }
    }

    private var titol: String {
        switch variable {
        case .cost: return periode == .anys ? "Quant pagues al mes (mitjana de l'any)" : "Quant has pagat cada mes"
        case .consum: return periode == .anys ? "Quant gastes al mes (mitjana de l'any)" : "Quant has gastat cada mes"
        case .preu: return "Preu per \(servei.unitat)"
        }
    }

    private var peu: String {
        switch variable {
        case .preu:
            return servei == .aigua
                ? "Tot inclòs: a l'aigua hi ha quotes fixes i taxes (clavegueram, residus), per això cada m³ surt car."
                : "Tot inclòs: potència o terme fix, lloguer del comptador i impostos, dividit pel que has gastat."
        default:
            return periode == .anys
                ? "Les barres clares són anys dels quals encara no hi ha totes les factures."
                : "Les factures que cobreixen més d'un mes es reparteixen pels dies."
        }
    }

    private func valor(_ y: CasaConsumAny) -> Double? {
        switch variable {
        case .cost: return y.costMes
        case .consum: return y.consumMes
        case .preu: return y.preu
        }
    }

    private func text(_ v: Double) -> String {
        switch variable {
        case .cost: return CasaFmt.euros(v)
        case .consum: return num(v)
        case .preu: return preuText(v)
        }
    }

    private func graficAnys(_ anys: [CasaConsumAny]) -> some View {
        Section {
            Chart(anys.filter { valor($0) != nil }) { y in
                if variable == .preu {
                    LineMark(x: .value("Any", String(y.any)), y: .value("Preu", valor(y) ?? 0))
                        .foregroundStyle(servei.color)
                    PointMark(x: .value("Any", String(y.any)), y: .value("Preu", valor(y) ?? 0))
                        .foregroundStyle(servei.color)
                        .annotation(position: .top) {
                            Text(text(valor(y) ?? 0)).font(.system(size: 10)).foregroundStyle(.secondary)
                        }
                } else {
                    BarMark(x: .value("Any", String(y.any)), y: .value(variable.rawValue, valor(y) ?? 0))
                        .foregroundStyle(servei.color.opacity(y.mesos >= 11 ? 1 : 0.4))
                        .annotation(position: .top) {
                            Text(text(valor(y) ?? 0)).font(.system(size: 10)).foregroundStyle(.secondary)
                        }
                }
            }
            .chartYAxis(.hidden)
            .frame(height: 200)
            .padding(.vertical, 6)
        } header: {
            Text(titol)
        } footer: {
            Text(peu)
        }
    }

    private func graficMesos() -> some View {
        let mesos = CasaConsumCalcul.mesos(registres, servei: servei)
        return Section {
            Chart(mesos) { m in
                if variable == .preu {
                    LineMark(x: .value("Mes", m.mes, unit: .month), y: .value("Preu", m.consum > 0 ? m.cost / m.consum : 0))
                        .foregroundStyle(servei.color)
                } else {
                    BarMark(x: .value("Mes", m.mes, unit: .month), y: .value(variable.rawValue, variable == .cost ? m.cost : m.consum))
                        .foregroundStyle(servei.color)
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .year)) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.year())
                }
            }
            .frame(height: 220)
            .padding(.vertical, 6)
        } header: {
            Text(titol)
        } footer: {
            Text(peu)
        }
    }

    @ViewBuilder private func mateixosMesos() -> some View {
        if let m = CasaConsumCalcul.mateixosMesos(CasaConsumCalcul.trams(registres, servei: servei)) {
            Section {
                FilaCanvi(nom: "Pagat", color: servei.color, a: m.abans.1, b: m.ara.1,
                          detall: "\(CasaFmt.euros(m.abans.1)) → \(CasaFmt.euros(m.ara.1))")
                FilaCanvi(nom: "Gastat", color: servei.color, a: m.abans.0, b: m.ara.0,
                          detall: "\(num(m.abans.0)) → \(num(m.ara.0)) \(servei.unitat)")
            } header: {
                Text("\(String(m.any)) contra \(String(m.any - 1))")
            } footer: {
                Text("De gener a \(CasaConsumView.nomMes(m.finsMes)), comparat amb els mateixos mesos de l'any anterior.")
            }
        }
    }

    @ViewBuilder private func rares() -> some View {
        let rs = CasaConsumCalcul.rares(CasaConsumCalcul.factures(registres, servei: servei))
        if !rs.isEmpty {
            Section {
                ForEach(rs) { r in
                    let f = r.factura, x = r.vegades
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(CasaTheme.late)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(CasaFmt.human(CasaFmt.string(f.inici))) – \(CasaFmt.human(CasaFmt.string(f.fi)))")
                                .font(Theme.body(15, weight: .semibold))
                            Text("\(num(f.consum)) \(servei.unitat) · \(CasaFmt.euros(f.cost)) · " +
                                 String(format: "%.1f", x).replacingOccurrences(of: ".", with: ",") + " vegades el normal")
                                .font(Theme.body(13, relativeTo: .footnote))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text("Factures rares")
            } footer: {
                Text("Gasten molt més per dia que les de la mateixa època dels altres anys. Pot ser una lectura estimada o un error: val la pena mirar-les.")
            }
        }
    }

    @ViewBuilder private func resum(_ anys: [CasaConsumAny]) -> some View {
        // Comparem el primer i l'últim any amb prou mesos per fer-ne una mitjana fiable
        let bons = anys.filter { $0.mesos >= 3 }
        if let a = bons.first, let b = bons.last, a.any != b.any {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Del \(String(a.any)) al \(String(b.any))", systemImage: servei.icon)
                        .font(Theme.display(18))
                        .foregroundStyle(servei.color, .primary)
                    if let ma = a.costMes, let mb = b.costMes {
                        FilaCanvi(nom: "Factura al mes", color: servei.color, a: ma, b: mb,
                                  detall: "\(CasaFmt.euros(ma)) → \(CasaFmt.euros(mb))")
                    }
                    if let ca = a.consumMes, let cb = b.consumMes {
                        FilaCanvi(nom: "Consum al mes", color: servei.color, a: ca, b: cb,
                                  detall: "\(num(ca)) → \(num(cb)) \(servei.unitat)")
                    }
                    if let pa = a.preu, let pb = b.preu {
                        FilaCanvi(nom: "Preu per \(servei.unitat)", color: servei.color, a: pa, b: pb,
                                  detall: "\(preuText(pa)) → \(preuText(pb))")
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private func taula(_ anys: [CasaConsumAny]) -> some View {
        Section("Any per any") {
            ForEach(anys.reversed()) { y in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(String(y.any)).font(Theme.body(17, weight: .semibold))
                        Spacer()
                        Text(CasaFmt.euros(y.cost)).font(Theme.body(17, weight: .semibold))
                    }
                    HStack {
                        Text("\(num(y.consum)) \(servei.unitat)")
                        if let p = y.preu { Text("· \(preuText(p))/\(servei.unitat)") }
                        Spacer()
                        Text(y.mesos >= 12 ? "any sencer" : "\(y.mesos) mesos amb factura")
                    }
                    .font(Theme.body(13, relativeTo: .footnote))
                    .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func num(_ v: Double) -> String {
        v >= 100 ? String(format: "%.0f", v) : String(format: "%.1f", v).replacingOccurrences(of: ".", with: ",")
    }

    private func preuText(_ v: Double) -> String {
        String(format: v < 1 ? "%.3f €" : "%.2f €", v).replacingOccurrences(of: ".", with: ",")
    }
}

/// Una fila "nom ... abans → ara  +12 %": vermell si puja, verd si baixa.
private struct FilaCanvi: View {
    let nom: String
    let color: Color
    let a: Double
    let b: Double
    var detall: String? = nil

    var body: some View {
        let pct = a > 0 ? (b - a) / a * 100 : 0
        let puja = pct >= 0
        HStack(spacing: 8) {
            Circle().fill(color).frame(width: 9, height: 9)
            Text(nom).font(Theme.body(15))
            Spacer()
            if let detall { Text(detall).font(Theme.body(13)).foregroundStyle(.secondary) }
            Text((puja ? "+" : "−") + String(format: "%.0f %%", abs(pct)))
                .font(Theme.body(15, weight: .semibold))
                .foregroundStyle(abs(pct) < 5 ? Color.secondary : (puja ? CasaTheme.late : CasaTheme.green))
                .frame(minWidth: 52, alignment: .trailing)
        }
    }
}

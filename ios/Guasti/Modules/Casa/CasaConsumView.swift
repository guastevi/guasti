import SwiftUI
import Charts

/// Llum, aigua i gas any a any: quant se n'ha gastat, quant ha costat i a quin preu.
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
}

/// Un any d'un subministrament. Les factures que passen d'un any a l'altre es reparteixen pels dies.
struct CasaConsumAny: Identifiable {
    let any: Int
    var consum: Double = 0
    var cost: Double = 0
    /// Dies de l'any que tenen factura (per saber si l'any és sencer).
    var dies: Double = 0
    var factures = 0

    var id: Int { any }
    /// Preu mitjà de cada kWh o m³, amb tot inclòs (impostos, quotes fixes...).
    var preu: Double? { consum > 0 ? cost / consum : nil }
    /// Mitjanes al mes: serveixen per comparar anys que no estan sencers.
    var consumMes: Double? { dies >= 20 ? consum / dies * 30.44 : nil }
    var costMes: Double? { dies >= 20 ? cost / dies * 30.44 : nil }
    var mesos: Int { Int((dies / 30.44).rounded()) }
}

enum CasaConsumCalcul {
    static func anys(_ registres: [CasaRegistre], servei: CasaServei) -> [CasaConsumAny] {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Madrid") ?? .current
        var per: [Int: CasaConsumAny] = [:]
        var vistes = Set<String>()
        for r in registres where r.kind == .factura && r.displayTitle == servei.rawValue {
            guard let consum = r.consumValue else { continue }
            // La propietària de vegades envia el mateix PDF dues vegades
            let clau = "\(r.inici ?? "")|\(r.venciment)|\(consum)|\(r.imp)" + ((r.inici ?? "").isEmpty ? "|\(r.data)" : "")
            guard vistes.insert(clau).inserted else { continue }
            let cost = r.importValue ?? 0

            if let a = (r.inici).flatMap(CasaFmt.date), let b = CasaFmt.date(r.venciment), b > a {
                let total = b.timeIntervalSince(a) / 86400
                var trams: [(Int, Double)] = []
                var d = a
                while d < b {
                    let any = cal.component(.year, from: d)
                    let next = min(cal.date(from: DateComponents(year: any + 1, month: 1, day: 1)) ?? b, b)
                    trams.append((any, next.timeIntervalSince(d) / 86400))
                    d = next
                }
                for (any, dies) in trams {
                    let f = dies / total
                    var y = per[any] ?? CasaConsumAny(any: any)
                    y.consum += consum * f
                    y.cost += cost * f
                    y.dies += dies
                    per[any] = y
                }
                let anyFi = cal.component(.year, from: b)
                per[anyFi, default: CasaConsumAny(any: anyFi)].factures += 1
            } else if let any = Int(r.data.prefix(4)) {
                var y = per[any] ?? CasaConsumAny(any: any)
                y.consum += consum
                y.cost += cost
                y.dies += servei == .aigua ? 61 : 30.44 // sense període: una factura normal
                y.factures += 1
                per[any] = y
            }
        }
        return per.values.map { var y = $0; y.dies = min(y.dies, 366); return y }.sorted { $0.any < $1.any }
    }
}

struct CasaConsumView: View {
    @ObservedObject private var store = CasaStore.shared
    @State private var servei: CasaServei = .llum

    var body: some View {
        let anys = CasaConsumCalcul.anys(store.registres, servei: servei)
        let perLlegir = store.registres(.factura).filter { $0.displayTitle == servei.rawValue && $0.consum == nil }.count
        List {
            Section {
                Picker("Subministrament", selection: $servei) {
                    ForEach(CasaServei.allCases) { s in Text(s.rawValue).tag(s) }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }

            if perLlegir > 0 {
                Section {
                    Label("Encara s'estan llegint \(perLlegir) factures de \(servei.rawValue.lowercased()). Això s'anirà completant sol.",
                          systemImage: "hourglass")
                        .font(Theme.body(14))
                        .foregroundStyle(.secondary)
                }
            }

            if anys.isEmpty {
                Section {
                    Text("Encara no hi ha factures de \(servei.rawValue.lowercased()) amb el consum llegit.")
                        .foregroundStyle(.secondary)
                }
            } else {
                resum(anys)
                grafic("Consum mitjà al mes", unitat: servei.unitat, anys: anys, valor: \.consumMes, format: num)
                grafic("Cost mitjà al mes", unitat: "€", anys: anys, valor: \.costMes, format: CasaFmt.euros)
                preuGrafic(anys)
                taula(anys)
            }
        }
        .navigationTitle("Consum any a any")
        .tint(CasaTheme.green)
        .refreshable { await store.load() }
    }

    // MARK: parts

    @ViewBuilder private func resum(_ anys: [CasaConsumAny]) -> some View {
        // Comparem el primer i l'últim any amb prou mesos per fer-ne una mitjana fiable
        let bons = anys.filter { $0.mesos >= 3 }
        if let a = bons.first, let b = bons.last, a.any != b.any {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Del \(String(a.any)) al \(String(b.any))").font(Theme.display(18))
                    if let ca = a.consumMes, let cb = b.consumMes {
                        canvi("Consum", ca, cb)
                    }
                    if let pa = a.preu, let pb = b.preu {
                        canvi("Preu per \(servei.unitat)", pa, pb)
                    }
                    if let ma = a.costMes, let mb = b.costMes {
                        canvi("Factura mitjana al mes", ma, mb, detall: "\(CasaFmt.euros(ma)) → \(CasaFmt.euros(mb))")
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private func canvi(_ nom: String, _ a: Double, _ b: Double, detall: String? = nil) -> some View {
        let pct = a > 0 ? (b - a) / a * 100 : 0
        let puja = pct >= 0
        return HStack {
            Text(nom).font(Theme.body(15))
            Spacer()
            if let detall { Text(detall).font(Theme.body(13)).foregroundStyle(.secondary) }
            Text((puja ? "+" : "−") + String(format: "%.0f%%", abs(pct)))
                .font(Theme.body(15, weight: .semibold))
                .foregroundStyle(abs(pct) < 5 ? Color.secondary : (puja ? CasaTheme.late : CasaTheme.green))
        }
    }

    private func grafic(_ titol: String, unitat: String, anys: [CasaConsumAny],
                        valor: KeyPath<CasaConsumAny, Double?>, format: @escaping (Double) -> String) -> some View {
        Section {
            Chart(anys.filter { $0[keyPath: valor] != nil }) { y in
                BarMark(x: .value("Any", String(y.any)), y: .value(unitat, y[keyPath: valor] ?? 0))
                    .foregroundStyle(CasaTheme.green.opacity(y.mesos >= 11 ? 1 : 0.45))
                    .annotation(position: .top) {
                        Text(format(y[keyPath: valor] ?? 0)).font(.system(size: 10)).foregroundStyle(.secondary)
                    }
            }
            .chartYAxis(.hidden)
            .frame(height: 170)
            .padding(.vertical, 6)
        } header: {
            Text(titol)
        } footer: {
            if titol.hasPrefix("Consum") {
                Text("Les barres clares són anys dels quals encara no hi ha totes les factures.")
            }
        }
    }

    private func preuGrafic(_ anys: [CasaConsumAny]) -> some View {
        Section {
            Chart(anys.filter { $0.preu != nil }) { y in
                LineMark(x: .value("Any", String(y.any)), y: .value("€", y.preu ?? 0))
                    .foregroundStyle(CasaTheme.late)
                PointMark(x: .value("Any", String(y.any)), y: .value("€", y.preu ?? 0))
                    .foregroundStyle(CasaTheme.late)
                    .annotation(position: .top) {
                        Text(preuText(y.preu ?? 0)).font(.system(size: 10)).foregroundStyle(.secondary)
                    }
            }
            .chartYAxis(.hidden)
            .frame(height: 150)
            .padding(.vertical, 6)
        } header: {
            Text("Preu per \(servei.unitat)")
        } footer: {
            Text(servei == .aigua
                 ? "Tot inclòs: a l'aigua hi ha quotes fixes i taxes (clavegueram, residus), per això cada m³ surt car."
                 : "Tot inclòs: potència o terme fix, lloguer del comptador i impostos, dividit pel que has gastat.")
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

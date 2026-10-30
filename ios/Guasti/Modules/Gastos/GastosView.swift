import SwiftUI
import Charts

struct GastosModule: GuastiModule {
    let id = "gastos"
    let title = "Gastos"
    let subtitle = "Finances"
    let systemImage = "eurosign.circle.fill"
    let tint = Color(white: 0.11)
    let isAvailable = true

    @MainActor func makeRootView() -> AnyView {
        AnyView(GastosView())
    }

    @MainActor func prepareSearch() async {
        await GastosStore.shared.carregaTots()
    }

    @MainActor func search(_ query: SearchQuery) -> [SearchResult] {
        GastosStore.shared.tots.filter {
            query.matches([$0.concepte, $0.categoria, $0.tipus, Fin.nomDia($0.data), Fin.nomMes($0.mes), Fin.eur($0.imp)])
        }.map { m in
            let title = m.concepte.isEmpty ? m.categoria : m.concepte
            return SearchResult(
                id: "gastos-" + m.id,
                title: title,
                subtitle: [m.concepte.isEmpty ? "" : m.categoria, m.tipus, Fin.nomDia(m.data) + " " + String(m.mes.prefix(4))]
                    .filter { !$0.isEmpty }.joined(separator: " · "),
                trailing: (m.tipus == "Ingrés" ? "+" : "−") + Fin.eur(m.imp),
                trailingColor: Fin.color(m.tipus),
                systemImage: systemImage,
                rank: query.rank(title: title),
                destination: { AnyView(GastosView(mes: m.mes, vista: .moviments)) }
            )
        }
    }
}

/// L'app "Finances" de Gastos: Afegir, Resum i Moviments, com a la web.
struct GastosView: View {
    enum Vista: String, CaseIterable {
        case afegir, resum, moviments

        var title: String {
            switch self {
            case .afegir: return "Afegir"
            case .resum: return "Resum"
            case .moviments: return "Moviments"
            }
        }

        var icon: String {
            switch self {
            case .afegir: return "plus.circle"
            case .resum: return "chart.bar"
            case .moviments: return "list.bullet"
            }
        }
    }

    @ObservedObject private var store = GastosStore.shared
    @State private var vista: Vista
    @State private var toast: Toast?
    /// Mes amb què s'obre (des del cercador); nil = el que s'estava mirant.
    private let mesInicial: String?

    init(mes: String? = nil, vista: Vista = .afegir) {
        mesInicial = mes
        _vista = State(initialValue: vista)
    }

    struct Toast: Equatable {
        let text: String
        let error: Bool
        let id = UUID()
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                Group {
                    if let d = store.dades {
                        switch vista {
                        case .afegir: GastosAfegir(dades: d, showToast: show)
                        case .resum: GastosResumView(resum: d.resum, evolucio: d.evolucio)
                        case .moviments: GastosMoviments(moviments: d.moviments, showToast: show)
                        }
                    } else if let error = store.errorMessage {
                        Text("No s'han pogut carregar les dades.\n\(error)")
                            .foregroundStyle(Fin.muted)
                            .multilineTextAlignment(.center)
                            .padding(.vertical, 60)
                    } else {
                        Text("Carregant...")
                            .foregroundStyle(Fin.muted)
                            .padding(.vertical, 60)
                    }
                }
                .frame(maxWidth: 560)
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
            .refreshable { await store.load(store.dades?.mes) }
            nav
        }
        .background(Fin.bg.ignoresSafeArea())
        .foregroundStyle(Fin.text)
        .font(.system(size: 16))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Fin.bg, for: .navigationBar)
        .overlay(alignment: .bottom) { toastView }
        .task { await store.load(mesInicial ?? (store.dades?.mes == store.dades?.mesActual ? nil : store.dades?.mes)) }
        .onChange(of: store.errorMessage) { _, error in
            if let error, store.dades != nil { show(error, error: true) }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text("Finances")
                .font(.system(size: 24, weight: .heavy))
                .tracking(-0.24)
            Spacer()
            if let d = store.dades {
                Menu {
                    Picker("Mes", selection: Binding(get: { d.mes }, set: { m in Task { await store.load(m) } })) {
                        ForEach(d.mesos, id: \.self) { Text(Fin.nomMes($0)).tag($0) }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(Fin.nomMes(d.mes))
                        if store.isLoading {
                            ProgressView().controlSize(.mini)
                        } else {
                            Image(systemName: "chevron.up.chevron.down").font(.system(size: 11, weight: .semibold))
                        }
                    }
                    .font(.system(size: 15))
                    .foregroundStyle(Fin.text)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Fin.card, in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Fin.line))
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 10)
    }

    private var nav: some View {
        HStack {
            ForEach(Vista.allCases, id: \.self) { v in
                Button {
                    vista = v
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: v.icon).font(.system(size: 22))
                        Text(v.title).font(.system(size: 13, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(6)
                    .foregroundStyle(vista == v ? Fin.text : Fin.muted)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 8)
        .background(Fin.card.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) { Rectangle().fill(Fin.line).frame(height: 1) }
    }

    @ViewBuilder
    private var toastView: some View {
        if let toast {
            Text(toast.text)
                .font(.system(size: 15, weight: .semibold))
                .multilineTextAlignment(.center)
                .foregroundStyle(toast.error ? Color.white : Fin.bg)
                .padding(.horizontal, 18)
                .padding(.vertical, 11)
                .background(toast.error ? Fin.sortida : Fin.text, in: RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 20)
                .padding(.bottom, 86)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .id(toast.id)
        }
    }

    private func show(_ text: String, error: Bool = false) {
        let t = Toast(text: text, error: error)
        withAnimation(.easeOut(duration: 0.25)) { toast = t }
        Task {
            try? await Task.sleep(for: .seconds(2.4))
            if toast == t { withAnimation(.easeIn(duration: 0.25)) { toast = nil } }
        }
    }
}

/// Targeta blanca amb vora, com les .card de la web.
struct FinCard<Content: View>: View {
    var title: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let title {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .padding(.bottom, 12)
            }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Fin.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Fin.line))
        .padding(.bottom, 12)
    }
}

/// Etiqueta en majúscules petites (els <label> de la web).
struct FinLabel: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 12, weight: .semibold))
            .tracking(0.6)
            .foregroundStyle(Fin.muted)
            .padding(.top, 18)
            .padding(.bottom, 8)
    }
}

// MARK: - Afegir

struct GastosAfegir: View {
    let dades: GastosDades
    let showToast: (String, Bool) -> Void

    @ObservedObject private var store = GastosStore.shared
    @State private var tipus = "Despesa"
    @State private var imp = ""
    @State private var cat = ""
    @State private var conc = ""
    @State private var data = Date()
    @State private var saving = false
    @State private var dateSet = false
    @FocusState private var focus: Field?

    enum Field { case imp, cat, conc }

    private var cats: [String] { dades.categories[tipus] ?? [] }

    private var nomCat: String {
        let actual = cat.trimmingCharacters(in: .whitespaces).lowercased()
        return cats.prefix(10).first { $0.lowercased() == actual } ?? cat.trimmingCharacters(in: .whitespaces)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            (Text(Fin.nomMes(dades.mes) + ": despeses ") + Text(Fin.eur(dades.resum.despeses)).fontWeight(.semibold).foregroundColor(Fin.text)
             + Text(" · disponible ") + Text(Fin.eur(dades.resum.disponible)).fontWeight(.semibold).foregroundColor(Fin.text))
                .font(.system(size: 14))
                .foregroundStyle(Fin.muted)
                .padding(.horizontal, 2)
                .padding(.bottom, 12)

            FinCard {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) {
                    ForEach(Fin.tipus, id: \.self) { t in
                        Button {
                            tipus = t
                            cat = ""
                            conc = ""
                        } label: {
                            Text(t)
                                .font(.system(size: 14, weight: .semibold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 9)
                                .padding(.horizontal, 4)
                                .foregroundStyle(t == tipus ? Color.white : Fin.muted)
                                .background(t == tipus ? Fin.color(t) : Fin.bg, in: RoundedRectangle(cornerRadius: 10))
                                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(t == tipus ? Color.clear : Fin.line))
                        }
                        .buttonStyle(.plain)
                    }
                }

                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    TextField("0,00", text: $imp)
                        .keyboardType(.decimalPad)
                        .font(.system(size: 44, weight: .heavy))
                        .focused($focus, equals: .imp)
                    Text("€")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundStyle(Fin.muted)
                }
                .padding(.top, 18)
                .padding(.bottom, 6)
                .overlay(alignment: .bottom) { Rectangle().fill(Fin.line).frame(height: 1) }

                FinLabel(text: "Categoria")
                chips(Array(cats.prefix(10)), selected: cat) { c in
                    cat = c
                    conc = ""
                }
                field("Escriu o tria una categoria", text: $cat, focus: .cat)
                if focus == .cat {
                    suggestions
                }

                FinLabel(text: "Concepte (opcional)")
                chips(Array((dades.conceptes[nomCat] ?? []).prefix(8)), selected: conc) { c in conc = c }
                field("Per exemple: Mercadona", text: $conc, focus: .conc)

                FinLabel(text: "Data")
                DatePicker("Data", selection: $data, displayedComponents: .date)
                    .labelsHidden()
                    .environment(\.locale, Locale(identifier: "ca_ES"))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Fin.bg, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Fin.line))

                Button {
                    Task { await save() }
                } label: {
                    Text(saving ? "Desant..." : "Desar")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(16)
                        .background(Fin.color(tipus), in: RoundedRectangle(cornerRadius: 14))
                        .opacity(saving ? 0.5 : 1)
                }
                .buttonStyle(.plain)
                .disabled(saving)
                .padding(.top, 20)
            }
        }
        .onAppear {
            if !dateSet, let avui = Self.dateFormatter.date(from: dades.avui) {
                data = avui
                dateSet = true
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Fet") { focus = nil }
            }
        }
    }

    /// Com el <datalist> de la web: la resta de categories, filtrades pel que s'escriu.
    @ViewBuilder
    private var suggestions: some View {
        let q = cat.trimmingCharacters(in: .whitespaces).lowercased()
        let list = cats.filter { q.isEmpty || $0.lowercased().contains(q) }.filter { $0.lowercased() != q }.prefix(8)
        if !list.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(list), id: \.self) { c in
                    Button {
                        cat = c
                        conc = ""
                        focus = nil
                    } label: {
                        Text(c)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)
                    Divider().overlay(Fin.line)
                }
            }
            .background(Fin.card, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Fin.line))
            .padding(.top, 6)
        }
    }

    private func chips(_ items: [String], selected: String, pick: @escaping (String) -> Void) -> some View {
        FlowLayout(spacing: 8) {
            ForEach(items, id: \.self) { c in
                let on = c.lowercased() == selected.trimmingCharacters(in: .whitespaces).lowercased()
                Button {
                    pick(c)
                } label: {
                    Text(c)
                        .font(.system(size: 15))
                        .padding(.horizontal, 13)
                        .padding(.vertical, 7)
                        .foregroundStyle(on ? Fin.bg : Fin.text)
                        .background(on ? Fin.text : Fin.bg, in: Capsule())
                        .overlay(Capsule().strokeBorder(on ? Fin.text : Fin.line))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.bottom, items.isEmpty ? 0 : 10)
    }

    private func field(_ placeholder: String, text: Binding<String>, focus f: Field) -> some View {
        TextField(placeholder, text: text)
            .focused($focus, equals: f)
            .autocorrectionDisabled()
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Fin.bg, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(focus == f ? Fin.muted : Fin.line))
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "Europe/Madrid")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private func save() async {
        let i = imp.trimmingCharacters(in: .whitespaces)
        let c = cat.trimmingCharacters(in: .whitespaces)
        guard !i.isEmpty, Fin.number(i) > 0 else {
            showToast("Escriu un import", true)
            focus = .imp
            return
        }
        guard !c.isEmpty else {
            showToast("Tria una categoria", true)
            return
        }
        focus = nil
        saving = true
        defer { saving = false }
        do {
            let msg = try await store.afegir(tipus: tipus, imp: i, categoria: c,
                                             concepte: conc.trimmingCharacters(in: .whitespaces),
                                             data: Self.dateFormatter.string(from: data))
            imp = ""
            cat = ""
            conc = ""
            showToast(msg, false)
        } catch {
            showToast(error.localizedDescription, true)
        }
    }
}

// MARK: - Resum

struct GastosResumView: View {
    let resum: GastosResum
    let evolucio: [GastosEvolucio]

    var body: some View {
        VStack(spacing: 0) {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                kpi("Ingressos", Fin.eur(resum.ingressos), color: Fin.entrada)
                kpi("Despeses", Fin.eur(resum.despeses), color: Fin.sortida)
                kpi("Estalvi i inversió", Fin.eur(resum.estalvi + resum.inversio), color: Fin.estalvi,
                    note: "\(Fin.eur0(resum.estalvi)) estalvi · \(Fin.eur0(resum.inversio)) inversió")
                kpi("Disponible", Fin.eur(resum.disponible), color: resum.disponible < 0 ? Fin.sortida : Fin.text)
            }
            .padding(.bottom, 12)

            FinCard(title: "En què gasto més") {
                if resum.categories.isEmpty {
                    empty("Encara no hi ha despeses aquest mes.")
                } else {
                    donut
                    rank(resum.categories, colors: true)
                }
            }

            FinCard(title: "Conceptes amb més despesa") {
                if resum.conceptes.isEmpty {
                    empty("Sense dades.")
                } else {
                    rank(resum.conceptes, colors: false)
                }
            }

            FinCard(title: "Últims 6 mesos") {
                evolucioChart
            }

            FinCard(title: "Ingressos per font") {
                if resum.fonts.isEmpty {
                    empty("Encara no hi ha ingressos aquest mes.")
                } else {
                    VStack(spacing: 11) {
                        ForEach(resum.fonts) { f in
                            VStack(spacing: 5) {
                                HStack {
                                    Text(f.nom).lineLimit(1)
                                    Spacer()
                                    Text(Fin.eur(f.total)).monospacedDigit()
                                }
                                .font(.system(size: 15))
                                bar(fraction: f.pct / 100, color: Fin.entrada)
                            }
                        }
                    }
                }
            }
        }
    }

    private func kpi(_ title: String, _ value: String, color: Color, note: String? = nil) -> some View {
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

    private var donut: some View {
        Chart(Array(resum.categories.enumerated()), id: \.element.nom) { i, c in
            SectorMark(angle: .value("Total", c.total), innerRadius: .ratio(0.66), angularInset: 1)
                .foregroundStyle(Fin.paleta[i % Fin.paleta.count])
        }
        .chartLegend(.hidden)
        .frame(height: 220)
        .overlay {
            VStack(spacing: 0) {
                Text("Total").font(.system(size: 12)).foregroundStyle(Fin.muted)
                Text(Fin.eur0(resum.despeses)).font(.system(size: 20, weight: .bold))
            }
        }
        .padding(.bottom, 12)
    }

    private func rank(_ list: [GastosPart], colors: Bool) -> some View {
        let maxV = Swift.max(list.map(\.total).max() ?? 1, 1)
        return VStack(spacing: 11) {
            ForEach(Array(list.enumerated()), id: \.element.nom) { i, x in
                let col = colors ? Fin.paleta[i % Fin.paleta.count] : Fin.sortida
                VStack(spacing: 5) {
                    HStack(spacing: 8) {
                        if colors {
                            Circle().fill(col).frame(width: 10, height: 10)
                        }
                        Text(x.nom).lineLimit(1)
                        Spacer(minLength: 8)
                        Text(Fin.eur(x.total)).monospacedDigit()
                        Text(Fin.pct(x.pct))
                            .font(.system(size: 13))
                            .foregroundStyle(Fin.muted)
                    }
                    .font(.system(size: 15))
                    bar(fraction: x.total / maxV, color: col)
                }
            }
        }
    }

    private func bar(fraction: Double, color: Color) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Fin.line)
                Capsule().fill(color).frame(width: geo.size.width * min(1, Swift.max(0, fraction)))
            }
        }
        .frame(height: 6)
    }

    private var evolucioChart: some View {
        let series: [(String, Color, KeyPath<GastosEvolucio, Double>)] = [
            ("Ingressos", Fin.entrada, \.ingressos),
            ("Despeses", Fin.sortida, \.despeses),
            ("Estalvi i inversió", Fin.estalvi, \.estalvi),
        ]
        return Chart {
            ForEach(series, id: \.0) { name, _, key in
                ForEach(evolucio) { e in
                    BarMark(x: .value("Mes", Fin.mesCurt(e.mes)), y: .value("Import", e[keyPath: key]))
                        .position(by: .value("Sèrie", name))
                        .foregroundStyle(by: .value("Sèrie", name))
                        .cornerRadius(5)
                }
            }
        }
        .chartForegroundStyleScale(domain: series.map(\.0), range: series.map(\.1))
        .chartLegend(position: .bottom, alignment: .center)
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
        .frame(height: 230)
    }

    private func empty(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 15))
            .foregroundStyle(Fin.muted)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
    }
}

// MARK: - Moviments

struct GastosMoviments: View {
    let moviments: [Moviment]
    let showToast: (String, Bool) -> Void

    @ObservedObject private var store = GastosStore.shared
    @State private var toDelete: Moviment?

    private var days: [(String, [Moviment])] {
        var out: [(String, [Moviment])] = []
        for m in moviments {
            if out.last?.0 == m.data { out[out.count - 1].1.append(m) } else { out.append((m.data, [m])) }
        }
        return out
    }

    var body: some View {
        FinCard {
            if moviments.isEmpty {
                Text("No hi ha moviments aquest mes.")
                    .font(.system(size: 15))
                    .foregroundStyle(Fin.muted)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(days.enumerated()), id: \.element.0) { n, day in
                        Text(Fin.nomDia(day.0).uppercased())
                            .font(.system(size: 12, weight: .semibold))
                            .tracking(0.6)
                            .foregroundStyle(Fin.muted)
                            .padding(.top, n == 0 ? 0 : 14)
                            .padding(.bottom, 2)
                        ForEach(Array(day.1.enumerated()), id: \.element.id) { i, m in
                            item(m)
                            if i < day.1.count - 1 || n < days.count - 1 {
                                Rectangle().fill(Fin.line).frame(height: 1)
                            }
                        }
                    }
                }
            }
        }
        .confirmationDialog("Vols esborrar aquest moviment?", isPresented: Binding(get: { toDelete != nil }, set: { if !$0 { toDelete = nil } }),
                            titleVisibility: .visible, presenting: toDelete) { m in
            Button("Esborrar", role: .destructive) {
                Task {
                    do {
                        try await store.esborrar(m)
                        showToast("Esborrat", false)
                    } catch {
                        showToast(error.localizedDescription, true)
                    }
                }
            }
        }
    }

    private func item(_ m: Moviment) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(m.concepte.isEmpty ? m.categoria : m.concepte)
                    .font(.system(size: 16, weight: .semibold))
                    .lineLimit(1)
                Text(m.concepte.isEmpty ? m.tipus : "\(m.categoria) · \(m.tipus)")
                    .font(.system(size: 13))
                    .foregroundStyle(Fin.muted)
            }
            Spacer(minLength: 8)
            Text((m.tipus == "Ingrés" ? "+" : "−") + Fin.eur(m.imp))
                .font(.system(size: 16, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(Fin.color(m.tipus))
            Button {
                toDelete = m
            } label: {
                Text("×")
                    .font(.system(size: 22))
                    .foregroundStyle(Fin.muted)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Esborrar")
        }
        .padding(.vertical, 10)
    }
}

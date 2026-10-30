import SwiftUI
import UniformTypeIdentifiers

struct HomeView: View {
    @ObservedObject private var connection = Connection.shared
    @State private var showSettings = false
    /// Ordre dels quadres de l'inici, triat per l'usuària (ids separats per comes).
    @AppStorage("homeOrder") private var orderRaw = ""
    @State private var dragging: String?

    /// Les seccions en l'ordre desat; les noves (encara no ordenades) van al final.
    private var ordered: [any GuastiModule] {
        let order = orderRaw.split(separator: ",").map(String.init)
        return ModuleRegistry.all.enumerated().sorted { a, b in
            let ia = order.firstIndex(of: a.element.id) ?? order.count + a.offset
            let ib = order.firstIndex(of: b.element.id) ?? order.count + b.offset
            return ia < ib
        }.map(\.element)
    }

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 3)

    var body: some View {
        NavigationStack {
            // A l'iPad només hi ha Partitures: s'obre directament
            if UIDevice.current.userInterfaceIdiom == .pad {
                PartituresView()
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button { showSettings = true } label: { Image(systemName: "gearshape") }
                                .accessibilityLabel("Configuració")
                        }
                    }
                    .sheet(isPresented: $showSettings) { NavigationStack { SetupView() } }
                    .onAppear { if !connection.isConfigured { showSettings = true } }
            } else {
                modules
            }
        }
    }

    /// Posa la secció arrossegada al lloc de la secció de sota el dit, i desa l'ordre.
    private func move(_ id: String, to target: String) {
        var ids = ordered.map(\.id)
        guard id != target, let from = ids.firstIndex(of: id), let to = ids.firstIndex(of: target) else { return }
        ids.remove(at: from)
        ids.insert(id, at: to)
        withAnimation(.snappy) { orderRaw = ids.joined(separator: ",") }
    }

    private var modules: some View {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(ordered, id: \.id) { module in
                        Group {
                            if module.isAvailable {
                                NavigationLink {
                                    module.makeRootView()
                                } label: {
                                    ModuleTile(module: module)
                                }
                                .buttonStyle(.plain)
                            } else {
                                ModuleTile(module: module)
                                    .opacity(0.45)
                            }
                        }
                        // Mantenint premut un quadre es pot arrossegar a un altre lloc
                        .opacity(dragging == module.id ? 0.5 : 1)
                        .onDrag {
                            dragging = module.id
                            return NSItemProvider(object: module.id as NSString)
                        }
                        .onDrop(of: [.text], delegate: TileDrop(target: module.id, dragging: $dragging, move: move))
                    }
                }
                .padding()
            }
            // Si es deixa anar fora d'un quadre, també s'acaba l'arrossegament
            .onDrop(of: [.text], isTargeted: nil) { _ in
                dragging = nil
                return true
            }
            .navigationTitle("Guasti")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Configuració")
                }
            }
            .sheet(isPresented: $showSettings) {
                NavigationStack { SetupView() }
            }
            .onAppear {
                if !connection.isConfigured { showSettings = true }
            }
    }
}

private struct TileDrop: DropDelegate {
    let target: String
    @Binding var dragging: String?
    let move: (String, String) -> Void

    func dropEntered(info: DropInfo) {
        if let dragging { move(dragging, target) }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }

    func performDrop(info: DropInfo) -> Bool {
        dragging = nil
        return true
    }
}

private struct ModuleTile: View {
    let module: any GuastiModule

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let logo = module.logo {
                Image(logo)
                    .resizable()
                    .scaledToFit()
                    .frame(height: 24)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 3)
                    .background(.white, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .accessibilityHidden(true)
            } else {
                Image(systemName: module.systemImage)
                    .font(.system(size: 20, weight: .semibold))
            }
            Spacer(minLength: 0)
            Text(module.title)
                .font(Theme.display(15))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .foregroundStyle(module.tileText)
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)
        .background(
            LinearGradient(colors: [module.tint, module.tint.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.primary.opacity(module.tileText == .white ? 0 : 0.15)))
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

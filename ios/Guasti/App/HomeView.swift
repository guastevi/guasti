import SwiftUI

struct HomeView: View {
    @ObservedObject private var connection = Connection.shared
    @State private var showSettings = false

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

    private var modules: some View {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(ModuleRegistry.all, id: \.id) { module in
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
                }
                .padding()
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

import SwiftUI

struct HomeView: View {
    @ObservedObject private var connection = Connection.shared
    @State private var showSettings = false

    private let columns = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 14) {
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
}

private struct ModuleTile: View {
    let module: any GuastiModule

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: module.systemImage)
                .font(.system(size: 30, weight: .semibold))
            Spacer(minLength: 0)
            Text(module.title)
                .font(.title3.weight(.semibold))
            Text(module.subtitle)
                .font(.footnote)
                .opacity(0.85)
        }
        .foregroundStyle(.white)
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 140, alignment: .leading)
        .background(
            LinearGradient(colors: [module.tint, module.tint.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 22, style: .continuous)
        )
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

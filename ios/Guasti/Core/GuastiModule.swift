import SwiftUI

/// Una secció de l'app (Armari, Gastos, Partitures...).
/// Per afegir-ne una de nova: crea una carpeta a Modules/, fes un tipus que compleixi
/// aquest protocol i afegeix-lo a `ModuleRegistry.all`. La resta de l'app no canvia.
protocol GuastiModule {
    var id: String { get }
    var title: String { get }
    var subtitle: String { get }
    var systemImage: String { get }
    var tint: Color { get }
    var isAvailable: Bool { get }
    @MainActor func makeRootView() -> AnyView
}

enum ModuleRegistry {
    static let all: [any GuastiModule] = [
        ArmariModule(),
        ComingSoonModule(id: "gastos", title: "Gastos", systemImage: "eurosign.circle.fill", tint: .green),
        ComingSoonModule(id: "partitures", title: "Partitures", systemImage: "music.note.list", tint: .indigo),
    ]
}

/// Lloc reservat per a seccions que encara no s'han fet.
struct ComingSoonModule: GuastiModule {
    let id: String
    let title: String
    let subtitle = "Aviat"
    let systemImage: String
    let tint: Color
    let isAvailable = false

    @MainActor func makeRootView() -> AnyView {
        AnyView(ContentUnavailableView(title, systemImage: systemImage, description: Text("Aquesta secció arribarà aviat.")))
    }
}

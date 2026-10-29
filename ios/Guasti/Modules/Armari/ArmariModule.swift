import SwiftUI

struct ArmariModule: GuastiModule {
    let id = "armari"
    let title = "Armari"
    let subtitle = "La teva roba"
    let systemImage = "tshirt.fill"
    let tint = Theme.accent
    let isAvailable = true

    @MainActor func makeRootView() -> AnyView {
        AnyView(ArmariHomeView())
    }
}

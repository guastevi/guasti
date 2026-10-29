import SwiftUI

@main
struct GuastiApp: App {
    init() {
        Theme.configureAppearance()
    }

    var body: some Scene {
        WindowGroup {
            HomeView()
                .font(Theme.body())
                .tint(Theme.tint)
        }
    }
}

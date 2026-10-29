import SwiftUI

/// Mostra de color com la de l'app web.
struct ColorSwatch: View {
    let name: String
    var size: CGFloat = 26

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
            .fill(fill)
            .frame(width: size, height: size)
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
                    .strokeBorder(Color.gray.opacity(0.35), lineWidth: 1)
            )
            .accessibilityLabel(name)
    }

    private var fill: AnyShapeStyle {
        guard let hex = ArmariCatalog.colors.first(where: { $0.name == name })?.hex else {
            return AnyShapeStyle(Color(.secondarySystemFill))
        }
        if hex == "multi" {
            return AnyShapeStyle(AngularGradient(colors: [.red, .yellow, .green, .blue, .purple, .pink, .red], center: .center))
        }
        return AnyShapeStyle(Color(hex: hex))
    }
}

extension Color {
    init(hex: String) {
        let v = UInt64(hex, radix: 16) ?? 0
        self.init(red: Double((v >> 16) & 0xff) / 255, green: Double((v >> 8) & 0xff) / 255, blue: Double(v & 0xff) / 255)
    }
}

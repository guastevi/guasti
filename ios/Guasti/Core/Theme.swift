import SwiftUI
import UIKit

/// Els colors i la lletra de les apps web: granat, Bricolage Grotesque per als títols i Figtree per al text.
enum Theme {
    /// Granat dels botons i fons destacats (#6e1423, i #8a1a2b en mode fosc).
    static let accent = Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: 0x8A1A2B) : UIColor(hex: 0x6E1423) })
    /// Granat per a textos i vores (més clar en mode fosc perquè es llegeixi).
    static let tint = Color("AccentColor")
    /// Blau de les apps de Gastos i Partitures.
    static let blue = Color(UIColor(hex: 0x2AABEE))

    static func display(_ size: CGFloat) -> Font {
        .custom(size >= 30 ? "BricolageGrotesque-Bold" : "BricolageGrotesqueSmall-Bold", size: size)
    }

    static func body(_ size: CGFloat = 17, weight: Font.Weight = .regular, relativeTo style: Font.TextStyle = .body) -> Font {
        let name: String
        switch weight {
        case .semibold, .bold, .heavy, .black: name = "Figtree-SemiBold"
        case .medium: name = "Figtree-Medium"
        default: name = "Figtree-Regular"
        }
        return .custom(name, size: size, relativeTo: style)
    }

    /// Lletra de les barres de navegació (els títols de pantalla), com els h2 de la web.
    static func configureAppearance() {
        let title = UIFont(name: "BricolageGrotesqueSmall-Bold", size: 20) ?? .boldSystemFont(ofSize: 20)
        let large = UIFont(name: "BricolageGrotesque-Bold", size: 34) ?? .boldSystemFont(ofSize: 34)
        let tint = UIColor(named: "AccentColor") ?? .label
        let appearance = UINavigationBar.appearance()
        appearance.titleTextAttributes = [.font: title, .foregroundColor: tint]
        appearance.largeTitleTextAttributes = [.font: large, .foregroundColor: tint]
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255,
                  blue: CGFloat(hex & 0xff) / 255, alpha: 1)
    }
}

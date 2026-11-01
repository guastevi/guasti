import SwiftUI
import UIKit

/// El full de compartir de l'iPhone (WhatsApp, Correu, AirDrop, Desa a Fitxers, Desa la imatge...).
enum ShareSheet {
    /// Desa les dades en un fitxer temporal amb aquest nom, per poder-lo compartir amb el nom bo.
    static func tempFile(_ data: Data, name: String) -> URL? {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("comparteix-\(UUID().uuidString)", isDirectory: true)
        let clean = name.replacingOccurrences(of: "/", with: "-").trimmingCharacters(in: .whitespacesAndNewlines)
        let url = dir.appendingPathComponent(clean.isEmpty ? "fitxer" : clean)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try data.write(to: url)
            return url
        } catch {
            return nil
        }
    }

    /// Una foto com a fitxer JPG (es pot desar a Fotos o a Fitxers).
    static func imageFile(_ image: UIImage, name: String) -> URL? {
        guard let data = image.jpegData(compressionQuality: 0.92) else { return nil }
        let base = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return tempFile(data, name: (base.isEmpty ? "Foto" : base) + ".jpg")
    }

    /// Obre el full de compartir per sobre de tot (també dins de pantalles completes).
    @MainActor
    static func present(_ items: [Any]) {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        guard let root = scene?.windows.first(where: \.isKeyWindow)?.rootViewController ?? scene?.windows.first?.rootViewController
        else { return }
        var top = root
        while let next = top.presentedViewController, !next.isBeingDismissed { top = next }
        let vc = UIActivityViewController(activityItems: items, applicationActivities: nil)
        if let pop = vc.popoverPresentationController {
            pop.sourceView = top.view
            pop.sourceRect = CGRect(x: top.view.bounds.midX, y: top.view.bounds.minY + 60, width: 1, height: 1)
            pop.permittedArrowDirections = .up
        }
        top.present(vc, animated: true)
    }
}

/// Botó rodó de compartir per a les pantalles negres (fotos i partitures a pantalla sencera).
struct ShareCircleButton: View {
    var busy = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                if busy {
                    ProgressView().tint(.white)
                } else {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.white)
                        .offset(y: -1)
                }
            }
            .frame(width: 44, height: 44)
            .background(Color.black.opacity(0.6), in: Circle())
        }
        .disabled(busy)
        .accessibilityLabel("Comparteix o desa")
    }
}

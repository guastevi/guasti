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

    @MainActor func prepareSearch() async {
        await ArmariStore.shared.refreshIfNeeded()
    }

    /// Les peces privades no surten al cercador: només es veuen a l'Armari amb Face ID.
    @MainActor func search(_ query: SearchQuery) -> [SearchResult] {
        let store = ArmariStore.shared
        return store.peces.filter { !$0.isPrivate && query.matches([$0.searchText]) }.map { p in
            let cover = p.portada.isEmpty ? (store.photos(for: p).first?.path ?? "") : p.portada
            return SearchResult(
                id: "armari-" + p.id,
                title: p.nom,
                subtitle: [p.talla.isEmpty ? "" : "Talla \(p.talla)", p.marca, p.ubicacio, p.color]
                    .filter { !$0.isEmpty }.joined(separator: " · "),
                systemImage: systemImage,
                thumbnail: cover.isEmpty ? nil : AnyView(DrivePhoto(path: cover)),
                rank: query.rank(title: p.nom),
                destination: { AnyView(PecaDetailView(pecaID: p.id)) }
            )
        }
    }
}

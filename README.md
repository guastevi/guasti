# Guasti

App nativa d'iOS (SwiftUI) amb totes les teves seccions a dins: **Armari** (ja feta), **Gastos** i **Partitures** (aviat).

Les dades no es mouen: l'app llegeix i escriu als mateixos fulls de Google i a la mateixa carpeta de fotos que l'app web. Així pots fer servir les dues alhora.

```
iPhone (Guasti)  ⇄  Guasti API (Apps Script, al teu compte)  ⇄  Fulls "Armari Guasteví" + fotos de Drive
```

## Què fa la secció Armari

- Graella amb la foto de portada de cada peça, cerca i filtres (tipus, temporada, ubicació, color).
- Fitxa de cada peça amb totes les fotos (llisca), zoom a pantalla completa.
- Afegir i editar peces, amb suggeriments dels valors que ja fas servir.
- Afegir fotos des de la càmera o la galeria; triar portada; eliminar fotos.
- Peces **privades** amagades fins que passes Face ID.
- Funciona sense cobertura amb el que ja s'ha carregat (botó de filtres → "Baixa les fotos per veure-les sense connexió").

## Posada en marxa

### 1. Pont amb Google (5 minuts, un sol cop)

1. Obre [script.new](https://script.new) amb el teu compte i posa-li de nom **Guasti API**.
2. Enganxa-hi tot el contingut de [`apps-script/Api.gs`](apps-script/Api.gs).
3. Engranatge (Configuració del projecte) → **Propietats de l'script** → afegeix `API_KEY` amb una clau llarga inventada.
4. Opcional: tria la funció `provaArmari` i prem ▶︎ Executa. Al registre ha de dir quantes peces i fotos hi ha.
5. **Implementa → Implementació nova → Aplicació web**. Executa com: **Jo**. Qui hi té accés: **Qualsevol usuari**.
6. Autoritza els permisos i copia l'URL que acaba en `/exec`.

### 2. Compilar l'app

La compilació la fa GitHub sola (gratis) cada cop que hi ha canvis, i deixa el fitxer `Guasti.ipa` a *Releases*. No cal Xcode.

### 3. Instal·lar-la amb SideStore

- **Un sol cop, amb el Mac:** instal·lar SideStore a l'iPhone i generar el fitxer d'aparellament.
- A SideStore, afegeix la font `https://github.com/<usuari>/guasti/releases/download/sidestore/sidestore.json` i instal·la **Guasti**. Les versions noves t'apareixeran com a actualització.
- Obre Guasti, toca l'engranatge i enganxa l'URL i la clau del pas 1.

### Renovació cada 7 dies

Amb un Apple ID gratuït, les apps caduquen als 7 dies i només n'hi pot haver 3 d'actives (SideStore compta com una, així que Guasti en fa servir una altra i en queda una de lliure). SideStore les renova des del mateix iPhone; amb una automatització de Dreceres diària no has de fer res. Només caldrà intervenir si l'iPhone passa més de 7 dies sense poder renovar (apagat, sense internet) o si una actualització d'iOS obliga a refer l'aparellament.

## Afegir una secció nova

1. Crea `ios/Guasti/Modules/<Nom>/` amb un tipus que compleixi `GuastiModule`.
2. Afegeix-lo a `ModuleRegistry.all` (`ios/Guasti/Core/GuastiModule.swift`), substituint el `ComingSoonModule`.
3. Afegeix les accions que necessiti a `Api.gs` (p. ex. `gastos.list`) i torna a implementar l'script (Gestiona les implementacions → editar → versió nova, així l'URL no canvia).

# Instal·lar Guasti a l'iPhone (un sol cop)

Necessites: el Mac, l'iPhone amb codi, un cable USB i Wi‑Fi (no dades mòbils). Uns 15 minuts.

## 1. Al iPhone: la VPN local
1. Instal·la **LocalDevVPN** de l'App Store (és gratuïta).
2. Obre-la i toca **Connect**. Si demana "Permetre configuracions VPN", toca Permetre i posa el codi.

Aquesta VPN només funciona dins el mòbil (no envia res enlloc). SideStore la necessita encesa per renovar.

## 2. Al Mac: instal·lar SideStore
1. Descarrega **iloader**: https://github.com/nab138/iloader/releases/latest/download/iloader-darwin-universal.dmg i arrossega'l a Aplicacions.
2. Connecta l'iPhone amb el cable. Si l'iPhone pregunta "Confiar en aquest ordinador?", toca Confiar.
3. Obre iloader, entra amb el teu **Apple ID** (vigila majúscules), tria el teu iPhone i toca **Install SideStore (Stable)**.

## 3. Al iPhone: activar SideStore
1. Configuració → General → **VPN i gestió de dispositius** → toca el teu Apple ID → **Confiar** (o "Permetre i reiniciar").
2. Configuració → Privacitat i seguretat → a baix de tot, **Mode desenvolupador** → activa'l. L'iPhone es reinicia.
3. Obre LocalDevVPN → **Connect**.
4. Obre **SideStore**, entra amb el mateix Apple ID.
5. Ves a **My Apps** i toca el botó **7 DAYS** al costat de SideStore. Si pregunta per un certificat, digues **Sí / Refresh Now**. SideStore es tancarà i tornarà a obrir-se sol.

## 4. Instal·lar Guasti
1. A SideStore → **Sources** → **+** → enganxa:
   `https://github.com/guastevi/guasti/releases/download/sidestore/sidestore.json`
2. Obre la font "Guasti" → **Guasti** → **Free / Install**.
3. Obre Guasti. Et sortirà la pantalla de **Configuració**:
   - URL: `https://script.google.com/macros/s/AKfycbzhMjCC_xh_xI66YNAYV585bDyneZiEMZIx290kRd5tYxrCiCGKZCZA3JMAhZppE86nZQ/exec`
   - Clau: la API_KEY que vas posar a les propietats del script.
   - Toca **Prova i desa**. Després entra a Armari: la primera vegada tarda una mica a baixar-ho tot.

## 5. Que es renovi sol (cada 7 dies)
- A SideStore → Settings: activa **Background Refresh**. Deixa LocalDevVPN connectada.
- Recomanat: app **Dreceres** → Automatització → **+** → "Hora del dia" (p. ex. 3:00 de la nit, cada dia) → "Executar immediatament" →
  - si LocalDevVPN surt a les accions, afegeix primer la seva acció de connectar;
  - afegeix l'acció de SideStore **Refresh All Apps**.

Així es renova sola cada nit, mentre el mòbil tingui Wi‑Fi o dades i la VPN estigui connectada.

### Quan sí hauràs de fer alguna cosa (poques vegades)
- Si passes més de 7 dies sense que es pugui renovar (mòbil apagat, sense internet): les apps no s'obriran. Obre LocalDevVPN, després SideStore → My Apps → toca el comptador. **Les dades no es perden**: són a Google.
- Després d'actualitzar iOS, de vegades cal tornar a fer el "pairing file" amb iloader i el Mac (2 minuts).

## Actualitzacions de Guasti
Quan jo afegeixi coses (Gastos, Partitures…), a SideStore sortirà **Update** a Guasti. Només s'ha de tocar.

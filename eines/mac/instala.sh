#!/bin/bash
# Instal·lador de les còpies automàtiques de Guasti al Mac. S'executa un sol cop:
#   curl -fsSL https://raw.githubusercontent.com/guastevi/guasti/main/eines/mac/instala.sh | bash
# 1) Publica la Guasti API nova (còpies de cada nit) amb clasp, mantenint els mateixos enllaços.
# 2) Instal·la l'actualització de cada dilluns de la carpeta «Guasti - tot el codi i dades».
# 3) Baixa ja la primera còpia de les dades a la carpeta (que va a iCloud).
set -uo pipefail
RAW="https://raw.githubusercontent.com/guastevi/guasti/main"
ESTAT="$HOME/Library/Application Support/Guasti"
SCRIPT_ID="10BJTCjO-e-wSRQZMvotKANB_B8u2zsgaqCXJIjRLgu5UwgI1XvFk2g4C"
API_URL="https://script.google.com/macros/s/AKfycbwIA7qJp4WlfGefX87oKfubbDG4EWq4sRTbUrhXUfG39nPck4aY82rZdL45BI71YvV1QQ/exec"
export PATH="/opt/homebrew/bin:/usr/local/bin:$HOME/.npm-global/bin:$HOME/.local/bin:$PATH"
for d in "$HOME"/.nvm/versions/node/*/bin; do [ -d "$d" ] && PATH="$d:$PATH"; done
mkdir -p "$ESTAT" "$HOME/Library/LaunchAgents"
OK_API=0

echo "1/3 · Publicant la Guasti API…"
CLASP=""
if command -v clasp >/dev/null 2>&1; then CLASP="clasp"; elif command -v npx >/dev/null 2>&1; then CLASP="npx -y @google/clasp"; fi
if [ -z "$CLASP" ]; then
  echo "   No he trobat clasp ni node en aquest Mac: aquesta part la faré d'una altra manera."
else
  TOKEN=$(cat "$ESTAT/token" 2>/dev/null || (LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 40))
  T=$(mktemp -d)
  ( cd "$T" && printf '{"scriptId":"%s","rootDir":"."}' "$SCRIPT_ID" > .clasp.json \
    && $CLASP pull >/dev/null \
    && ls | grep -q '^C.*digo\.js$' \
    && F=$(ls | grep '^C.*digo\.js$' | head -1) \
    && curl -fsSL "$RAW/apps-script/Api.gs" -o "$F" \
    && sed -i '' "s/^const COPIES_TOKEN_MAC = '';/const COPIES_TOKEN_MAC = '$TOKEN';/" "$F" \
    && grep -q "COPIES_TOKEN_MAC = '$TOKEN'" "$F" \
    && $CLASP push -f >/dev/null \
    && IDS=$($CLASP deployments | grep -oE 'AKfycb[A-Za-z0-9_-]+ @[0-9]+' | awk '{print $1}') \
    && [ -n "$IDS" ] \
    && for id in $IDS; do $CLASP deploy -i "$id" -d "copies de seguretat" >/dev/null || exit 1; done ) \
    && { echo "$TOKEN" > "$ESTAT/token"; printf 'URL=%s\nTOKEN=%s\n' "$API_URL" "$TOKEN" > "$ESTAT/api.conf"; chmod 600 "$ESTAT/api.conf" "$ESTAT/token"; OK_API=1; echo "   Fet."; } \
    || echo "   No s'ha pogut publicar (clasp ha fallat)."
  rm -rf "$T"
fi

echo "2/3 · Instal·lant l'actualització de cada dilluns…"
curl -fsSL "$RAW/eines/mac/actualitza-carpeta.sh" -o "$ESTAT/actualitza-carpeta.sh" && chmod +x "$ESTAT/actualitza-carpeta.sh"
curl -fsSL "$RAW/eines/mac/cat.guasti.carpeta.plist" -o "$HOME/Library/LaunchAgents/cat.guasti.carpeta.plist"
launchctl bootout "gui/$(id -u)/cat.guasti.carpeta" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$HOME/Library/LaunchAgents/cat.guasti.carpeta.plist" && echo "   Fet."

echo "3/3 · Posant la carpeta al dia ara…"
bash "$ESTAT/actualitza-carpeta.sh" --forca
tail -5 "$ESTAT/registre.log" | sed 's/^/   /'
echo
if [ "$OK_API" = 1 ]; then echo "Tot fet ✅  Ja pots tancar el Terminal."; else echo "Fet en part. Digues a Claude «fet» i acabarà la resta."; fi

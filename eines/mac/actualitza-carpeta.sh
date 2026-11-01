#!/bin/bash
# Manté al dia la carpeta "Guasti - tot el codi i dades" del Mac.
# L'executa el Mac sol cada dia (cat.guasti.carpeta.plist). Si hi ha canvis nous a GitHub,
# substitueix el codi per la versió nova, refà el .zip (esborra l'antic) i, si el Google Drive
# del Mac està instal·lat, hi posa la còpia de seguretat de les dades més recent.
# Ús manual: bash actualitza-carpeta.sh [--forca]
set -euo pipefail

DEST="${GUASTI_CARPETA:-$HOME/Documents/Guasti - tot el codi i dades}"
ESTAT="$HOME/Library/Application Support/Guasti"
REPO="https://github.com/guastevi/guasti"
mkdir -p "$ESTAT"
LOG="$ESTAT/registre.log"
exec >>"$LOG" 2>&1
echo "== $(date '+%Y-%m-%d %H:%M') =="

SHA=$(curl -fsS -H 'Accept: application/vnd.github.sha' https://api.github.com/repos/guastevi/guasti/commits/main) || { echo "Sense connexió amb GitHub"; exit 0; }
ANTIC=$(cat "$ESTAT/darrer-commit" 2>/dev/null || true)

CANVIS=0
if [ "$SHA" != "$ANTIC" ] || [ "${1:-}" = "--forca" ]; then
  TMP=$(mktemp -d)
  trap 'rm -rf "$TMP"' EXIT
  if command -v git >/dev/null 2>&1 && git --version >/dev/null 2>&1; then
    git clone -q "$REPO.git" "$TMP/guasti"
  else
    mkdir -p "$TMP/guasti"
    curl -fsSL "$REPO/archive/refs/heads/main.tar.gz" | tar -xz -C "$TMP/guasti" --strip-components 1
  fi
  CODI="$DEST/1 Codi de l'app Guasti (GitHub)"
  mkdir -p "$CODI"
  rm -rf "$CODI/guasti"
  mv "$TMP/guasti" "$CODI/guasti"
  echo "$SHA" > "$ESTAT/darrer-commit"
  CANVIS=1
  echo "Codi actualitzat a ${SHA:0:7}"
fi

# Còpia de les dades: la fa la Guasti API cada nit al Drive. Si el Drive està al Mac, la copiem.
DRIVE=$(ls -d "$HOME"/Library/CloudStorage/GoogleDrive-*/*/"Guasti - còpies de seguretat" 2>/dev/null | head -1 || true)
if [ -n "$DRIVE" ]; then
  DARRERA=$(ls -1 "$DRIVE" | grep -E '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' | sort | tail -1 || true)
  if [ -n "$DARRERA" ] && [ "$DARRERA" != "$(cat "$ESTAT/darreres-dades" 2>/dev/null || true)" ]; then
    rm -rf "$DEST"/"3 Dades"*
    mkdir -p "$DEST/3 Dades (copia del $DARRERA)"
    cp -R "$DRIVE/$DARRERA/." "$DEST/3 Dades (copia del $DARRERA)/"
    echo "$DARRERA" > "$ESTAT/darreres-dades"
    CANVIS=1
    echo "Dades del $DARRERA copiades"
  fi
fi

if [ "$CANVIS" = 1 ] || [ ! -f "$DEST.zip" ]; then
  printf 'Última actualització: %s\nVersió del codi: %s (%s/commit/%s)\n' \
    "$(date '+%d/%m/%Y %H:%M')" "${SHA:0:7}" "$REPO" "$SHA" > "$DEST/ACTUALITZAT.txt"
  rm -f "$DEST.zip.nou"
  ditto -c -k --keepParent "$DEST" "$DEST.zip.nou"
  mv -f "$DEST.zip.nou" "$DEST.zip"
  echo "Zip refet"
else
  echo "Sense canvis"
fi

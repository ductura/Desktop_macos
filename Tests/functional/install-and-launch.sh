#!/usr/bin/env bash
# Funkcionalna provjera: korisnik preuzima odgovarajući paket i pokreće Ducturu iz mape Aplikacije.
# Radi samo na macOS-u (CI: macos-latest) nakon scripts/build-dmg.sh.
set -euo pipefail
cd "$(dirname "$0")/../.."
DMG="${1:-dist/Ductura-macOS.dmg}"
APPS="${APPS_DIR:-/Applications}"

# 1. "Preuzimanje" u mapu Preuzimanja; paket dobiva oznaku karantene kao iz preglednika.
DL="$(mktemp -d)/Ductura-macOS.dmg"
cp "$DMG" "$DL"
xattr -w com.apple.quarantine "0081;$(printf %x "$(date +%s)");Safari;" "$DL" || true

# 2. Otvaranje paketa i povlačenje u Aplikacije.
MNT="$(mktemp -d)"
hdiutil attach "$DL" -nobrowse -readonly -mountpoint "$MNT" >/dev/null
trap 'hdiutil detach "$MNT" -quiet || true' EXIT
test -L "$MNT/Applications" || { echo "U paketu nema prečaca na Aplikacije"; exit 1; }
rm -rf "$APPS/Ductura.app"
cp -R "$MNT/Ductura.app" "$APPS/"
xattr -dr com.apple.quarantine "$APPS/Ductura.app" || true  # nepotpisan build; korisnik bi potvrdio u dijalogu

# 3. Pokretanje iz mape Aplikacije preko Launch Servicesa (kao dvoklik).
OUT="$(mktemp -d)/smoke.txt"
open -W -n -a "$APPS/Ductura.app" --args --smoke-out "$OUT"
grep -q '^Ductura OK' "$OUT" || { echo "Ductura se nije ispravno pokrenula"; exit 1; }
echo "OK: $(cat "$OUT")"

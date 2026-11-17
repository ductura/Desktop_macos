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

# 4. Prozor (DAN-957): WKWebView s adresom iz Info.plist, a s neispravnom adresom samo poruka.
# Redak piše aplikacija iz stvarnog sadržaja prozora; drugi redak je putanja pokrenutog paketa.
window_report() { # <aplikacija> <očekivani redak>
  local app="$1" want="$2" out
  out="$(mktemp -d)/window.txt"
  rm -f "$out"
  if ! perl -e 'alarm 60; exec @ARGV' open -W -n -a "$app" --args --smoke-window "$out"; then
    pkill -f "$app/Contents/MacOS/Ductura" || true
    echo "Ductura se nije ugasila ($app)"; exit 1
  fi
  test -f "$out" || { echo "Nema izvještaja prozora ($app)"; exit 1; }
  [ "$(sed -n 1p "$out")" = "$want" ] || { echo "Prozor ($app): $(cat "$out"), očekivano: $want"; exit 1; }
  [ "$(sed -n 2p "$out")" = "$app" ] || { echo "Pokrenut je drugi paket: $(sed -n 2p "$out")"; exit 1; }
}
for bad in "http://ductura.org/app/" "https://evil.org/app/"; do
  COPY="$(cd "$(mktemp -d)" && pwd -P)/Ductura.app"  # /var -> /private/var, as bundlePath sees it
  cp -R "$APPS/Ductura.app" "$COPY"
  /usr/libexec/PlistBuddy -c "Set :DucturaWebURL $bad" "$COPY/Contents/Info.plist"
  codesign --force --sign - "$COPY" && codesign --verify --strict "$COPY"
  window_report "$COPY" "Ductura window message"
done
URL="$(/usr/libexec/PlistBuddy -c 'Print :DucturaWebURL' "$APPS/Ductura.app/Contents/Info.plist")"
window_report "$APPS/Ductura.app" "Ductura window web $URL"
echo "OK: prozor s WKWebView ($URL), neispravna adresa ostaje poruka"

# Nalazi spikea (README): veličina i prava paketa.
du -sk "$APPS/Ductura.app" "$DMG"
codesign -d --entitlements - "$APPS/Ductura.app" 2>&1 || true

# Ductura / desktop-macos

macOS aplikacija i instalacijski paket. Swift (AppKit za početak, editor kasnije preko WKWebView), paket kao `.dmg` s univerzalnim binarnim (Apple Silicon + Intel).

## Funkcionalna provjera

Korisnik preuzima odgovarajući paket i pokreće Ducturu iz mape Aplikacije.
Pokriva je `Tests/functional/install-and-launch.sh`: kopija paketa s oznakom karantene, otvaranje `.dmg`, kopiranje u `/Applications` i pokretanje preko `open` (`--smoke-out`). Radi samo na macOS-u i pokreće se u CI-ju.

## Struktura

| Mapa | Sadržaj |
|---|---|
| `Sources/DucturaCore` | Pomoćne funkcije (argumenti, nazivi paketa, verzije) |
| `Sources/Ductura` | macOS aplikacija |
| `Tests/DucturaCoreTests` | Testovi pomoćnih funkcija (XCTest) |
| `Tests/functional` | Funkcionalni test instalacije |
| `scripts/build-dmg.sh` | Izrada `Ductura.app` i `dist/Ductura-macOS.dmg` |
| `scripts/ci-ok.test.mjs` | Test obvezne zbirne provjere `ci-ok` u `.github/workflows/ci.yml` (`node --test`, u CI-ju na Linuxu) |

## Pokretanje (na Macu)

```bash
swift test
./scripts/build-dmg.sh
./Tests/functional/install-and-launch.sh
```

Build je potpisan samo ad-hoc. Prije javnog izdanja trebaju Apple Developer ID (99 USD godišnje) i notarizacija, inače macOS Gatekeeper blokira prvo pokretanje.

# Ductura / desktop-macos

macOS aplikacija i instalacijski paket. Swift (AppKit prozor s WKWebView od spikea D-0.1, DAN-957; tehnologija ljuske ovisi o odluci 8, otvoreno), paket kao `.dmg` s univerzalnim binarnim (Apple Silicon + Intel).

Plan repozitorija: [docs/PLAN.md](docs/PLAN.md).

## Funkcionalna provjera

Korisnik preuzima odgovarajući paket i pokreće Ducturu iz mape Aplikacije.
Pokriva je `Tests/functional/install-and-launch.sh`: kopija paketa s oznakom karantene, otvaranje `.dmg`, kopiranje u `/Applications` i pokretanje preko `open` (`--smoke-out`). Radi samo na macOS-u i pokreće se u CI-ju.

## Struktura

| Mapa | Sadržaj |
|---|---|
| `Sources/DucturaCore` | Pomoćne funkcije (argumenti, nazivi paketa, verzije) |
| `Sources/DucturaCore/WorkId.swift` | ID rada iz poveznice `ductura://doc/<id>` po pravilu ugovora S-1H.1-c (isto kao serverski `work-id.ts`) i URL s kodiranim ID-om |
| `Sources/DucturaCore/WebAddress.swift` | Provjera adrese weba iz `Info.plist` (DAN-883) |
| `Sources/DucturaCore/Startup.swift` | Ishod `--smoke`, adresa za WKWebView ili poruka (`windowContent`) i redak `--smoke-window` |
| `Sources/Ductura` | macOS aplikacija |
| `Tests/DucturaCoreTests` | Testovi pomoćnih funkcija (XCTest) |
| `Tests/functional` | Funkcionalni test instalacije |
| `scripts/build-dmg.sh` | Izrada `Ductura.app` i `dist/Ductura-macOS.dmg` |
| `scripts/ci-ok.test.mjs` | Test obvezne zbirne provjere `ci-ok` u `.github/workflows/ci.yml` (`npm ci` pa `node --test`, u CI-ju na Linuxu). `package.json` i `package-lock.json` služe samo tom testu (YAML parser `yaml`); aplikacija ne koristi Node. |

## Adresa weba

Adresa web aplikacije nije upisana u kod. Čita se iz konfiguracije paketa, ključeva u `packaging/Info.plist`, koje `scripts/build-dmg.sh` kopira u `Ductura.app`.

| Ključ | Zadano | Značenje |
|---|---|---|
| `DucturaWebURL` | `https://ductura.org/app/` | Adresa s putem; rad se otvara na `<adresa>#/doc/<ID>` |
| `DucturaWebHosts` | `ductura.org` | Dopušteni hostovi, odvojeni s `;` |

`WebAddress` prihvaća samo `https` adresu s hosta s popisa, bez porta, korisnika, upita, fragmenta i `%` kodiranja, s putem koji završava s `/`. Ako adresa ne prolazi, prozor umjesto WKWebView pokazuje poruku, a `--smoke` vraća 1 i ne piše potvrdu. Zato i goli `swift run Ductura --smoke` (bez `Info.plist`) vraća 1.

Konačnu domenu (V-0) upiši u ta dva ključa.

## WKWebView (spike D-0.1, DAN-957)

Prozor sadrži WKWebView koji učitava provjerenu adresu (s ID-om rada `#/doc/<ID>` ako je zadan). Bez provjerene adrese WKWebView se ne stvara, nego prozor pokazuje poruku. Gumb za otvaranje u sustavnom pregledniku je uklonjen. Spike ne odlučuje o tehnologiji ljuske (odluka 8).

Funkcionalni test pokreće aplikaciju s `--smoke-window <datoteka>`: aplikacija izgradi prozor, zapiše što prozor stvarno sadrži (`Ductura window web <adresa>`, `Ductura window message` ili `Ductura window error`) i putanju paketa, pa se ugasi. Kopije paketa s `http://` adresom i hostom izvan popisa moraju dati `message`.

Nalazi (CI `macos-latest`):

| Pitanje | Nalaz |
|---|---|
| Veličina paketa | Artefakt CI-ja s `.dmg`: 92 266 B na `main` 0a6d2f5, 115 043 B s WKWebView (+23 KB). `du -k` u funkcionalnom testu: `Ductura.app` 372 KB, `.dmg` 128 KB. WebKit je sustavni okvir, pa se ne pakira; razlika je samo kod ljuske. |
| Sandbox | Paket nije u App Sandboxu: potpisan je ad-hoc, a `codesign -d --entitlements -` u logu funkcionalnog testa ne ispisuje nijedno pravo. |
| Mrežna prava | Bez sandboxa WKWebView smije na mrežu bez dodatnih prava. Uz App Sandbox paket treba `com.apple.security.network.client`, inače se stranica ne učitava. |
| ATS | Nije provjereno: `http` adresu odbija već `WebAddress`, prije WKWebView-a. |
| Što ne ulazi | Prijava, nadogradnje, potpis i notarizacija; pravila navigacije (`decidePolicyFor`, DAN-961). |

## CI

`.github/workflows/ci.yml` ima samo prava čitanja (`permissions: contents: read`), a svaki `uses:` je prikvačen na puni SHA. Skeniranje tajni (`secret-scan.yml`) i pregled ovisnosti (`dependency-review.yml`) pozivaju se iz `ductura/.github`. Obvezna provjera `ci-ok` traži uspjeh svih poslova; samo pregled ovisnosti smije biti preskočen, i to izvan pull requesta (push na `main`).

## Pokretanje (na Macu)

```bash
swift test
./scripts/build-dmg.sh
./Tests/functional/install-and-launch.sh
```

Build je potpisan samo ad-hoc. Prije javnog izdanja trebaju Apple Developer ID (99 USD godišnje) i notarizacija, inače macOS Gatekeeper blokira prvo pokretanje.

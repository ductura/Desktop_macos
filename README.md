# Ductura / desktop-macos

macOS aplikacija i instalacijski paket. Swift (AppKit za početak, editor kasnije preko WKWebView; ovisi o odluci 8, otvoreno), paket kao `.dmg` s univerzalnim binarnim (Apple Silicon + Intel).

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
| `Sources/DucturaCore/Startup.swift` | Ishod `--smoke` i poveznica prema provjerenoj adresi |
| `Sources/DucturaCore/Navigation.swift` | Pravilo navigacije za WKWebView (DAN-961): host s popisa ostaje u ljusci, drugi `https` host ide u preglednik, ostalo se odbija. Još nije spojeno na `decidePolicyFor`. |
| `Sources/DucturaCore/ClientVersion.swift` | Provjera verzije pri pokretanju (DAN-945): odluka iz `health.minClientVersion` i `CFBundleShortVersionString`. Još nije spojena na prozor ni na poziv servera. |
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

`WebAddress` prihvaća samo `https` adresu s hosta s popisa, bez porta, korisnika, upita, fragmenta i `%` kodiranja, s putem koji završava s `/`. Ako adresa ne prolazi, aplikacija umjesto gumba pokazuje poruku, a `--smoke` vraća 1 i ne piše potvrdu. Zato i goli `swift run Ductura --smoke` (bez `Info.plist`) vraća 1.

Konačnu domenu (V-0) upiši u ta dva ključa.

## Najmanja verzija klijenta

Pri pokretanju se verzija aplikacije (`CFBundleShortVersionString`) uspoređuje s `minClientVersion` iz odgovora `health` (`ClientVersion`, DAN-945). Verzije su strogo `major.minor.patch`: samo ASCII znamenke, bez vodećih nula i predznaka, najviše 9 znamenki po dijelu.

| Stanje | Odluka | Web |
|---|---|---|
| Klijent je stariji od minimuma | nadogradnja (statična poruka, bez teksta ili poveznice sa servera) | ne otvara se |
| Verzija klijenta nije ispravna, a server daje minimum | nadogradnja: verziju upisuje `build-dmg.sh`, pa neispravna znači pokvaren paket (i `__VERSION__` u buildu bez upisa) | ne otvara se |
| Isti ili noviji klijent, ili server ne daje minimum | otvori | otvara se |
| Server nedostupan, `status` nije `ok` ili minimum nije ispravan | server nedostupan: web je offline-first, a API ionako odbija klijenta s kojim ne može raditi | otvara se |

Spajanje na prozor i stvarni poziv servera s rokom slijede nakon DAN-957.

## CI

`.github/workflows/ci.yml` ima samo prava čitanja (`permissions: contents: read`), a svaki `uses:` je prikvačen na puni SHA. Skeniranje tajni (`secret-scan.yml`) i pregled ovisnosti (`dependency-review.yml`) pozivaju se iz `ductura/.github`. Obvezna provjera `ci-ok` traži uspjeh svih poslova; samo pregled ovisnosti smije biti preskočen, i to izvan pull requesta (push na `main`).

## Pokretanje (na Macu)

```bash
swift test
./scripts/build-dmg.sh
./Tests/functional/install-and-launch.sh
```

Build je potpisan samo ad-hoc. Prije javnog izdanja trebaju Apple Developer ID (99 USD godišnje) i notarizacija, inače macOS Gatekeeper blokira prvo pokretanje.

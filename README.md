# Ductura / desktop-macos

macOS aplikacija i instalacijski paket. Swift (AppKit prozor s WKWebView od spikea D-0.1, DAN-957; tehnologija ljuske ovisi o odluci 8, otvoreno), paket kao `.dmg` s univerzalnim binarnim (Apple Silicon + Intel).

Plan repozitorija: [docs/PLAN.md](docs/PLAN.md).

## Funkcionalna provjera

Korisnik preuzima odgovarajući paket i pokreće Ducturu iz mape Aplikacije.
Pokriva je `Tests/functional/install-and-launch.sh`: kopija paketa s oznakom karantene, otvaranje `.dmg`, kopiranje u `/Applications` i pokretanje preko `open` (`--smoke-out`). Radi samo na macOS-u i pokreće se u CI-ju.
Drugi prolaz (DAN-998) kopira paket iz `.dmg` u izmišljenu mapu `Ductura test/Šđčćž mapa` i pokreće ga odande. Putanju paketa iz `--smoke-window` uspoređuje u NFD obliku, jer APFS čuva oblik imena kakav je zadan. Kontrola potvrđuje da se paket iz `/Applications` odbija kad se očekuje onaj iz te mape.

## Struktura

| Mapa | Sadržaj |
|---|---|
| `Sources/DucturaCore` | Pomoćne funkcije (argumenti, nazivi paketa, verzije) |
| `Sources/DucturaCore/WorkId.swift` | ID rada iz poveznice `ductura://doc/<id>` po pravilu ugovora S-1H.1-c (isto kao serverski `work-id.ts`) i URL s kodiranim ID-om |
| `Sources/DucturaCore/WebAddress.swift` | Provjera adrese weba iz `Info.plist` (DAN-883) |
| `Sources/DucturaCore/Startup.swift` | Ishod `--smoke`, adresa za WKWebView ili poruka (`windowContent`) i redak `--smoke-window` |
| `Sources/DucturaCore/Navigation.swift` | Pravilo navigacije za WKWebView (DAN-961): host s popisa ostaje u ljusci, drugi `https` host ide u preglednik, ostalo se odbija. Još nije spojeno na `decidePolicyFor`. |
| `Sources/DucturaCore/Contracts.generated.swift` | Klijent ugovora (DAN-959), generiran iz OpenAPI-ja zaključanog `@ductura/contracts`; zasad samo `health`. Ne uređuje se ručno. |
| `Sources/DucturaCore/ClientVersion.swift` | Provjera verzije pri pokretanju (DAN-945): odluka iz `health.minClientVersion` i `CFBundleShortVersionString`. Još nije spojena na prozor ni na poziv servera. |
| `Sources/Ductura` | macOS aplikacija |
| `Tests/DucturaCoreTests` | Testovi pomoćnih funkcija (XCTest) |
| `Tests/functional` | Funkcionalni test instalacije |
| `scripts/build-dmg.sh` | Izrada `Ductura.app` i `dist/Ductura-macOS.dmg` |
| `scripts/ci-ok.test.mjs` | Test obvezne zbirne provjere `ci-ok` u `.github/workflows/ci.yml` (`npm ci` pa `node --test`, u CI-ju na Linuxu). `package.json` i `package-lock.json` služe samo Node provjerama u CI-ju (YAML parser `yaml`); aplikacija ne koristi Node. |
| `test-fakes.lock.json`, `Tests/DucturaCoreTests/ContractVectorsTests.swift` | Zaključano izdanje `@ductura/test-fakes` (URL `.tgz`, sha256) i test (DAN-999) koji `health` vektore iz njega provodi kroz generirani dekoder i `ClientVersion`. `swift test` ga preuzima bez tokena; bez mreže ili uz drugi sha256 test namjerno pada, ne preskače se. |
| `contracts.lock.json`, `scripts/contracts.mjs` | Zaključana verzija `@ductura/contracts` (URL `.tgz` s GitHub Releasea servera i sha256) i generator Swifta bez ovisnosti. `node scripts/contracts.mjs --write` regenerira klijent; `--check` u CI-ju pada (izlaz 1) kad se commitani Swift i zaključani OpenAPI razilaze, a izlaz 2 znači da tarball nije upotrebljiv (mreža, sha256, sadržaj). Testovi: `scripts/contracts.test.mjs`. |

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

Funkcionalni test pokreće aplikaciju s `--smoke-window <datoteka>`: aplikacija izgradi prozor, zapiše što prozor stvarno sadrži (`Ductura window web <adresa>`, `Ductura window message` ili `Ductura window error`) i putanju paketa, pa se ugasi. Adresa u retku `web` je ona koju je WebKit stvarno počeo učitavati (`decidePolicyFor` glavnog okvira); ako WKWebView u 30 s ne započne navigaciju, redak je `error`. Kopije paketa s `http://` adresom i hostom izvan popisa moraju dati `message`.

Nalazi (CI `macos-latest`):

| Pitanje | Nalaz |
|---|---|
| Veličina paketa | Artefakt CI-ja s `.dmg`: 92 266 B na `main` 0a6d2f5, 115 043 B s WKWebView (+23 KB). `du -k` u funkcionalnom testu: `Ductura.app` 372 KB, `.dmg` 128 KB. WebKit je sustavni okvir, pa se ne pakira; razlika je samo kod ljuske. |
| Sandbox | Paket nije u App Sandboxu: potpisan je ad-hoc, a `codesign -d --entitlements -` u logu funkcionalnog testa ne ispisuje nijedno pravo. |
| Mrežna prava | Bez sandboxa WKWebView smije na mrežu bez dodatnih prava. Uz App Sandbox paket treba `com.apple.security.network.client`, inače se stranica ne učitava. |
| ATS | Nije provjereno: `http` adresu odbija već `WebAddress`, prije WKWebView-a. |
| Što ne ulazi | Prijava, nadogradnje, potpis i notarizacija; pravila navigacije (`decidePolicyFor`, DAN-961). |

## Najmanja verzija klijenta

Pri pokretanju se verzija aplikacije (`CFBundleShortVersionString`) uspoređuje s `minClientVersion` iz odgovora `health` (`ClientVersion`, DAN-945). Verzije su strogo `major.minor.patch`: samo ASCII znamenke, bez vodećih nula i predznaka, najviše 9 znamenki po dijelu.

| Stanje | Odluka | Web |
|---|---|---|
| Klijent je stariji od minimuma | nadogradnja (statična poruka, bez teksta ili poveznice sa servera) | ne otvara se |
| Verzija klijenta nije ispravna, a server daje minimum | nadogradnja: verziju upisuje `build-dmg.sh`, pa neispravna znači pokvaren paket (i `__VERSION__` u buildu bez upisa) | ne otvara se |
| Isti ili noviji klijent, ili server ne daje minimum | otvori | otvara se |
| Server nedostupan, `status` nije `ok` ili minimum nije ispravan | server nedostupan: web je offline-first, a API ionako odbija klijenta s kojim ne može raditi | otvara se |

Spajanje na prozor i stvarni poziv servera s rokom slijede u sljedećem dijelu (DAN-945-2).

## CI

`.github/workflows/ci.yml` ima samo prava čitanja (`permissions: contents: read`), a svaki `uses:` je prikvačen na puni SHA. Skeniranje tajni (`secret-scan.yml`) i pregled ovisnosti (`dependency-review.yml`) pozivaju se iz `ductura/.github`. Obvezna provjera `ci-ok` traži uspjeh svih poslova; samo pregled ovisnosti smije biti preskočen, i to izvan pull requesta (push na `main`).

## Pokretanje (na Macu)

```bash
swift test
./scripts/build-dmg.sh
./Tests/functional/install-and-launch.sh
```

Build je potpisan samo ad-hoc. Prije javnog izdanja trebaju Apple Developer ID (99 USD godišnje) i notarizacija, inače macOS Gatekeeper blokira prvo pokretanje.

Kanonski plan migracije: [PLAN-MIGRACIJE.md](https://github.com/ductura/.github/blob/main/docs/plan/PLAN-MIGRACIJE.md). Ovaj dokument je dio tog plana.

# Ductura/desktop-macos: plan repozitorija

Stanje: 17. 11. 2026. · **Ovo je samo plan.** Dokument ništa ne gradi, ne kupuje i ne odlučuje (DAN-878, D1).
Izvori:
- [plan migracije](https://github.com/ductura/.github/blob/main/docs/plan/PLAN-MIGRACIJE.md) (u daljnjem tekstu: migracija): §1a, §1b, §3, §4 (faza E), §5, §6, §8 t. 5 do 8 i §9;
- [karta](https://github.com/ductura/.github/blob/main/docs/plan/KARTA.md) (u daljnjem tekstu: karta): paketi, §1, §3, §4 i §5 t. 12.

Oblik je isti kao u [planu servera](https://github.com/ductura/Institution_server/blob/main/docs/PLAN.md) i [planu weba](https://github.com/ductura/Institution_front_web_chrome/blob/main/docs/PLAN.md). Vlasnik je 16. 11. desktopu dopustio samo zadatke D1 do D6, bez odluka 8 i 12 (Ductus#2012).

## 0. Otvorene odluke (ovaj plan ih ne donosi)

| Stavka | Pitanje | Stanje |
|---|---|---|
| 8 | Tehnologija ljuske (migracija §9). Put A: Swift s WKWebView ovdje i C#/.NET s WebView2 u Windowsu. Put B: Tauri ili Electron, jedan kod za oba sustava. | **otvoreno**. Migracija §8 t. 5 kaže: najkasnije na kraju faze C, a spike D-0.1 ide ranije. |
| 12 | Jedan ili dva desktop repozitorija (migracija §9) | **otvoreno**. Uz put A to su `desktop-windows` i `desktop-macos`, uz put B jedan `desktop` s dva cilja. |
| potpis paketa | Apple Developer ID (oko 99 USD godišnje) i notarizacija kod Applea. Bez toga Gatekeeper blokira prvo pokretanje (migracija §8 t. 6). Tko plaća taj trošak (karta §5 t. 12). | **otvoreno** |

Stavke koje ovise o tim odlukama nose oznaku „ovisi o odluci 8”, „ovisi o odluci 12” ili „ovisi o potpisu”.

Postojeći kostur u Swiftu je zatečeno stanje, a ne izbor puta A. Ako odluka 8 ili 12 ode drugim putem, kostur se zamjenjuje, a provjere iz §6 prelaze u repo koji ga zamijeni.

Karta za ugovorni klijent piše „C#/Swift klijent”. To vrijedi samo uz put A, pa je i to otvoreno.

## 1. Svrha i granica

**Svrha.** macOS aplikacija Ducture je tanka izvorna ljuska oko **istog web paketa** iz `ductura/Institution_front_web_chrome` (migracija §8 t. 5). Ljuska radi:
- prozor;
- instalaciju i ažuriranje;
- prijavu tokom po ADR-u S-1E-e;
- lokalno spremište.

Repo posjeduje i paket, potpis i notarizaciju kod Applea (ovisi o potpisu) te prvo pokretanje (migracija §1a).

**Granica (nikad ne ulazi):**
- vlastiti editor: izvorni editor u Swiftu nikad, editor je web paket (migracija §8 t. 5);
- vlastiti server ili baza; poslovna pravila i odluke o ovlastima (samo server);
- druga prijava osim one preko servera. Studenti se prijavljuju samo kroz AAI@EduHr (D-09). Ljuska ne koristi kolačić nego token u zaglavlju (migracija §1b, S-1E-e);
- izravno pisanje u tablice evidencije, predaje i revizijskog traga (samo API);
- tajne, ključ za potpis i podaci za notarizaciju u repou. Ključ smije postojati samo kao tajna CI-ja, i to kad postoji (ovisi o potpisu);
- stvarni osobni podaci i studentski radovi u testovima.

## 2. Zatečeno stanje (kostur, 17. 11.)

- Swift. AppKit prozor s WKWebView koji učitava provjerenu adresu (`Sources/Ductura`; spike D-0.1, DAN-957). Pomoćne funkcije su u `Sources/DucturaCore` (`LaunchOptions`, `Packaging`, `WorkId`, `WebAddress`, `Startup`).
- Spojeni PR-ovi:
  - #1, DAN-885: `ci-ok`;
  - #2, DAN-880: skeniranje tajni i pregled ovisnosti iz `ductura/.github`;
  - #3, DAN-882: ID rada iz poveznice `ductura://doc/<id>`;
  - #4, DAN-883: adresa weba iz `packaging/Info.plist`.
- Testovi:
  - XCTest u `Tests/DucturaCoreTests`;
  - funkcionalni test `Tests/functional/install-and-launch.sh`: paket s oznakom karantene, otvaranje `.dmg`, kopiranje u `/Applications` i pokretanje preko `open` s `--smoke-out`;
  - `scripts/ci-ok.test.mjs` (Node, samo za `ci-ok`).
- Paket: `scripts/build-dmg.sh` gradi `dist/Ductura-macOS.dmg` s univerzalnim binarnim (Apple Silicon i Intel), macOS 13 ili noviji. Paket je **potpisan samo ad-hoc** i nije notariziran, pa Gatekeeper blokira prvo pokretanje.
- Adresa weba `https://ductura.org/app/` je zadana vrijednost dok se ne odluči V-0 (domena).
- Još nema web paketa u ljusci, prijave tokom ni ažuriranja. Ugovorni klijent ima samo `health` (DAN-959): Swift generiran iz OpenAPI-ja zaključanog `@ductura/contracts` (`contracts.lock.json`); `health` vektori iz zaključanog `@ductura/test-fakes` (`test-fakes.lock.json`) prolaze u `swift test` (DAN-999). Vektori ID-a rada iz zaključanog `@ductura/contracts` još ne ulaze u `swift test` (DAN-1001 dio 2). Gradi na zatečenom kosturu i ne donosi odluku 8.

## 3. Sadržaj (PRIJEDLOG; ovisi o odluci 8)

```
Sources/DucturaCore/      pomoćne funkcije bez sučelja (testirane)
Sources/Ductura/          prozor i ljuska; web paket u WKWebView (ovisi o odluci 8)
Tests/DucturaCoreTests/   testovi pomoćnih funkcija
Tests/functional/         preuzimanje, Aplikacije, pokretanje
packaging/, scripts/      paket; potpis i notarizacija ovise o potpisu
docs/, .github/ (poziva ductura/.github punim SHA-om)
```

## 4. Što dolazi iz Ductusa i paketa

Iz Ductusa se ne prenosi nijedan kod (migracija §3). Ljuska učitava isti web paket. Polazi od:
- manifesta i simulacije preuzimanja u serveru (S-1H.5, S-1H.6);
- ADR-a S-1E-e;
- spikea D-0.1 (Ductus `spikes/`).

| Paket (karta) | Kako ga desktop koristi |
|---|---|
| `@ductura/contracts` | Klijent iz istog OpenAPI-ja s ugovornim vektorima. Jezik klijenta ovisi o odluci 8. |
| `@ductura/test-fakes` | Lažni server iz ugovora i lažni AAI za testove |
| `@ductura/editor-core` | Samo kroz web paket (karta: „ovisno o odluci 8”) |
| `@ductura/parity` | Scenariji S-1H.8/1..6 u ljusci |

## 5. Zadaci

| Korak | Što | Ovisi o |
|---|---|---|
| D1 (DAN-878) | Ovaj plan | — |
| D-0.1 | Spike ljuske (WebView2, WKWebView, Tauri) s istom web izgradnjom, u Ductusu | kraj faze B |
| odluke 8 i 12 | Vlasnik | D-0.1; najkasnije kraj faze C |
| Faza E · aktivacija desktop razvoja | Vlasnička radnja, odvojena od V-1b (karta §3) | vlasnik; ulaz faze E (migracija §4): odluke 8 i 12, potpis, V-5 |
| ljuska | Prozor učitava isti web paket s provjerene adrese (`WebAddress`) | odluka 8, aktivacija faze E |
| prijava | Token u zaglavlju po ADR-u S-1E-e; samo preko servera | S-1E-e, V-5 (Srce) |
| klijent ugovora | Iz OpenAPI-ja u `@ductura/contracts`; vektori u CI-ju | U10, odluka 8 |
| izdanje | GitHub Release desktop repoa kao izvor paketa. Server u manifestu drži adresu i SHA-256, a korisnik preuzima kroz `/preuzimanje/` (PRIJEDLOG, migracija §8 t. 8). | S-1H.5, S-1H.6, odluka 12 |
| potpis | Potpisani paket | ovisi o potpisu |

Koraci bez ID-a su PRIJEDLOG: ID dodjeljuje orkestrator.

## 6. Testovi

| Sloj | Konkretni slučajevi |
|---|---|
| **Pomoćne funkcije** | Argumenti, nazivi paketa, ID rada, adresa weba i ishod `--smoke` (postoje). Nove funkcije ljuske dobivaju testove u `DucturaCore`. |
| **Funkcionalni** | Preuzimanje, mapa Aplikacije i pokretanje; arhitektura (Apple Silicon i Intel) (karta §4). Nakon potpisa (ovisi o potpisu): prvo pokretanje bez blokade Gatekeepera. |
| **Ugovor** | Klijent prikvači verziju ugovora i pokreće njegove vektore (migracija §6). |
| **Paritet** | `@ductura/parity` S-1H.8/1..6 u ljusci (ovisi o odluci 8). |
| **Simulacija preuzimanja** | Pravi paket, SHA-256 jednak manifestu, preuzimanje samo na klik (migracija §6). Pokreće ga CI desktopa pri izdanju. |
| **Sigurnost** | Nema tajni (`secret-scan`). Ljuska otvara samo provjerenu adresu. Prijava ide samo preko servera. |

**Matrica:** `macos-latest` za izgradnju i funkcionalni test, `ubuntu-latest` samo za `ci-ok-test`.
**Prag „gotovo”:** `ci-ok` je zelen i ništa nije preskočeno. Funkcionalni test na čistom Macu prolazi.

## 7. CI i gate

- **Danas** (`.github/workflows/ci.yml`, `permissions: contents: read`, svaki `uses:` na punom SHA-u):
  - `build-test` (`macos-latest`);
  - `ci-ok-test`;
  - `secret-scan` i `dependency-review` iz `ductura/.github`;
  - obvezni `ci-ok`.
- **Kasnije:**
  - reusable `ci-swift` iz `ductura/.github` (ime vrijedi samo uz put A, ovisi o odluci 8);
  - vektori ugovora za ostale rute (generirani klijent prema zaključanom OpenAPI-ju je u `ci-ok-test`, DAN-959; `health` vektori su u `swift test`, DAN-999);
  - izdanje na oznaku `vX.Y.Z` kao potpisani paket u GitHub Releaseu (migracija §5; ovisi o potpisu).
- **Risk (PRIJEDLOG):** `.github/**` je `critical`, kao u drugim repoima. Ostale putanje dodjeljuje tablica rizika.
- **Vlasničke radnje:**
  - Faza E · aktivacija desktop razvoja;
  - Apple Developer račun (ovisi o potpisu);
  - V-0, V-2, V-3 i V-5;
  - odluke 8 i 12.

## 8. Kriterij izlaza (faza E; ovisi o odlukama 8 i 12 i o potpisu)

Izlaz faze E prema migraciji §4: „Potpisani paketi; instalacija i pokretanje na čistom Windowsu i Macu; gumbi preloadera vode na prava izdanja”. Za ovaj repo to znači:

1. Paket je potpisan i notariziran (ovisi o potpisu) i objavljen u GitHub Releaseu. SHA-256 je jednak onom u manifestu servera.
2. Instalacija i pokretanje prolaze na čistom Macu, na Apple Siliconu i Intelu.
3. Gumb preloadera za macOS vodi na to izdanje.
4. Editor dolazi iz web paketa. Nema nijednog retka izvornog editora.
5. Prijava ide samo preko servera, tokom (S-1E-e). Za studente je to AAI@EduHr (D-09).
6. `ci-ok` je zelen. Prihvat vala s instalacijom desktopa je **otvoren** (karta §4).

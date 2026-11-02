# Soccer Overview

Ein Fussball-Dashboard für Windows, geschrieben in PowerShell mit einer WPF-Oberfläche. Suche Clubs und Spieler, vergleiche ihre Saisonwerte und speichere interessante Profile als Favoriten. Die mitgelieferte Demo funktioniert offline.

## In einer Minute starten

1. Entpacke den gesamten Projektordner auf einem Windows-10- oder Windows-11-PC.
2. Doppelklicke auf **Start.cmd**. Der Starter öffnet die App mit Windows PowerShell 5.1 im STA-Modus. Zusätzliche Module oder Adminrechte brauchst du für die Demo nicht.
3. **Arsenal** ist bereits ausgewählt. Oben siehst du Spiele, Tore und Gegentore. Die paarweisen Balken darunter zeigen, wie viele Tore Arsenal in den einzelnen Spielen geschossen und kassiert hat.
4. Wähle links **Spieler**, tippe **Haaland** und drücke **Enter**. Jetzt zeigen die Balken Tore und Assists pro Wettbewerb. Wähle **Favorit speichern**, öffne **Favoriten** und starte die App neu. Das gespeicherte Profil bleibt verfügbar.

Die Demo enthält Arsenal, Manchester City, Bayern München, Erling Haaland, Bukayo Saka und Jamal Musiala. Wähle **2024** als Saison. Die Zahlen sind erfundene Beispieldaten. Auch eine leere Suche zeigt alle Demo-Einträge der gewählten Kategorie.

## Echte Daten mit API-Football

1. Erstelle im [API-Sports-Dashboard](https://dashboard.api-football.com/) einen API-Football-Key. Das Projekt nutzt den direkten API-Sports-Zugang.
2. Öffne im Projektordner eine PowerShell. Die folgenden Zeilen fragen den Key verdeckt ab, setzen ihn für diese Sitzung und starten die App. Der Key wird weder in einer Projektdatei noch in den Favoriten gespeichert.

   ```powershell
   $secret = Read-Host 'API-Football-Key' -AsSecureString
   $env:API_FOOTBALL_KEY = [System.Net.NetworkCredential]::new('', $secret).Password
   .\Start.cmd
   ```

3. Wähle oben rechts **Live · API-Football**. Gib mindestens vier Zeichen ein, bei Spielern den **Nachnamen**. Die Saison ist das **Startjahr** des Wettbewerbs, beispielsweise 2024 für 2024/25.
4. Suche z. B. nach **Arsenal** oder **Haaland**. Wähle bei mehreren Treffern das richtige Profil links aus. Bei genau einem Treffer lädt die App das Profil direkt.
5. Wähle eine Saison, die dein Tarif freigibt. Kontingent, verfügbare Saisons und Datenabdeckung richten sich nach deinem Konto. Nach dem Test kannst du die Variable mit `Remove-Item Env:\API_FOOTBALL_KEY` aus der Sitzung entfernen.

### Was bei einer Suche passiert

| Schritt | Anfrage oder Skript | Ergebnis |
|---|---|---|
| Clubs finden | `GET /teams?search=Arsenal` | Namen, IDs, Land, Stadion und Gründungsjahr |
| Club öffnen | `GET /fixtures?team=42&season=2024` | Spiele des Clubs für die gewählte Saison |
| Spieler finden | `GET /players/profiles?search=Haaland` | Namensliste mit Spieler-IDs, unabhängig von der Saison |
| Spieler öffnen | `GET /players?id=<Spieler-ID>&season=2024` | Statistiken je Team und Wettbewerb |
| Favorit speichern | `write.ps1 -Eintrag …` | Schreibt das angezeigte Profil samt Diagrammdaten nach `data/football.json` |
| Favoriten öffnen | `read.ps1` | Liest die lokale Datei, auch offline |

Die Basisadresse lautet `https://v3.football.api-sports.io`. `Invoke-FootballApi` sendet den Schlüssel im HTTP-Header `x-apisports-key`, kodiert Suchbegriffe und liest weitere Ergebnisseiten, wenn die API mehrere Seiten meldet. HTTP-Fehler und Fehler im Feld `errors` erscheinen unten im Fenster. API-Anfragen laufen im Hintergrund. [Offizielle API-Dokumentation](https://www.api-football.com/documentation_v3)

### Wie die Diagramme rechnen

| Ansicht | Erstes Diagramm | Zweites Diagramm |
|---|---|---|
| Club | Eigene Tore und Gegentore aus den letzten fünf abgeschlossenen Spielen, ältestes zuerst | Siege, Remis und Niederlagen über alle gewerteten Spiele der Saison |
| Spieler | Tore und Assists je Wettbewerb und Verein, auch bei einem Transfer | Startelf und Einwechslungen über alle gelieferten Wettbewerbe. Darunter stehen die Spielminuten. |

- Clubdaten berücksichtigen die beendeten Spiele mit Status `FT`, `AET` und `PEN` und bekanntem Torstand. Die Bilanz basiert auf den Spieltoren inklusive Verlängerung. Ein im Elfmeterschiessen entschiedenes Remis zählt in dieser Bilanz als Remis.
- Bei Spielern werden die gelieferten Wettbewerbszeilen summiert. Einwechslungen entsprechen Einsätzen minus Startelfeinsätzen.
- Alle Balken innerhalb eines Diagramms verwenden dieselbe Skala. Eine **0** ist ein bekannter Nullwert. Ein **–** steht für eine fehlende Angabe. Fehlt ein Teilwert, erscheint auch die entsprechende Gesamtsumme als unbekannt.

## Welche Datei macht was?

| Datei | Aufgabe |
|---|---|
| `Start.cmd` | Öffnet PowerShell mit den passenden Optionen. Die Ausführungsrichtlinie gilt nur für diesen Prozess. |
| `Start.ps1` | Lädt das Fenster, verarbeitet Klicks und Suchanfragen, zeichnet Balken aus den ausgewählten Daten. |
| `ui/Dashboard.xaml` | Enthält Layout, Farben, Navigation und Steuerelemente des Fensters. |
| `src/Soccer.ps1` | Enthält die Datenlogik für Suche, API-Aufrufe, Statistikberechnung und den lokalen Speicher. |
| `write.ps1` | Speichert Profile, aktualisiert bestehende Einträge und kann einen Favoriten entfernen. |
| `read.ps1` | Gibt gespeicherte Einträge als PowerShell-Objekte zurück. |
| `demo/saison.json` | Enthält die mitgelieferten fiktiven Daten. |
| `tests/Test.ps1` | Prüft Suche, API-Verarbeitung, Statistikwerte und den Speicher. Auf Windows prüft es zusätzlich die WPF-Ansichten. |

### Skripte ohne Oberfläche benutzen

Im Projektordner ausführen. Die ersten beiden Beispiele funktionieren ohne API-Key.

```powershell
.\write.ps1 -Typ Spieler -Suche Haaland -Saison 2024 -Demo
.\read.ps1 -Typ Spieler -Suche Haaland | Format-Table Name, Saison, Tore, Assists

# Live mit dem zuvor gesetzten API_FOOTBALL_KEY
.\write.ps1 -Typ Club -Suche Arsenal -Saison 2024
.\read.ps1 -Typ Club | Select-Object Name, Stadion, Saison, Tore, Gegentore
```

Das CLI lädt und speichert **alle Treffer** einer Suche. In der Oberfläche kannst du einen einzelnen Treffer öffnen und speichern. Beide Wege benutzen dieselben Datenfunktionen. Mit `-DataFile` kannst du eine andere JSON-Datei wählen.

### Lokaler Speicher

Beim Start liest die App die Anzahl gespeicherter Favoriten ein. Beim Öffnen von **Favoriten** liest sie die Datei erneut. Der Ordner `data` entsteht beim ersten Speichern. Ein Profil ist über Quelle, Typ, API-ID und Saison identifiziert. Erneutes Speichern aktualisiert denselben Eintrag. Demo- und Live-Daten bleiben getrennt.

Das Datenformat behält die Liste `Eintraege` der ursprünglichen Skripte bei. Ältere Einträge kannst du weiterhin lesen. Wenn ihnen Diagrammdaten fehlen, suche das Profil im Live-Modus erneut und speichere es für die gewünschte Saison. Eine beschädigte Datei führt zu einer Fehlermeldung und wird beim Speichern nicht überschrieben.

## Fehler finden und Tests ausführen

| Was du siehst | Was du prüfen kannst |
|---|---|
| Die Demo liefert keine Treffer | Wähle Saison 2024, die richtige Kategorie und lasse den Suchbegriff leer. |
| API-Key fehlt | Setze die Variable und starte die App aus derselben PowerShell. |
| Plan-, Kontingent- oder HTTP-Fehler | Lies die Statuszeile, prüfe Tarif und Saison im API-Dashboard. |
| Profil gefunden, aber keine Balken | Für diesen Treffer und diese Saison fehlen auswertbare Daten. Probiere eine Saison mit Datenabdeckung. |
| Windows blockiert das Skript | Nutze den mitgelieferten Starter. Bei verwalteten Geräten können Richtlinien deiner Organisation gelten. |
| Die lokale Datei ist beschädigt | Sichere `data/football.json` und prüfe das JSON. Du kannst die Datei umbenennen und mit einer leeren Favoritenliste starten. |

```powershell
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File .\tests\Test.ps1
```

Die Tests verwenden temporäre Dateien und simulierte HTTP-Antworten. Sie prüfen auch Pagination, `null` gegenüber null Toren, alte Speicherdateien und beschädigtes JSON. Der Windows-Smoke-Test lädt das echte WPF-Fenster und wechselt zwischen Club- und Spieleransicht. Die Datenlogik lässt sich mit PowerShell 7 auch auf Linux oder macOS testen.

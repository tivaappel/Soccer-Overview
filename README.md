# Soccer Overview

Eine Windows-App für die Club- und Spielersuche mit API-Football. Wähle eine Saison, öffne einen Treffer und vergleiche seine echten Statistiken in zwei Diagrammen. Favoriten speichern das angezeigte Profil samt Zahlen auf deinem PC.

## Start in drei Schritten

1. Lade das Repo auf GitHub über **Code → Download ZIP** herunter. Entpacke den ganzen Ordner und öffne **Start.cmd** auf Windows 10 oder 11. Es nutzt Windows PowerShell 5.1 und braucht keine Zusatzmodule.
2. Kopiere deinen API-Football-Key aus dem [API-Sports-Dashboard](https://dashboard.api-football.com/) in das verdeckte Feld oben rechts und klicke **Key setzen**. Der Key gilt für die laufende Sitzung. Die App speichert ihn weder im Projekt noch in den Favoriten.
3. Wähle **Club** oder **Spieler**, gib z. B. **Arsenal** oder **Haaland** ein und drücke **Enter**. Bei mehreren Treffern wählst du links den richtigen aus. Die Saison ist das Startjahr des Wettbewerbs, z. B. 2024 für 2024/25. Wähle ein Jahr, das dein API-Tarif abdeckt.

Ohne Schlüssel kannst du echte, bereits gespeicherte Profile unter **Favoriten** öffnen. Bei der ersten Suche füllen sich die Diagramme, sobald API-Football Daten für das gewählte Profil und Jahr liefert.

## Was die Diagramme zeigen

| Ansicht | Vergleich | Bilanz |
|---|---|---|
| Club | Eigene Tore und Gegentore aus den letzten fünf abgeschlossenen Spielen, ältestes zuerst | Siege, Remis und Niederlagen über alle gewerteten Spiele der gewählten Saison |
| Spieler | Tore und Assists je Wettbewerb und Verein, auch bei einem Transfer | Startelf, Einwechslungen und insgesamt absolvierte Minuten |

Die Balken eines Diagramms haben dieselbe Skala. **0** bedeutet, dass die API null Aktionen gemeldet hat. **–** bedeutet, dass eine Angabe fehlt. Fehlt ein Teilwert, bleibt auch die zugehörige Gesamtsumme offen.

Bei Clubs zählen abgeschlossene Spiele mit bekanntem Torstand und Status `FT`, `AET` oder `PEN`. Die Bilanz basiert auf den Toren inklusive Verlängerung. Ein im Elfmeterschiessen entschiedenes Remis zählt nach dieser Definition als Remis. Bei Spielern summiert die App die gelieferten Wettbewerbszeilen. Einwechslungen sind Einsätze minus Startelfeinsätze.

## Vom Skript bis zur API

| Was du machst | Was die App ausführt |
|---|---|
| App starten | `Start.cmd` öffnet `Start.ps1` im STA-Modus. Es lädt `ui/Dashboard.xaml`, verbindet die Bedienfelder und liest die Favoriten ein. |
| Club suchen | `GET /teams?search=Arsenal` liefert IDs, Namen, Land und Stadion. |
| Club öffnen | `GET /fixtures?team=42&season=2024` liefert die Spiele. `src/Soccer.ps1` berechnet daraus Saisonbilanz und Torverlauf aus Sicht des Clubs. |
| Spieler suchen | `GET /players/profiles?search=Haaland` sucht nach dem Nachnamen und liefert Spieler-IDs. |
| Spieler öffnen | `GET /players?id=<Spieler-ID>&season=2024` liefert die Saisonstatistiken je Verein und Wettbewerb. |
| Favorit speichern | `write.ps1` schreibt den ausgewählten Stand nach `data/football.json`. Die gleiche ID, Kategorie und Saison aktualisieren den bestehenden Eintrag. |
| Favoriten öffnen | `read.ps1` liest die JSON-Datei. Um Daten zu aktualisieren, suche das Profil erneut und speichere es. |

Die API-Basisadresse lautet `https://v3.football.api-sports.io`. Die Funktion `Invoke-FootballApi` sendet den Key im Header `x-apisports-key`, kodiert Suchbegriffe und verarbeitet weitere Ergebnisseiten. Netzwerkzugriffe laufen ausserhalb des UI-Threads. Die Statuszeile meldet auch Fehler, die der Anbieter in einer HTTP-200-Antwort zurückgibt. [Offizielle API-Dokumentation](https://www.api-football.com/documentation_v3)

## PowerShell ohne Oberfläche

Öffne PowerShell im Projektordner. Für eine Live-Abfrage kannst du den Schlüssel verdeckt für die aktuelle Sitzung setzen. Die GUI übernimmt die Variable ebenfalls.

```powershell
$secret = Read-Host 'API-Football-Key' -AsSecureString
$env:API_FOOTBALL_KEY = [System.Net.NetworkCredential]::new('', $secret).Password

.\write.ps1 -Typ Spieler -Suche Haaland -Saison 2024
.\read.ps1 -Typ Spieler -Suche Haaland | Format-Table Name, Saison, Tore, Assists
```

Die CLI speichert alle Treffer der Suche, die GUI nur das von dir gewählte Profil. Mit `-DataFile` kannst du einen anderen Speicherpfad verwenden. Gleichzeitige Schreibzugriffe werden serialisiert. Bei beschädigtem JSON wird die vorhandene Datei geschützt.

## Wenn Daten fehlen

| Meldung | Was du prüfen kannst |
|---|---|
| **API-Key fehlt** | Schlüssel oben eingeben und **Key setzen** wählen. Alternativ die App aus einer PowerShell mit gesetzter Umgebungsvariable starten. |
| **Keine Treffer** | Mindestens vier Zeichen verwenden. Bei Spielern nach dem Nachnamen suchen. |
| **Saison gesperrt oder Limit erreicht** | Tarif, freigegebene Saisons und verbleibende Anfragen im API-Dashboard prüfen. |
| **Profil ohne Statistik** | Für diesen Treffer und dieses Jahr gibt es keine auswertbaren Daten. Ein anderes abgedecktes Jahr wählen. |
| **Lokale Daten konnten nicht gelesen werden** | `data/football.json` sichern und das JSON prüfen. Um die Favoritenliste neu aufzubauen, die Datei umbenennen. |

## Tests

```powershell
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File .\tests\Test.ps1
```

Die Tests prüfen die Verarbeitung von API-Antworten, fehlende Werte, Diagrammrechnungen, Favoriten und ältere Speicherdateien ohne Verbrauch deines API-Kontingents. Unter Windows testen sie zusätzlich die echte WPF-Oberfläche. [Windows-Testläufe auf GitHub](https://github.com/tivaappel/Soccer-Overview/actions/workflows/windows.yml)

# Soccer Overview

Eine Windows-App für die Club- und Spielersuche mit API-Football. Tippe einen Namen ein, wähle ein Profil und lies Ergebnisse und Statistiken auf der Stadiontafel. Favoriten speichern das angezeigte Profil samt Zahlen auf deinem PC.

## Start in drei Schritten

1. Lade das Repo auf GitHub über **Code → Download ZIP** herunter. Entpacke den ganzen Ordner und öffne **Start.cmd** auf Windows 10 oder 11. Es nutzt Windows PowerShell 5.1 und braucht keine Zusatzmodule.
2. Kopiere deinen API-Football-Key aus dem [API-Sports-Dashboard](https://dashboard.api-football.com/) in das verdeckte Feld oben rechts und klicke **Key setzen**. Der Key gilt für die laufende Sitzung. Die App speichert ihn weder im Projekt noch in den Favoriten.
3. Wähle **Club** oder **Spieler** und tippe mindestens vier Zeichen, z. B. **Arse** oder **Haal**. Nach einer kurzen Schreibpause erscheinen bis zu zwölf Vorschläge mit Logo oder Foto. Klicke einen an, oder öffne mit **↓** den ersten Treffer. **Enter** oder **Suchen** ruft die vollständige Trefferliste ab.
4. Nach der Profilauswahl lädt die App seine verfügbaren Saisons und öffnet die neueste. Über **Saison** kannst du zu einem anderen Jahr wechseln. Angezeigt wird das Startjahr, z. B. 2024 für eine Saison 2024/25. Wenn die API einen freigegebenen Jahresbereich für deinen Tarif meldet, berücksichtigt die App ihn bei der Auswahl.

Unter **Favoriten** kannst du gespeicherte Zahlen auch offline lesen. Spielerfotos sowie Vereins- und Wettbewerbslogos lädt die App direkt vom Bilderdienst von API-Sports. Fehlt ein Bild, bleibt die Tafel mit einem neutralen Wappen lesbar.

## Was auf der Stadiontafel steht

| Ansicht | Anzeige | Saisonbilanz |
|---|---|---|
| Club | Die letzten fünf abgeschlossenen Spiele, neuestes zuerst. Links steht das Heimteam, rechts das Auswärtsteam, in der Mitte der Spielstand. Bei einem Elfmeterschiessen steht auch dessen Ergebnis dabei. | Spiele, Tore, Gegentore, Siege, Remis und Niederlagen |
| Spieler | Tore und Assists als getrennte Zahlen pro Wettbewerb und Verein, mit Spielerfoto und Logos | Einsätze, Tore, Assists, Startelfeinsätze, Einwechslungen und Minuten |

**0** steht für einen gemeldeten Nullwert. **–** bedeutet, dass eine Angabe fehlt. Bei älteren Favoriten ohne gespeicherte Heim- und Gastzuordnung ist das Ergebnis als **Clubsicht** gekennzeichnet. Erneut suchen und speichern ergänzt die vollständigen Daten.

Bei Clubs zählen abgeschlossene Spiele mit bekanntem Torstand und Status `FT`, `AET` oder `PEN`. Die Bilanz basiert auf den Toren inklusive Verlängerung. Ein im Elfmeterschiessen entschiedenes Remis zählt nach dieser Definition als Remis. Bei Spielern summiert die App die gelieferten Wettbewerbszeilen. Einwechslungen sind Einsätze minus Startelfeinsätze.

## Vom Skript bis zur API

| Was du machst | Was die App ausführt |
|---|---|
| App starten | `Start.cmd` öffnet `Start.ps1` im STA-Modus. Es lädt `ui/Dashboard.xaml`, verbindet die Bedienfelder und liest die Favoriten ein. |
| Club suchen | `GET /teams?search=Arsenal` liefert IDs, Namen, Land und Stadion. |
| Saisons laden | `GET /teams/seasons?team=42` bzw. `GET /players/seasons?player=<Spieler-ID>` liefert die erfassten Jahre für das ausgewählte Profil. Die Auswahl zeigt sie absteigend und ohne Duplikate. |
| Club öffnen | `GET /fixtures?team=42&season=2024` liefert die Spiele. `src/Soccer.ps1` berechnet daraus Saisonbilanz und die letzten Resultate in Heim-/Gastreihenfolge. |
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

Die Tests prüfen Suchvorschläge, Saisonwahl, Bildadressen, Heim-/Auswärtsergebnisse, fehlende Werte, Favoriten und ältere Speicherdateien ohne Verbrauch deines API-Kontingents. Unter Windows testen sie zusätzlich die echte WPF-Oberfläche. [Windows-Testläufe auf GitHub](https://github.com/tivaappel/Soccer-Overview/actions/workflows/windows.yml)

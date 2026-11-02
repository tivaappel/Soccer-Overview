# Lokale Tests ohne API-Key. Unter Windows öffnet der Test das WPF-Layout im Speicher.
[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
. (Join-Path $root 'src/Soccer.ps1')
function Verify([bool]$Condition,[string]$Name) {
    if (!$Condition) { throw "Test fehlgeschlagen: $Name" }
    Write-Host "OK  $Name"
}
$dir=Join-Path ([IO.Path]::GetTempPath()) ('soccer-test-'+[guid]::NewGuid())
[void][IO.Directory]::CreateDirectory($dir)
$file=Join-Path $dir 'football.json'
try {
    Verify (@(& (Join-Path $root 'read.ps1') -DataFile $file).Count -eq 0) 'Erster Start ohne Datendatei'
    $missing=$false
    try { Find-SoccerEntry Spieler Haaland 2024 -ApiKey '' } catch { $missing=$_.Exception.Message -like '*API-Key*' }
    Verify $missing 'Fehlender Schlüssel wird erklärt'

    # Die HTTP-Grenze simulieren. Der echte URL-Bau, Pagination und Normalisierung laufen mit.
    $script:urls=@()
    function Invoke-RestMethod {
        param($Uri,$Headers,$TimeoutSec,$ErrorAction)
        if ($Headers['x-apisports-key'] -ne 'test-only') { throw 'API-Header fehlt' }
        $script:urls+=$Uri
        $page=1; $pages=1; $rows=@(); $errors=@()
        if ($Uri -like '*/players/profiles?*') {
            $pages=2
            if ($Uri -match '[?&]page=2') { $page=2 }
            $rows=@(@{player=@{id=$page;name="Test $page";nationality='Schweiz'}})
        } elseif ($Uri -like '*/players?*') {
            $rows=@(@{statistics=@(
                @{team=@{name='FC Test'};league=@{name='Liga'};games=@{appearences=10;lineups=9;minutes=810};goals=@{total=4;assists=2}},
                @{team=@{name='FC Test'};league=@{name='Cup'};games=@{appearences=2;lineups=1;minutes=110};goals=@{total=0;assists=$null}}
            )})
        } elseif ($Uri -like '*/teams?*') {
            $rows=@(@{team=@{id=42;name='Test FC';country='Schweiz'};venue=@{name='Stadion'}})
        } elseif ($Uri -like '*/fixtures?*') {
            $rows=@(
                @{fixture=@{timestamp=1725000000;status=@{short='FT'}};teams=@{home=@{id=42};away=@{id=2;name='FC A'}};goals=@{home=2;away=0}},
                @{fixture=@{timestamp=1725100000;status=@{short='AET'}};teams=@{home=@{id=3;name='FC B'};away=@{id=42}};goals=@{home=2;away=1}},
                @{fixture=@{timestamp=1725200000;status=@{short='2H'}};goals=@{home=1;away=0}}
            )
        } else { $errors=@{plan='Saison gesperrt'} }
        [pscustomobject]@{paging=@{current=$page;total=$pages};response=$rows;errors=$errors}
    }
    $people=@(Find-SoccerEntry Spieler 'Test A' 2024 -ApiKey 'test-only')
    Verify ($people.Count -eq 2 -and $script:urls[0] -like '*search=Test%20A*') 'Profil-Suche, URL-Encoding und Pagination'
    $p=Get-SoccerDetail $people[0] -ApiKey 'test-only'
    Verify ($p.Tore -eq 4 -and $p.Einsaetze -eq 12 -and $p.Serien.Count -eq 2) 'Spielerwerte über zwei Wettbewerbe'
    Verify ($null -eq $p.Assists -and $p.Serien[1].A -eq 0) 'Fehlende Werte bleiben unbekannt, echte Null bleibt 0'
    $c=Find-SoccerEntry Club 'Test FC' 2024 -ApiKey 'test-only'
    $c=Get-SoccerDetail $c -ApiKey 'test-only'
    Verify ($c.Gegentore -eq 2 -and $c.Tore -eq 3 -and $c.Siege -eq 1 -and $c.Niederlagen -eq 1 -and $c.Serien.Count -eq 2) 'Clubdiagramme zählen nur beendete Spiele aus Clubsicht'
    $failed=$false
    try { Invoke-FootballApi 'status-test' @{} 'test-only' } catch { $failed=$_.Exception.Message -like '*Saison gesperrt*' }
    Verify $failed 'HTTP 200 mit API-Fehler wird erkannt'
    & (Join-Path $root 'write.ps1') -Typ Club -Suche 'Test FC' -Saison 2024 -ApiKey 'test-only' -DataFile $file | Out-Null
    & (Join-Path $root 'write.ps1') -Eintrag $p -DataFile $file
    & (Join-Path $root 'write.ps1') -Eintrag $c -DataFile $file
    Verify (@(Read-SoccerStore $file).Count -eq 2) 'Erneutes Speichern aktualisiert denselben Favoriten'
    $filtered=@(& (Join-Path $root 'read.ps1') -Typ Spieler -Suche 'Test 1' -DataFile $file)
    Verify ($filtered.Count -eq 1 -and $filtered[0].Serien.Count -eq 2) 'Profil und Diagrammdaten nach Neustart'
    $guiFile=Join-Path $dir 'gui.json'
    Copy-Item $file $guiFile
    & (Join-Path $root 'write.ps1') -Eintrag $p -Entfernen -DataFile $file
    Verify (@(Read-SoccerStore $file).Count -eq 1) 'Gezieltes Entfernen'
    & (Join-Path $root 'write.ps1') -Eintrag $c -Entfernen -DataFile $file
    Verify (@(Read-SoccerStore $file).Count -eq 0) 'Letzten Favoriten entfernen'
    [IO.File]::WriteAllText($file,'{"Eintraege":[{"Typ":"Club","Id":42,"Name":"Arsenal","Saison":null},{"Typ":"Club","Id":10,"Name":"Beispiel","Quelle":"Testbestand"}]}')
    Update-SoccerStore $file @($c)
    Verify (@(Read-SoccerStore $file).Count -eq 2) 'Alte API-Einträge lesbar, fremde Datenquellen ausgeschlossen'
    [IO.File]::WriteAllText($file,'{ kaputt')
    $failed=$false
    try { Update-SoccerStore $file @($c) } catch { $failed=$true }
    Verify ($failed -and [IO.File]::ReadAllText($file) -eq '{ kaputt') 'Ungültige JSON-Datei bleibt intakt'
    $doc=[xml](Get-Content (Join-Path $root 'ui/Dashboard.xaml') -Encoding UTF8 -Raw)
    Verify ($doc.DocumentElement.LocalName -eq 'Window') 'Dashboard-XAML ist gültiges XML'
    if ($env:OS -eq 'Windows_NT') {
        $result=& (Join-Path $root 'Start.ps1') -SmokeTest -DataFile $guiFile
        Verify ($result -contains 'WPF-Smoke-Test bestanden.') 'WPF lädt, Club- und Spieleransicht wechseln'
    } else { Write-Host 'WPF-Smoke-Test übersprungen (nur Windows).' }
} finally { Remove-Item -LiteralPath $dir -Recurse -Force }

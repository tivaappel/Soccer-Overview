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
        if ($Uri -like '*/teams/seasons?*' -or $Uri -like '*/players/seasons?*') {
            $rows=@(2023,2024,2023)
        } elseif ($Uri -like '*/players/profiles?*') {
            $pages=2
            if ($Uri -match '[?&]page=2') { $page=2 }
            $rows=@(@{player=@{id=$page;name="Test $page";nationality='Schweiz'}})
        } elseif ($Uri -like '*/players?*') {
            $rows=@(@{statistics=@(
                @{team=@{id=42;name='FC Test'};league=@{id=1;name='Liga'};games=@{appearences=10;lineups=9;minutes=810};goals=@{total=4;assists=2}},
                @{team=@{name='FC Test'};league=@{name='Cup'};games=@{appearences=2;lineups=1;minutes=110};goals=@{total=0;assists=$null}}
            )})
        } elseif ($Uri -like '*/teams?*') {
            $rows=@(@{team=@{id=42;name='Test FC';country='Schweiz'};venue=@{name='Stadion'}})
        } elseif ($Uri -like '*/fixtures?*') {
            $rows=@(
                @{fixture=@{timestamp=1725000000;status=@{short='FT'}};teams=@{home=@{id=42;name='Test FC'};away=@{id=2;name='FC A'}};goals=@{home=2;away=0}},
                @{fixture=@{timestamp=1725100000;status=@{short='AET'}};teams=@{home=@{id=3;name='FC B'};away=@{id=42;name='Test FC'}};goals=@{home=2;away=1}},
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
    Verify ($c.Gegentore -eq 2 -and $c.Tore -eq 3 -and $c.Siege -eq 1 -and $c.Niederlagen -eq 1 -and $c.Serien.Count -eq 2) 'Saisonbilanz zählt nur beendete Spiele aus Clubsicht'
    $away=$c.Serien[1]
    Verify ($away.Heim -eq 'FC B' -and $away.Gast -eq 'Test FC' -and $away.HeimTore -eq 2 -and $away.GastTore -eq 1) 'Heim/Gast-Anzeige für ein Auswärtsspiel'
    Verify ($away.GastLogo -eq 'https://media.api-sports.io/football/teams/42.png' -and
        $p.Logo -eq 'https://media.api-sports.io/football/players/1.png' -and $p.Serien[0].LigaLogo -like '*/leagues/1.png') 'Team-, Wettbewerbslogos und Spielerfoto'
    $clubSeasons=@(Get-SoccerSeasons $c 'test-only')
    $playerSeasons=@(Get-SoccerSeasons $p 'test-only')
    Verify (($clubSeasons -join ',') -eq '2024,2023' -and ($playerSeasons -join ',') -eq '2024,2023' -and
        @($script:urls -like '*/teams/seasons?team=42').Count -eq 1 -and @($script:urls -like '*/players/seasons?player=1').Count -eq 1) 'Saisons pro Profil, absteigend und eindeutig'
    $oldCount=$script:urls.Count
    $suggest=@(Find-SoccerEntry Spieler 'Test' -ApiKey 'test-only' -FirstPage)
    Verify ($suggest.Count -eq 1 -and $script:urls.Count -eq $oldCount+1) 'Vorschläge brauchen nur die erste API-Seite'
    $failed=$false
    try { Invoke-FootballApi 'status-test' @{} 'test-only' } catch { $failed=$_.Exception.Message -like '*Saison gesperrt*' }
    Verify $failed 'HTTP 200 mit API-Fehler wird erkannt'
    & (Join-Path $root 'write.ps1') -Typ Club -Suche 'Test FC' -Saison 2024 -ApiKey 'test-only' -DataFile $file | Out-Null
    & (Join-Path $root 'write.ps1') -Eintrag $p -DataFile $file
    & (Join-Path $root 'write.ps1') -Eintrag $c -DataFile $file
    Verify (@(Read-SoccerStore $file).Count -eq 2) 'Erneutes Speichern aktualisiert denselben Favoriten'
    $filtered=@(& (Join-Path $root 'read.ps1') -Typ Spieler -Suche 'Test 1' -DataFile $file)
    Verify ($filtered.Count -eq 1 -and $filtered[0].Serien.Count -eq 2) 'Profil und Tafelwerte nach Neustart'
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
        # Ein temporärer API-Transport vermeidet Netzwerkanfragen und testet den echten UI-Worker.
        $workerRoot=Join-Path $dir 'worker'
        $workerSrc=Join-Path $workerRoot 'src'
        [void][IO.Directory]::CreateDirectory($workerSrc)
        $workerCore=Join-Path $workerSrc 'Soccer.ps1'
        Copy-Item (Join-Path $root 'src/Soccer.ps1') $workerCore
        $transport=(Get-Command Invoke-RestMethod -CommandType Function).Definition
        Add-Content -LiteralPath $workerCore -Encoding UTF8 -Value ("
function Invoke-RestMethod {
" + $transport + "
}")
        function Wait-ForUi([scriptblock]$Condition) {
            $until=[DateTime]::UtcNow.AddSeconds(12)
            while (!(& $Condition)) {
                if ([DateTime]::UtcNow -ge $until) { throw "UI-Zeitlimit: $($ui.Status.Text)" }
                $window.Dispatcher.Invoke([Action]{},[Windows.Threading.DispatcherPriority]::ApplicationIdle)
                Start-Sleep -Milliseconds 25
            }
        }
        . (Join-Path $root 'Start.ps1') -SmokeTest -DataFile $guiFile
        try {
            $SoccerRoot=$workerRoot
            $ui.KeyBox.Password='test-only'; Set-SessionKey
            $ui.Query.Text='Test FC'
            Wait-ForUi { $ui.Results.Items.Count -eq 1 }
            Verify ($ui.Results.SelectedIndex -eq -1 -and !$ui.Season.IsEnabled) 'Tippen zeigt echte Vorschläge ohne automatische Profilabfrage'
            $ui.Results.SelectedIndex=0
            Wait-ForUi { $state.entry.Saison -eq 2024 }
            Verify ($ui.Season.Items.Count -eq 2 -and $ui.Boards.Items[0].Score -eq '2 : 1' -and $ui.Boards.Items[0].Left -eq 'FC B') 'Saisonliste und jüngstes Auswärtsergebnis auf der Stadiontafel'
            $ui.Season.SelectedItem=[int]2023
            Wait-ForUi { $state.entry.Saison -eq 2023 }
            $ui.TypeBox.SelectedIndex=1
            Wait-ForUi { $ui.Results.Items.Count -eq 1 }
            $ui.Results.SelectedIndex=0
            Wait-ForUi { $state.entry.Typ -eq 'Spieler' }
            Verify ($ui.Boards.Items[0].Goals -eq '4' -and $ui.Boards.Items[1].Assists -eq '–' -and $ui.Portrait.DataContext.Logo -like '*/players/*.png') 'Spielertafel und Bildquelle wechseln mit der Auswahl'
            Submit-Search
            $ui.Query.Text='Te'
            Wait-ForUi { !$state.job }
            Verify ($ui.Results.Items.Count -eq 0 -and !$state.entry) 'Veraltete Antworten überschreiben keine neuere Eingabe'
        } finally { $window.Close() }
    } else { Write-Host 'WPF-Smoke-Test übersprungen (nur Windows).' }
} finally { Remove-Item -LiteralPath $dir -Recurse -Force }

# Gemeinsame Funktionen für die Oberfläche und die beiden Konsolenskripte.
$SoccerRoot = Split-Path $PSScriptRoot -Parent

function Invoke-FootballApi {
    param([string]$Endpoint, [hashtable]$Query, [string]$ApiKey, [switch]$FirstPage)
    if ([string]::IsNullOrWhiteSpace($ApiKey)) {
        throw 'Live-Modus braucht einen API-Key. Gib oben im Fenster den Schlüssel ein oder setze API_FOOTBALL_KEY vor dem Start.'
    }
    $parameters = foreach ($name in $Query.Keys) {
        '{0}={1}' -f $name, [Uri]::EscapeDataString([string]$Query[$name])
    }
    $uri = 'https://v3.football.api-sports.io/{0}?{1}' -f $Endpoint, ($parameters -join '&')
    $page = 1
    do {
        $url = $uri
        if ($page -gt 1) { $url += "&page=$page" }
        try {
            $data = Invoke-RestMethod -Uri $url -Headers @{'x-apisports-key'=$ApiKey} -TimeoutSec 25 -ErrorAction Stop
        } catch {
            throw "API-Anfrage an /$Endpoint fehlgeschlagen. Prüfe Verbindung, API-Key und Kontingent. $($_.Exception.Message)"
        }
        if ($null -eq $data) { return }
        if ($data.errors) {
            $message = ConvertTo-Json -InputObject $data.errors -Compress
            if ($message -notin '[]','{}') { throw "API-Football (/$Endpoint): $message" }
        }
        foreach ($item in $data.response) { if ($null -ne $item) { $item } }
        $page++
    } while (!$FirstPage -and $page -le [int]$data.paging.total)
}

function Get-SoccerPicture {
    param([string]$Url, [ValidateSet('teams','players','leagues')][string]$Kind, $Id)
    $address=$null
    if ([uri]::TryCreate($Url,[UriKind]::Absolute,[ref]$address) -and
        $address.Scheme -eq 'https' -and $address.Host.EndsWith('.api-sports.io')) {
        return $address.AbsoluteUri
    }
    if ([int]$Id -gt 0) { return "https://media.api-sports.io/football/$Kind/$Id.png" }
}

function Get-SoccerSeasons {
    param($Entry, [string]$ApiKey=$env:API_FOOTBALL_KEY)
    if ($Entry.Typ -eq 'Club') {
        $years=Invoke-FootballApi 'teams/seasons' @{team=$Entry.Id} $ApiKey
    } else {
        $years=Invoke-FootballApi 'players/seasons' @{player=$Entry.Id} $ApiKey
    }
    $years | Where-Object { [string]$_ -match '^(19|20)[0-9]{2}$' } |
        ForEach-Object { [int]$_ } | Sort-Object -Descending -Unique
}

function Find-SoccerEntry {
    param([ValidateSet('Club','Spieler')][string]$Typ, [string]$Suche, [int]$Saison,
          [string]$ApiKey = $env:API_FOOTBALL_KEY, [switch]$FirstPage)
    $term = $Suche.Trim()
    if ($term.Length -lt 4) { throw 'Gib für die Live-Suche mindestens vier Zeichen ein.' }
    $path = if ($Typ -eq 'Club') { 'teams' } else { 'players/profiles' }
    foreach ($item in (Invoke-FootballApi $path @{search=$term} $ApiKey -FirstPage:$FirstPage)) {
        if ($Typ -eq 'Club') {
            $id = $item.team.id; $name = $item.team.name; $country = $item.team.country
            $logo = Get-SoccerPicture $item.team.logo teams $id; $stadium = $item.venue.name; $founded = $item.team.founded
        } else {
            $id = $item.player.id; $name = $item.player.name; $country = $item.player.nationality
            $logo = Get-SoccerPicture $item.player.photo players $id; $stadium = $null; $founded = $null
        }
        [pscustomobject]@{ Typ=$Typ; Id=$id; Name=$name; Land=$country; Logo=$logo; Stadion=$stadium
            Gruendungsjahr=$founded; Saison=$Saison; Quelle='API-Football' }
    }
}

function Get-KnownTotal {
    param([object[]]$Values)
    # Ohne vollständige Abdeckung ist eine exakte Summe unbekannt.
    if (!$Values.Count -or $Values -contains $null) { return $null }
    return ($Values | Measure-Object -Sum).Sum
}

function Get-SoccerDetail {
    param($Entry, [string]$ApiKey = $env:API_FOOTBALL_KEY)
    $extra = [ordered]@{ Aktualisiert=(Get-Date).ToString('o'); Verein=$null; Position=$null
        Einsaetze=$null; Tore=$null; Assists=$null; Gegentore=$null; Siege=$null; Remis=$null
        Niederlagen=$null; Startelf=$null; Minuten=$null; Serien=@(); Hinweis='' }
    if ($Entry.Typ -eq 'Spieler') {
        $players = @(Invoke-FootballApi 'players' @{id=$Entry.Id; season=$Entry.Saison} $ApiKey)
        $stats = @($players | ForEach-Object { $_.statistics } | Where-Object { $null -ne $_ })
        if ($stats.Count) {
            $extra.Verein = (($stats | ForEach-Object { $_.team.name } | Select-Object -Unique) -join ' / ')
            $extra.Position = $stats[0].games.position
            $extra.Einsaetze = Get-KnownTotal ($stats | ForEach-Object { $_.games.appearences })
            $extra.Tore = Get-KnownTotal ($stats | ForEach-Object { $_.goals.total })
            $extra.Assists = Get-KnownTotal ($stats | ForEach-Object { $_.goals.assists })
            $extra.Startelf = Get-KnownTotal ($stats | ForEach-Object { $_.games.lineups })
            $extra.Minuten = Get-KnownTotal ($stats | ForEach-Object { $_.games.minutes })
            $extra.Serien = @(foreach ($s in $stats) {
                [pscustomobject]@{ Label=("$($s.league.name) · $($s.team.name)")
                    Wettbewerb=$s.league.name; Team=$s.team.name
                    LigaLogo=(Get-SoccerPicture $s.league.logo leagues $s.league.id)
                    TeamLogo=(Get-SoccerPicture $s.team.logo teams $s.team.id)
                    A=$s.goals.total; B=$s.goals.assists }
            })
        } else { $extra.Hinweis = 'Keine Spielerstatistik für diese Saison verfügbar.' }
    } else {
        $fixtures = @(Invoke-FootballApi 'fixtures' @{team=$Entry.Id; season=$Entry.Saison} $ApiKey)
        $games = @(foreach ($f in ($fixtures | Sort-Object { [long]$_.fixture.timestamp })) {
            if ($f.fixture.status.short -notin 'FT','AET','PEN') { continue }
            if ($null -eq $f.goals.home -or $null -eq $f.goals.away) { continue }
            $isHomeGame = $f.teams.home.id -eq $Entry.Id
            if ($isHomeGame) { $a=$f.goals.home; $b=$f.goals.away; $opp=$f.teams.away.name }
            else { $a=$f.goals.away; $b=$f.goals.home; $opp=$f.teams.home.name }
            $date = [DateTimeOffset]::FromUnixTimeSeconds([long]$f.fixture.timestamp).UtcDateTime
            [pscustomobject]@{ Label=("{0:dd.MM.} · {1}" -f $date,$opp)
                Datum=$date.ToString('dd.MM.yyyy'); Heim=$f.teams.home.name; Gast=$f.teams.away.name
                HeimLogo=(Get-SoccerPicture $f.teams.home.logo teams $f.teams.home.id)
                GastLogo=(Get-SoccerPicture $f.teams.away.logo teams $f.teams.away.id)
                HeimTore=$f.goals.home; GastTore=$f.goals.away; Status=$f.fixture.status.short
                ElferHeim=$f.score.penalty.home; ElferGast=$f.score.penalty.away
                A=[int]$a; B=[int]$b }
        })
        if ($games.Count) {
            $extra.Einsaetze = $games.Count
            $extra.Tore = Get-KnownTotal $games.A
            $extra.Gegentore = Get-KnownTotal $games.B
            $extra.Siege = @($games | Where-Object { $_.A -gt $_.B }).Count
            $extra.Remis = @($games | Where-Object { $_.A -eq $_.B }).Count
            $extra.Niederlagen = @($games | Where-Object { $_.A -lt $_.B }).Count
            $extra.Serien = @($games | Select-Object -Last 5)
        } else { $extra.Hinweis = 'Keine beendeten Spiele mit Resultat in dieser Saison verfügbar.' }
    }
    foreach ($key in $extra.Keys) {
        $Entry | Add-Member -NotePropertyName $key -NotePropertyValue $extra[$key] -Force
    }
    return $Entry
}

function Get-EntryKey {
    param($Entry)
    return "$($Entry.Typ)/$($Entry.Id)/$($Entry.Saison)"
}

function Read-SoccerStore {
    param([string]$Path)
    if (-not [IO.File]::Exists($Path)) { return }
    try {
        $doc = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        if ($null -eq $doc -or !$doc.PSObject.Properties['Eintraege'] -or $doc.Eintraege -isnot [array]) {
            throw 'Das Feld Eintraege muss eine Liste sein.'
        }
        foreach ($row in $doc.Eintraege) {
            # Originaldateien haben keine Quelle. Neue Profile stammen aus API-Football.
            if ($null -ne $row -and (!$row.Quelle -or $row.Quelle -eq 'API-Football')) { $row }
        }
    } catch { throw "Lokale Daten konnten nicht gelesen werden ($Path): $($_.Exception.Message)" }
}

function Update-SoccerStore {
    param([string]$Path, [object[]]$Entries, [switch]$Remove)
    $Path = [IO.Path]::GetFullPath($Path)
    $dir = [IO.Path]::GetDirectoryName($Path)
    [void][IO.Directory]::CreateDirectory($dir)
    # Ein stabiler Lock serialisiert Read-Modify-Write auch zwischen GUI und CLI.
    $lock = $null
    $temp = Join-Path $dir ([guid]::NewGuid().ToString() + '.tmp')
    try {
        $deadline = [datetime]::UtcNow.AddSeconds(4)
        while (!$lock) {
            try { $lock = [IO.File]::Open("$Path.lock",'OpenOrCreate','ReadWrite','None') }
            catch [IO.IOException] {
                if ([datetime]::UtcNow -ge $deadline) { throw 'Datendatei ist belegt. Bitte erneut versuchen.' }
                Start-Sleep -Milliseconds 80
            }
        }
        $rows = [ordered]@{}
        foreach ($e in (Read-SoccerStore $Path)) { $rows[(Get-EntryKey $e)] = $e }
        foreach ($e in $Entries) {
            $key = Get-EntryKey $e
            if ($Remove) { $rows.Remove($key) } else { $rows[$key] = $e }
        }
        $doc = [ordered]@{ Aktualisiert=(Get-Date).ToString('o'); Eintraege=@($rows.Values) }
        $json = ConvertTo-Json -InputObject $doc -Depth 15
        [IO.File]::WriteAllText($temp,$json,(New-Object System.Text.UTF8Encoding($false)))
        if ([IO.File]::Exists($Path)) {
            [IO.File]::Replace($temp,$Path,[System.Management.Automation.Language.NullString]::Value)
        } else { [IO.File]::Move($temp,$Path) }
    } finally {
        if ([IO.File]::Exists($temp)) { [IO.File]::Delete($temp) }
        if ($lock) { $lock.Dispose() }
    }
}

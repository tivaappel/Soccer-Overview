# Desktop-Startpunkt. Die Datenlogik in src/Soccer.ps1 ist unabhängig von WPF.
[CmdletBinding()]
param([switch]$SmokeTest, [string]$DataFile)
$ErrorActionPreference = 'Stop'
if (!$DataFile) { $DataFile=Join-Path $PSScriptRoot 'data/football.json' }
if ($env:OS -ne 'Windows_NT') { throw 'Die WPF-Oberfläche braucht Windows. read.ps1 und write.ps1 laufen auch mit PowerShell 7 unter Linux.' }
if ([Threading.Thread]::CurrentThread.ApartmentState -ne 'STA') { throw 'Starte Start.cmd oder powershell.exe -STA -File .\Start.ps1.' }
Add-Type -AssemblyName PresentationFramework
. (Join-Path $PSScriptRoot 'src/Soccer.ps1')
[xml]$layout = Get-Content (Join-Path $PSScriptRoot 'ui/Dashboard.xaml') -Raw -Encoding UTF8
$reader = New-Object System.Xml.XmlNodeReader $layout
try { $window = [Windows.Markup.XamlReader]::Load($reader) } finally { $reader.Close() }
$screen = [Windows.SystemParameters]::WorkArea
$window.Width = [Math]::Min($window.Width,$screen.Width)
$window.Height = [Math]::Min($window.Height,$screen.Height)
$ui = @{}
$ns = New-Object Xml.XmlNamespaceManager($layout.NameTable)
$ns.AddNamespace('x','http://schemas.microsoft.com/winfx/2006/xaml')
foreach ($node in $layout.SelectNodes('//*[@x:Name]', $ns)) {
    $name = $node.GetAttribute('Name','http://schemas.microsoft.com/winfx/2006/xaml')
    $control = $window.FindName($name)
    if ($null -ne $control) { $ui[$name] = $control }
}
$state = @{
    tab='Suche'; entry=$null; saved=@(); updating=$false; apiKey=$env:API_FOOTBALL_KEY
    revision=0; job=$null; pending=$null; searches=@{}; seasons=@{}; allowedYears=$null
}
$window.AddHandler([Windows.Controls.Image]::ImageFailedEvent, [System.EventHandler[Windows.ExceptionRoutedEventArgs]]{
    param($sender,$event)
    $event.Handled=$true
    if ($event.OriginalSource -is [Windows.Controls.Image]) {
        $event.OriginalSource.SetCurrentValue([Windows.Controls.Image]::SourceProperty,$window.Resources['ImageFallback'])
    }
})

function Set-Status([string]$Message,[switch]$ErrorState) {
    $ui.Status.Text=$Message
    $ui.Status.Foreground = if ($ErrorState) { '#992F28' } else { '#365344' }
}
function Format-Value($Value) {
    if ($null -eq $Value -or [string]$Value -eq '') { return '–' }
    return [string]$Value
}
function New-NumberTile([string]$Label,$Value) {
    [pscustomobject]@{Label=$Label; Number=(Format-Value $Value)}
}
function Show-Profile($Entry,[switch]$IdentityOnly) {
    $player=$null -ne $Entry -and $Entry.Typ -eq 'Spieler'
    $ready=$null -ne $Entry -and !$IdentityOnly
    $state.entry=if ($ready) { $Entry }
    $ui.PinButton.IsEnabled=$ready
    $ui.PinButton.Content=if ($state.tab -eq 'Favoriten') { 'Favorit entfernen' } else { 'Favorit speichern' }
    $ui.Portrait.DataContext=$Entry
    $ui.SourceTag.Text=if (!$Entry) { '' } elseif ($state.tab -eq 'Favoriten') { 'LOKAL GESPEICHERT' } else { 'API-FOOTBALL' }
    if ($Entry) {
        $ui.Badge.Text=$Entry.Typ.ToUpperInvariant()
        if ($ready -and $Entry.Saison) { $ui.Badge.Text+="   /   SAISON $($Entry.Saison)" }
        $ui.Profile.Text=$Entry.Name
        $meta=if ($player) { $Entry.Verein; $Entry.Land; $Entry.Position } else { $Entry.Land; $Entry.Stadion; if ($Entry.Gruendungsjahr) { "Gegründet $($Entry.Gruendungsjahr)" } }
        $ui.Meta.Text=(@($meta | Where-Object { $_ }) -join '  ·  ')
    } else {
        $ui.Badge.Text='SOCCER OVERVIEW'; $ui.Profile.Text='Stadiontafel'
        $ui.Meta.Text='Wähle links einen Club oder Spieler.'
    }
    $ui.SeriesTitle.Text=if ($player) { 'Wettbewerbe' } else { 'Letzte Ergebnisse' }
    $ui.BalanceTitle.Text=if ($player) { 'Einsatzprofil' } else { 'Ergebnisbilanz' }
    $ui.Totals.ItemsSource=$null; $ui.Balance.ItemsSource=$null; $ui.Boards.ItemsSource=$null
    $ui.EmptyHint.Visibility='Visible'
    if (!$ready) {
        $ui.EmptyHint.Text=if ($Entry) { 'Wähle eine verfügbare Saison für die Anzeigetafel.' } else { 'Gib einen Namen ein und wähle einen Suchvorschlag.' }
        return
    }
    $ui.Totals.ItemsSource=if ($player) {
        @(New-NumberTile 'EINSÄTZE' $Entry.Einsaetze; New-NumberTile 'TORE' $Entry.Tore; New-NumberTile 'ASSISTS' $Entry.Assists)
    } else {
        @(New-NumberTile 'SPIELE' $Entry.Einsaetze; New-NumberTile 'TORE' $Entry.Tore; New-NumberTile 'GEGENTORE' $Entry.Gegentore)
    }
    if ($player) {
        $sub=$null
        if ($null -ne $Entry.Einsaetze -and $null -ne $Entry.Startelf) { $sub=$Entry.Einsaetze-$Entry.Startelf }
        $ui.Balance.ItemsSource=@(New-NumberTile 'STARTELF' $Entry.Startelf; New-NumberTile 'EINGEWECHSELT' $sub; New-NumberTile 'MINUTEN' $Entry.Minuten)
        $ui.Boards.ItemTemplate=$window.Resources['PlayerRow']
        $rows=@(foreach ($r in $Entry.Serien) {
            $league=if ($r.Wettbewerb) { $r.Wettbewerb } else { $r.Label }
            [pscustomobject]@{ Left=$league; Right=$r.Team; LeftLogo=$r.LigaLogo; RightLogo=$r.TeamLogo
                Goals=(Format-Value $r.A); Assists=(Format-Value $r.B) }
        })
    } else {
        $ui.Balance.ItemsSource=@(New-NumberTile 'SIEGE' $Entry.Siege; New-NumberTile 'REMIS' $Entry.Remis; New-NumberTile 'NIEDERLAGEN' $Entry.Niederlagen)
        $ui.Boards.ItemTemplate=$window.Resources['MatchRow']
        $series=@($Entry.Serien | Where-Object { $null -ne $_ })
        $rows=@(for ($i=$series.Count-1; $i -ge 0; $i--) {
            $r=$series[$i]
            if ($r.Heim -and $r.Gast) {
                $caption="$($r.Datum)   ·   HEIM / GAST"
                if ($r.Status -eq 'PEN') { $caption+="   ·   i. E. $(Format-Value $r.ElferHeim):$(Format-Value $r.ElferGast)" }
                elseif ($r.Status -eq 'AET') { $caption+='   ·   n. V.' }
                [pscustomobject]@{Left=$r.Heim; Right=$r.Gast; LeftLogo=$r.HeimLogo; RightLogo=$r.GastLogo
                    Caption=$caption; Score="$(Format-Value $r.HeimTore) : $(Format-Value $r.GastTore)"}
            } else {
                # Ältere Favoriten enthalten nur Tore aus Sicht des ausgewählten Clubs.
                [pscustomobject]@{Left=$Entry.Name; Right='Gegner'; LeftLogo=$Entry.Logo; RightLogo=$null
                    Caption="$($r.Label)  ·  Clubsicht"; Score="$(Format-Value $r.A) : $(Format-Value $r.B)"}
            }
        })
    }
    $ui.Boards.ItemsSource=$rows
    if ($rows.Count) { $ui.EmptyHint.Visibility='Collapsed' }
    elseif ($Entry.Hinweis) { $ui.EmptyHint.Text=$Entry.Hinweis }
    else { $ui.EmptyHint.Text='Für diese Saison sind keine Einzelwerte verfügbar.' }
}

function Invalidate-Request {
    $state.revision++; $state.pending=$null; $debounce.Stop()
}
function Set-SeasonList([int[]]$Years) {
    $state.updating=$true
    try {
        $ui.Season.ItemsSource=$null; $ui.Season.ItemsSource=$Years
        $ui.Season.IsEnabled=$state.tab -eq 'Suche' -and $Years.Count -gt 0
        if ($Years.Count) { $ui.Season.SelectedIndex=0 }
    } finally { $state.updating=$false }
}
function Set-Results([object[]]$Rows,[string]$Title,[switch]$AutoSelect) {
    Set-SeasonList @()
    $state.updating=$true
    try { $ui.Results.ItemsSource=$null; $ui.Results.ItemsSource=$Rows; Show-Profile $null }
    finally { $state.updating=$false }
    $ui.ResultsTitle.Text="$Title   /   $($Rows.Count)"
    if ($AutoSelect -and $Rows.Count) { $ui.Results.SelectedIndex=0 }
}

# Nur der letzte Stand darf die Oberfläche aktualisieren. Während einer Anfrage bleibt die Suche editierbar.
function Start-Request([string]$Kind,[hashtable]$Options,[string]$CacheKey='') {
    $request=@{Kind=$Kind; Options=$Options; CacheKey=$CacheKey; Revision=$state.revision}
    if ($state.job) { $state.pending=$request; return }
    $shell=[PowerShell]::Create()
    [void]$shell.AddScript({
        param($Path,$Kind,$Options)
        $ErrorActionPreference='Stop'
        . $Path
        switch ($Kind) {
            'Vorschläge' { Find-SoccerEntry @Options -FirstPage | Select-Object -First 12 }
            'Suche'      { Find-SoccerEntry @Options }
            'Saisons'    { Get-SoccerSeasons @Options }
            'Profil'     { Get-SoccerDetail @Options }
        }
    }).AddArgument((Join-Path $SoccerRoot 'src/Soccer.ps1')).AddArgument($Kind).AddArgument($Options)
    try { $request.Handle=$shell.BeginInvoke() } catch { $shell.Dispose(); throw }
    $request.Shell=$shell; $state.job=$request
    $message=switch ($Kind) {
        'Profil' { 'Saisonstatistik wird geladen …' }
        'Saisons' { 'Verfügbare Saisons werden geladen …' }
        default { 'Suche läuft …' }
    }
    Set-Status $message
    $timer.Start()
}
function Show-SearchResults([object[]]$Rows,[string]$Kind) {
    if ($Rows.Count) { Set-Status 'Wähle einen Treffer, um seine Saisons anzuzeigen.' }
    else { Set-Status 'Keine Treffer. Prüfe den Clubnamen oder den Nachnamen.' }
    Set-Results $Rows $(if ($Kind -eq 'Vorschläge') { 'VORSCHLÄGE' } else { 'TREFFER' }) -AutoSelect:($Kind -eq 'Suche' -and $Rows.Count -eq 1)
}
function Find-Selection([switch]$Suggest) {
    if ($state.tab -ne 'Suche') { return }
    $term=$ui.Query.Text.Trim()
    if (!$state.apiKey) { Set-Status 'Gib oben deinen API-Football-Key ein.'; return }
    if ($term.Length -lt 4) { Set-Status 'Gib mindestens vier Zeichen für Suchvorschläge ein.'; return }
    $kind=if ($Suggest) { 'Vorschläge' } else { 'Suche' }
    $type=[string]$ui.TypeBox.SelectedItem.Content
    $key="$kind/$type/$term"
    if ($state.searches.ContainsKey($key)) { Show-SearchResults $state.searches[$key] $kind; return }
    Start-Request $kind @{Typ=$type; Suche=$term; ApiKey=$state.apiKey} $key
}
function Load-Season {
    $item=$ui.Results.SelectedItem; $year=$ui.Season.SelectedItem
    if (!$item -or !$year -or $state.tab -ne 'Suche') { return }
    Invalidate-Request
    Show-Profile $item -IdentityOnly
    $selected=$item.PSObject.Copy(); $selected.Saison=[int]$year
    Start-Request 'Profil' @{Entry=$selected; ApiKey=$state.apiKey}
}
function Show-Seasons([int[]]$Years) {
    if ($state.allowedYears) { $Years=@($Years | Where-Object { $state.allowedYears -contains $_ }) }
    Set-SeasonList $Years
    if ($Years.Count) { Load-Season }
    else { Set-Status 'Für dieses Profil ist keine anzeigbare Saison verfügbar.' }
}
function Read-Favorites {
    $state.saved=@(& (Join-Path $SoccerRoot 'read.ps1') -DataFile $DataFile)
    $ui.FavTab.Content="Favoriten ($($state.saved.Count))"
}
function Show-Tab([string]$Name) {
    Invalidate-Request
    $state.tab=$Name; $search=$Name -eq 'Suche'
    $ui.SearchFields.Visibility=if ($search) { 'Visible' } else { 'Collapsed' }
    $ui.SearchTab.Background=if ($search) { '#C9EDDA' } else { '#EAF0EC' }
    $ui.FavTab.Background=if ($search) { '#EAF0EC' } else { '#C9EDDA' }
    if ($search) {
        Set-Results @() 'VORSCHLÄGE'
        if ($state.apiKey) { Find-Selection -Suggest }
        else { Set-Status 'Gib oben deinen API-Football-Key ein. Gespeicherte Favoriten kannst du auch offline öffnen.' }
    } else {
        try {
            Read-Favorites
            Set-Status 'Deine lokal gespeicherten Profile.'
            Set-Results $state.saved 'GESPEICHERT' -AutoSelect
            if (!$state.saved.Count) { Set-Status 'Noch keine Favoriten. Öffne ein Profil und wähle «Favorit speichern».' }
        } catch { Set-Results @() 'GESPEICHERT'; Set-Status $_.Exception.Message -ErrorState }
    }
}

$timer=[Windows.Threading.DispatcherTimer]::new()
$timer.Interval=[TimeSpan]::FromMilliseconds(100)
$timer.Add_Tick({
    $job=$state.job
    if (!$job -or !$job.Handle.IsCompleted) { return }
    $timer.Stop(); $state.job=$null
    try {
        $rows=@($job.Shell.EndInvoke($job.Handle))
        if ($job.Shell.HadErrors) { throw [string]$job.Shell.Streams.Error[0] }
        if ($job.Revision -eq $state.revision) {
            switch ($job.Kind) {
                'Saisons' { $state.seasons[$job.CacheKey]=$rows; Show-Seasons $rows }
                'Profil'  { Show-Profile $rows[0]; Set-Status 'Saisonstatistik geladen.' }
                default   { $state.searches[$job.CacheKey]=$rows; Show-SearchResults $rows $job.Kind }
            }
        }
    } catch {
        if ($job.Revision -eq $state.revision) {
            $message=$_.Exception.Message
            # Manche Tarife melden den tatsächlich freigegebenen Zeitraum erst beim Detailaufruf.
            if ($job.Kind -eq 'Profil' -and $message -match '(?i)season.{0,120}?from\s+(20\d{2})\s+to\s+(20\d{2})') {
                $first=[int]$Matches[1]; $last=[int]$Matches[2]
                if ($first -le $last -and ($job.Options.Entry.Saison -notin ($first..$last))) {
                    $state.allowedYears=$first..$last
                    Show-Seasons @($ui.Season.ItemsSource)
                } else { Set-Status $message -ErrorState }
            } else { Set-Status $message -ErrorState }
        }
    } finally {
        $job.Shell.Dispose()
        $next=$state.pending; $state.pending=$null
        if ($next -and $next.Revision -eq $state.revision -and !$state.job) {
            Start-Request $next.Kind $next.Options $next.CacheKey
        }
    }
})
$debounce=[Windows.Threading.DispatcherTimer]::new()
$debounce.Interval=[TimeSpan]::FromMilliseconds(500)
$debounce.Add_Tick({ $debounce.Stop(); Find-Selection -Suggest })
$ui.Query.Add_TextChanged({
    if ($state.tab -ne 'Suche') { return }
    Invalidate-Request; Set-Results @() 'VORSCHLÄGE'
    if ($ui.Query.Text.Trim().Length -ge 4 -and $state.apiKey) { $debounce.Start() }
    elseif ($state.apiKey) { Set-Status 'Gib mindestens vier Zeichen für Suchvorschläge ein.' }
})
$ui.Results.Add_SelectionChanged({
    if ($state.updating) { return }
    Invalidate-Request; Set-SeasonList @()
    $item=$ui.Results.SelectedItem
    if (!$item) { Show-Profile $null; return }
    if ($state.tab -eq 'Favoriten') {
        if ($item.Saison) { Set-SeasonList @([int]$item.Saison) }
        Show-Profile $item; return
    }
    Show-Profile $item -IdentityOnly
    $key="$($item.Typ)/$($item.Id)"
    if ($state.seasons.ContainsKey($key)) { Show-Seasons $state.seasons[$key] }
    else { Start-Request 'Saisons' @{Entry=$item; ApiKey=$state.apiKey} $key }
})
$ui.Season.Add_SelectionChanged({ if (!$state.updating) { Load-Season } })
$ui.PinButton.Add_Click({
    try {
        if (!$state.entry) { return }
        $remove=$state.tab -eq 'Favoriten'
        & (Join-Path $SoccerRoot 'write.ps1') -Eintrag $state.entry -DataFile $DataFile -Entfernen:$remove
        if ($remove) { Show-Tab 'Favoriten'; Set-Status 'Favorit entfernt.' }
        else { Read-Favorites; Set-Status "$($state.entry.Name) ist in den Favoriten gespeichert." }
    } catch { Set-Status $_.Exception.Message -ErrorState }
})
function Submit-Search { Invalidate-Request; Set-Results @() 'TREFFER'; Find-Selection }
$ui.SearchButton.Add_Click({ Submit-Search })
$ui.Query.Add_KeyDown({ param($sender,$e)
    if ($e.Key -eq 'Return') { Submit-Search; $e.Handled=$true }
    if ($e.Key -eq 'Down' -and $ui.Results.Items.Count) {
        $ui.Results.SelectedIndex=0; [void]$ui.Results.Focus(); $e.Handled=$true
    }
})
$ui.SearchTab.Add_Click({ Show-Tab 'Suche' }); $ui.FavTab.Add_Click({ Show-Tab 'Favoriten' })
$ui.TypeBox.Add_SelectionChanged({ if ($state.tab -eq 'Suche') { Show-Tab 'Suche' } })
function Set-SessionKey {
    $key=$ui.KeyBox.Password.Trim()
    if (!$key) { Set-Status 'Gib zuerst deinen API-Football-Key ein.' -ErrorState; return }
    $state.apiKey=$key; $state.allowedYears=$null; $state.searches.Clear(); $state.seasons.Clear()
    $ui.KeyBox.Clear(); $ui.KeyStatus.Text='API-Key gesetzt'
    Show-Tab 'Suche'
}
$ui.KeyStatus.Text=if ($state.apiKey) { 'API-Key gesetzt' } else { 'API-Key fehlt' }
$ui.ApplyKey.Add_Click({ Set-SessionKey })
$ui.KeyBox.Add_KeyDown({ param($sender,$e) if ($e.Key -eq 'Return') { Set-SessionKey; $e.Handled=$true } })
$window.Add_Closed({
    $debounce.Stop(); $timer.Stop()
    if ($state.job) { $state.job.Shell.Stop(); $state.job.Shell.Dispose(); $state.job=$null }
})
Show-Tab 'Suche'
try { Read-Favorites } catch { Set-Status $_.Exception.Message -ErrorState }
if ($SmokeTest) {
    if ($ui.Profile.Text -ne 'Stadiontafel' -or $ui.Season.IsEnabled) { throw 'Startansicht fehlerhaft.' }
    Show-Tab 'Favoriten'
    foreach ($profile in $state.saved) {
        $ui.Results.SelectedItem=$profile
        if ($ui.Profile.Text -ne $profile.Name -or $ui.Totals.Items[1].Number -ne (Format-Value $profile.Tore)) { throw 'Profilwerte fehlerhaft.' }
        if ($profile.Serien -and $ui.Boards.Items.Count -ne $profile.Serien.Count) { throw 'Anzeigetafel fehlerhaft.' }
        if ($profile.Saison -and $ui.Season.SelectedItem -ne $profile.Saison) { throw 'Gespeicherte Saison fehlt.' }
    }
    if ($MyInvocation.InvocationName -ne '.') { $window.Close() }
    return 'WPF-Smoke-Test bestanden.'
}
[void]$window.ShowDialog()

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
$state = @{ tab='Suche'; entry=$null; saved=@(); job=$null; updating=$false; apiKey=$env:API_FOOTBALL_KEY }
$today=Get-Date
$year=$today.Year
if ($today.Month -lt 7) { $year-- }
$ui.Season.Text=[string]$year
$green = '#1D7850'; $blue = '#5D7EB3'

function Set-Status([string]$Message,[switch]$ErrorState) {
    $ui.Status.Text=$Message
    $ui.Status.Foreground = if ($ErrorState) { '#992F28' } else { '#365344' }
}
function Format-Value($Value) {
    if ($null -eq $Value -or [string]$Value -eq '') { return '–' }
    return [string]$Value
}
function Add-ChartNote($Panel,[string]$Message) {
    $label=[Windows.Controls.TextBlock]::new()
    $label.Text=$Message; $label.TextWrapping='Wrap'; $label.Foreground='#52695D'
    $label.Margin='0,4,0,3'; [void]$Panel.Children.Add($label)
}
function New-BarTrack($Value,[double]$Maximum,[string]$Color) {
    $row=[Windows.Controls.Grid]::new()
    $last=[Windows.Controls.ColumnDefinition]::new(); $last.Width=36
    [void]$row.ColumnDefinitions.Add([Windows.Controls.ColumnDefinition]::new())
    [void]$row.ColumnDefinitions.Add($last)
    $valueText=[Windows.Controls.TextBlock]::new(); $valueText.Text=(Format-Value $Value)
    $valueText.FontSize=12; $valueText.TextAlignment='Right'
    [Windows.Controls.Grid]::SetColumn($valueText,1); [void]$row.Children.Add($valueText)
    $track=[Windows.Controls.Border]::new(); $track.Height=7; $track.CornerRadius=3
    $track.Background='#EAF0EC'; $grid=[Windows.Controls.Grid]::new(); $track.Child=$grid
    if ($null -ne $Value -and [double]$Value -gt 0) {
        $fill=[Windows.Controls.ColumnDefinition]::new()
        $fill.Width=[Windows.GridLength]::new([double]$Value,'Star')
        $space=[Windows.Controls.ColumnDefinition]::new()
        $space.Width=[Windows.GridLength]::new([Math]::Max(0, $Maximum-[double]$Value),'Star')
        [void]$grid.ColumnDefinitions.Add($fill); [void]$grid.ColumnDefinitions.Add($space)
        $bar=[Windows.Controls.Border]::new(); $bar.Background=$Color; $bar.CornerRadius=3
        [void]$grid.Children.Add($bar)
    }
    [void]$row.Children.Add($track)
    return $row
}
function Add-ChartRows($Panel,[array]$Rows,[switch]$Pair) {
    if (!$Rows.Count) { Add-ChartNote $Panel 'Für diese Auswahl sind keine Diagrammdaten verfügbar.'; return }
    $max=1.0
    foreach ($r in $Rows) { $max=[Math]::Max($max,[double]$r.A); if ($Pair) { $max=[Math]::Max($max,[double]$r.B) } }
    foreach ($r in $Rows) {
        $row=[Windows.Controls.Grid]::new(); $row.Margin='0,3,0,3'
        $left=[Windows.Controls.ColumnDefinition]::new(); $left.Width=[Windows.GridLength]::new(0.85,'Star')
        $right=[Windows.Controls.ColumnDefinition]::new(); $right.Width=[Windows.GridLength]::new(2,'Star')
        [void]$row.ColumnDefinitions.Add($left); [void]$row.ColumnDefinitions.Add($right)
        $label=[Windows.Controls.TextBlock]::new(); $label.Text=$r.Label; $label.FontSize=12
        $label.VerticalAlignment='Center'; $label.Margin='0,0,10,0'; $label.TextWrapping='Wrap'
        [void]$row.Children.Add($label)
        $bars=[Windows.Controls.StackPanel]::new()
        [void]$bars.Children.Add((New-BarTrack $r.A $max $green))
        if ($Pair) { [void]$bars.Children.Add((New-BarTrack $r.B $max $blue)) }
        [Windows.Controls.Grid]::SetColumn($bars,1); [void]$row.Children.Add($bars)
        [void]$Panel.Children.Add($row)
    }
}
function Show-Profile($Entry) {
    $state.entry=$Entry
    $ui.SeriesPanel.Children.Clear(); $ui.BalancePanel.Children.Clear()
    $ui.PinButton.IsEnabled=$null -ne $Entry
    $ui.SourceTag.Text=''
    $ui.Legend.Visibility='Collapsed'
    $ui.V1.Text='–'; $ui.V2.Text='–'; $ui.V3.Text='–'
    $ui.K1.Text='SPIELE'; $ui.K2.Text='TORE'; $ui.K3.Text='GEGENTORE'
    if ($null -eq $Entry) {
        $ui.Badge.Text='SOCCER OVERVIEW'; $ui.Profile.Text='Spielanalyse'; $ui.Meta.Text='Suche links einen Club oder Spieler, um seine Saison zu analysieren.'
        $ui.SeriesTitle.Text='Saisonvergleich'; $ui.BalanceTitle.Text='Saisonbilanz'; $ui.PinButton.Content='Favorit speichern'
        Add-ChartNote $ui.SeriesPanel 'Hier erscheinen die Werte der ausgewählten Saison.'
        return
    }
    $ui.SourceTag.Text = if ($state.tab -eq 'Favoriten') { 'LOKAL GESPEICHERT' } else { 'API-FOOTBALL' }
    $ui.Badge.Text = ('{0}   /   SAISON {1}' -f $Entry.Typ.ToUpperInvariant(), (Format-Value $Entry.Saison))
    $ui.Profile.Text=$Entry.Name
    $player=$Entry.Typ -eq 'Spieler'
    $meta = if ($player) { $Entry.Verein; $Entry.Land; $Entry.Position } else { $Entry.Land; $Entry.Stadion; if ($Entry.Gruendungsjahr) { "Gegründet $($Entry.Gruendungsjahr)" } }
    $ui.Meta.Text = (@($meta | Where-Object { $_ }) -join '  ·  ')
    $ui.PinButton.Content = if ($state.tab -eq 'Favoriten') { 'Favorit entfernen' } else { 'Favorit speichern' }
    $ui.K1.Text=if ($player) { 'EINSÄTZE' } else { 'SPIELE' }; $ui.K3.Text=if ($player) { 'ASSISTS' } else { 'GEGENTORE' }
    $ui.V1.Text=Format-Value $Entry.Einsaetze; $ui.V2.Text=Format-Value $Entry.Tore
    $third=if ($player) { $Entry.Assists } else { $Entry.Gegentore }; $ui.V3.Text=Format-Value $third
    $ui.SeriesTitle.Text=if ($player) { 'Scorer nach Wettbewerb' } else { 'Tore der letzten fünf Spiele' }
    $ui.LegendA.Text='Tore'; $ui.LegendB.Text=if ($player) { 'Assists' } else { 'Gegentore' }
    if ($Entry.Serien) { $ui.Legend.Visibility='Visible' }
    Add-ChartRows $ui.SeriesPanel @($Entry.Serien | Where-Object { $null -ne $_ }) -Pair
    if ($Entry.Hinweis) { Add-ChartNote $ui.SeriesPanel $Entry.Hinweis }
    if ($player) {
        $ui.BalanceTitle.Text='Einsatzprofil'
        $sub=$null
        if ($null -ne $Entry.Einsaetze -and $null -ne $Entry.Startelf) { $sub=$Entry.Einsaetze-$Entry.Startelf }
        Add-ChartRows $ui.BalancePanel @(@{Label='Startelf';A=$Entry.Startelf},@{Label='Eingewechselt';A=$sub})
        Add-ChartNote $ui.BalancePanel ("Spielminuten: $(Format-Value $Entry.Minuten)")
    } else {
        $ui.BalanceTitle.Text='Ergebnisbilanz'
        Add-ChartRows $ui.BalancePanel @(@{Label='Siege';A=$Entry.Siege},@{Label='Remis';A=$Entry.Remis},@{Label='Niederlagen';A=$Entry.Niederlagen})
    }
}
function Set-Results([object[]]$Rows,[switch]$AutoSelect) {
    $state.updating=$true
    try { $ui.Results.ItemsSource=$null; Show-Profile $null; $ui.Results.ItemsSource=$Rows }
    finally { $state.updating=$false }
    $label=if ($state.tab -eq 'Suche') { 'TREFFER' } else { 'GESPEICHERT' }
    $ui.ResultsTitle.Text="$label  /  $($Rows.Count)"
    if ($AutoSelect -and $Rows.Count) { $ui.Results.SelectedIndex=0 }
}
function Start-LiveRequest([string]$Kind,[hashtable]$Options) {
    if ($state.job) { return }
    $shell=[PowerShell]::Create()
    [void]$shell.AddScript({
        param($Path,$Kind,$Options)
        $ErrorActionPreference='Stop'
        . $Path
        if ($Kind -eq 'Suche') { Find-SoccerEntry @Options } else { Get-SoccerDetail @Options }
    }).AddArgument((Join-Path $SoccerRoot 'src/Soccer.ps1')).AddArgument($Kind).AddArgument($Options)
    try { $handle=$shell.BeginInvoke() } catch { $shell.Dispose(); throw }
    $state.job=@{Shell=$shell;Handle=$handle;Kind=$Kind}
    $ui.SearchFields.IsEnabled=$false; $ui.Results.IsEnabled=$false; $ui.ApplyKey.IsEnabled=$false
    $ui.SearchTab.IsEnabled=$false; $ui.FavTab.IsEnabled=$false
    Set-Status 'API-Football lädt …'; $timer.Start()
}
function Find-Selection {
    try {
        if ($state.job) { return }
        if ($ui.Season.Text -notmatch '^(19|20)[0-9]{2}$') { throw 'Gib das vierstellige Startjahr der Saison ein.' }
        $options=@{Typ=[string]$ui.TypeBox.SelectedItem.Content; Suche=$ui.Query.Text; Saison=[int]$ui.Season.Text}
        Set-Results @()
        if (!$state.apiKey) { throw 'API-Key fehlt. Gib den Schlüssel oben ein und wähle «Key setzen».' }
        if ($options.Suche.Trim().Length -lt 4) { throw 'Gib mindestens vier Zeichen für die Suche ein.' }
        $options.ApiKey=$state.apiKey
        Start-LiveRequest 'Suche' $options
    } catch { Set-Status $_.Exception.Message -ErrorState }
}
function Read-Favorites {
    $state.saved=@(& (Join-Path $SoccerRoot 'read.ps1') -DataFile $DataFile)
    $ui.FavTab.Content="Favoriten ($($state.saved.Count))"
}

function Show-Tab([string]$Name) {
    $state.tab=$Name
    $search=$Name -eq 'Suche'
    $ui.SearchFields.Visibility=if ($search) { 'Visible' } else { 'Collapsed' }
    $ui.SearchTab.Background=if ($search) { '#C9EDDA' } else { '#EAF0EC' }
    $ui.FavTab.Background=if ($search) { '#EAF0EC' } else { '#C9EDDA' }
    if ($search) {
        Set-Results @()
        if ($state.apiKey) { Set-Status 'API-Football · Clubname oder Nachname eingeben und Suchen wählen.' }
        else { Set-Status 'Gib oben deinen API-Football-Key ein. Gespeicherte Favoriten kannst du auch offline öffnen.' }

    } else {
        try {
            Read-Favorites
            Set-Status 'Deine lokal gespeicherten Profile.'
            Set-Results $state.saved -AutoSelect
            if (!$state.saved.Count) { Set-Status 'Noch keine Favoriten. Öffne einen Treffer und wähle «Favorit speichern».' }
        } catch { Set-Results @(); Set-Status $_.Exception.Message -ErrorState }
    }
}
$timer=[Windows.Threading.DispatcherTimer]::new()
$timer.Interval=[TimeSpan]::FromMilliseconds(120)
$timer.Add_Tick({
    $job=$state.job
    if (!$job -or !$job.Handle.IsCompleted) { return }
    $timer.Stop(); $state.job=$null
    $ui.SearchFields.IsEnabled=$true; $ui.Results.IsEnabled=$true; $ui.ApplyKey.IsEnabled=$true
    $ui.SearchTab.IsEnabled=$true; $ui.FavTab.IsEnabled=$true
    try {
        $rows=@($job.Shell.EndInvoke($job.Handle))
        if ($job.Shell.HadErrors) { throw [string]$job.Shell.Streams.Error[0] }
        if ($job.Kind -eq 'Suche') {
            if ($rows.Count) { Set-Status 'Wähle einen Treffer, um die Saisonstatistik zu laden.' }
            else { Set-Status 'Keine Treffer. Prüfe den Clubnamen oder den Nachnamen des Spielers.' }
            Set-Results $rows -AutoSelect:($rows.Count -eq 1)
        } else { Show-Profile $rows[0]; Set-Status 'Saisonstatistik geladen.' }
    } catch { Show-Profile $null; Set-Status $_.Exception.Message -ErrorState }
    finally { $job.Shell.Dispose() }
})
$ui.Results.Add_SelectionChanged({
    if ($state.updating) { return }
    $item=$ui.Results.SelectedItem
    try {
        if (!$item -or $state.tab -eq 'Favoriten') { Show-Profile $item }
        else { Show-Profile $null; Start-LiveRequest 'Detail' @{Entry=$item; ApiKey=$state.apiKey} }
    } catch { Set-Status $_.Exception.Message -ErrorState }
})
$ui.PinButton.Add_Click({
    try {
        if (!$state.entry) { return }
        $remove=$state.tab -eq 'Favoriten'
        & (Join-Path $SoccerRoot 'write.ps1') -Eintrag $state.entry -DataFile $DataFile -Entfernen:$remove
        if ($remove) { Show-Tab 'Favoriten'; Set-Status 'Favorit entfernt.' }
        else { Read-Favorites; Set-Status "$($state.entry.Name) ist in den Favoriten gespeichert." }
    } catch { Set-Status $_.Exception.Message -ErrorState }
})
$ui.SearchButton.Add_Click({ Find-Selection })
$ui.Query.Add_KeyDown({ param($sender,$e) if ($e.Key -eq 'Return') { Find-Selection; $e.Handled=$true } })
$ui.SearchTab.Add_Click({ Show-Tab 'Suche' }); $ui.FavTab.Add_Click({ Show-Tab 'Favoriten' })
$ui.TypeBox.Add_SelectionChanged({
    $ui.Query.Text=''
    if ($state.tab -eq 'Suche') { Show-Tab 'Suche' }
})
function Set-SessionKey {
    $key=$ui.KeyBox.Password.Trim()
    if (!$key) { Set-Status 'Gib zuerst deinen API-Football-Key ein.' -ErrorState; return }
    $state.apiKey=$key
    $ui.KeyBox.Clear()
    $ui.KeyStatus.Text='API-Key gesetzt'
    Set-Status 'Schlüssel für diese Sitzung gesetzt. Starte eine Suche.'
}
$ui.KeyStatus.Text=if ($state.apiKey) { 'API-Key gesetzt' } else { 'API-Key fehlt' }
$ui.ApplyKey.Add_Click({ Set-SessionKey })
$ui.KeyBox.Add_KeyDown({ param($sender,$e) if ($e.Key -eq 'Return' -and !$state.job) { Set-SessionKey; $e.Handled=$true } })
$window.Add_Closed({
    $timer.Stop()
    if ($state.job) { $state.job.Shell.Stop(); $state.job.Shell.Dispose(); $state.job=$null }
})
Show-Tab 'Suche'
try { Read-Favorites } catch { Set-Status $_.Exception.Message -ErrorState }
if ($SmokeTest) {
    if ($ui.Profile.Text -ne 'Spielanalyse' -or $ui.SeriesPanel.Children.Count -ne 1) { throw 'Startansicht fehlerhaft.' }
    Show-Tab 'Favoriten'
    if ($state.saved.Count) {
        if ($ui.Results.Items.Count -ne $state.saved.Count) { throw 'Favoritenliste fehlerhaft.' }
        foreach ($profile in $state.saved) {
            $ui.Results.SelectedItem=$profile
            if ($ui.Profile.Text -ne $profile.Name -or $ui.V2.Text -ne (Format-Value $profile.Tore)) { throw 'Profilwerte fehlerhaft.' }
            if ($profile.Serien -and $ui.SeriesPanel.Children.Count -ne $profile.Serien.Count) { throw 'Diagramm fehlerhaft.' }
        }
    }
    $window.Close()
    return 'WPF-Smoke-Test bestanden.'
}
[void]$window.ShowDialog()

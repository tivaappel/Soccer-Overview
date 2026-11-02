[CmdletBinding(DefaultParameterSetName='Suche')]
param(
    [Parameter(Mandatory,ParameterSetName='Suche')][ValidateSet('Club','Spieler')][string]$Typ,
    [Parameter(Mandatory,ParameterSetName='Suche')][string]$Suche,
    [Parameter(ParameterSetName='Suche')][ValidateRange(1900,2100)][int]$Saison=(Get-Date).Year,
    [Parameter(ParameterSetName='Suche')][string]$ApiKey=$env:API_FOOTBALL_KEY,
    [Parameter(ParameterSetName='Suche')][switch]$Demo,
    [Parameter(Mandatory,ParameterSetName='Auswahl')][psobject]$Eintrag,
    [Parameter(ParameterSetName='Auswahl')][switch]$Entfernen,
    [string]$DataFile=(Join-Path $PSScriptRoot 'data/football.json')
)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'src/Soccer.ps1')
if ($PSCmdlet.ParameterSetName -eq 'Auswahl') {
    Update-SoccerStore $DataFile @($Eintrag) -Remove:$Entfernen
    return
}
$entries = @(Find-SoccerEntry -Typ $Typ -Suche $Suche -Saison $Saison -Demo:$Demo -ApiKey $ApiKey |
    ForEach-Object { Get-SoccerDetail $_ -ApiKey $ApiKey })
if (!$entries.Count) { Write-Warning 'Keine passenden Daten gefunden.'; return }
Update-SoccerStore $DataFile $entries
$entries

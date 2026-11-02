[CmdletBinding()]
param(
    [ValidateSet('Alle','Club','Spieler')][string]$Typ='Alle',
    [string]$Suche='',
    [string]$DataFile=(Join-Path $PSScriptRoot 'data/football.json')
)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'src/Soccer.ps1')
Read-SoccerStore $DataFile | Where-Object {
    ($Typ -eq 'Alle' -or $_.Typ -eq $Typ) -and
    (!$Suche -or $_.Name -like "*$Suche*" -or $_.Verein -like "*$Suche*")
}

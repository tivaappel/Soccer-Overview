[CmdletBinding()]
param(
    [ValidateSet('Alle','Club','Spieler')][string]$Typ='Alle',
    [string]$Suche='',
    [string]$DataFile
)
$ErrorActionPreference='Stop'
if (!$DataFile) { $DataFile=Join-Path $PSScriptRoot 'data/football.json' }
. (Join-Path $PSScriptRoot 'src/Soccer.ps1')
Read-SoccerStore $DataFile | Where-Object {
    ($Typ -eq 'Alle' -or $_.Typ -eq $Typ) -and
    (!$Suche -or $_.Name -like "*$Suche*" -or $_.Verein -like "*$Suche*")
}

# fetch-db2.ps1 - download named game-data (DB2) tables at one build from
# wago.tools as CSV, for the derive scripts beside this one.
#
#   pwsh dev/scripts/fetch-db2.ps1 -Build <build> -Tables <Table>[,<Table>...] -OutDir <absolute dir>
#
# Writes <OutDir>/<Table>.csv as served and appends "<Table> <url> <date>"
# to <OutDir>/SOURCE.txt. Exits 1, naming the table, on a failed request or a
# response whose header row has no ID column. Needs the network, so CI never
# runs it.

param(
    [Parameter(Mandatory)][string]$Build,
    [Parameter(Mandatory)][string[]]$Tables,
    [Parameter(Mandatory)][string]$OutDir
)

$ErrorActionPreference = 'Stop'

if (-not [System.IO.Path]::IsPathRooted($OutDir)) {
    Write-Output "[db2] FAIL -OutDir must be an absolute path: $OutDir"
    exit 1
}
New-Item -ItemType Directory -Path $OutDir -Force | Out-Null
$source = Join-Path $OutDir 'SOURCE.txt'
$today = (Get-Date).ToString('yyyy-MM-dd')

foreach ($table in ($Tables | ForEach-Object { $_ -split ',' } | Where-Object { $_ })) {
    $url = "https://wago.tools/db2/$table/csv?build=$Build"
    try {
        $response = Invoke-WebRequest -Uri $url -TimeoutSec 120 -UseBasicParsing
    } catch {
        Write-Output "[db2] FAIL ${table}: $($_.Exception.Message)"
        exit 1
    }
    $bytes = $response.RawContentStream.ToArray()
    $text = [System.Text.Encoding]::UTF8.GetString($bytes)
    $header = ($text -split "`r?`n", 2)[0].TrimStart([char]0xFEFF)
    if (-not (($header -split ',') -contains 'ID')) {
        Write-Output "[db2] FAIL ${table}: the response has no ID column (header: $header)"
        exit 1
    }
    [System.IO.File]::WriteAllBytes((Join-Path $OutDir "$table.csv"), $bytes)
    [System.IO.File]::AppendAllText($source, "$table $url $today`n")
    Write-Output "[db2] $table -> $table.csv"
}
exit 0

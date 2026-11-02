# Автосценарии приложения (F-REL-09) на ПК или в эмуляторе Android.
#
# Создаёт новую папку данных в %TEMP%\memoria-auto\<время> и запускает
# integration_test с ней (F-REL-10): база и обложки владельца не
# трогаются. Каждый прогон начинается с пустой полки.
#
#   powershell -File tool\agent\scenarios.ps1                 # Windows
#   powershell -File tool\agent\scenarios.ps1 -Device emulator-5554
#
# Папки прогонов остаются в %TEMP%\memoria-auto — по ним видно, что
# записало приложение. Удалять их можно в любой момент.

param(
    [string]$Device = 'windows',
    [string]$Target = 'integration_test'
)

$ErrorActionPreference = 'Stop'
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$root = Join-Path $env:TEMP 'memoria-auto'
$data = Join-Path $root $stamp
New-Item -ItemType Directory -Force -Path $root | Out-Null

# На Android путь — внутри песочницы приложения: туда приложение пишет
# без разрешений.
if ($Device -ne 'windows') {
    $data = "/data/user/0/io.github.owner102007.memoria/files/auto-$stamp"
}

Write-Host "Папка данных прогона: $data"
Push-Location (Join-Path $PSScriptRoot '..\..')
try {
    flutter test $Target -d $Device --no-pub "--dart-define=MEMORIA_DATA_DIR=$data"
    exit $LASTEXITCODE
} finally {
    Pop-Location
}

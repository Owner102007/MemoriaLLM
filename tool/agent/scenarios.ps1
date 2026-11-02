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

# CMake для нативного кода плагинов (jni) — по пути ярлыка окружения.
#
# Android SDK окружения лежит в папке с пробелами и кириллицей, а
# программы видят его через ярлык C:\EcoTestEnv (ECO-D-030). Android Gradle
# Plugin сам «разворачивает» ярлык до настоящего пути и не может запустить
# по нему ninja. Явный `cmake.dir` в local.properties (файл этого ПК, не в
# git) оставляет путь через ярлык.
function Set-CmakeDir {
    if (-not $env:ANDROID_HOME) { return }
    $cmake = Get-ChildItem (Join-Path $env:ANDROID_HOME 'cmake') -Directory -ErrorAction SilentlyContinue |
        Sort-Object Name -Descending | Select-Object -First 1
    if (-not $cmake) { return }
    $file = 'android\local.properties'
    $lines = @()
    if (Test-Path $file) { $lines = @(Get-Content $file | Where-Object { $_ -notmatch '^cmake\.dir=' }) }
    $lines += 'cmake.dir=' + ($cmake.FullName -replace '\\', '/')
    Set-Content -Path $file -Value $lines -Encoding ASCII
}

$root = Join-Path $env:TEMP 'memoria-auto'
New-Item -ItemType Directory -Force -Path $root | Out-Null

# Новая папка данных на каждую попытку: сценарий начинает с пустой полки.
function New-DataDir {
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    # На Android путь — внутри песочницы приложения: туда приложение
    # пишет без разрешений.
    if ($Device -ne 'windows') {
        return "/data/user/0/io.github.owner102007.memoria/files/auto-$stamp"
    }
    return (Join-Path $root $stamp)
}

# Основное приложение на Android собирается флейвором full (как в CI).
$flavor = @()
if ($Device -ne 'windows') { $flavor = @('--flavor', 'full') }

# Признаки сбоя связи с устройством, а не падения теста.
$linkLost = 'VmServiceDisappeared|Service connection disposed|device .* not found|device offline'

Push-Location (Join-Path $PSScriptRoot '..\..')
try {
    # Вывод программ в stderr при Stop обрывает скрипт (Windows PowerShell).
    $ErrorActionPreference = 'Continue'
    if ($Device -ne 'windows') { Set-CmakeDir }
    foreach ($attempt in 1, 2) {
        if ($Device -ne 'windows') {
            & adb -s $Device wait-for-device
            # Прошлый прогон мог оставить приложение запущенным.
            & adb -s $Device shell am force-stop io.github.owner102007.memoria 2>$null
        }
        $data = New-DataDir
        Write-Host "Папка данных прогона: $data"
        $out = & flutter test $Target -d $Device --no-pub @flavor "--dart-define=MEMORIA_DATA_DIR=$data" 2>&1 |
            ForEach-Object { $line = "$_"; Write-Host $line; $line }
        $code = $LASTEXITCODE
        # Повтор — только если оборвалась связь с устройством. Упавший
        # тест не повторяется: это настоящий результат.
        if ($code -eq 0 -or $attempt -eq 2 -or -not (($out -join "`n") -match $linkLost)) {
            exit $code
        }
        Write-Host 'Связь с устройством оборвалась — повтор прогона.'
    }
} finally {
    Pop-Location
}

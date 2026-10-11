#<PS>
# Обновление сборки исследования СНО2026 на ПК с папкой _MemoriaTest
# (SNO-F-CFG-07, шаг 35).
#
# Ярлык «Обновить сборку исследования.cmd» лежит в _MemoriaTest рядом с
# папками I\ и II\ (распакованные ZIP ветвей для Windows). Он:
#   1. узнаёт, какая сборка стоит в I\ и II\ (метка .study-tag или тег,
#      зашитый в data\app.so);
#   2. берёт с GitHub последний релиз sno2026-N; та же сборка — ничего не
#      качает;
#   3. не обновляет, пока в ветви есть незавершённая сессия записи;
#   4. качает ZIP ветвей и SHA256SUMS.txt в _download\<тег>\, сверяет
#      суммы — не сошлась хоть одна, ничего не заменяется;
#   5. закрывает Memoria и спутник взгляда, запущенные из I\ и II\;
#   6. распаковывает новую сборку рядом, прежние I\ и II\ откладывает в
#      _прежние\<прежний тег>\ и ставит новые на их место.
#
# Полка, эталон, место записи и записи лежат в папке данных Windows
# (%APPDATA%\HohloBaron\Memoria LLM HB\sno2026-I и -II), а не здесь:
# замена I\ и II\ их не трогает.
#
# Этот файл — исходник: в .cmd он вклеен целиком после строки #<PS>
# (tool/study_update/build_cmd.py). Писан под Windows PowerShell 5.1.
param(
    [string]$Root = '',
    [string]$Repo = 'Owner102007/MemoriaLLM',
    [string]$Api = 'https://api.github.com',
    [string]$Site = 'https://github.com',
    [string]$DataRoot = '',
    # Не спрашивать подтверждений (проверка самого скрипта).
    [switch]$Yes,
    # Не искать и не закрывать запущенные программы (проверка скрипта).
    [switch]$NoStop
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
try {
    [Net.ServicePointManager]::SecurityProtocol =
        [Net.ServicePointManager]::SecurityProtocol -bor
        [Net.SecurityProtocolType]::Tls12
} catch {
}

$StudyTag = '^sno2026-[1-9][0-9]*(\.[1-9][0-9]*)?$'
$Branches = @('I', 'II')
$StampName = '.study-tag'

if (-not $Root) {
    if ($env:MEMORIA_SELF) {
        $Root = Split-Path -Parent $env:MEMORIA_SELF
    } else {
        $Root = (Get-Location).Path
    }
}
if (-not $DataRoot) {
    if ($env:APPDATA) {
        $DataRoot = Join-Path $env:APPDATA 'HohloBaron\Memoria LLM HB'
    }
}

function Write-Step([string]$Text) {
    Write-Host ''
    Write-Host "== $Text" -ForegroundColor Cyan
}

function Write-Note([string]$Text) {
    Write-Host "   $Text"
}

function Stop-With([string]$Text, [int]$Code = 1) {
    Write-Host ''
    Write-Host $Text -ForegroundColor Yellow
    exit $Code
}

function Confirm-Step([string]$Question) {
    if ($Yes) {
        return $true
    }
    $answer = Read-Host "$Question [Д/н]"
    return ($answer -eq '' -or $answer -match '^(д|да|y|yes)$')
}

# Тег сборки в папке ветви: метка, которую кладёт это обновление, или
# строка тега в снимке кода Dart (data\app.so); $null — не узнать.
function Get-InstalledTag([string]$Dir) {
    $stamp = Join-Path $Dir $StampName
    if (Test-Path -LiteralPath $stamp) {
        $text = (Get-Content -LiteralPath $stamp -Raw).Trim()
        if ($text -match $StudyTag) {
            return $text
        }
    }
    $so = Join-Path (Join-Path $Dir 'data') 'app.so'
    if (Test-Path -LiteralPath $so) {
        $bytes = [IO.File]::ReadAllBytes($so)
        $text = [Text.Encoding]::GetEncoding(28591).GetString($bytes)
        $found = [regex]::Matches($text, 'sno2026-[1-9][0-9]*(?:\.[1-9][0-9]*)?(?![0-9.])')
        $tags = @($found | ForEach-Object { $_.Value } | Sort-Object -Unique)
        if ($tags.Count -eq 1) {
            return $tags[0]
        }
    }
    return $null
}

# Номер сборки для сравнения: sno2026-2 → 2.0, sno2026-1.1 → 1.1.
function Get-TagOrder([string]$Tag) {
    if (-not $Tag -or $Tag -notmatch $StudyTag) {
        return [version]'0.0'
    }
    $number = $Tag.Substring('sno2026-'.Length)
    if ($number -notmatch '\.') {
        $number = "$number.0"
    }
    return [version]$number
}

function Get-LatestStudy {
    $headers = @{ 'User-Agent' = 'memoria-study-update' }
    try {
        $all = Invoke-RestMethod -UseBasicParsing -Headers $headers `
            -Uri "$Api/repos/$Repo/releases?per_page=100"
    } catch {
        Stop-With ('GitHub не отдал список релизов — нет интернета или ' +
            "GitHub недоступен ($($_.Exception.Message)). Ничего не изменено.")
    }
    $study = @($all | Where-Object {
            $_.tag_name -match $StudyTag -and -not $_.draft
        } | Sort-Object { Get-TagOrder $_.tag_name } -Descending)
    if ($study.Count -eq 0) {
        Stop-With 'Сборки исследования на GitHub ещё нет. Ничего не изменено.'
    }
    return $study[0]
}

function Get-File([string]$Url, [string]$Path) {
    $part = "$Path.part"
    $curl = Get-Command 'curl.exe' -ErrorAction SilentlyContinue
    $done = $false
    if ($curl) {
        # Оборванная загрузка продолжается с места обрыва; ход виден.
        & $curl.Source '-L' '--fail' '--progress-bar' '-C' '-' '-o' $part $Url
        $done = $LASTEXITCODE -eq 0
        if (-not $done) {
            Write-Note "curl не справился (код $LASTEXITCODE) — качаю иначе…"
        }
    }
    if (-not $done) {
        # Без curl или с путём, который он не понял, — средствами
        # PowerShell: без хода и с начала.
        if (Test-Path -LiteralPath $part) {
            Remove-Item -LiteralPath $part -Force
        }
        Invoke-WebRequest -UseBasicParsing -Uri $Url -OutFile $part
    }
    if (Test-Path -LiteralPath $Path) {
        Remove-Item -LiteralPath $Path -Force
    }
    Move-Item -LiteralPath $part $Path
}

function Read-Sums([string]$Path) {
    $sums = @{}
    foreach ($line in Get-Content -LiteralPath $Path) {
        if ($line -match '^([0-9a-fA-F]{64})\s+\*?(\S+)\s*$') {
            $sums[$Matches[2]] = $Matches[1].ToLowerInvariant()
        }
    }
    return $sums
}

function Get-Sha256([string]$Path) {
    $sha = [Security.Cryptography.SHA256]::Create()
    $stream = [IO.File]::OpenRead($Path)
    try {
        $hash = $sha.ComputeHash($stream)
    } finally {
        $stream.Dispose()
        $sha.Dispose()
    }
    return -join ($hash | ForEach-Object { $_.ToString('x2') })
}

# Незавершённая сессия записи ветви: её папка лежит в Записи\.current.
function Test-OpenSession([string]$Branch) {
    if (-not $DataRoot) {
        return $false
    }
    $current = Join-Path (Join-Path (Join-Path $DataRoot "sno2026-$Branch") 'Записи') '.current'
    if (-not (Test-Path -LiteralPath $current)) {
        return $false
    }
    return @(Get-ChildItem -LiteralPath $current -Directory -ErrorAction SilentlyContinue).Count -gt 0
}

function Get-Running([string[]]$Dirs) {
    $found = @()
    foreach ($proc in @(Get-Process -ErrorAction SilentlyContinue)) {
        $path = $null
        try {
            $path = $proc.Path
        } catch {
        }
        if (-not $path) {
            continue
        }
        foreach ($dir in $Dirs) {
            $prefix = $dir.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
            if ($path.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
                $found += $proc
                break
            }
        }
    }
    return $found
}

function Expand-Zip([string]$Zip, [string]$Into) {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    if (Test-Path -LiteralPath $Into) {
        Remove-Item -LiteralPath $Into -Recurse -Force
    }
    [IO.Compression.ZipFile]::ExtractToDirectory($Zip, $Into)
    if (Test-Path -LiteralPath (Join-Path $Into 'memoria.exe')) {
        return $Into
    }
    $inner = Get-ChildItem -LiteralPath $Into -Recurse -Filter 'memoria.exe' |
        Select-Object -First 1
    if (-not $inner) {
        throw "в $Zip нет memoria.exe"
    }
    return $inner.DirectoryName
}

function Get-FreeName([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) {
        return $Path
    }
    for ($i = 2; ; $i++) {
        $next = "$Path ($i)"
        if (-not (Test-Path -LiteralPath $next)) {
            return $next
        }
    }
}

# --- ход -----------------------------------------------------------------

Write-Host 'Обновление сборки исследования СНО2026' -ForegroundColor Cyan
Write-Note "Папка: $Root"

$present = @($Branches | Where-Object {
        Test-Path -LiteralPath (Join-Path (Join-Path $Root $_) 'memoria.exe')
    })
if ($present.Count -eq 0) {
    Stop-With ('Рядом нет папок I и II с memoria.exe. Положите этот файл ' +
        'в папку _MemoriaTest — рядом с папками I и II — и запустите ' +
        'снова. Ничего не изменено.')
}

Write-Step 'Что стоит сейчас'
$installed = @{}
foreach ($branch in $present) {
    $tag = Get-InstalledTag (Join-Path $Root $branch)
    $installed[$branch] = $tag
    if ($tag) {
        Write-Note "Ветвь $branch — сборка исследования $tag"
    } else {
        Write-Note "Ветвь $branch — сборка не узнана (не сборка исследования?)"
    }
}

Write-Step 'Что есть на GitHub'
$release = Get-LatestStudy
$tag = $release.tag_name
$published = ''
if ($release.published_at) {
    $published = ', опубликована ' +
        ([datetime]$release.published_at).ToLocalTime().ToString('dd.MM.yyyy HH:mm')
}
Write-Note "Последняя сборка исследования — $tag$published"

$stale = @($present | Where-Object { $installed[$_] -ne $tag })
if ($stale.Count -eq 0) {
    Stop-With "Уже стоит последняя сборка $tag — скачивать нечего." 0
}
$older = @($stale | Where-Object {
        $installed[$_] -and (Get-TagOrder $installed[$_]) -gt (Get-TagOrder $tag)
    })
if ($older.Count -gt 0) {
    Stop-With ("Здесь стоит сборка новее, чем на GitHub ($($installed[$older[0]])). " +
        'Ничего не изменено.')
}

foreach ($branch in $stale) {
    if (Test-OpenSession $branch) {
        Stop-With ("В ветви $branch есть незавершённая сессия записи. " +
            "Откройте приложение ветви $branch, завершите сессию и заберите " +
            'запись, потом запустите обновление снова. Ничего не изменено.')
    }
}

Write-Host ''
Write-Note "Обновится: $($stale -join ' и ') → $tag."
Write-Note 'Полка, эталон, место записи и записи на этом ПК останутся:'
Write-Note 'они лежат в папке данных Windows, а не здесь.'
if (-not (Confirm-Step 'Обновить?')) {
    Stop-With 'Отменено. Ничего не изменено.' 0
}

$need = 0L
foreach ($branch in $stale) {
    $asset = $release.assets | Where-Object {
        $_.name -eq "memoria-sno2026-$branch-windows.zip"
    } | Select-Object -First 1
    if (-not $asset) {
        Stop-With "В релизе $tag нет сборки ветви $branch для Windows. Ничего не изменено."
    }
    $need += [long]$asset.size * 4
}
$free = $null
try {
    $drive = New-Object IO.DriveInfo ([IO.Path]::GetPathRoot((Resolve-Path -LiteralPath $Root).Path))
    $free = $drive.AvailableFreeSpace
} catch {
}
if ($null -ne $free -and $free -lt $need) {
    Stop-With ('Мало места на диске: нужно около {0:N1} ГБ, свободно {1:N1} ГБ. Ничего не изменено.' -f
        ($need / 1GB), ($free / 1GB))
}

Write-Step "Скачиваю $tag"
$download = Join-Path (Join-Path $Root '_download') $tag
$null = New-Item -ItemType Directory -Path $download -Force
$base = "$Site/$Repo/releases/download/$tag"
$sumsPath = Join-Path $download 'SHA256SUMS.txt'
try {
    Get-File "$base/SHA256SUMS.txt" $sumsPath
} catch {
    Stop-With "Не скачались суммы сборки ($($_.Exception.Message)). Ничего не изменено."
}
$sums = Read-Sums $sumsPath
$zips = @{}
foreach ($branch in $stale) {
    $name = "memoria-sno2026-$branch-windows.zip"
    $zip = Join-Path $download $name
    $expected = $sums[$name]
    if (-not $expected) {
        Stop-With "В SHA256SUMS.txt нет суммы $name. Ничего не изменено."
    }
    if ((Test-Path -LiteralPath $zip) -and (Get-Sha256 $zip) -eq $expected) {
        Write-Note "$name уже скачан."
    } else {
        Write-Note "Скачиваю $name…"
        try {
            Get-File "$base/$name" $zip
        } catch {
            Stop-With "Не скачалось: $($_.Exception.Message). Запустите обновление ещё раз — загрузка продолжится. Ничего не изменено."
        }
        if ((Get-Sha256 $zip) -ne $expected) {
            Remove-Item -LiteralPath $zip -Force
            Stop-With ("$name скачался с ошибкой — сумма не сходится с " +
                'SHA256SUMS.txt. Запустите обновление ещё раз. Ничего не изменено.')
        }
    }
    Write-Note "$name — сумма сходится."
    $zips[$branch] = $zip
}

if (-not $NoStop) {
    $dirs = @($stale | ForEach-Object { Join-Path $Root $_ })
    $running = @(Get-Running $dirs)
    if ($running.Count -gt 0) {
        Write-Host ''
        Write-Note 'Запущены Memoria или спутник взгляда из этих папок.'
        if (-not (Confirm-Step 'Закрыть их? Незавершённой сессии нет.')) {
            Stop-With 'Отменено. Закройте Memoria и запустите обновление снова. Ничего не изменено.' 0
        }
        $running | Stop-Process -Force
        Start-Sleep -Seconds 2
    }
}

Write-Step 'Ставлю'
$fresh = @{}
foreach ($branch in $stale) {
    Write-Note "Распаковываю ветвь $branch…"
    $into = Join-Path $Root "$branch.new"
    try {
        $fresh[$branch] = @{ Into = $into; Root = (Expand-Zip $zips[$branch] $into) }
    } catch {
        Stop-With "Не распаковалась ветвь ${branch}: $($_.Exception.Message). Ничего не изменено."
    }
}
foreach ($branch in $stale) {
    $current = Join-Path $Root $branch
    $old = $installed[$branch]
    if (-not $old) {
        $old = 'прежняя ' + (Get-Date).ToString('yyyy-MM-dd HH-mm')
    }
    $keepDir = Join-Path (Join-Path $Root '_прежние') $old
    $null = New-Item -ItemType Directory -Path $keepDir -Force
    $kept = Get-FreeName (Join-Path $keepDir $branch)
    try {
        Move-Item -LiteralPath $current $kept
    } catch {
        Stop-With ("Папка $branch занята — закройте всё, что открыто из неё " +
            "(Memoria, Проводник, консоль), и запустите снова. Ветвь $branch не изменена.")
    }
    try {
        Move-Item -LiteralPath $fresh[$branch].Root $current
    } catch {
        # Новую не поставить — прежняя возвращается на место.
        Move-Item -LiteralPath $kept $current
        Stop-With "Не удалось поставить новую сборку ветви ${branch}: $($_.Exception.Message). Прежняя на месте."
    }
    Set-Content -LiteralPath (Join-Path $current $StampName) -Value $tag -Encoding ASCII
    if (Test-Path -LiteralPath $fresh[$branch].Into) {
        Remove-Item -LiteralPath $fresh[$branch].Into -Recurse -Force
    }
    Write-Note "Ветвь $branch — $tag. Прежняя сборка — в _прежние\$old\$(Split-Path -Leaf $kept)."
}
Remove-Item -LiteralPath $download -Recurse -Force -ErrorAction SilentlyContinue
$downloads = Join-Path $Root '_download'
if (@(Get-ChildItem -LiteralPath $downloads -ErrorAction SilentlyContinue).Count -eq 0) {
    Remove-Item -LiteralPath $downloads -Force -ErrorAction SilentlyContinue
}

Write-Step "Готово: стоит сборка исследования $tag"
Write-Note 'Дальше в каждой обновлённой ветви:'
Write-Note "  1) «Тестирование» → «О ветви»: «Сборка исследования $tag»."
Write-Note '  2) «Для экспериментатора»: удерживать «Забыть эталон», добавить'
Write-Note '     архив с литературой ещё раз и удерживать сброс —'
Write-Note '     «Сейчас: совпадает с эталоном».'
Write-Note 'Прежнюю сборку из _прежние\ можно удалить, когда новая проверена.'
exit 0

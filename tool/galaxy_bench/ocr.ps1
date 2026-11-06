# Стенд «Галактики» (S62, ALG-MAP-21): распознаёт картинки страниц встроенным OCR Windows
# (Windows.Media.Ocr — часть ОС, языковые пакеты ru и en-US). Обходит папку вглубь, у каждой
# <номер>.png пишет рядом <номер>.<язык>.txt (UTF-8); уже распознанные пропускает.
# Зовёт ocr_edges.py:  powershell -File ocr.ps1 -Dir <папка> -Lang ru|en-US
param([string]$Dir, [string]$Lang)
Add-Type -AssemblyName System.Runtime.WindowsRuntime
$null = [Windows.Media.Ocr.OcrEngine, Windows.Foundation, ContentType = WindowsRuntime]
$null = [Windows.Graphics.Imaging.BitmapDecoder, Windows.Foundation, ContentType = WindowsRuntime]
$null = [Windows.Storage.StorageFile, Windows.Foundation, ContentType = WindowsRuntime]
$null = [Windows.Globalization.Language, Windows.Foundation, ContentType = WindowsRuntime]
$asTask = ([System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object { $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1' })[0]
function Await($op, [Type]$t) { $task = $asTask.MakeGenericMethod($t).Invoke($null, @($op)); $task.Wait(-1) | Out-Null; $task.Result }
$engine = [Windows.Media.Ocr.OcrEngine]::TryCreateFromLanguage([Windows.Globalization.Language]::new($Lang))
if ($null -eq $engine) { Write-Error "нет языкового пакета OCR: $Lang"; exit 3 }
Get-ChildItem $Dir -Filter *.png -Recurse | Where-Object { -not (Test-Path ($_.FullName -replace '\.png$', ".$Lang.txt")) } | ForEach-Object {
  $sw = [Diagnostics.Stopwatch]::StartNew()
  $file = Await ([Windows.Storage.StorageFile]::GetFileFromPathAsync($_.FullName)) ([Windows.Storage.StorageFile])
  $stream = Await ($file.OpenAsync([Windows.Storage.FileAccessMode]::Read)) ([Windows.Storage.Streams.IRandomAccessStream])
  $decoder = Await ([Windows.Graphics.Imaging.BitmapDecoder]::CreateAsync($stream)) ([Windows.Graphics.Imaging.BitmapDecoder])
  $bitmap = Await ($decoder.GetSoftwareBitmapAsync()) ([Windows.Graphics.Imaging.SoftwareBitmap])
  if ($bitmap.PixelWidth -gt [Windows.Media.Ocr.OcrEngine]::MaxImageDimension -or $bitmap.PixelHeight -gt [Windows.Media.Ocr.OcrEngine]::MaxImageDimension) {
    $t = [Windows.Graphics.Imaging.BitmapTransform]::new(); $k = [Windows.Media.Ocr.OcrEngine]::MaxImageDimension / [Math]::Max($bitmap.PixelWidth, $bitmap.PixelHeight)
    $t.ScaledWidth = [uint32]($bitmap.PixelWidth * $k); $t.ScaledHeight = [uint32]($bitmap.PixelHeight * $k)
    $bitmap = Await ($decoder.GetSoftwareBitmapAsync([Windows.Graphics.Imaging.BitmapPixelFormat]::Bgra8, [Windows.Graphics.Imaging.BitmapAlphaMode]::Premultiplied, $t, [Windows.Graphics.Imaging.ExifOrientationMode]::IgnoreExifOrientation, [Windows.Graphics.Imaging.ColorManagementMode]::DoNotColorManage)) ([Windows.Graphics.Imaging.SoftwareBitmap])
  }
  $result = Await ($engine.RecognizeAsync($bitmap)) ([Windows.Media.Ocr.OcrResult])
  $text = ($result.Lines | ForEach-Object { $_.Text }) -join "`n"
  [IO.File]::WriteAllText(($_.FullName -replace '\.png$', ".$Lang.txt"), $text, [Text.Encoding]::UTF8)
  "{0} {1} мс {2} строк" -f $_.Name, $sw.ElapsedMilliseconds, $result.Lines.Count
}

# GinDPI dağıtım paketi: Release derlemesi + zip + kurulum sihirbazı.
# Kullanım: powershell -ExecutionPolicy Bypass -File tools\package.ps1
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
Set-Location $root

$version = ((Select-String -Path pubspec.yaml -Pattern '^version:\s*(\S+)').Matches[0].Groups[1].Value -split '\+')[0]
Write-Host "GinDPI $version paketleniyor"

flutter build windows --release
if ($LASTEXITCODE -ne 0) { throw 'Derleme basarisiz' }

$release = Join-Path $root 'build\windows\x64\runner\Release'
$dist = Join-Path $root 'dist'
$stage = Join-Path $dist 'GinDPI'
if (Test-Path $dist) { Remove-Item $dist -Recurse -Force }
New-Item -ItemType Directory -Force $stage | Out-Null
Copy-Item "$release\*" $stage -Recurse

# Visual C++ çalışma kitaplıkları: temiz bir Windows'ta yoksa uygulama açılmaz (uygulama-yerel dağıtım).
foreach ($n in 'msvcp140.dll', 'vcruntime140.dll', 'vcruntime140_1.dll', 'msvcp140_1.dll') {
  $src = Join-Path $env:SystemRoot "System32\$n"
  if (Test-Path $src) { Copy-Item $src $stage }
}

@"
GinDPI $version

Kurulum gerektirmeyen sürüm: klasörü istediğiniz yere çıkarın, gindpi.exe'yi çalıştırın.
Uygulama yönetici olarak açılır (tek onay). Sürücü yüklemez.
Kaldırmak için önce uygulamadan çıkın (tepsi simgesi > Çıkış), sonra klasörü silin.
"@ | Set-Content (Join-Path $stage 'BENI-OKU.txt') -Encoding UTF8

Compress-Archive -Path $stage -DestinationPath (Join-Path $dist "GinDPI-$version-portable.zip") -CompressionLevel Optimal

$iscc = "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe"
if (-not (Test-Path $iscc)) { $iscc = "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe" }
if (Test-Path $iscc) {
  & $iscc "/DAppVersion=$version" (Join-Path $root 'installer\gindpi.iss')
  if ($LASTEXITCODE -ne 0) { throw 'Kurulum sihirbazi derlenemedi' }
} else {
  Write-Warning 'Inno Setup bulunamadi; yalnizca zip uretildi.'
}

Get-ChildItem $dist -File | Select-Object Name, @{ n = 'MB'; e = { [math]::Round($_.Length / 1MB, 1) } }

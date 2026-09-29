# Builds the Windows release and packages it into dist/:
#   LocalBoard-<version>-Setup-x64.exe      (+ LocalBoard-Setup-x64.exe alias)
#   LocalBoard-<version>-windows-x64.zip    (+ LocalBoard-windows-x64.zip alias)
#   SHA256SUMS (every LocalBoard-* file in dist/)
# The un-versioned aliases are what the website's "latest" download links use.
#
# Usage: scripts/package-windows.ps1 [-SkipBuild]
param([switch]$SkipBuild)
$ErrorActionPreference = "Stop"

$Root = Resolve-Path (Join-Path $PSScriptRoot "..")
Set-Location $Root

$Version = (Select-String -Path apps/desktop/pubspec.yaml -Pattern '^version:\s*([0-9.]+)').Matches[0].Groups[1].Value
$Bundle = Join-Path $Root "apps/desktop/build/windows/x64/runner/Release"
$Dist = Join-Path $Root "dist"
$Work = Join-Path $Root "build/package-windows"

Write-Host "==> Local Board $Version"

if (-not $SkipBuild) {
  Push-Location apps/desktop
  flutter build windows --release --build-name=$Version
  if ($LASTEXITCODE -ne 0) { throw "flutter build windows failed" }
  Pop-Location
}
if (-not (Test-Path (Join-Path $Bundle "LocalBoard.exe"))) { throw "missing $Bundle\LocalBoard.exe" }
foreach ($dll in "msvcp140.dll", "vcruntime140.dll", "vcruntime140_1.dll") {
  if (-not (Test-Path (Join-Path $Bundle $dll))) { throw "missing bundled runtime $dll" }
}

Remove-Item -Recurse -Force $Work -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force $Work, $Dist | Out-Null

# ---------- portable .zip ----------
$Portable = Join-Path $Work "Local Board"
Copy-Item -Recurse $Bundle $Portable
Copy-Item LICENSE $Portable
Set-Content -Path (Join-Path $Portable "VERSION") -Value $Version -Encoding ascii
$Zip = "LocalBoard-$Version-windows-x64.zip"
Remove-Item (Join-Path $Dist $Zip) -ErrorAction SilentlyContinue
Compress-Archive -Path $Portable -DestinationPath (Join-Path $Dist $Zip)
Copy-Item (Join-Path $Dist $Zip) (Join-Path $Dist "LocalBoard-windows-x64.zip") -Force
Write-Host "==> $Zip"

# ---------- installer (Inno Setup 6) ----------
$Iscc = @(
  (Get-Command iscc.exe -ErrorAction SilentlyContinue).Source,
  "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe",
  "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
  "$env:ProgramFiles\Inno Setup 6\ISCC.exe"
) | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
if (-not $Iscc) { throw "Inno Setup 6 not found (winget install JRSoftware.InnoSetup)" }

& $Iscc /Q "/DAppVersion=$Version" "/DSourceDir=$Bundle" "/DOutputDir=$Dist" apps/desktop/windows/packaging/local-board.iss
if ($LASTEXITCODE -ne 0) { throw "Inno Setup failed" }
$Setup = "LocalBoard-$Version-Setup-x64.exe"
Copy-Item (Join-Path $Dist $Setup) (Join-Path $Dist "LocalBoard-Setup-x64.exe") -Force
Write-Host "==> $Setup"

# ---------- checksums (sha256sum format) ----------
Get-ChildItem $Dist -Filter "LocalBoard-*" | Sort-Object Name | ForEach-Object {
  "{0}  {1}" -f (Get-FileHash $_.FullName -Algorithm SHA256).Hash.ToLower(), $_.Name
} | Set-Content -Path (Join-Path $Dist "SHA256SUMS") -Encoding ascii

Get-ChildItem $Dist | Format-Table Name, @{ n = "MB"; e = { [math]::Round($_.Length / 1MB, 1) } } -AutoSize

# Builds a PORTABLE LocalSend Windows bundle (ZIP) on a local machine and writes it to app/dist/.
# Mirrors the portable ZIP flow of .github/workflows/build_windows_zip_x64.yml:
#   generate MSIX helper -> build -> verify PE architecture -> portable post-processing -> zip.
#
# Why the result is portable:
#   - portable.marker next to the executable makes the app store its configuration
#     beside the exe instead of in %APPDATA%\LocalSend (app/lib/provider/persistence_provider.dart).
#   - The MSIX helper is dropped, so nothing registers an MSIX package or a shell extension.
#   - The VC++ runtime DLLs are bundled, so it also runs without the Visual C++ Redistributable.
# Binaries are NOT code signed (that needs a certificate), so SmartScreen may warn on first run.
#
# Usage (from any directory):
#   .\support\scripts\compile_windows_portable.ps1              # x86_64, runs flutter clean first
#   .\support\scripts\compile_windows_portable.ps1 -NoClean     # incremental build
#   .\support\scripts\compile_windows_portable.ps1 -Arch arm64  # only valid on native ARM64 Windows

[CmdletBinding()]
param(
    [ValidateSet('x64', 'arm64')]
    [string] $Arch = 'x64',

    # Keep the default clean for a first build, after switching architecture, or when stale output is suspected.
    [switch] $NoClean
)

$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$appDir = Join-Path $repoRoot 'app'
$distDir = Join-Path $appDir 'dist'
$releaseDir = Join-Path $appDir "build\windows\$Arch\runner\Release"
$zipName = if ($Arch -eq 'x64') { 'LocalSend-windows-x86_64.zip' } else { 'LocalSend-windows-arm64.zip' }
$zipPath = Join-Path $distDir $zipName

# On a non-UTF-8 code page (for example 936) plugin sources trigger warning C4819, which the
# repository's /WX turns into error C2220. _CL_ is read by cl.exe and only affects this session.
$env:_CL_ = '/utf-8'

function Get-PEMachine {
    param([string] $Path)

    $stream = [System.IO.File]::OpenRead($Path)
    try {
        $reader = [System.IO.BinaryReader]::new($stream)
        $stream.Seek(0x3c, [System.IO.SeekOrigin]::Begin) | Out-Null
        $peOffset = $reader.ReadInt32()
        $stream.Seek($peOffset, [System.IO.SeekOrigin]::Begin) | Out-Null
        if ($reader.ReadUInt32() -ne 0x00004550) {
            throw "Not a valid PE file: $Path"
        }
        return $reader.ReadUInt16()
    }
    finally {
        $stream.Dispose()
    }
}

function Assert-Success {
    param([string] $What)

    if ($LASTEXITCODE -ne 0) {
        throw "$What failed with exit code $LASTEXITCODE"
    }
}

# 1. MSIX helper. The install step of app/windows/CMakeLists.txt copies it, but the file is not in
#    version control, so a missing helper fails the build with error MSB3073 during INSTALL.
#    It is removed from the portable bundle again in step 4.
$msixPath = Join-Path $appDir 'windows\localsend_msix_helper.msix'
if (-not (Test-Path $msixPath)) {
    Write-Host 'Building localsend_msix_helper.msix ...'
    $makepri = Get-ChildItem 'C:\Program Files (x86)\Windows Kits\10\bin\10.*\x64\makepri.exe' | Select-Object -Last 1
    if (-not $makepri) {
        throw 'makepri.exe not found; install the Windows SDK'
    }
    $makeappx = 'C:\Program Files (x86)\Windows Kits\10\App Certification Kit\makeappx.exe'
    if (-not (Test-Path $makeappx)) {
        $makeappx = (Get-ChildItem 'C:\Program Files (x86)\Windows Kits\10\bin\10.*\x64\makeappx.exe' | Select-Object -Last 1).FullName
    }

    Push-Location $repoRoot
    try {
        & $makepri.FullName new /pr support\build\msix\content /cf support\build\msix\priconfig.xml /mn support\build\msix\content\AppxManifest.xml /of support\build\msix\content\resources.pri /o
        Assert-Success 'makepri'
        & $makeappx pack /o /d support\build\msix\content /nv /p app\windows\localsend_msix_helper.msix
        Assert-Success 'makeappx'
    }
    finally {
        Pop-Location
    }
}

# 2. Build.
if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
    throw 'flutter not found; make sure the bin directory of Flutter 3.41.9 is on PATH'
}

Push-Location $appDir
try {
    if (-not $NoClean) {
        flutter clean
        Assert-Success 'flutter clean'
    }
    flutter pub get
    Assert-Success 'flutter pub get'
    flutter build windows --release
    Assert-Success 'flutter build windows'
}
finally {
    Pop-Location
}

# 3. Verify the architecture: 0x8664 is x86_64, 0xAA64 is ARM64.
$exePath = Join-Path $releaseDir 'localsend_app.exe'
if (-not (Test-Path $exePath)) {
    throw "Build output not found: $exePath"
}

$machine = Get-PEMachine -Path $exePath
$expected = if ($Arch -eq 'x64') { 0x8664 } else { 0xAA64 }
if ($machine -ne $expected) {
    throw ('PE machine 0x{0:X4} does not match the target architecture (expected 0x{1:X4}); do not ship it' -f $machine, $expected)
}
Write-Host ('PE machine: 0x{0:X4}  {1}' -f $machine, $exePath)

# 4. Portable post-processing, same order as the CI workflow.
# 4a. Keep the marker separate from user settings so an upgrade cannot overwrite them.
$settingsPath = Join-Path $releaseDir 'settings.json'
if (Test-Path $settingsPath) { Remove-Item $settingsPath -Force }
[System.IO.File]::WriteAllText((Join-Path $releaseDir 'portable.marker'), '')
Write-Host "Added portable.marker (enables portable mode)"

# 4b. VC++ runtime, so the bundle runs on machines without the Visual C++ Redistributable.
#     The repository ships the x64 DLLs; arm64 comes from the Visual Studio redist, like CI does.
if ($Arch -eq 'x64') {
    $crtDir = Join-Path $repoRoot 'support\build\windows\x64'
}
else {
    $crtDir = @(
        'C:\Program Files\Microsoft Visual Studio\2022\*\VC\Redist\MSVC\*\arm64\Microsoft.VC143.CRT'
        'C:\Program Files (x86)\Microsoft Visual Studio\2022\*\VC\Redist\MSVC\*\arm64\Microsoft.VC143.CRT'
    ) | ForEach-Object { Get-ChildItem $_ -ErrorAction SilentlyContinue } | Select-Object -Last 1 -ExpandProperty FullName
}

if (-not $crtDir -or -not (Test-Path $crtDir)) {
    throw "VC++ runtime directory not found for $Arch; install the MSVC redistributable component"
}

foreach ($dll in 'msvcp140.dll', 'vcruntime140.dll', 'vcruntime140_1.dll') {
    $src = Join-Path $crtDir $dll
    if (-not (Test-Path $src)) {
        throw "VC++ runtime DLL not found: $src"
    }
    Copy-Item $src -Destination $releaseDir -Force
}
Write-Host "Added VC++ runtime from $crtDir"

# 4c. The MSIX helper only makes sense for the installer; portable users must not register an MSIX
#     package. Only the copies inside the build output are removed, so the next build still works.
foreach ($extra in 'localsend_msix_helper.msix', 'install_msix_helper.ps1', 'localsend_app.exe.manifest') {
    $path = Join-Path $releaseDir $extra
    if (Test-Path $path) {
        Remove-Item $path -Force
        Write-Host "Removed $extra from the portable bundle"
    }
}

# 5. Zip every file and subdirectory of the Release output into app/dist.
New-Item -ItemType Directory -Force -Path $distDir | Out-Null
Compress-Archive -Path "$releaseDir\*" -DestinationPath $zipPath -Force

$zip = Get-Item $zipPath
$files = Get-ChildItem $releaseDir -Recurse -File
$unpackedMB = [math]::Round(($files | Measure-Object Length -Sum).Sum / 1MB, 1)
Write-Host ('ZIP: {0}' -f $zip.FullName)
Write-Host ('     {0} MB ({1} files, {2} MB unpacked)' -f [math]::Round($zip.Length / 1MB, 1), $files.Count, $unpackedMB)
Write-Host 'Portable and unsigned: unpack into a new empty directory, start localsend_app.exe,'
Write-Host 'and confirm that Portable Mode is true (Settings > About > Debugging).'

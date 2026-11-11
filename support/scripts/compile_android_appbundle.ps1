# UNCOMMENT THESE LINES TO BUILD FROM LATEST COMMIT
# git reset --hard origin/main
# git pull

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
Set-Location (Join-Path $repoRoot 'app')
fvm flutter clean
fvm flutter pub get
fvm flutter build appbundle
Set-Location $repoRoot

Write-Output 'Generated Android Appbundle!'

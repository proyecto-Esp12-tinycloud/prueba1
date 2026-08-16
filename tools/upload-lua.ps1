param(
    [string]$ComPort = 'COM4',
    [string]$InitLua = 'firmware\init.lua',
    [string]$PageHtml = 'firmware\page.html'
)

$upload = Join-Path $PSScriptRoot "nodemcu-upload.ps1"

Write-Host "Subiendo $InitLua..."
& powershell -ExecutionPolicy Bypass -File $upload -ComPort $ComPort -File (Join-Path $PSScriptRoot "..\$InitLua") -Dest init.lua
if ($LASTEXITCODE -ne 0) { Write-Error "Fallo subiendo init.lua"; exit $LASTEXITCODE }

if (Test-Path (Join-Path $PSScriptRoot "..\$PageHtml")) {
    Write-Host "Subiendo $PageHtml..."
    & powershell -ExecutionPolicy Bypass -File $upload -ComPort $ComPort -File (Join-Path $PSScriptRoot "..\$PageHtml") -Dest page.html
    if ($LASTEXITCODE -ne 0) { Write-Error "Fallo subiendo page.html"; exit $LASTEXITCODE }
}

Write-Host "OK. Archivos Lua subidos."
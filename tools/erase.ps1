param([string]$ComPort = 'COM4')

Write-Host "Borrando TODO el flash en $ComPort..."
python -m esptool --port $ComPort erase_flash
if ($LASTEXITCODE -ne 0) { Write-Error "Erase fallo (codigo $LASTEXITCODE)"; exit $LASTEXITCODE }
Write-Host "OK. Flash borrado. Ahora correr tools\flash.ps1 para re-flashear el firmware."
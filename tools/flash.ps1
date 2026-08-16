param(
    [string]$ComPort = 'COM4',
    [int]$Baud = 460800,
    [string]$File = 'nodemcu-main\nodemcu-release-8mod-float.bin'
)

if (-not (Test-Path $File)) { Write-Error "No existe $File"; exit 1 }

Write-Host "Flasheando $File a 0x0 en $ComPort..."
python -m esptool --port $ComPort --baud $Baud write_flash --verify -fm qio -fs 4MB -ff 40m 0x0 $File
if ($LASTEXITCODE -ne 0) { Write-Error "Flash fallo (codigo $LASTEXITCODE)"; exit $LASTEXITCODE }
Write-Host "OK. Firmware flasheado y verificado."
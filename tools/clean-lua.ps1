param([string]$ComPort = 'COM4')

$cmd = "for k,v in pairs(file.list()) do file.remove(k) end; print('FS limpio')"
Write-Host "Borrando todos los archivos del FS de Lua en $ComPort..."
& powershell -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "..\nodemcu-main\serial-cmd.ps1") -ComPort $ComPort -Cmd $cmd -Seconds 5
Write-Host "Verificando..."
& powershell -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "..\nodemcu-main\serial-cmd.ps1") -ComPort $ComPort -Cmd "for k,v in pairs(file.list()) do print(k) end" -Seconds 5
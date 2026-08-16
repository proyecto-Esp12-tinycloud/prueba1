param([string]$ComPort = 'COM4', [int]$Seconds = 10)

& powershell -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "..\nodemcu-main\serial-read.ps1") -ComPort $ComPort -Seconds $Seconds
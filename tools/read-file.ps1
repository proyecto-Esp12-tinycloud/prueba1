param(
    [string]$ComPort = 'COM4',
    [int]$Baud = 115200,
    [string]$File = 'init.lua',
    [string]$Dest = '',
    [int]$TimeoutSec = 25
)

if (-not $Dest) { $Dest = Join-Path $PSScriptRoot "..\firmware\$File" }
$destDir = Split-Path -Parent $Dest
if ($destDir -and -not (Test-Path $destDir)) {
    New-Item -ItemType Directory -Path $destDir -Force | Out-Null
}

$cmd = "local f=file.open('$File','r');if not f then print('E')else local n=0;while true do local s=f:read(60);if not s then break end;local h='';for i=1,#s do h=h..string.format('%02x',s:byte(i))end;print(n..' '..h);n=n+1 end;f:close();print('DONE')end"
if ($cmd.Length -gt 250) { Write-Error "Comando demasiado largo ($($cmd.Length)) para el REPL"; exit 1 }

$sp = New-Object System.IO.Ports.SerialPort($ComPort, $Baud, 'None', 8, 'One')
$sp.Encoding = [System.Text.Encoding]::UTF8
$sp.ReadTimeout = 1000
$sp.WriteTimeout = 1000

try {
    $sp.Open()
    Start-Sleep -Milliseconds 400
    $sp.DiscardInBuffer()
    $sp.Write($cmd + "`r`n")

    $b = New-Object System.Text.StringBuilder
    $deadline = [Environment]::TickCount + ($TimeoutSec * 1000)
    while ([Environment]::TickCount -lt $deadline) {
        if ($sp.BytesToRead -gt 0) {
            [void]$b.Append($sp.ReadExisting())
            if ($b.ToString() -match '(?m)^DONE\s*$') { break }
        } else {
            Start-Sleep -Milliseconds 50
        }
    }
    $out = $b.ToString()

    $bytes = New-Object System.Collections.Generic.List[byte]
    foreach ($line in ($out -split '\r?\n')) {
        if ($line -match '^\d+ ([0-9a-f]+)$') {
            $hex = $Matches[1]
            for ($i = 0; $i -lt $hex.Length; $i += 2) {
                $bytes.Add([Convert]::ToByte($hex.Substring($i, 2), 16))
            }
        }
    }

    if ($bytes.Count -eq 0) {
        if ($out -match '(?m)^E\s*$') { Write-Error "No se pudo abrir '$File' en el chip"; exit 1 }
        Write-Error "Sin respuesta del chip. Output: $out"; exit 1
    }

    [System.IO.File]::WriteAllBytes($Dest, $bytes.ToArray())
    Write-Host "OK. '$File' extraido ($($bytes.Count) bytes) -> $Dest"
}
finally {
    if ($sp.IsOpen) { $sp.Close() }
    $sp.Dispose()
}
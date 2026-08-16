param(
    [string]$ComPort = 'COM5',
    [int]$Baud = 115200,
    [string]$File = '',
    [string]$Dest = 'init.lua',
    [switch]$Run
)

if (-not $File) { Write-Error "Indica el archivo con -File"; exit 1 }
if (-not (Test-Path $File)) { Write-Error "No existe $File"; exit 1 }

$content = [System.IO.File]::ReadAllText($File)
$bytes = [System.Text.Encoding]::UTF8.GetBytes($content)
$chunkSize = 60

function Wait-Prompt($sp, $timeoutMs = 3000) {
    $deadline = [Environment]::TickCount + $timeoutMs
    $acc = New-Object System.Text.StringBuilder
    while ([Environment]::TickCount -lt $deadline) {
        if ($sp.BytesToRead -gt 0) {
            $data = $sp.ReadExisting()
            [void]$acc.Append($data)
            if ($acc.ToString() -match '>') { return $acc.ToString() }
        } else {
            Start-Sleep -Milliseconds 50
        }
    }
    return $acc.ToString()
}

function Send-Cmd($sp, $cmd) {
    $sp.Write($cmd + "`r`n")
    Start-Sleep -Milliseconds 80
    return Wait-Prompt $sp
}

$sp = New-Object System.IO.Ports.SerialPort($ComPort, $Baud, 'None', 8, 'One')
$sp.ReadTimeout = 1000
$sp.WriteTimeout = 1000

try {
    $sp.Open()
    Start-Sleep -Milliseconds 500

    Write-Host "Limpiando consola..."
    Send-Cmd $sp "" | Out-Null

    Write-Host "Borrando archivo remoto existente..."
    Send-Cmd $sp "file.remove(`"$Dest`")" | Out-Null

    Write-Host "Abriendo $Dest para escritura..."
    $r = Send-Cmd $sp "f = file.open(`"$Dest`", `"w`")"
    if ($r -match 'error|attempt') { Write-Host "ERROR al abrir: $r"; exit 1 }

    Write-Host "Subiendo en chunks de $chunkSize bytes..."
    $total = [Math]::Ceiling($bytes.Length / $chunkSize)
    for ($i = 0; $i -lt $bytes.Length; $i += $chunkSize) {
        $len = [Math]::Min($chunkSize, $bytes.Length - $i)
        $seg = [System.Text.Encoding]::UTF8.GetString($bytes, $i, $len)
        $esc = ($seg -replace "\\", "\\") -replace "'", "\'" -replace "`n", "\n" -replace "`r", "\r"
        $n = $i / $chunkSize + 1
        $r = Send-Cmd $sp "f:write('$esc')"
        if ($r -match 'attempt to|bad argument|stdin:\d|closed file|out of memory') { Write-Host "ERROR chunk $n/$total : $r"; exit 1 }
        Write-Host ("  chunk {0}/{1} ok" -f $n, $total)
    }

    Write-Host "Cerrando archivo..."
    $r = Send-Cmd $sp "f:close()"
    if ($r -match 'attempt to|bad argument|stdin:\d|closed file|out of memory') { Write-Host "ERROR al cerrar: $r"; exit 1 }

    Write-Host "Verificando tamano remoto..."
    $r = Send-Cmd $sp "f = file.open(`"$Dest`", `"r`"); print('size=' .. f:seek(`"end`")); f:close()"
    Write-Host "  -> $r"

    if ($Run) {
        Write-Host "Ejecutando dofile($Dest)..."
        $r = Send-Cmd $sp "dofile(`"$Dest`")"
        Write-Host "  -> $r"
    }

    Write-Host "OK. Subida completa."
}
finally {
    if ($sp.IsOpen) { $sp.Close() }
    $sp.Dispose()
}

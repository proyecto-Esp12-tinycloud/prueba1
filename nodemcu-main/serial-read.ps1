param([string]$ComPort = 'COM5', [int]$Baud = 115200, [int]$Seconds = 8)

$sp = New-Object System.IO.Ports.SerialPort($ComPort, $Baud, 'None', 8, 'One')
$sp.ReadTimeout = 1000
$sp.WriteTimeout = 1000

try {
    $sp.Open()
    Start-Sleep -Milliseconds 400
    $sp.Write("`r`n")
    $b = New-Object System.Text.StringBuilder
    $dl = [Environment]::TickCount + ($Seconds * 1000)
    while ([Environment]::TickCount -lt $dl) {
        if ($sp.BytesToRead -gt 0) {
            [void]$b.Append($sp.ReadExisting())
        } else {
            Start-Sleep -Milliseconds 100
        }
    }
    Write-Host $b.ToString()
}
finally {
    if ($sp.IsOpen) { $sp.Close() }
    $sp.Dispose()
}

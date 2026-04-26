param([string]$DumpPath)

$fs = [System.IO.File]::OpenRead($DumpPath)
$br = New-Object System.IO.BinaryReader $fs

$magic = $br.ReadBytes(4)
if ($magic[0] -ne 0x4D -or $magic[1] -ne 0x44 -or $magic[2] -ne 0x4D -or $magic[3] -ne 0x50) {
    Write-Host "Not a minidump"; exit 1
}
$null = $br.ReadUInt32()
$nStreams = $br.ReadUInt32()
$streamDirRva = $br.ReadUInt32()
$null = $br.ReadUInt32(); $null = $br.ReadUInt32(); $null = $br.ReadUInt64()

$fs.Seek($streamDirRva, 'Begin') | Out-Null
$streams = @()
for ($i=0; $i -lt $nStreams; $i++) {
    $stype = $br.ReadUInt32()
    $ssize = $br.ReadUInt32()
    $srva  = $br.ReadUInt32()
    $streams += [PSCustomObject]@{Type=$stype; Size=$ssize; Rva=$srva}
}

# Type 6 = ExceptionStream
$ex = $streams | Where-Object { $_.Type -eq 6 } | Select-Object -First 1
if (-not $ex) { Write-Host "No exception stream"; exit 0 }

$fs.Seek([long]$ex.Rva, 'Begin') | Out-Null
$threadId = $br.ReadUInt32()
$null = $br.ReadUInt32() # alignment
$excCode = $br.ReadUInt32()
$excFlags = $br.ReadUInt32()
$excRecord = $br.ReadUInt64()
$excAddr = $br.ReadUInt64()
$nParams = $br.ReadUInt32()
$null = $br.ReadUInt32()
$params = @()
for ($i=0; $i -lt 15; $i++) { $params += $br.ReadUInt64() }

$dumpFile = Split-Path $DumpPath -Leaf
Write-Host "=== $dumpFile ==="
$ecHex = '{0:x8}' -f $excCode
$eaHex = '{0:x}' -f $excAddr
Write-Host "ThreadId: $threadId"
Write-Host "ExceptionCode: 0x$ecHex"
Write-Host "ExceptionAddress: 0x$eaHex"
Write-Host "Params (first 4):"
for ($i=0; $i -lt 4; $i++) {
    $pHex = '{0:x}' -f $params[$i]
    Write-Host "  [$i] = 0x$pHex"
}

$br.Close(); $fs.Close()

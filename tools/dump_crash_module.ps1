param([string]$DumpPath, [uint64]$Addr)

$fs = [System.IO.File]::OpenRead($DumpPath)
$br = New-Object System.IO.BinaryReader $fs
$null = $br.ReadBytes(4)
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

# Type 4 = ModuleListStream
$ml = $streams | Where-Object { $_.Type -eq 4 } | Select-Object -First 1
$fs.Seek([long]$ml.Rva, 'Begin') | Out-Null
$nModules = $br.ReadUInt32()
Write-Host "Modules: $nModules. Address 0x$($Addr.ToString('x'))"
$found = $false
for ($i=0; $i -lt $nModules; $i++) {
    $base = $br.ReadUInt64()
    $size = $br.ReadUInt32()
    $null = $br.ReadUInt32() # checksum
    $null = $br.ReadUInt32() # timestamp
    $nameRva = $br.ReadUInt32()
    # MINIDUMP_MODULE is 108 bytes total; we've read 24 (base+size+checksum+ts+nameRva); skip 84 more
    $br.ReadBytes(84) | Out-Null
    $end = $base + $size
    # List all modules and their range; flag the one containing $Addr
    $savedPos = $fs.Position
    $fs.Seek([long]$nameRva, 'Begin') | Out-Null
    $nameBytes = $br.ReadUInt32()
    $nameRaw = $br.ReadBytes($nameBytes)
    $name = [System.Text.Encoding]::Unicode.GetString($nameRaw)
    $fs.Seek($savedPos, 'Begin') | Out-Null
    $marker = ''
    if ($Addr -ge $base -and $Addr -lt $end) { $marker = ' <-- CRASH HERE'; $found = $true }
    if ($name -match 'dwmapi|dll' -or $marker) {
        Write-Host ("  base=0x{0,-14:x} end=0x{1,-14:x} {2}{3}" -f $base, $end, ($name -split '\\')[-1], $marker)
    }
}
if (-not $found) { Write-Host "Address not in any loaded module" }
$br.Close(); $fs.Close()

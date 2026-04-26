param([string]$DumpPath = 'C:\temp\dumps\Longvinter.dmp')

$targets = @(
    # The chunks pointer from FUObjectArray
    @{ Name='Chunks array (5 chunk pointers)'; VA=[uint64]0x18787bb9a88c0 }
)
$NumBytes = 64

$fs = [System.IO.File]::OpenRead($DumpPath)
$br = New-Object System.IO.BinaryReader $fs

$magic = $br.ReadBytes(4)
if ($magic[0] -ne 0x4D -or $magic[1] -ne 0x44 -or $magic[2] -ne 0x4D -or $magic[3] -ne 0x50) {
    Write-Host "Not a minidump"; exit 1
}
$null = $br.ReadUInt32()
$nStreams = $br.ReadUInt32()
$streamDirRva = $br.ReadUInt32()
$null = $br.ReadUInt32()
$null = $br.ReadUInt32()
$null = $br.ReadUInt64()

$streamDirHex = '{0:x}' -f $streamDirRva
Write-Host "Streams: $nStreams, dir RVA: 0x$streamDirHex"

$fs.Seek($streamDirRva, 'Begin') | Out-Null
$streams = @()
for ($i=0; $i -lt $nStreams; $i++) {
    $stype = $br.ReadUInt32()
    $ssize = $br.ReadUInt32()
    $srva  = $br.ReadUInt32()
    $streams += [PSCustomObject]@{Type=$stype; Size=$ssize; Rva=$srva}
    $rvaHex = '{0:x}' -f $srva
    Write-Host ("  Type={0,-6} Size={1,-12} Rva=0x{2}" -f $stype, $ssize, $rvaHex)
}

function Read-Target($targets, $br, $fs, $NumBytes, $rangeList, $is64) {
    foreach ($t in $targets) {
        $vaHex = '{0:x}' -f $t.VA
        $hit = $null
        foreach ($r in $rangeList) {
            if ($t.VA -ge $r.Start -and $t.VA -lt ($r.Start + $r.Size)) {
                $hit = $r; break
            }
        }
        if ($null -ne $hit) {
            $offset = [uint64]($t.VA - $hit.Start)
            $fileOff = [uint64]$hit.Rva + $offset
            $fs.Seek([long]$fileOff, 'Begin') | Out-Null
            $bytes = $br.ReadBytes($NumBytes)
            $hex = ($bytes | ForEach-Object { '{0:x2}' -f $_ }) -join ' '
            $tn = $t.Name
            Write-Host "$tn @ VA 0x${vaHex}: $hex"
        } else {
            $tn = $t.Name
            Write-Host "$tn @ VA 0x${vaHex}: NOT FOUND"
        }
    }
}

# Memory64ListStream = 9
$mem64 = $streams | Where-Object { $_.Type -eq 9 } | Select-Object -First 1
if ($mem64) {
    $rvaHex = '{0:x}' -f $mem64.Rva
    Write-Host "Mem64Stream at 0x$rvaHex"
    $fs.Seek([long]$mem64.Rva, 'Begin') | Out-Null
    $nRanges = $br.ReadUInt64()
    $baseRva = $br.ReadUInt64()
    Write-Host "  $nRanges ranges, baseRva=0x$('{0:x}' -f $baseRva)"
    $cur = [uint64]$baseRva
    $ranges = @()
    for ($i=0; $i -lt [int]$nRanges; $i++) {
        $startVa = $br.ReadUInt64()
        $size    = $br.ReadUInt64()
        $ranges += [PSCustomObject]@{Start=$startVa; Size=$size; Rva=$cur}
        $cur += $size
    }
    Read-Target $targets $br $fs $NumBytes $ranges $true
} else {
    # MemoryListStream = 5
    $mem5 = $streams | Where-Object { $_.Type -eq 5 } | Select-Object -First 1
    if ($mem5) {
        $rvaHex = '{0:x}' -f $mem5.Rva
        Write-Host "MemoryListStream at 0x$rvaHex"
        $fs.Seek([long]$mem5.Rva, 'Begin') | Out-Null
        $nRanges = $br.ReadUInt32()
        Write-Host "  $nRanges ranges"
        $ranges = @()
        for ($i=0; $i -lt [int]$nRanges; $i++) {
            $startVa = $br.ReadUInt64()
            $size    = $br.ReadUInt32()
            $rva     = $br.ReadUInt32()
            $ranges += [PSCustomObject]@{Start=$startVa; Size=$size; Rva=$rva}
        }
        Read-Target $targets $br $fs $NumBytes $ranges $false
    } else {
        Write-Host "No memory stream found in dump"
    }
}

$br.Close(); $fs.Close()

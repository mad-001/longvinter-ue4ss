# DLL Injector via P/Invoke
param(
    [Parameter(Mandatory=$true)][string]$ProcessName,
    [Parameter(Mandatory=$true)][string]$DllPath
)

if (-not (Test-Path $DllPath)) { Write-Host "DLL not found: $DllPath"; exit 1 }
$DllPath = (Resolve-Path $DllPath).Path

$proc = Get-Process -Name $ProcessName -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $proc) { Write-Host "Process not found: $ProcessName"; exit 1 }
Write-Host "Target: $ProcessName PID=$($proc.Id)"
Write-Host "DLL: $DllPath"

Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

public class Injector {
    [DllImport("kernel32.dll")]
    public static extern IntPtr OpenProcess(uint access, bool inherit, int pid);
    [DllImport("kernel32.dll")]
    public static extern IntPtr VirtualAllocEx(IntPtr hProc, IntPtr addr, uint size, uint type, uint protect);
    [DllImport("kernel32.dll")]
    public static extern bool WriteProcessMemory(IntPtr hProc, IntPtr addr, byte[] buf, uint size, out IntPtr written);
    [DllImport("kernel32.dll")]
    public static extern IntPtr GetModuleHandleA(string name);
    [DllImport("kernel32.dll")]
    public static extern IntPtr GetProcAddress(IntPtr hMod, string name);
    [DllImport("kernel32.dll")]
    public static extern IntPtr CreateRemoteThread(IntPtr hProc, IntPtr sec, uint stackSize, IntPtr startAddr, IntPtr param, uint flags, IntPtr thrId);
    [DllImport("kernel32.dll")]
    public static extern uint WaitForSingleObject(IntPtr handle, uint ms);
    [DllImport("kernel32.dll")]
    public static extern bool CloseHandle(IntPtr h);
}
"@

$PROCESS_ALL_ACCESS = 0x001F0FFF
$MEM_COMMIT_RESERVE = 0x3000
$PAGE_RW = 4

$hProc = [Injector]::OpenProcess($PROCESS_ALL_ACCESS, $false, $proc.Id)
if ($hProc -eq [IntPtr]::Zero) { Write-Host "OpenProcess failed: $((New-Object System.ComponentModel.Win32Exception([Marshal]::GetLastWin32Error())).Message)"; exit 1 }
Write-Host "OpenProcess OK"

$pathBytes = [System.Text.Encoding]::ASCII.GetBytes($DllPath + "`0")
$remoteAddr = [Injector]::VirtualAllocEx($hProc, [IntPtr]::Zero, $pathBytes.Length, $MEM_COMMIT_RESERVE, $PAGE_RW)
if ($remoteAddr -eq [IntPtr]::Zero) { Write-Host "VirtualAllocEx failed"; exit 1 }
Write-Host "Allocated remote memory at 0x$($remoteAddr.ToString('x'))"

$written = [IntPtr]::Zero
$ok = [Injector]::WriteProcessMemory($hProc, $remoteAddr, $pathBytes, [uint32]$pathBytes.Length, [ref]$written)
if (-not $ok) { Write-Host "WriteProcessMemory failed"; exit 1 }
Write-Host "Wrote DLL path ($($pathBytes.Length) bytes)"

$kernel32 = [Injector]::GetModuleHandleA("kernel32.dll")
$loadLibraryA = [Injector]::GetProcAddress($kernel32, "LoadLibraryA")
if ($loadLibraryA -eq [IntPtr]::Zero) { Write-Host "GetProcAddress LoadLibraryA failed"; exit 1 }
Write-Host "LoadLibraryA at 0x$($loadLibraryA.ToString('x'))"

$thrHandle = [Injector]::CreateRemoteThread($hProc, [IntPtr]::Zero, 0, $loadLibraryA, $remoteAddr, 0, [IntPtr]::Zero)
if ($thrHandle -eq [IntPtr]::Zero) { Write-Host "CreateRemoteThread failed"; exit 1 }
Write-Host "Remote thread created, waiting up to 30s..."

$waitResult = [Injector]::WaitForSingleObject($thrHandle, 30000)
Write-Host "Wait result: $waitResult (0=signaled, 0x102=timeout)"

[Injector]::CloseHandle($thrHandle) | Out-Null
[Injector]::CloseHandle($hProc) | Out-Null
Write-Host "Injection complete"

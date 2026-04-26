# Tools

PowerShell utilities used during the reverse-engineering of Uuvana's UE 5.7.2 build.

## inject_dll.ps1

DLL injector via P/Invoke. Used to inject Dumper-7.dll into the running game process.

```powershell
.\inject_dll.ps1 -ProcessName "LongvinterServer-Win64-Shipping" -DllPath "C:\path\to\Dumper-7.dll"
```

Internals: `OpenProcess(PROCESS_ALL_ACCESS)` → `VirtualAllocEx` → `WriteProcessMemory(dll_path)` → `CreateRemoteThread(LoadLibraryA, dll_path_addr)`.

## dump_crash_exception.ps1

Reads a Windows minidump and prints the exception address + parameters.

```powershell
.\dump_crash_exception.ps1 -DumpPath "...\ue4ss\crash_2026_04_26_10_58_16.dmp"
```

Output:
```
ExceptionCode: 0xc0000005
ExceptionAddress: 0x7fffba34b0b1
Params: [0]=0x0 (read), [1]=0x1991ea (address being accessed)
```

## dump_crash_module.ps1

Identifies which loaded module contains a given crash address.

```powershell
.\dump_crash_module.ps1 -DumpPath "...\crash.dmp" -Addr 0x7fffba34b0b1
```

Output highlights the matching module:
```
base=0x7fffb9f90000   end=0x7fffbaf20000   UE4SS.dll <-- CRASH HERE
```

The crash offset within the DLL = `Addr - module_base`. That offset is deterministic across runs even though ASLR moves the module base.

## extract_minidump_bytes.ps1

Reads bytes from arbitrary virtual addresses out of a Windows minidump (handles both `MemoryListStream` and `Memory64ListStream`). Useful for inspecting the live memory state captured at the moment of crash without re-running the game.

Edit the `$targets` array at the top to set what to read.

## Requirements

All scripts run on Windows PowerShell 5+ (ships with Windows). No external dependencies. The injector requires admin privileges to inject into a service-running process.

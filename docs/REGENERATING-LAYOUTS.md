# Regenerating layouts after a Longvinter / UE upgrade

If a future Longvinter update changes UE struct layouts, the steps below regenerate `MemberVariableLayout.ini` from a fresh SDK dump.

## 1. Build Dumper-7

On a machine with Visual Studio 2022 (Community is fine):

```bash
git clone --depth 1 https://github.com/Encryqed/Dumper-7.git
cd Dumper-7\Dumper
"C:\Program Files\Microsoft Visual Studio\2022\Community\MSBuild\Current\Bin\MSBuild.exe" Dumper.vcxproj /p:Configuration=Release /p:Platform=x64 /p:PlatformToolset=v143
```

Output: `Dumper-7\Dumper\x64\Release\Dumper-7.dll`

## 2. Inject into the running server

Use `tools/inject_dll.ps1` (P/Invoke DLL injector):

```powershell
.\inject_dll.ps1 -ProcessName "LongvinterServer-Win64-Shipping" -DllPath "C:\path\to\Dumper-7.dll"
```

The injection takes a couple seconds; Dumper-7 then writes `C:\Dumper-7\<engine-version>-Longvinter\` (~300 MB, 3000+ files).

## 3. Read the new layouts

Open `C:\Dumper-7\<engine-version>-Longvinter\CppSDK\SDK\Basic.hpp` and look for:

- `// Predefined struct FUObjectItem`
- `// Predefined struct TUObjectArray`
- `// Predefined struct FUObjectArray`
- `// Predefined struct FName`
- `// Predefined struct FField`

Each block lists every member with its byte offset (`// 0x0008(0x0008)` = field is at offset 0x8, size 8 bytes).

For derived classes (`UStruct`, `UClass`, `UFunction`, `UEnum`), look in `CoreUObject_classes.hpp`.

## 4. Update MemberVariableLayout.ini

Compare the Dumper-7 output to the existing `ue4ss/MemberVariableLayout.ini`. For any struct whose offsets differ, replace that section.

The starting point should always be the official UE4SS template for the engine version:
- `https://github.com/UE4SS-RE/RE-UE4SS/blob/main/assets/MemberVarLayoutTemplates/MemberVariableLayout_<MAJOR>_<MINOR>_Template.ini`

Then layer Uuvana-specific overrides on top.

## 5. Restart and verify

After deploying the updated INI:

```powershell
# stop server (kills the lock)
Stop-Process -Name LongvinterServer-Win64-Shipping -Force
# wait for Monitor.ps1 to auto-restart it, OR launch via Monitor.ps1 directly
```

Tail `ue4ss/UE4SS.log`. Success looks like:

```
Starting Lua mod 'CheatManagerEnablerMod'
...
Event loop start
[FCallbackGarbageCollector] Freed invalid callbacks!
```

Failure looks like a process crash dump (`crash_*.dmp`) appearing in `ue4ss/`. Use `tools/dump_crash_exception.ps1` to read its `ExceptionAddress`, then `tools/dump_crash_module.ps1` to find which DLL it's in. If it's UE4SS.dll, the crash offset within UE4SS.dll is the same across runs (deterministic), so disassembling that offset in `UE4SS.dll` (capstone or Ghidra) tells you which struct field UE4SS is mis-reading.

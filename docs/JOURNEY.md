# How this configuration was discovered

A 12+ hour debugging session on 2026-04-25/26 to make UE4SS work on Longvinter.

## The problem

Stock UE4SS (any build, including the experimental v3.0.1-946-g265115c0) refuses to attach to Longvinter's dedicated server with this in the log:

```
[PS] Failed to find FName::FName(wchar_t*): FNameCtorWchar: expected at least one value
[PS] Failed to find GNatives: GNatives: expected at least one value
[PS] Failed to find StaticConstructObject_Internal: ...
[PS] Failed to find FUObjectHashTables::Get(): ...
Fatal Error: PS scan timed out
```

UE4SS's pattern scanner (`patternsleuth`) cannot find any of the AOBs it needs. Without them, UE4SS can't hook anything.

The binary on disk: `Longvinter/Binaries/Win64/LongvinterServer-Win64-Shipping.exe` — 158 MB stripped Windows PE, no PDB, built from `F:\uuvana\UE_5.7_Source\` (a custom in-house UE 5.7.2 fork).

## Phase 1: AOB hunting

We found the binary's actual function addresses by:

1. **Static analysis in Ghidra** — imported the exe, ran auto-analysis (24 GB heap, ~50 min), located candidate functions by:
   - Functions calling `wcslen` (filtered for FName::FName(WIDECHAR*) candidates)
   - Functions matching the patternsleuth canonical signatures
   - String anchoring on UE-internal names like `MovementComponent0`, `TGPUSkinVertexFactoryUnlimited`

2. **Procdump validation** — captured a 3.2 GB minidump of the running process (`procdump64 -ma`), then verified candidate addresses against runtime bytes. Caught binary-vs-Ghidra-DB mismatches (the user updated the game during the session, requiring a Ghidra re-analysis).

3. **patternsleuth source** — pulled `patternsleuth/src/resolvers/unreal/{fname,kismet,fuobject_hash_tables}.rs` from GitHub to see the exact byte patterns UE4SS expects, then translated to the nibble-with-slash format Lua signatures use.

This produced the three Lua signatures in `ue4ss/UE4SS_Signatures/`. With these in place, UE4SS's PS scan succeeded.

## Phase 2: The crash that wouldn't quit

After AOBs resolved, UE4SS crashed during init at the same offset every time:

```
ExceptionAddress: 0x...34df2c (FFW build) / 0x...351b0c (UE4SS 946)
ExceptionCode: 0xc0000005 (Access Violation)
Reading at: 0xffffffffffffffff
```

The crashing instruction was always `mov rdx, [rax]` after a call to a `_Init_thread_header`-style helper that returns `rbx + cached_offset`. The cached offset came from looking up a UE struct field name (`NamePrivate`, `RefLink`, `ChildProperties`, etc.) in a hash table populated by `MemberVariableLayout.ini`.

We tried:
- Various MemberVariableLayout.ini configs (Silent Hill F, Palworld) — partial fix
- Disabling individual UE4SS hooks — didn't help (crash before hooks install)
- Patching UE4SS.dll to bypass the crashing code — bypass worked but UE4SS spun forever in `while (!KismetStringLibrary)`, then crashed dereferencing the null result
- Switching between UE4SS DLL builds (ours 946, FFW 938) — same crash, different offset
- Setting `DefaultFNameToStringMethod = Conv_NameToString` (chicken/egg, needs KismetSystemLibrary first)

Server stayed alive but UE4SS never completed init. We held in this partial state for ~6 hours of stability monitoring.

## Phase 3: The breakthrough — Dumper-7

The path forward: stop guessing UE struct offsets, just **read them from the running binary**.

[Dumper-7](https://github.com/Encryqed/Dumper-7) is an injectable SDK generator that walks GUObjectArray inside the live process and writes complete C++ headers for every UClass with discovered offsets.

Steps:

1. Cloned Dumper-7 source, built `Dumper-7.dll` with MSBuild (`/p:Configuration=Release /p:Platform=x64 /p:PlatformToolset=v143`) — output ~1.4 MB.
2. Wrote a PowerShell DLL injector (`tools/inject_dll.ps1`) using P/Invoke: `OpenProcess` → `VirtualAllocEx` → `WriteProcessMemory` → `CreateRemoteThread` targeting `LoadLibraryA`.
3. Injected into the running `LongvinterServer-Win64-Shipping.exe`. Wait result was 0 (signaled).
4. Dumper-7 generated 3,498 files to `C:\Dumper-7\5.7.2-0+UE5-Longvinter\` — full SDK, GObjects dump, mappings.

Reading `CppSDK/SDK/Basic.hpp`:

```cpp
// Predefined struct FUObjectItem
// 0x0020 (0x0020 - 0x0000)
struct FUObjectItem final
{
    uint8                 Pad_0[0x8];      // 0x0000(0x0008)
    class UObject*        Object;          // 0x0008(0x0008)  ← +0x8, NOT +0x0
    uint8                 Pad_10[0x10];    // 0x0010(0x0010)
};                                          // total 0x20, NOT 0x18
```

This was the answer. **Uuvana customized FUObjectItem** to add 8 bytes of padding before AND after the Object pointer, making the struct 32 bytes instead of stock 24. UE4SS's iteration walks the chunks with stride 24, reads `[item + 0x00]` expecting the Object pointer, gets padding (zeros) every time, sees every UObject as null, gives up.

## Phase 4: The fix

Updated `MemberVariableLayout.ini` with:

```ini
[FUObjectItem]
Object = 0x8           ; was 0x0 in stock
Flags = 0x10
ClusterAndFlags = 0x10
FlagsAndRefCount = 0x10
ClusterRootIndex = 0x14
ClusterIndex = 0x14
SerialNumber = 0x18
RefCount = 0x18
UEP_TotalSize = 0x20   ; was 0x18 in stock
```

(All other Uuvana struct layouts match UE4SS's official UE 5.07 template, so we use that template as the base.)

Restarted the server. UE4SS log proceeded straight through:

```
GameModeBase::InitGameState address 0x...
AActor::BeginPlay address 0x...
ProcessEvent address 0x...
Constructed 1 of 1 objects
Locating KismetSystemLibrary...
Locating KismetSystemLibrary:Conv_NameToString...
Locating KismetSystemLibrary CDO...
Starting Lua mod 'CheatManagerEnablerMod'
Starting Lua mod 'ConsoleEnablerMod'
Starting Lua mod 'BPModLoaderMod'
CreateLogicModsDirectory: LogicMods directory created.
Starting Lua mod 'Keybinds'
Event loop start
[FCallbackGarbageCollector] Freed invalid callbacks!
```

Done.

## Lessons

- For obscure UE customizations, **dump first, debug second**. Dumper-7 would have saved ~10 hours if reached for earlier.
- UE4SS's `MemberVariableLayout.ini` is powerful but the lookups are silent — when a field offset is wrong, you get crashes deep in seemingly unrelated code, not "field offset wrong" errors.
- The official UE4SS template files at `assets/MemberVarLayoutTemplates/MemberVariableLayout_5_07_Template.ini` are the right starting point for any UE 5.7 game; only override what's actually different in your binary.

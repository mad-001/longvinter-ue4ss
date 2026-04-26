# UE4SS for Longvinter (Uuvana UE 5.7.2)

A working configuration for **[UE4SS](https://github.com/UE4SS-RE/RE-UE4SS)** (Unreal Engine Scripting System) on **Longvinter** dedicated servers running Uuvana's custom-compiled UE 5.7.2 engine.

Out-of-the-box UE4SS does not work on this build because Uuvana modified internal UE struct layouts. This package provides the exact configuration needed to make UE4SS attach, hook, and load Lua mods on Longvinter.

## Status

✅ UE4SS attaches without crashing
✅ All AOB scans resolve (FName::FName, GNatives, StaticConstructObject)
✅ Engine struct walking works (GUObjectArray iteration)
✅ KismetSystemLibrary lookup completes
✅ All UE4SS hooks install (ProcessEvent, ProcessConsoleExec, EngineTick, etc.)
✅ Lua mods load and execute
✅ Blueprint mod loader (BPModLoaderMod) initializes; LogicMods directory created
✅ Native function hooks register

## Quick install

1. Stop the Longvinter dedicated server.
2. Copy `proxy/dwmapi.dll` to `<game>/Longvinter/Binaries/Win64/`
3. Copy the contents of `ue4ss/` to `<game>/Longvinter/Binaries/Win64/ue4ss/` (creating the folder)
4. Start the server. UE4SS will load on next launch.

The full path layout in the game folder should look like:

```
Longvinter/Binaries/Win64/
├── LongvinterServer-Win64-Shipping.exe
├── dwmapi.dll                              ← from proxy/
└── ue4ss/
    ├── UE4SS.dll                           ← from ue4ss/
    ├── UE4SS-settings.ini                  ← from ue4ss/
    ├── MemberVariableLayout.ini            ← from ue4ss/  (CRITICAL)
    ├── UE4SS_Signatures/
    │   ├── FName_Constructor.lua
    │   ├── GNatives.lua
    │   └── StaticConstructObject.lua
    └── Mods/                               ← drop your Lua mods here
```

## What's in this repo

- `ue4ss/` — drop-in replacement folder for `<game>/Win64/ue4ss/`
- `proxy/dwmapi.dll` — UE4SS proxy DLL (drop into `<game>/Win64/`)
- `tools/` — PowerShell utilities used during reverse engineering
- `docs/` — technical write-up of how this was figured out, in case Uuvana changes the engine again

## What makes Longvinter different

Standard UE 5.7 layouts (used by stock UE4SS) do not match Uuvana's compiled binary. Specifically:

- **`FUObjectItem`** is **32 bytes** (not 24), with the `Object` pointer at **+0x8** (not +0x0). Uuvana added 8 bytes of padding before AND after the Object field.
- All other major structs (`UObjectBase`, `UStruct`, `UClass`, `UFunction`, `FField`, etc.) match the official UE 5.07 template offsets.

UE4SS's `MemberVariableLayout.ini` is the override mechanism for this. The file in this repo is the official UE4SS UE 5.07 template plus a Uuvana-specific `[FUObjectItem]` block.

## How the UE struct layouts were discovered

We injected **[Dumper-7](https://github.com/Encryqed/Dumper-7)** into the running server to generate a complete C++ SDK from Uuvana's binary, then read `Basic.hpp` for the exact `FUObjectItem` definition.

If Uuvana ever updates the engine and breaks this config:
1. Build Dumper-7 (`tools/build-dumper-7.md` — see docs)
2. Inject it via `tools/inject_dll.ps1`
3. Read `C:\Dumper-7\<engine-version>-Longvinter\CppSDK\SDK\Basic.hpp` for the new layouts
4. Update `MemberVariableLayout.ini` accordingly

See `docs/JOURNEY.md` for the full back-story.

## Credits

- **[UE4SS](https://github.com/UE4SS-RE/RE-UE4SS)** — the engine scripting system itself
- **[Far Far West UE4SS package](https://www.nexusmods.com/farfarwest/mods/2)** — the UE4SS DLL build used here is from the Far Far West UE 5.7 package (commit g733e596). Their FName_Constructor.lua and GNatives.lua signatures were kept.
- **[Dumper-7](https://github.com/Encryqed/Dumper-7)** by Encryqed — the SDK dumper that made discovery possible
- **[patternsleuth](https://github.com/trumank/patternsleuth)** — UE4SS's AOB scanner; its source informed the GNatives Lua signature

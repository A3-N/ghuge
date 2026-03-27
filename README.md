# ghuge - Windows hash-cracker TUI

This is a Windows PowerShell hash-cracker TUI inspired by [SensePost's hash-cracker](https://github.com/sensepost/hash-cracker). It acts as an orchestration layer for hashcat, allowing users to rapidly configure, execute, and analyze hash attacks from a fully interactive terminal menu.

The core design revolves around "TheNumbers" - a directory of PowerShell attack scripts that are imported dynamically at runtime. Adding or removing scripts in `TheNumbers/` instantly updates the main interactive menu without modifying the engine.

## Features
- **Dynamic Script Loading**: Drop `.ps1` attack scripts into the `TheNumbers/` folder and they become immediately available in the main menu.
- **Multi-Mode Execution**: Configure multiple hash modes (e.g. `modes 1000, 3000`) and the engine will automatically cross-execute your chosen attack scripts against all selected modes sequentially.
- **Multi-Script Queueing**: Select multiple imported scripts at the interactive prompt (e.g. `1, 3` or `all`) to queue and execute a chain of attack methods back-to-back.
- **Dynamic File Aggregation**: Pass array selections to internal prompts. `ghuge` will aggregate multiple hashlists into temporary combined targets or pool multiple dictionaries into a single concurrent hashcat run.
- **Advanced Stat Parsing**: Dedicated menus to parse the potfile and individual hash directories to extract password lengths, character statistics, extremes, and identify password reuse across different server configurations.
- **Robust Error Handling**: Real-time syntax validation, automatic hex-decoding of complex passwords, and graceful interrupt handling.

## Requirements
- PowerShell 7+ (`pwsh`)
- Windows build of hashcat (point the `hashcat` setting to the folder containing `hashcat.exe`)
- Valid Hashlist, Rulelist, and Wordlist directories

## Quick run
From the script directory run:
```powershell
pwsh -File .\ghuge.ps1

or 

.\ghuge.ps1
```

On first run, the script will prompt for missing base paths and generate a `settings.json`. After configuration, it boots directly into the interactive menu.

## Minimal expected file structure
```
├─ ghuge.ps1
├─ settings.json          # created on first run
├─ TheNumbers/            # dynamically imported attack modules
│  ├─ 1.ps1
│  ├─ 2.ps1
│  └─ 3.ps1
├─ hashes/
│  ├─ 1000/
│  │  └─ target.ntds
│  └─ 22000/
│     └─ handshake.wpa
├─ rulelists/
│  └─ best64.rule
└─ wordlists/
   └─ rockyou.txt
```

## Notes
- Hashcat expects certain folders (e.g. `OpenCL`, `modules`) next to its binary. Point the `hashcat` variable in `ghuge.ps1` to the top-level hashcat directory, not the `.exe` itself.
- Scripts in `TheNumbers` are dot-sourced strictly into the execution environment and rely on secure environment variables exported dynamically from `ghuge.ps1`.

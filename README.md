# ghuge — Windows hash-cracker TUI

This is a tiny Windows version of a hash-cracker TUI (inspired by [SensePost's hash-cracker](https://github.com/sensepost/hash-cracker)).
It launches numbered PowerShell scripts from `TheNumbers/`, stores a small `settings.json` and runs hashcat commands.

## Requirements
- PowerShell 7+ (`pwsh`)
- Windows build of **hashcat** (point `settings.json` `hashcat` to the folder containing `hashcat.exe`)
- Rulelists, Wordlists and Hashes folders (see structure below)

## Quick run
From the script directory run:
```powershell
pwsh -File .\ghuge.ps1

or 

.\ghuge.ps1
```

On first run the script will prompt for missing base paths and create `settings.json`. After that it uses the saved settings automatically.

## Minimal expected file structure
```
├─ ghuge.ps1
├─ settings.json          # created on first run
├─ TheNumbers/
│  ├─ 1.ps1
│  ├─ 2.ps1
│  └─ 3.ps1
├─ hashes/
│  ├─ 1000/
│  │  └─ example.ntlm
│  └─ 22000/
│     └─ example.wpa
├─ rulelists/
│  └─ some.rule
└─ wordlists/
   └─ rockyou.txt
```

## Notes
- Hashcat expects certain folders (e.g. `OpenCL`) next to the binary; point `hashcat` to the top-level hashcat folder.
- Scripts in `TheNumbers` are dot-sourced and rely on environment vars exported from `ghuge.ps1`.

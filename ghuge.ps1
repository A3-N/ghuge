<# ghuge.ps1 (PowerShell 7+) — hash-cracker TUI #>

if (-not $PSVersionTable.PSVersion -or $PSVersionTable.PSVersion.Major -lt 7) {
  Write-Error "ghuge.ps1 requires PowerShell 7+. Detected: $($PSVersionTable.PSVersion)"
  exit 1
}

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ScriptDir    = try { Split-Path -Parent $MyInvocation.MyCommand.Path } catch { (Get-Location).Path }
$Root         = Join-Path -Path $ScriptDir -ChildPath 'TheNumbers'
$SettingsPath = Join-Path -Path $ScriptDir -ChildPath 'settings.json'

# ── Load helpers ─────────────────────────────────────────────────────
$helpersPath = Join-Path -Path $ScriptDir -ChildPath 'helpers.ps1'
if (-not (Test-Path -LiteralPath $helpersPath -PathType Leaf)) {
  Write-Error "helpers.ps1 not found at: $helpersPath"
  exit 1
}
. $helpersPath

if (-not (Test-Path -LiteralPath $Root)) {
  Write-Err "TheNumbers folder not found at: $Root"
  exit 1
}

# ═══════════════════════════════════════════════════════════════════════
#  SETTINGS
# ═══════════════════════════════════════════════════════════════════════

function New-DefaultSettings {
  [ordered]@{
    hashcat    = $null
    rulelists  = $null
    wordlists  = $null
    hashes     = $null
    potfile    = $null
    mode       = 1000
    modes      = @()      # multi-hashmode: when non-empty, attacks repeat for each mode
    loopback   = $true
    kernel     = $false
    hwmon      = $false
    rule_files = @{
      big             = '1big.rule'
      buka            = 'buka_400k.rule'
      d3ad0ne         = 'd3ad0ne.rule'
      d3adhob0        = 'd3adhob0.rule'
      digits1         = 'digits1.rule'
      digits2         = 'digits2.rule'
      digits3         = 'digits3.rule'
      dive            = 'dive.rule'
      fbfull          = 'facebook-firstnames-capital.rule'
      fbtop           = 'facebook-firstnames-capital-top.rule'
      fordyv1         = 'fordyv1.rule'
      generated2      = 'generated2.rule'
      generated3      = 'generated3.rule'
      hob064          = 'hob064.rule'
      huge            = 'huge.rule'
      leetspeak       = 'leetspeak.rule'
      NSAKEYv2        = 'NSAKEY.v2.dive.rule'
      ORTRTA          = 'OneRuleToRuleThemAll.rule'
      ORTRTS          = 'OneRuleToRuleThemStill.rule'
      OUTD            = 'OptimizedUpToDate.rule'
      pantag          = 'pantagrule.popular.rule'
      passwordpro     = 'passwordspro.rule'
      robotmyfavorite = 'Robot_MyFavorite.rule'
      rockyou30000    = 'rockyou-30000.rule'
      rule3           = '3.rule'
      stacking58      = 'stacking58.rule'
      techtrip2       = 'techtrip_2.rule'
      tenKrules       = '10krules.rule'
      toggles1        = 'toggles1.rule'
      toggles2        = 'toggles2.rule'
      toprules2020    = 'toprules2020.rule'
      TOXIC10k        = 'TOXIC-10krules.rule'
      TOXICSP         = 'T0XlC-insert_space_and_special_0_F.rule'
      williamsuper    = 'williamsuper.rule'
    }
    effective = $null
  }
}

function Prompt-For-Dir([string]$Label, [bool]$RequireHashcat = $false) {
  while ($true) {
    Write-C "  Enter " -Fg white -NoNewline
    Write-C $Label -Fg cyan -Bold -NoNewline
    Write-C " path: " -Fg white -NoNewline
    $in = Read-Host
    if ([string]::IsNullOrWhiteSpace($in)) { Write-Warn "  Path cannot be empty."; continue }

    $resolved = Resolve-ExistingDirectory $in
    if (-not $resolved) { Write-Warn "  Directory not found. Try again."; continue }

    if ($RequireHashcat -and -not (Validate-HashcatDir $resolved)) {
      Write-Warn "  No hashcat binary found in that folder. Try again."
      continue
    }
    return $resolved
  }
}

function Run-SetAll {
  Write-Banner "Set All Paths"

  $hc = Prompt-For-Dir -Label "hashcat" -RequireHashcat:$true
  $rl = Prompt-For-Dir -Label "rulelists"
  $wl = Prompt-For-Dir -Label "wordlists"
  $hh = Prompt-For-Dir -Label "hashes"

  $Settings.hashcat   = $hc
  $Settings.rulelists = $rl
  $Settings.wordlists = $wl
  $Settings.hashes    = $hh

  Save-Settings $Settings
  $script:Settings = Load-Settings
  Write-Success "All paths saved."
  Start-Sleep -Milliseconds 600
}

function Resolve-ExistingDirectory([string]$InputPath) {
  if ([string]::IsNullOrWhiteSpace($InputPath)) { return $null }
  $p = $InputPath.Trim().Trim('"', "'")
  try {
    $expanded = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($p)
  } catch { return $null }
  if (Test-Path -LiteralPath $expanded -PathType Container) { return (Resolve-Path -LiteralPath $expanded).Path }
  return $null
}

function Validate-HashcatDir([string]$Dir) {
  if (-not $Dir) { return $false }
  $exe = Join-Path $Dir 'hashcat.exe'
  $bin = Join-Path $Dir 'hashcat'
  return (Test-Path -LiteralPath $exe -PathType Leaf) -or (Test-Path -LiteralPath $bin -PathType Leaf)
}

function Resolve-HashcatExe([string]$Dir) {
  if (-not $Dir) { return $null }
  $exe = Join-Path $Dir 'hashcat.exe'
  $bin = Join-Path $Dir 'hashcat'
  if (Test-Path -LiteralPath $exe -PathType Leaf) { return $exe }
  if (Test-Path -LiteralPath $bin -PathType Leaf) { return $bin }
  return $null
}

function Compute-Effective([object]$cfg) {
  $kernelFlag   = if ($cfg.kernel)   { '-O' }              else { '' }
  $loopbackFlag = if ($cfg.loopback) { '--loopback' }      else { '' }
  $hwmonFlag    = if ($cfg.hwmon)    { '--hwmon-disable' } else { '' }
  $hashcatExe   = Resolve-HashcatExe $cfg.hashcat

  $rulePaths = @{}
  if ($cfg.rule_files) {
    $names = @()
    if ($cfg.rule_files -is [hashtable]) {
      $names = $cfg.rule_files.Keys
    } elseif ($cfg.rule_files.PSObject) {
      $names = $cfg.rule_files.PSObject.Properties.Name
    }

    foreach ($k in $names) {
      $fname = $null
      if ($cfg.rule_files -is [hashtable]) {
        $fname = $cfg.rule_files[$k]
      } else {
        $prop = $cfg.rule_files.PSObject.Properties[$k]
        if ($prop) { $fname = $prop.Value }
      }

      if (-not [string]::IsNullOrWhiteSpace($fname) -and $cfg.rulelists) {
        $rulePaths[$k] = Join-Path -Path $cfg.rulelists -ChildPath $fname
      } else {
        $rulePaths[$k] = $fname
      }
    }
  }

  # resolve potfile path
  $potfilePath = $null
  if ($cfg.potfile -and -not [string]::IsNullOrWhiteSpace($cfg.potfile)) {
    $potfilePath = $cfg.potfile
  } elseif ($cfg.hashcat) {
    # default: hashcat.potfile next to hashcat binary
    $potfilePath = Join-Path $cfg.hashcat 'hashcat.potfile'
  }

  [pscustomobject]@{
    kernelFlag   = $kernelFlag
    loopbackFlag = $loopbackFlag
    hwmonFlag    = $hwmonFlag
    hashcatExe   = $hashcatExe
    hashtype     = $cfg.mode
    rulelists    = Resolve-ExistingDirectory $cfg.rulelists
    wordlists    = Resolve-ExistingDirectory $cfg.wordlists
    hashes       = Resolve-ExistingDirectory $cfg.hashes
    rulePaths    = $rulePaths
    potfile      = $potfilePath
  }
}

function Save-Settings([object]$Settings) {
  $Settings.effective = Compute-Effective $Settings

  if ($Settings.effective -and ($Settings.effective.PSObject.Properties.Name -contains 'rule_files')) {
    $Settings.effective.PSObject.Properties.Remove('rule_files')
  }

  $out = [ordered]@{
    hashcat    = $Settings.hashcat
    rulelists  = $Settings.rulelists
    wordlists  = $Settings.wordlists
    hashes     = $Settings.hashes
    potfile    = $Settings.potfile
    mode       = [int]$Settings.mode
    modes      = @($Settings.modes)
    loopback   = [bool]$Settings.loopback
    kernel     = [bool]$Settings.kernel
    hwmon      = [bool]$Settings.hwmon
    rule_files = $Settings.rule_files
    effective  = $Settings.effective
  }

  ($out | ConvertTo-Json -Depth 8 | Out-String).Trim() |
    Set-Content -LiteralPath $SettingsPath -Encoding UTF8
}

function Load-Settings {
  $defaults = New-DefaultSettings
  if (-not (Test-Path -LiteralPath $SettingsPath -PathType Leaf)) { return $null }

  try {
    $raw = Get-Content -LiteralPath $SettingsPath -Raw -ErrorAction Stop

    if (-not (Test-Json -Json $raw)) {
      Write-Warn "settings.json failed JSON validation. Using defaults for this session."
      return $null
    }

    $obj = $raw | ConvertFrom-Json -Depth 10
    if ($obj.PSObject.Properties.Name -contains 'rule_files') {
      $rf = $obj.rule_files
      if ($rf -and -not ($rf -is [hashtable])) {
        $h = @{}
        foreach ($p in $rf.PSObject.Properties) { $h[$p.Name] = $p.Value }
        $obj.rule_files = $h
      }
    }

    foreach ($k in (New-DefaultSettings).Keys) {
      if (-not ($obj.PSObject.Properties.Name -contains $k)) {
        $obj | Add-Member -NotePropertyName $k -NotePropertyValue $defaults[$k]
      }
    }

    if ($obj.effective -and ($obj.effective.PSObject.Properties.Name -contains 'rule_files')) {
      $obj.effective.PSObject.Properties.Remove('rule_files')
    }

    $obj.effective = Compute-Effective $obj
    return $obj
  }
  catch {
    Write-Warn ("Load-Settings: failed to parse settings.json: {0}" -f $_.Exception.Message)
    return $null
  }
}

function Add-HashcatDirsToPath([string]$HashcatExePath) {
  if ([string]::IsNullOrWhiteSpace($HashcatExePath)) { return }
  $hcDir = Split-Path -Parent $HashcatExePath
  if (-not (Test-Path -LiteralPath $hcDir -PathType Container)) { return }

  $toAdd = @($hcDir)
  try {
    $toAdd += (Get-ChildItem -LiteralPath $hcDir -Directory -ErrorAction SilentlyContinue |
               Select-Object -ExpandProperty FullName)
  } catch { }

  $cur = ($env:PATH -split ';') | Where-Object { $_ -and $_.Trim() -ne '' }
  foreach ($p in $toAdd) {
    if ($cur -notcontains $p) { $cur = ,$p + $cur }
  }
  $env:PATH = ($cur -join ';')
}

function Parse-YesNo([string]$s) {
  if ([string]::IsNullOrWhiteSpace($s)) { return $null }
  switch ($s.Trim().ToLowerInvariant()) {
    'y'     { return $true  }
    'yes'   { return $true  }
    'true'  { return $true  }
    '1'     { return $true  }
    'n'     { return $false }
    'no'    { return $false }
    'false' { return $false }
    '0'     { return $false }
    default { return $null  }
  }
}

# ═══════════════════════════════════════════════════════════════════════
#  FIRST-RUN SETUP
# ═══════════════════════════════════════════════════════════════════════

$Settings = Load-Settings
if (-not $Settings) {
  Write-Banner "First-Time Setup"
  Write-Info "No settings.json found. Let's configure your environment."
  Write-Host ''

  $Settings = [pscustomobject](New-DefaultSettings)

  try {
    $hc = Get-Command hashcat, hashcat.exe -ErrorAction Stop | Select-Object -First 1
    if ($hc) {
      $Settings.hashcat = Split-Path -Parent $hc.Source
      Write-Success "Auto-detected hashcat at: $($Settings.hashcat)"
    }
  } catch { }

  if (-not $Settings.hashcat) {
    $h = Read-Host "Enter path to hashcat folder (or leave blank)"
    if ($h) {
      $dir = Resolve-ExistingDirectory $h
      if ($dir -and (Validate-HashcatDir $dir)) { $Settings.hashcat = $dir }
      else { Write-Warn "hashcat not found under '$h' — set later with: set hashcat <path>" }
    }
  }

  $r = Read-Host "Enter path to rulelists folder (or leave blank)"; if ($r)  { $Settings.rulelists = Resolve-ExistingDirectory $r }
  $w = Read-Host "Enter path to wordlists folder (or leave blank)"; if ($w)  { $Settings.wordlists = Resolve-ExistingDirectory $w }
  $hs= Read-Host "Enter path to hashes folder (or leave blank)"   ; if ($hs) { $Settings.hashes    = Resolve-ExistingDirectory $hs }

  Save-Settings $Settings
  if (-not (Test-Path -LiteralPath $SettingsPath -PathType Leaf)) {
    Write-Err "Failed to write settings.json at $SettingsPath"
    exit 1
  }
  Write-Success "settings.json created at $SettingsPath"
  $Settings = Load-Settings
} else {
  $Settings = Load-Settings
}

# ═══════════════════════════════════════════════════════════════════════
#  SCRIPT DISCOVERY
# ═══════════════════════════════════════════════════════════════════════

function Get-ScriptMap {
  $map = @{}
  Get-ChildItem -LiteralPath $Root -File -Filter '*.ps1' |
    Where-Object { $_.BaseName -match '^\d+$' } |
    Sort-Object { [int]$_.BaseName } |
    ForEach-Object {
      $num = $_.BaseName
      $content = Get-Content -LiteralPath $_.FullName -Raw
      $display = if ($content -match '<#(.*?)#>') {
        ($matches[1].Trim() -replace '\s+',' ')
      } else { "(no name)" }
      $map[$num] = [pscustomobject]@{ Path = $_.FullName; Display = $display }
    }
  $map
}

# ═══════════════════════════════════════════════════════════════════════
#  DISPLAY FUNCTIONS
# ═══════════════════════════════════════════════════════════════════════

function Show-Params([object]$Cfg) {
  Clear-Host
  Write-Banner "Parameters"

  Write-Header "Base Paths:"
  $pathPairs = @(
    @('hashcat',   $Cfg.hashcat),
    @('rulelists', $Cfg.rulelists),
    @('wordlists', $Cfg.wordlists),
    @('hashes',    $Cfg.hashes),
    @('potfile',   $Cfg.potfile)
  )
  foreach ($pair in $pathPairs) {
    $val = $pair[1]
    Write-C "  $($pair[0].PadRight(12)): " -Fg white -NoNewline
    if ($val) { Write-C $val -Fg green } else { Write-C "(not set)" -Fg brightblack }
  }

  Write-Host ''
  Write-Header "Flags & Mode:"
  $loopbackStatus = if ($Cfg.loopback) { 'enabled (--loopback)' } else { 'disabled' }
  $kernelStatus   = if ($Cfg.kernel)   { 'enabled (-O)' } else { 'disabled' }
  $hwmonStatus    = if ($Cfg.hwmon)    { 'disabled (--hwmon-disable)' } else { 'enabled' }
  Write-C "  mode        : " -Fg white -NoNewline; Write-C "$($Cfg.mode ?? 1000)" -Fg brightyellow -Bold
  Write-C "  loopback    : " -Fg white -NoNewline; Write-C $loopbackStatus -Fg $(if ($Cfg.loopback) {'green'} else {'brightblack'})
  Write-C "  kernel opt  : " -Fg white -NoNewline; Write-C $kernelStatus   -Fg $(if ($Cfg.kernel)   {'green'} else {'brightblack'})
  Write-C "  hw monitor  : " -Fg white -NoNewline; Write-C $hwmonStatus    -Fg $(if (-not $Cfg.hwmon) {'green'} else {'brightblack'})

  Write-Host ''
  Write-Header "Resolved (effective):"
  $eff = $Cfg.effective
  Write-C "  HASHCAT exe : " -Fg white -NoNewline; Write-C "$($eff.hashcatExe ?? '(not set)')" -Fg cyan
  Write-C "  KERNEL flag : " -Fg white -NoNewline; Write-C "$(if ($eff.kernelFlag) {$eff.kernelFlag} else {'(none)'})" -Fg yellow
  Write-C "  LOOPBACK    : " -Fg white -NoNewline; Write-C "$(if ($eff.loopbackFlag) {$eff.loopbackFlag} else {'(none)'})" -Fg yellow
  Write-C "  HWMON flag  : " -Fg white -NoNewline; Write-C "$(if ($eff.hwmonFlag) {$eff.hwmonFlag} else {'(none)'})" -Fg yellow
  Write-C "  HASHMODE    : " -Fg white -NoNewline; Write-C "$($eff.hashtype ?? '(not set)')" -Fg brightyellow -Bold

  Write-Host ''
  Write-Header "Rule Files:"
  Write-Dim "  base: $($Cfg.rulelists ?? '(not set)')"
  if ($eff.rulePaths -and $eff.rulePaths.Keys.Count -gt 0) {
    $eff.rulePaths.GetEnumerator() |
      Sort-Object Key |
      ForEach-Object {
        $val = $_.Value
        $exists = $false
        if ($val -and (Test-Path -LiteralPath $val -PathType Leaf)) { $exists = $true }
        Write-C "  $($_.Key.PadRight(18))" -Fg white -NoNewline
        if ($exists) {
          Write-C "[ok]     " -Fg green -NoNewline
        } else {
          Write-C "[missing] " -Fg red -NoNewline
        }
        Write-C ($val ?? '(filename only)') -Fg brightblack
      }
  } else {
    Write-Dim "  (none resolved)"
  }

  Write-Host ''
  Wait-Return
}

function Show-Menu([hashtable]$Map, [object]$Cfg) {
  $Cfg.effective = Compute-Effective $Cfg
  Clear-Host

  # Title
  $w = [math]::Max(20, [Console]::WindowWidth - 1)
  $titleText = 'g h u g e   ::   m e n u'
  $titlePad  = [math]::Max(0, [math]::Floor(($w - $titleText.Length) / 2))
  Write-C ('═' * $w) -Fg cyan
  Write-C (' ' * $titlePad + $titleText) -Fg brightcyan -Bold
  Write-C ('═' * $w) -Fg cyan
  Write-Host ''

  if ($Map.Count -eq 0) {
    Write-Warn "No numeric scripts found in: $Root"
  } else {
    Write-Header "Attacks:"
    foreach ($k in ($Map.Keys | Sort-Object {[int]$_})) {
      Write-C "  [" -Fg brightblack -NoNewline
      Write-C $k -Fg brightyellow -Bold -NoNewline
      Write-C "] " -Fg brightblack -NoNewline
      Write-C $Map[$k].Display -Fg white
    }
  }

  Write-Host ''
  Write-Separator
  Write-Header "Effective:"
  $eff = $Cfg.effective

  # Mode display — show multi-mode if set
  Write-C "  MODE    " -Fg white -NoNewline
  if ($Cfg.modes -and $Cfg.modes.Count -gt 0) {
    Write-C "$($Cfg.modes -join ', ')" -Fg brightyellow -Bold -NoNewline
    Write-C " (multi)" -Fg magenta -Bold -NoNewline
  } else {
    Write-C "$($eff.hashtype)" -Fg brightyellow -Bold -NoNewline
  }
  Write-C "    KERNEL " -Fg white -NoNewline
  Write-C "$(if ($eff.kernelFlag) {$eff.kernelFlag} else {'off'})" -Fg $(if ($eff.kernelFlag) {'green'} else {'brightblack'}) -NoNewline
  Write-C "    LOOPBACK " -Fg white -NoNewline
  Write-C "$(if ($eff.loopbackFlag) {'on'} else {'off'})" -Fg $(if ($eff.loopbackFlag) {'green'} else {'brightblack'}) -NoNewline
  Write-C "    HWMON " -Fg white -NoNewline
  Write-C "$(if ($eff.hwmonFlag) {'off'} else {'on'})" -Fg $(if ($eff.hwmonFlag) {'brightblack'} else {'green'})

  Write-Separator
  Write-Host ''
  Write-Dim "  Type a number to run, or:  help  config  stats"
}

function Show-Help([object]$Cfg) {
  Clear-Host
  Write-Banner "Help"
  Write-Host ''

  Write-Header "Attack Commands:"
  Write-C "  <number>                " -Fg brightyellow -Bold -NoNewline; Write-C "Run an attack script" -Fg white
  Write-Host ''

  Write-Header "Settings:"
  Write-C "  config                  " -Fg brightyellow -Bold -NoNewline; Write-C "Interactive settings (arrow keys)" -Fg white
  Write-C "  show                    " -Fg brightyellow -Bold -NoNewline; Write-C "Show all params/paths/rules" -Fg white
  Write-C "  set <key> <value>       " -Fg brightyellow -Bold -NoNewline; Write-C "Quick-set a value (e.g. set mode 1000)" -Fg white
  Write-C "  modes <int,int,...>     " -Fg brightyellow -Bold -NoNewline; Write-C "Multi-mode: repeat attacks per mode" -Fg white
  Write-C "  modes clear             " -Fg brightyellow -Bold -NoNewline; Write-C "Clear multi-mode (use single mode)" -Fg white
  Write-Host ''

  Write-Header "Analysis:"
  Write-C "  stats                   " -Fg brightyellow -Bold -NoNewline; Write-C "Interactive stats & analysis menu" -Fg white
  Write-C "  audit                   " -Fg brightyellow -Bold -NoNewline; Write-C "Full deep analysis of everything" -Fg white
  Write-Host ''

  Write-Header "Utilities:"
  Write-C "  search <term>           " -Fg brightyellow -Bold -NoNewline; Write-C "Search hash modes (e.g. 'search ntlm')" -Fg white
  Write-C "  combine                 " -Fg brightyellow -Bold -NoNewline; Write-C "Merge wordlists/rulelists (dedup)" -Fg white
  Write-C "  potgen                  " -Fg brightyellow -Bold -NoNewline; Write-C "Generate wordlist from potfile" -Fg white
  Write-Host ''

  Write-Header "Navigation:"
  Write-C "  r / refresh             " -Fg brightyellow -Bold -NoNewline; Write-C "Reload settings from disk" -Fg white
  Write-C "  ? / help                " -Fg brightyellow -Bold -NoNewline; Write-C "Show this help screen" -Fg white
  Write-C "  q / quit                " -Fg brightyellow -Bold -NoNewline; Write-C "Exit ghuge" -Fg white

  Write-Host ''
  Wait-Return
}

# ═══════════════════════════════════════════════════════════════════════
#  SEARCH HASH MODES
# ═══════════════════════════════════════════════════════════════════════

function Search-HashMode {
  param([string]$Term)

  if ([string]::IsNullOrWhiteSpace($Term)) {
    Write-Warn "Usage: search <term>  (e.g. 'search ntlm', 'search wpa')"
    Start-Sleep -Milliseconds 900
    return
  }

  $hashcatExe = Resolve-HashcatExe $Settings.hashcat
  if (-not $hashcatExe) {
    Write-Err "hashcat not configured — set hashcat path first."
    Start-Sleep -Milliseconds 900
    return
  }

  Write-Info "Searching hash modes for '$Term'..."
  $HashcatDir = Split-Path -Parent $hashcatExe

  try {
    Push-Location $HashcatDir
    $output = & $hashcatExe --example-hashes 2>$null
  } catch {
    Write-Err "Failed to run hashcat: $($_.Exception.Message)"
    return
  } finally {
    Pop-Location
  }

  # Parse the output into mode records
  $results = @()
  $currentMode = $null
  $currentName = $null
  $currentCategory = $null

  foreach ($line in $output) {
    if ($line -match '^Hash mode #(\d+)') {
      if ($currentMode -ne $null -and $currentName) {
        $results += [pscustomobject]@{ Mode=$currentMode; Name=$currentName; Category=$currentCategory }
      }
      $currentMode = $matches[1]
      $currentName = $null
      $currentCategory = $null
    }
    elseif ($line -match '^\s*Name\.+:\s*(.+)$') {
      $currentName = $matches[1].Trim()
    }
    elseif ($line -match '^\s*Category\.+:\s*(.+)$') {
      $currentCategory = $matches[1].Trim()
    }
  }
  # last record
  if ($currentMode -ne $null -and $currentName) {
    $results += [pscustomobject]@{ Mode=$currentMode; Name=$currentName; Category=$currentCategory }
  }

  # Filter
  $termLower = $Term.ToLower()
  $matched = $results | Where-Object {
    $_.Name.ToLower().Contains($termLower) -or
    $_.Category.ToLower().Contains($termLower) -or
    $_.Mode -eq $Term
  }

  if ($matched.Count -eq 0) {
    Write-Warn "No hash modes found matching '$Term'"
    Start-Sleep -Milliseconds 900
    return
  }

  Clear-Host
  Write-Banner "Search Results: '$Term'"
  Write-Host ''

  $i = 0
  foreach ($m in $matched) {
    $i++
    Write-C "  [" -Fg brightblack -NoNewline
    Write-C "$i" -Fg brightyellow -Bold -NoNewline
    Write-C "] " -Fg brightblack -NoNewline
    Write-C "Mode " -Fg white -NoNewline
    Write-C "$($m.Mode.ToString().PadRight(7))" -Fg brightyellow -Bold -NoNewline
    Write-C $m.Name -Fg cyan -NoNewline
    Write-C "  ($($m.Category))" -Fg brightblack
  }

  Write-Host ''
  Write-C "  Enter number to set mode, or " -Fg white -NoNewline
  Write-C "ENTER" -Fg brightblack -NoNewline
  Write-C " to return: " -Fg white -NoNewline
  $sel = Read-Host
  if ($sel -match '^\d+$') {
    $idx = [int]$sel
    if ($idx -ge 1 -and $idx -le $matched.Count) {
      $chosenMode = [int]$matched[$idx-1].Mode
      $Settings.mode = $chosenMode
      Save-Settings $Settings
      $script:Settings = Load-Settings
      Write-Success "Set mode -> $chosenMode ($($matched[$idx-1].Name))"

      # Validate hashes folder exists
      if ($Settings.hashes) {
        $modeFolder = Join-Path -Path $Settings.hashes -ChildPath ([string]$chosenMode)
        if (-not (Test-Path -LiteralPath $modeFolder -PathType Container)) {
          Write-Warn "Note: hashes/$chosenMode/ folder not found"
          Write-Dim "  Create it at: $modeFolder"
        } else {
          $hashCount = @(Get-ChildItem -LiteralPath $modeFolder -File -ErrorAction SilentlyContinue).Count
          if ($hashCount -eq 0) { Write-Warn "Note: hashes/$chosenMode/ folder is empty" }
          else { Write-Success "  Found $hashCount hashlist(s) in hashes/$chosenMode/" }
        }
      }
      Start-Sleep -Milliseconds 900
    }
  }
}

# ═══════════════════════════════════════════════════════════════════════
#  POTFILE UTILITIES
# ═══════════════════════════════════════════════════════════════════════

function Get-PotfilePath {
  if ($Settings.effective -and $Settings.effective.potfile -and
      (Test-Path -LiteralPath $Settings.effective.potfile -PathType Leaf)) {
    return $Settings.effective.potfile
  }
  # fallback: hashcat.potfile next to hashcat bin
  if ($Settings.hashcat) {
    $fallback = Join-Path $Settings.hashcat 'hashcat.potfile'
    if (Test-Path -LiteralPath $fallback -PathType Leaf) { return $fallback }
  }
  return $null
}

function Read-PotfilePasswords {
  param([string]$PotfilePath)
  if (-not $PotfilePath -or -not (Test-Path -LiteralPath $PotfilePath -PathType Leaf)) {
    return @()
  }

  $passwords = [System.Collections.Generic.HashSet[string]]::new()
  $reader = [System.IO.StreamReader]::new($PotfilePath, [System.Text.Encoding]::UTF8)
  try {
    while (-not $reader.EndOfStream) {
      $line = $reader.ReadLine()
      if ([string]::IsNullOrWhiteSpace($line)) { continue }
      # potfile format: hash:password  (password is everything after last ':' for simple hashes,
      # but for salted hashes the format is hash:salt:password, etc.)
      # Safest: take everything after the FIRST ':'
      $colonIdx = $line.IndexOf(':')
      if ($colonIdx -ge 0 -and $colonIdx -lt ($line.Length - 1)) {
        $pw = $line.Substring($colonIdx + 1)
        if (-not [string]::IsNullOrWhiteSpace($pw)) {
          [void]$passwords.Add($pw)
        }
      }
    }
  } finally {
    $reader.Close()
  }
  return $passwords
}

function Invoke-PotGen {
  Write-Banner "Potfile Wordlist Generator"

  $potPath = Get-PotfilePath
  if (-not $potPath) {
    Write-Err "No potfile found. Set with: set potfile <path>"
    Wait-Return
    return
  }

  Write-Info "Reading potfile: $potPath"
  $passwords = Read-PotfilePasswords $potPath
  if ($passwords.Count -eq 0) {
    Write-Warn "No passwords found in potfile."
    Wait-Return
    return
  }

  Write-Success "Found $($passwords.Count) unique passwords"

  # Options
  Write-Host ''
  Write-Header "Options:"
  Write-C "  Min password length? " -Fg white -NoNewline
  Write-C "(default: 1, recommended: 4)" -Fg brightblack -NoNewline
  Write-C ": " -Fg white -NoNewline
  $minLenRaw = Read-Host
  $minLen = 1
  if ($minLenRaw -match '^\d+$') { $minLen = [int]$minLenRaw }

  Write-C "  Extract base words (strip trailing digits/specials)? " -Fg white -NoNewline
  Write-C "(y/n, default: y)" -Fg brightblack -NoNewline
  Write-C ": " -Fg white -NoNewline
  $baseRaw = Read-Host
  $extractBase = $true
  if ($baseRaw -and $baseRaw.Trim().ToLower() -eq 'n') { $extractBase = $false }

  # Apply filters
  $filtered = [System.Collections.Generic.HashSet[string]]::new()
  foreach ($pw in $passwords) {
    if ($pw.Length -lt $minLen) { continue }
    [void]$filtered.Add($pw)
  }

  # Extract base words
  if ($extractBase) {
    $baseWords = [System.Collections.Generic.HashSet[string]]::new()
    foreach ($pw in $filtered) {
      # strip trailing digits and specials
      $base = $pw -replace '[0-9!@#$%^&*()_+\-=\[\]{}|;:''",.<>?/\\~`]+$', ''
      if ($base.Length -ge $minLen -and $base -ne $pw) {
        [void]$baseWords.Add($base)
      }
      # also strip leading digits
      $base2 = $pw -replace '^[0-9!@#$%^&*()_+\-=\[\]{}|;:''",.<>?/\\~`]+', ''
      if ($base2.Length -ge $minLen -and $base2 -ne $pw -and $base2 -ne $base) {
        [void]$baseWords.Add($base2)
      }
    }
    foreach ($bw in $baseWords) { [void]$filtered.Add($bw) }
    Write-Info "Added $($baseWords.Count) base words"
  }

  Write-Success "Total words after filtering: $($filtered.Count)"

  # Output path
  $defaultOut = 'potfile-words.txt'
  if ($Settings.wordlists) {
    $defaultOut = Join-Path $Settings.wordlists 'potfile-words.txt'
  }
  Write-C "  Output file " -Fg white -NoNewline
  Write-C "(default: $defaultOut)" -Fg brightblack -NoNewline
  Write-C ": " -Fg white -NoNewline
  $outPath = Read-Host
  if ([string]::IsNullOrWhiteSpace($outPath)) { $outPath = $defaultOut }

  try {
    $sorted = $filtered | Sort-Object
    $sorted | Set-Content -LiteralPath $outPath -Encoding UTF8
    Write-Success "Wrote $($filtered.Count) words to: $outPath"
  } catch {
    Write-Err "Failed to write: $($_.Exception.Message)"
  }

  Write-Host ''
  Wait-Return
}

# ═══════════════════════════════════════════════════════════════════════
#  STATS HELPERS
# ═══════════════════════════════════════════════════════════════════════

function Get-AvailableHashmodes {
  <# Returns array of [int] hashmode folders found under hashes root. #>
  if (-not $Settings.hashes -or -not (Test-Path -LiteralPath $Settings.hashes -PathType Container)) {
    return @()
  }
  $dirs = Get-ChildItem -LiteralPath $Settings.hashes -Directory -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -match '^\d+$' } |
    Sort-Object { [int]$_.Name }
  return @($dirs | ForEach-Object { [int]$_.Name })
}

function Get-CrackStatsForFile {
  <# Returns [pscustomobject] with Total, Cracked, Remaining, Pct for a hashfile+mode. #>
  param([string]$HashfilePath, [int]$Mode)
  $hashcatExe = Resolve-HashcatExe $Settings.hashcat
  if (-not $hashcatExe) { return $null }

  $total = (Get-Content -LiteralPath $HashfilePath -ErrorAction SilentlyContinue).Count
  $cracked = 0
  $potArgs = @()
  $potPath = Get-PotfilePath
  if ($potPath) { $potArgs += "--potfile-path=$potPath" }
  $HashcatDir = Split-Path -Parent $hashcatExe

  try {
    Push-Location $HashcatDir
    $out = & $hashcatExe -m$Mode $HashfilePath --show @potArgs 2>$null | Where-Object { $_ -and $_ -notmatch '^(Failed to parse|\[\*\])\s*' }
    $cracked = @($out | Where-Object { $_ -and $_.Trim() -ne '' }).Count
  } catch { } finally { Pop-Location }

  $remaining = $total - $cracked
  $pct = if ($total -gt 0) { [math]::Round(($cracked / $total) * 100, 1) } else { 0 }
  return [pscustomobject]@{ Total=$total; Cracked=$cracked; Remaining=$remaining; Pct=$pct }
}

function Write-ProgressBar {
  param([double]$Pct, [int]$Width = 30)
  $filled = [math]::Floor(($Pct / 100) * $Width)
  $empty  = $Width - $filled
  Write-C "  [" -Fg white -NoNewline
  Write-C ('█' * $filled) -Fg green -NoNewline
  Write-C ('░' * $empty) -Fg brightblack -NoNewline
  Write-C "] " -Fg white -NoNewline
  Write-C "$Pct%" -Fg brightyellow -Bold
}

function Read-PotfilePasswordCounts {
  <# Returns a hashtable of password -> count from potfile. #>
  param([string]$PotfilePath)
  $pwCount = @{}
  if (-not $PotfilePath -or -not (Test-Path -LiteralPath $PotfilePath -PathType Leaf)) { return $pwCount }
  $reader = [System.IO.StreamReader]::new($PotfilePath, [System.Text.Encoding]::UTF8)
  try {
    while (-not $reader.EndOfStream) {
      $line = $reader.ReadLine()
      if ([string]::IsNullOrWhiteSpace($line)) { continue }
      $colonIdx = $line.IndexOf(':')
      if ($colonIdx -ge 0 -and $colonIdx -lt ($line.Length - 1)) {
        $pw = $line.Substring($colonIdx + 1)
        if (-not [string]::IsNullOrWhiteSpace($pw)) {
          $pw = Decode-HexPw $pw
          if ($pwCount.ContainsKey($pw)) { $pwCount[$pw]++ } else { $pwCount[$pw] = 1 }
        }
      }
    }
  } finally { $reader.Close() }
  return $pwCount
}

function Decode-HexPw($p) {
  if ($p -match '^\$HEX\[([A-Fa-f0-9]+)\]$') {
    try {
      $h = $matches[1]
      $b = [byte[]]::new($h.Length / 2)
      for($i=0; $i -lt $h.Length; $i+=2){ $b[$i/2] = [convert]::ToByte($h.Substring($i,2), 16) }
      return [System.Text.Encoding]::UTF8.GetString($b)
    } catch { return $p }
  }
  return $p
}

function Write-ExtremesAndSpecials {
  param([string[]]$Passwords)
  
  # Shortest & longest
  if ($Passwords.Count -gt 0) {
    Write-Host ''
    Write-Header "Extremes:"
    $sorted = $Passwords | Sort-Object { $_.Length }
    $shortest = $sorted | Select-Object -First 3
    $longest  = $sorted | Select-Object -Last 3

    Write-C "  Shortest:" -Fg white
    foreach ($p in $shortest) {
      Write-C "    $p" -Fg cyan
    }

    Write-C "  Longest:" -Fg white
    foreach ($p in $longest) {
      $disp = if ($p.Length -gt 60) { $p.Substring(0, 57) + '...' } else { $p }
      Write-C "    $disp" -Fg cyan
    }
  }

  # Most common special characters
  Write-Host "`r  Loading: Special character analysis..." -NoNewline
  $specCount = @{}
  foreach ($pw in $Passwords) {
    foreach ($ch in [char[]]$pw) {
      if ($ch -match '[^a-zA-Z0-9]') {
        $s = [string]$ch
        if ($specCount.ContainsKey($s)) { $specCount[$s]++ } else { $specCount[$s] = 1 }
      }
    }
  }
  Write-Host "`r$(' ' * 60)`r" -NoNewline
  Write-Host ''
  Write-Header "Top Special Characters Used:"
  if ($specCount.Count -gt 0) {
    $topSpec = $specCount.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 10
    $rank = 0
    foreach ($entry in $topSpec) {
      $rank++
      Write-C "  $($rank.ToString().PadLeft(2)). " -Fg brightblack -NoNewline
      Write-C "$($entry.Value.ToString().PadLeft(6)) x " -Fg yellow -NoNewline
      Write-C "'$($entry.Key)'" -Fg white
    }
  } else { Write-Dim "  No special characters found." }
}

function Write-TopPasswords {
  param([hashtable]$PwCount, [int]$Top = 10, [string]$Title = 'Top Passwords')
  $sorted = $PwCount.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First $Top
  Write-Header "${Title}:"
  $rank = 0
  foreach ($entry in $sorted) {
    $rank++
    Write-C "  $($rank.ToString().PadLeft(2)). " -Fg brightblack -NoNewline
    Write-C "$($entry.Value.ToString().PadLeft(6)) x " -Fg yellow -NoNewline
    Write-C $entry.Key -Fg white
  }
}

function Write-LengthDistribution {
  param([object[]]$Passwords, [int]$Top = 8)
  Write-Header "Password Length Distribution:"
  $lenDist = @{}
  foreach ($pw in $Passwords) {
    $len = $pw.Length
    if ($lenDist.ContainsKey($len)) { $lenDist[$len]++ } else { $lenDist[$len] = 1 }
  }
  $topLens = $lenDist.GetEnumerator() | Sort-Object { [int]$_.Key } | Select-Object -First 15
  $maxCount = ($topLens | Measure-Object -Property Value -Maximum).Maximum
  foreach ($entry in $topLens) {
    $pct = [math]::Round(($entry.Value / $Passwords.Count) * 100, 1)
    $barWidth = if ($maxCount -gt 0) { [math]::Max(1, [math]::Floor(($entry.Value / $maxCount) * 25)) } else { 0 }
    Write-C "  len $($entry.Key.ToString().PadLeft(3)) : " -Fg white -NoNewline
    Write-C ('█' * $barWidth) -Fg cyan -NoNewline
    Write-C " $($entry.Value) ($pct%)" -Fg brightblack
  }
}

function Write-ComplexityBreakdown {
  param([object[]]$Passwords)
  Write-Header "Password Complexity:"
  $total = $Passwords.Count
  if ($total -eq 0) { Write-Dim "  No passwords."; return }
  $allLower = 0; $allUpper = 0; $allDigit = 0; $alphaDigit = 0; $hasSpecial = 0
  foreach ($pw in $Passwords) {
    $hasL = $pw -cmatch '[a-z]'
    $hasU = $pw -cmatch '[A-Z]'
    $hasD = $pw -match '\d'
    $hasS = $pw -match '[^a-zA-Z0-9]'
    if ($hasS) { $hasSpecial++ }
    elseif ($hasL -and -not $hasU -and -not $hasD) { $allLower++ }
    elseif ($hasU -and -not $hasL -and -not $hasD) { $allUpper++ }
    elseif ($hasD -and -not $hasL -and -not $hasU) { $allDigit++ }
    elseif (($hasL -or $hasU) -and $hasD -and -not $hasS) { $alphaDigit++ }
  }
  $categories = @(
    @('All lowercase',    $allLower,   'green'),
    @('All uppercase',    $allUpper,   'cyan'),
    @('All digits',       $allDigit,   'yellow'),
    @('Alpha + digits',   $alphaDigit, 'blue'),
    @('Has specials',     $hasSpecial, 'magenta')
  )
  foreach ($c in $categories) {
    $pct = [math]::Round(($c[1] / $total) * 100, 1)
    $barW = [math]::Max(0, [math]::Floor($pct / 3))
    Write-C "  $($c[0].PadRight(18))" -Fg white -NoNewline
    Write-C ('█' * $barW) -Fg $c[2] -NoNewline
    Write-C " $($c[1]) ($pct%)" -Fg brightblack
  }
}

# ═══════════════════════════════════════════════════════════════════════
#  STATS MENU
# ═══════════════════════════════════════════════════════════════════════

function Invoke-StatsMenu {
  $items = @(
    @{ Label='Crack stats';    Type='action'; Action={ Show-CrackStats } }
    @{ Label='Potfile';        Type='action'; Action={ Show-PotfileStats } }
    @{ Label='Audit';          Type='action'; Action={ Show-Audit } }
  )
  Invoke-InteractiveMenu -Title 'Stats & Analysis' -Items $items
}

# ═══════════════════════════════════════════════════════════════════════
#  CRACK STATS — pick a mode, then all hashfiles or a specific one
# ═══════════════════════════════════════════════════════════════════════

function Show-CrackStats {
  Clear-Host
  Write-Banner "Crack Stats"

  $hashcatExe = Resolve-HashcatExe $Settings.hashcat
  if (-not $hashcatExe) {
    Write-Err "hashcat not configured."
    Wait-Return
    return
  }
  if (-not $Settings.hashes) {
    Write-Err "Hashes path not configured."
    Wait-Return
    return
  }

  # List available hashmodes
  $modes = Get-AvailableHashmodes
  if ($modes.Count -eq 0) {
    Write-Err "No hashmode folders found under $($Settings.hashes)"
    Wait-Return
    return
  }

  Write-Header "Select Hashmode:"
  for ($i = 0; $i -lt $modes.Count; $i++) {
    $modeNum = $modes[$i]
    $modeFolder = Join-Path $Settings.hashes ([string]$modeNum)
    $fileCount = @(Get-ChildItem -LiteralPath $modeFolder -File -ErrorAction SilentlyContinue).Count
    $isCurrent = ($modeNum -eq $Settings.mode)
    Write-C "  [" -Fg brightblack -NoNewline
    Write-C "$($i+1)" -Fg brightyellow -Bold -NoNewline
    Write-C "] " -Fg brightblack -NoNewline
    Write-C "Mode $($modeNum.ToString().PadRight(8))" -Fg $(if ($isCurrent) {'brightcyan'} else {'white'}) -NoNewline
    Write-C "$fileCount hashfile(s)" -Fg brightblack -NoNewline
    if ($isCurrent) { Write-C "  ◄ current" -Fg cyan -Bold } else { Write-Host '' }
  }
  Write-Dim "  (Esc to go back)"
  $raw = Read-HostEsc ("Select mode (1..{0}): " -f $modes.Count)
  if ($null -eq $raw) { return }
  [int]$sel = 0
  if (-not [int]::TryParse($raw, [ref]$sel) -or $sel -lt 1 -or $sel -gt $modes.Count) {
    Write-Warn "Invalid selection."
    Start-Sleep -Milliseconds 600
    return
  }

  $chosenMode = $modes[$sel-1]
  $modeFolder = Join-Path $Settings.hashes ([string]$chosenMode)
  $hashFiles = @(Get-ChildItem -LiteralPath $modeFolder -File -ErrorAction SilentlyContinue | Sort-Object Name)
  if ($hashFiles.Count -eq 0) {
    Write-Warn "No hashfiles in mode $chosenMode"
    Wait-Return
    return
  }

  # Choose: all hashfiles or a specific one
  Write-Host ''
  Write-Header "Scope for mode ${chosenMode}:"
  Write-C "  [" -Fg brightblack -NoNewline
  Write-C "A" -Fg brightyellow -Bold -NoNewline
  Write-C "] " -Fg brightblack -NoNewline
  Write-C "All hashfiles" -Fg white -NoNewline
  Write-C " ($($hashFiles.Count) files)" -Fg brightblack
  for ($i = 0; $i -lt $hashFiles.Count; $i++) {
    Write-C "  [" -Fg brightblack -NoNewline
    Write-C "$($i+1)" -Fg brightyellow -Bold -NoNewline
    Write-C "] " -Fg brightblack -NoNewline
    Write-C $hashFiles[$i].Name -Fg white
  }
  Write-Dim "  (Esc to go back)"
  $scope = Read-HostEsc "  Choose (A or 1..$($hashFiles.Count)): "
  if ($null -eq $scope) { return }

  $potPath = Get-PotfilePath
  $potArgs = @()
  if ($potPath) { $potArgs += "--potfile-path=$potPath" }
  $HashcatDir = Split-Path -Parent $hashcatExe

  # ── SINGLE HASHFILE ──
  if ($scope -match '^\d+$') {
    $fIdx = [int]$scope
    if ($fIdx -lt 1 -or $fIdx -gt $hashFiles.Count) {
      Write-Warn "Invalid selection."
      Start-Sleep -Milliseconds 600
      return
    }
    $hf = $hashFiles[$fIdx-1]
    Clear-Host
    $rec = Start-StatRecording
    Write-Banner "Crack Stats — $($hf.Name) (Mode $chosenMode)"
    Write-Host "`r  Querying hashcat..." -NoNewline

    $total = @(Get-Content -LiteralPath $hf.FullName -ErrorAction SilentlyContinue).Count
    $cracked = 0; $showOutput = @()
    try {
      Push-Location $HashcatDir
      $showOutput = & $hashcatExe -m $chosenMode $hf.FullName --show @potArgs 2>$null | Where-Object { $_ -and $_ -notmatch '^(Failed to parse|\[\*\])\s*' }
      $cracked = @($showOutput | Where-Object { $_ -is [string] -and $_.Trim() -ne '' }).Count
    } catch { } finally { Pop-Location }
    Write-Host "`r$(' ' * 40)`r" -NoNewline

    $remaining = $total - $cracked
    $pct = if ($total -gt 0) { [math]::Round(($cracked / $total) * 100, 1) } else { 0 }

    Write-C "  Cracked: " -Fg white -NoNewline
    Write-C "$cracked" -Fg brightgreen -Bold -NoNewline
    Write-C " / $total" -Fg cyan -NoNewline
    Write-C "  Remaining: " -Fg white -NoNewline
    Write-C "$remaining" -Fg yellow -NoNewline
    Write-C "  ($pct%)" -Fg brightyellow -Bold
    Write-ProgressBar -Pct $pct -Width 40

    if ($cracked -gt 0) {
      Write-Host ''
      Write-Header "Cracked Passwords:"
      $displayCount = [math]::Min($cracked, 50)
      $lineNum = 0
      
      $fileDecodedPws = [System.Collections.Generic.List[string]]::new()
      $filePwCount = @{}

      foreach ($line in $showOutput) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        $lineNum++
        $printedThisLine = $false

        $colonIdx = $line.IndexOf(':')
        if ($colonIdx -ge 0) {
          $hashPart = $line.Substring(0, [math]::Min($colonIdx, 40))
          $pwPart   = $line.Substring($colonIdx + 1)
          if ($colonIdx -gt 40) { $hashPart += '...' }
          
          $pwPart = Decode-HexPw $pwPart
          $fileDecodedPws.Add($pwPart)
          if ($filePwCount.ContainsKey($pwPart)) { $filePwCount[$pwPart]++ } else { $filePwCount[$pwPart] = 1 }

          if ($lineNum -le $displayCount) {
            Write-C "  $hashPart" -Fg brightblack -NoNewline
            Write-C ":" -Fg white -NoNewline
            Write-C $pwPart -Fg brightgreen
            $printedThisLine = $true
          }
        } else {
          if ($lineNum -le $displayCount) {
            Write-C "  $line" -Fg white
            $printedThisLine = $true
          }
        }

        if ($lineNum -eq $displayCount -and $cracked -gt $displayCount) {
          Write-Dim "  ... and $($cracked - $displayCount) more"
        }
      }

      if ($filePwCount.Count -gt 0) {
        Write-Host ''
        Write-TopPasswords -PwCount $filePwCount -Top 10 -Title "Top Cracked in $($hf.Name)"
        Write-ExtremesAndSpecials -Passwords $fileDecodedPws.ToArray()
      }
    } else {
      Write-Warn "No cracked hashes."
    }

    Write-Host ''
    Wait-Return -LogPrefix "CrackStats_Mode$($chosenMode)_$($hf.Name)" -TempFile $rec
    return
  }

  # ── ALL HASHFILES ── (scope is 'A' or anything non-numeric)
  Clear-Host
  $rec = Start-StatRecording
  Write-Banner "Crack Stats — Mode $chosenMode"
  $totalFiles = $hashFiles.Count
  Write-Host ''

  $allStats = @()
  $totalAll = 0; $crackedAll = 0

  for ($i = 0; $i -lt $hashFiles.Count; $i++) {
    $hf = $hashFiles[$i]
    $pctDone = [math]::Round((($i + 1) / $totalFiles) * 100)
    Write-Host "`r  Querying $($i+1)/${totalFiles}: $($hf.Name.PadRight(30)) [$pctDone%]" -NoNewline
    $total = @(Get-Content -LiteralPath $hf.FullName -ErrorAction SilentlyContinue).Count
    $cracked = 0
    try {
      Push-Location $HashcatDir
      $out = & $hashcatExe -m $chosenMode $hf.FullName --show @potArgs 2>$null | Where-Object { $_ -and $_ -notmatch '^(Failed to parse|\[\*\])\s*' }
      $cracked = @($out | Where-Object { $_ -is [string] -and $_.Trim() -ne '' }).Count
    } catch { } finally { Pop-Location }
    $remaining = $total - $cracked
    $pct = if ($total -gt 0) { [math]::Round(($cracked / $total) * 100, 1) } else { 0 }
    $totalAll += $total; $crackedAll += $cracked
    $allStats += [pscustomobject]@{ Index=($i+1); Name=$hf.Name; Path=$hf.FullName; Total=$total; Cracked=$cracked; Remaining=$remaining; Pct=$pct; Output=$out }
  }

  Write-Host "`r$(' ' * 80)`r" -NoNewline
  Write-Success "Scanned $totalFiles hashfile(s)"
  Write-Host ''

  foreach ($stat in $allStats) {
    $barLen = 20
    $pct = $stat.Pct
    $filled = [math]::Floor(($pct / 100) * $barLen)
    $empty = $barLen - $filled
    Write-C "  [" -Fg brightblack -NoNewline
    Write-C "$($stat.Index)" -Fg brightyellow -Bold -NoNewline
    Write-C "] " -Fg brightblack -NoNewline
    Write-C "$($stat.Name.PadRight(25))" -Fg white -NoNewline
    Write-C "[" -Fg white -NoNewline
    Write-C ('█' * $filled) -Fg green -NoNewline
    Write-C ('░' * $empty) -Fg brightblack -NoNewline
    Write-C "] " -Fg white -NoNewline
    Write-C "$($stat.Cracked.ToString().PadLeft(5))" -Fg brightgreen -Bold -NoNewline
    Write-C "/" -Fg white -NoNewline
    Write-C "$($stat.Total.ToString().PadLeft(5))" -Fg cyan -NoNewline
    Write-C " ($pct%)" -Fg brightyellow
  }

  # Summary
  Write-Host ''
  Write-Separator
  $totalPct = if ($totalAll -gt 0) { [math]::Round(($crackedAll / $totalAll) * 100, 1) } else { 0 }
  Write-C "  Total: " -Fg white -NoNewline
  Write-C "$crackedAll" -Fg brightgreen -Bold -NoNewline
  Write-C " / $totalAll cracked" -Fg white -NoNewline
  Write-C " ($totalPct%)" -Fg brightyellow -Bold
  Write-ProgressBar -Pct $totalPct -Width 40

  # Password reuse & Top Passwords & Extremes
  $pwToFiles = @{}
  $modePwCount = @{}
  $allDecodedPws = [System.Collections.Generic.List[string]]::new()

  if ($allStats.Count -gt 0) {
    foreach ($stat in $allStats) {
      if (-not $stat.Output) { continue }
      foreach ($line in $stat.Output) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        $colonIdx = $line.IndexOf(':')
        if ($colonIdx -ge 0 -and $colonIdx -lt ($line.Length - 1)) {
          $pw = $line.Substring($colonIdx + 1)
          if (-not [string]::IsNullOrWhiteSpace($pw)) {
            $pw = Decode-HexPw $pw
            $allDecodedPws.Add($pw)

            if (-not $pwToFiles.ContainsKey($pw)) { $pwToFiles[$pw] = [System.Collections.Generic.HashSet[string]]::new() }
            [void]$pwToFiles[$pw].Add($stat.Name)

            if ($modePwCount.ContainsKey($pw)) { $modePwCount[$pw]++ } else { $modePwCount[$pw] = 1 }
          }
        }
      }
    }

    # Print password reuse
    if ($allStats.Count -gt 1) {
      $shared = $pwToFiles.GetEnumerator() | Where-Object { $_.Value.Count -gt 1 }
      $sharedCount = @($shared).Count
      if ($sharedCount -gt 0) {
        Write-Host ''
        Write-Header "Shared Passwords (found in 2+ hashfiles):"
        Write-C "  $sharedCount password(s) appear across multiple hashfiles" -Fg magenta -Bold
        $topShared = @($shared) | Sort-Object { $_.Value.Count } -Descending | Select-Object -First 5
        foreach ($s in $topShared) {
          Write-C "  " -NoNewline
          Write-C "$($s.Key.PadRight(25))" -Fg white -NoNewline
          Write-C "→ $($s.Value.Count) files" -Fg brightblack
        }
      }
    }

    # Print Top Cracked
    if ($modePwCount.Count -gt 0) {
      Write-Host ''
      Write-TopPasswords -PwCount $modePwCount -Top 10 -Title "Top Cracked (Mode $chosenMode)"
      Write-ExtremesAndSpecials -Passwords $allDecodedPws.ToArray()
    }
  }

  Write-Host ''
  Wait-Return -LogPrefix "CrackStats_Mode$($chosenMode)_AllFiles" -TempFile $rec
}

# ═══════════════════════════════════════════════════════════════════════
#  POTFILE STATS — password analysis from potfile
# ═══════════════════════════════════════════════════════════════════════

function Show-PotfileStats {
  Clear-Host
  $rec = Start-StatRecording
  Write-Banner "Potfile Analysis"

  $potPath = Get-PotfilePath
  if (-not $potPath) {
    Write-Err "No potfile found. Set with: set potfile <path>"
    Wait-Return
    return
  }

  # Summary
  Write-Header "Potfile: $(Split-Path -Leaf $potPath)"
  $fileSize = (Get-Item -LiteralPath $potPath).Length
  $fileSizeMB = [math]::Round($fileSize / 1MB, 2)
  Write-C "  File size   : " -Fg white -NoNewline; Write-C "${fileSizeMB} MB" -Fg cyan

  Write-Host "`r  Loading: Reading potfile..." -NoNewline
  $pwCount = Read-PotfilePasswordCounts $potPath
  $totalEntries = ($pwCount.Values | Measure-Object -Sum).Sum
  $uniqueCount  = $pwCount.Count
  $reuseCount   = ($pwCount.Values | Where-Object { $_ -gt 1 } | Measure-Object).Count
  Write-Host "`r$(' ' * 60)`r" -NoNewline

  Write-C "  Total lines : " -Fg white -NoNewline; Write-C "$totalEntries" -Fg cyan
  Write-C "  Unique pwds : " -Fg white -NoNewline; Write-C "$uniqueCount" -Fg brightgreen -Bold
  Write-C "  Reused pwds : " -Fg white -NoNewline; Write-C "$reuseCount" -Fg magenta -NoNewline
  if ($uniqueCount -gt 0) {
    $reusePct = [math]::Round(($reuseCount / $uniqueCount) * 100, 1)
    Write-C " ($reusePct% appear in 2+ hashes)" -Fg brightblack
  } else { Write-Host '' }

  $passwords = [string[]]@($pwCount.Keys)

  # Top passwords
  Write-Host "`r  Loading: Ranking passwords..." -NoNewline
  Write-Host "`r$(' ' * 60)`r" -NoNewline
  Write-Host ''
  Write-TopPasswords -PwCount $pwCount -Top 15 -Title 'Top 15 Passwords'

  # Length distribution
  Write-Host "`r  Loading: Length distribution..." -NoNewline
  Write-Host "`r$(' ' * 60)`r" -NoNewline
  Write-Host ''
  Write-LengthDistribution -Passwords $passwords -Top 15

  # Complexity
  Write-Host "`r  Loading: Complexity analysis..." -NoNewline
  Write-Host "`r$(' ' * 60)`r" -NoNewline
  Write-Host ''
  Write-ComplexityBreakdown -Passwords $passwords

  # Extremes & Specials
  Write-ExtremesAndSpecials -Passwords $passwords

  Write-Host ''
  Wait-Return -LogPrefix 'PotfileStats' -TempFile $rec
}

# ═══════════════════════════════════════════════════════════════════════
#  AUDIT — full deep analysis
# ═══════════════════════════════════════════════════════════════════════

function Show-Audit {
  Clear-Host
  $rec = Start-StatRecording
  Write-Banner "Full Audit"

  $hashcatExe = Resolve-HashcatExe $Settings.hashcat
  $potPath = Get-PotfilePath

  # ── 1. Potfile summary ──────────────────
  if ($potPath) {
    Write-Header "Potfile Summary"
    Write-Host "`r  Loading: Reading potfile summary..." -NoNewline
    $pwCount = Read-PotfilePasswordCounts $potPath
    $totalEntries = ($pwCount.Values | Measure-Object -Sum).Sum
    $uniqueCount  = $pwCount.Count
    $fileSize = (Get-Item -LiteralPath $potPath).Length
    Write-Host "`r$(' ' * 60)`r" -NoNewline
    Write-C "  $([math]::Round($fileSize / 1MB, 2)) MB  |  $totalEntries entries  |  $uniqueCount unique passwords" -Fg cyan
    Write-Host ''
  } else {
    Write-Warn "No potfile configured."
    Write-Host ''
  }

  # ── 2. Per-mode crack rates ──────────────
  $modes = Get-AvailableHashmodes
  if ($modes.Count -gt 0 -and $hashcatExe) {
    Write-Header "Crack Rates by Hashmode"
    Write-Info "Scanning $($modes.Count) hashmode(s)..."

    $potArgs = @()
    if ($potPath) { $potArgs += "--potfile-path=$potPath" }
    $HashcatDir = Split-Path -Parent $hashcatExe

    $grandTotal = 0; $grandCracked = 0
    $modePasswords = @{}  # mode -> [string[]] passwords

    $modeIdx = 0
    foreach ($m in $modes) {
      $modeIdx++
      Write-Host "`r  Scanning mode $m ($modeIdx/$($modes.Count))..." -NoNewline
      $modeFolder = Join-Path $Settings.hashes ([string]$m)
      $hashFiles = @(Get-ChildItem -LiteralPath $modeFolder -File -ErrorAction SilentlyContinue | Sort-Object Name)
      if ($hashFiles.Count -eq 0) { continue }

      $modeTotal = 0; $modeCracked = 0
      $modePws = @()

      foreach ($hf in $hashFiles) {
        $total = @(Get-Content -LiteralPath $hf.FullName -ErrorAction SilentlyContinue).Count
        $cracked = 0
        try {
          Push-Location $HashcatDir
          $out = & $hashcatExe -m $m $hf.FullName --show @potArgs 2>$null | Where-Object { $_ -and $_ -notmatch '^(Failed to parse|\[\*\])\s*' }
          $cracked = @($out | Where-Object { $_ -is [string] -and $_.Trim() -ne '' }).Count
          foreach ($line in $out) {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            $colonIdx = $line.IndexOf(':')
            if ($colonIdx -ge 0 -and $colonIdx -lt ($line.Length - 1)) {
              $pw = $line.Substring($colonIdx + 1)
              $modePws += Decode-HexPw $pw
            }
          }
        } catch { } finally { Pop-Location }
        $modeTotal += $total; $modeCracked += $cracked
      }

      $grandTotal += $modeTotal; $grandCracked += $modeCracked
      $pct = if ($modeTotal -gt 0) { [math]::Round(($modeCracked / $modeTotal) * 100, 1) } else { 0 }
      $modePasswords[[string]$m] = $modePws

      $barLen = 20
      $filled = [math]::Floor(($pct / 100) * $barLen)
      $empty = $barLen - $filled
      Write-C "  Mode $($m.ToString().PadRight(8))" -Fg white -NoNewline
      Write-C "[" -Fg white -NoNewline
      Write-C ('█' * $filled) -Fg green -NoNewline
      Write-C ('░' * $empty) -Fg brightblack -NoNewline
      Write-C "] " -Fg white -NoNewline
      Write-C "$($modeCracked.ToString().PadLeft(6))" -Fg brightgreen -Bold -NoNewline
      Write-C "/$($modeTotal.ToString().PadLeft(6))" -Fg cyan -NoNewline
      Write-C " ($pct%)" -Fg brightyellow -NoNewline
      Write-C "  $($hashFiles.Count) file(s)" -Fg brightblack
    }

    Write-Host "`r$(' ' * 60)`r" -NoNewline
    Write-Separator
    $grandPct = if ($grandTotal -gt 0) { [math]::Round(($grandCracked / $grandTotal) * 100, 1) } else { 0 }
    Write-C "  TOTAL   " -Fg white -Bold -NoNewline
    Write-C "$grandCracked / $grandTotal" -Fg brightgreen -Bold -NoNewline
    Write-C " ($grandPct%)" -Fg brightyellow -Bold
    Write-Host ''

    # ── 3. Cross-mode password reuse ──────────
    if ($modePasswords.Count -gt 1) {
      Write-Header "Cross-Mode Password Reuse"
      Write-Host "`r  Loading: Correlating cross-mode hashes..." -NoNewline
      $pwToModes = @{}
      foreach ($entry in $modePasswords.GetEnumerator()) {
        foreach ($pw in $entry.Value) {
          if (-not [string]::IsNullOrWhiteSpace($pw)) {
            if (-not $pwToModes.ContainsKey($pw)) { $pwToModes[$pw] = [System.Collections.Generic.HashSet[string]]::new() }
            [void]$pwToModes[$pw].Add($entry.Key)
          }
        }
      }
      $crossMode = $pwToModes.GetEnumerator() | Where-Object { $_.Value.Count -gt 1 }
      $crossCount = @($crossMode).Count
      Write-Host "`r$(' ' * 60)`r" -NoNewline
      if ($crossCount -gt 0) {
        Write-C "  $crossCount password(s) cracked across multiple hashmodes" -Fg magenta -Bold
        $topCross = @($crossMode) | Sort-Object { $_.Value.Count } -Descending | Select-Object -First 5
        foreach ($c in $topCross) {
          Write-C "  $($c.Key.PadRight(25))" -Fg white -NoNewline
          Write-C "→ modes: $($c.Value -join ', ')" -Fg brightblack
        }
      } else {
        Write-Dim "  No passwords shared across modes."
      }
      Write-Host ''

      Write-Host "`r  Loading: Calculating mode overlaps..." -NoNewline
      # Calculate overlapping mode pairs
      $overlapCounts = @{}
      foreach ($c in $crossMode) {
        $modesArr = @($c.Value | Sort-Object { [int]$_ })
        if ($modesArr.Count -ge 2) {
          for ($i=0; $i -lt $modesArr.Count; $i++) {
            for ($j=$i+1; $j -lt $modesArr.Count; $j++) {
              $pair = "$($modesArr[$i]) & $($modesArr[$j])"
              if ($overlapCounts.ContainsKey($pair)) { $overlapCounts[$pair]++ } else { $overlapCounts[$pair] = 1 }
            }
          }
        }
      }
      
      Write-Host "`r$(' ' * 60)`r" -NoNewline
      if ($overlapCounts.Count -gt 0) {
        Write-Header "Most Common Mode Overlaps"
        $topOverlaps = $overlapCounts.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 5
        foreach ($o in $topOverlaps) {
          $m1,$m2 = $o.Key -split ' & '
          Write-C "  Mode $($m1.PadRight(6)) & Mode $($m2.PadRight(6)) " -Fg white -NoNewline
          Write-C "→ $($o.Value.ToString().PadLeft(4)) shared passwords" -Fg cyan
        }
        Write-Host ''
      }

      Write-Host "`r  Loading: Finding most common per mode..." -NoNewline
      # Most common per mode
      Write-Host "`r$(' ' * 60)`r" -NoNewline
      Write-Header "Most Common Password Per Mode"
      foreach ($entry in ($modePasswords.GetEnumerator() | Sort-Object Key)) {
        if ($entry.Value.Count -eq 0) { continue }
        $mc = @{}
        foreach ($p in $entry.Value) {
          if (-not [string]::IsNullOrWhiteSpace($p)) {
            if ($mc.ContainsKey($p)) { $mc[$p]++ } else { $mc[$p] = 1 }
          }
        }
        if ($mc.Count -eq 0) { continue }
        $top = $mc.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 1
        Write-C "  Mode $($entry.Key.PadRight(8))" -Fg white -NoNewline
        Write-C "$($top.Value.ToString().PadLeft(4)) x " -Fg yellow -NoNewline
        Write-C $top.Key -Fg brightgreen
      }
      Write-Host ''
    }
  } else {
    Write-Warn "No hashmode folders or hashcat not configured."
    Write-Host ''
  }

  # ── 4. Wordlist inventory ──────────────
  if ($Settings.wordlists -and (Test-Path -LiteralPath $Settings.wordlists -PathType Container)) {
    Write-Header "Wordlist Inventory"
    Write-Host "`r  Loading: Scanning wordlists..." -NoNewline
    $wlFiles = Get-ChildItem -LiteralPath $Settings.wordlists -File -Recurse -ErrorAction SilentlyContinue | Sort-Object FullName
    $rootResolved = (Resolve-Path -LiteralPath $Settings.wordlists).Path.TrimEnd([IO.Path]::DirectorySeparatorChar)
    $totalWlSize = 0
    Write-Host "`r$(' ' * 60)`r" -NoNewline
    foreach ($wl in $wlFiles) {
      $rel = $wl.FullName
      if ($rel.StartsWith($rootResolved)) {
        $rel = $rel.Substring($rootResolved.Length).TrimStart([IO.Path]::DirectorySeparatorChar)
      }
      $sizeMB = [math]::Round($wl.Length / 1MB, 1)
      $totalWlSize += $wl.Length
      # Estimate line count for small files, skip for large ones
      $lineEst = ''
      if ($wl.Length -lt 100MB) {
        try {
          $lc = 0
          $sr = [System.IO.StreamReader]::new($wl.FullName, [System.Text.Encoding]::UTF8)
          try { while ($sr.ReadLine() -ne $null) { $lc++ } } finally { $sr.Close() }
          $lineEst = "$($lc.ToString('N0')) lines"
        } catch { $lineEst = '(error)' }
      } else {
        $lineEst = '(large, skipped count)'
      }
      Write-C "  $($rel.PadRight(35))" -Fg white -NoNewline
      Write-C "$($sizeMB.ToString().PadLeft(8)) MB  " -Fg cyan -NoNewline
      Write-C $lineEst -Fg brightblack
    }
    $totalWlMB = [math]::Round($totalWlSize / 1MB, 1)
    Write-Separator
    Write-C "  $($wlFiles.Count) file(s), $totalWlMB MB total" -Fg white -Bold
    Write-Host ''
  }

  # ── 5. Rulelist inventory ──────────────
  if ($Settings.rulelists -and (Test-Path -LiteralPath $Settings.rulelists -PathType Container)) {
    Write-Header "Rulelist Inventory"
    Write-Host "`r  Loading: Scanning rulelists..." -NoNewline
    $rlFiles = Get-ChildItem -LiteralPath $Settings.rulelists -File -Recurse -ErrorAction SilentlyContinue |
      Where-Object { $_.Extension -eq '.rule' } | Sort-Object FullName
    $rootResolved = (Resolve-Path -LiteralPath $Settings.rulelists).Path.TrimEnd([IO.Path]::DirectorySeparatorChar)
    $totalRlSize = 0
    Write-Host "`r$(' ' * 60)`r" -NoNewline
    foreach ($rl in $rlFiles) {
      $rel = $rl.FullName
      if ($rel.StartsWith($rootResolved)) {
        $rel = $rel.Substring($rootResolved.Length).TrimStart([IO.Path]::DirectorySeparatorChar)
      }
      $sizeMB = [math]::Round($rl.Length / 1MB, 1)
      $totalRlSize += $rl.Length
      $lineEst = ''
      if ($rl.Length -lt 50MB) {
        try {
          $lc = 0
          $sr = [System.IO.StreamReader]::new($rl.FullName, [System.Text.Encoding]::UTF8)
          try { while ($sr.ReadLine() -ne $null) { $lc++ } } finally { $sr.Close() }
          $lineEst = "$($lc.ToString('N0')) rules"
        } catch { $lineEst = '(error)' }
      } else {
        $lineEst = '(large, skipped count)'
      }
      Write-C "  $($rel.PadRight(40))" -Fg white -NoNewline
      Write-C "$($sizeMB.ToString().PadLeft(8)) MB  " -Fg cyan -NoNewline
      Write-C $lineEst -Fg brightblack
    }
    $totalRlMB = [math]::Round($totalRlSize / 1MB, 1)
    Write-Separator
    Write-C "  $($rlFiles.Count) rule file(s), $totalRlMB MB total" -Fg white -Bold
    Write-Host ''
  }

  # ── 6. Potfile analysis (if available) ──────────
  if ($potPath) {
    Write-Header "Overall Potfile Quick Stats"
    Write-Host "`r  Loading: Crunching potfile..." -NoNewline
    $pwCount = Read-PotfilePasswordCounts $potPath
    $passwords = [string[]]@($pwCount.Keys)
    Write-Host "`r$(' ' * 60)`r" -NoNewline
    Write-TopPasswords -PwCount $pwCount -Top 10 -Title 'Top 10 Overall Passwords'
    Write-Host ''
    Write-Host "`r  Loading: Complexity breakdown..." -NoNewline
    Write-Host "`r$(' ' * 60)`r" -NoNewline
    Write-ComplexityBreakdown -Passwords $passwords
    Write-Host ''
  }

  Wait-Return -LogPrefix 'Audit' -TempFile $rec
}

# ═══════════════════════════════════════════════════════════════════════
#  INTERACTIVE CONFIG MENU
# ═══════════════════════════════════════════════════════════════════════

function Invoke-ConfigMenu {
  function Validate-PathOrWarn($v, $isDir) {
    if ([string]::IsNullOrWhiteSpace($v)) { return $v }
    if ($isDir -and -not (Test-Path -LiteralPath $v -PathType Container)) {
      Write-Warn "`nWarning: Directory does not exist yet: $v"
      Start-Sleep -Milliseconds 1500
    } elseif (-not $isDir -and -not (Test-Path -LiteralPath $v -PathType Leaf)) {
      Write-Warn "`nWarning: File does not exist yet: $v"
      Start-Sleep -Milliseconds 1500
    }
    return $v
  }

  $items = @(
    @{ Label='hashcat';   Type='path'; Get={ $Settings.hashcat };   Set={ param($v) $Settings.hashcat   = Validate-PathOrWarn $v $true }; Hint='path to hashcat folder' }
    @{ Label='rulelists';  Type='path'; Get={ $Settings.rulelists }; Set={ param($v) $Settings.rulelists = Validate-PathOrWarn $v $true }; Hint='path to rulelists folder' }
    @{ Label='wordlists';  Type='path'; Get={ $Settings.wordlists }; Set={ param($v) $Settings.wordlists = Validate-PathOrWarn $v $true }; Hint='path to wordlists folder' }
    @{ Label='hashes';     Type='path'; Get={ $Settings.hashes };    Set={ param($v) $Settings.hashes    = Validate-PathOrWarn $v $true }; Hint='path to hashes folder' }
    @{ Label='potfile';    Type='path'; Get={ $Settings.potfile };   Set={ param($v) $Settings.potfile   = Validate-PathOrWarn $v $false }; Hint='path to potfile' }
    @{ Label='mode';       Type='int';  
       Get={ if ($Settings.modes -and $Settings.modes.Count -gt 1) { $($Settings.modes -join ', ') } else { $Settings.mode } }; 
       Set={ param($v) $Settings.mode = $v; $Settings.modes = @() }; 
       SetMulti={ param($v) $Settings.modes = @($v) }; Hint='int or comma-sep for multi' }
    @{ Label='loopback';   Type='bool'; Get={ $Settings.loopback };  Set={ param($v) $Settings.loopback  = $v } }
    @{ Label='kernel -O';  Type='bool'; Get={ $Settings.kernel };    Set={ param($v) $Settings.kernel    = $v } }
    @{ Label='hwmon';      Type='bool'; Get={ -not $Settings.hwmon }; Set={ param($v) $Settings.hwmon = -not $v } }
    @{ Label='─────────';  Type='action'; Action={ } }  # visual separator
    @{ Label='Set all paths'; Type='action'; Action={ Run-SetAll } }
    @{ Label='Show params';   Type='action'; Action={ Show-Params $Settings } }
    @{ Label='Search modes';  Type='action'; Action={
      Write-Host ''
      Write-C '  Search term: ' -Fg white -NoNewline
      $term = Read-Host
      if ($term) { Search-HashMode -Term $term.Trim() }
    }}
  )

  Invoke-InteractiveMenu -Title 'Configuration' -Items $items -OnChange {
    Save-Settings $Settings
    $script:Settings = Load-Settings
  }
}

# ═══════════════════════════════════════════════════════════════════════
#  COMBINE WORDLISTS / RULELISTS
# ═══════════════════════════════════════════════════════════════════════

function Invoke-CombineCommand {
  Clear-Host
  Write-Banner "Combine & Deduplicate"
  Write-Host ''

  Write-Header "What to combine?"
  Write-C "  [" -Fg brightblack -NoNewline; Write-C "W" -Fg brightyellow -Bold -NoNewline; Write-C "] Wordlists" -Fg white
  Write-C "  [" -Fg brightblack -NoNewline; Write-C "R" -Fg brightyellow -Bold -NoNewline; Write-C "] Rulelists" -Fg white
  Write-C "  [" -Fg brightblack -NoNewline; Write-C "C" -Fg brightyellow -Bold -NoNewline; Write-C "] Custom paths" -Fg white
  $choice = Read-Host "  Choose (W/R/C)"
  if (-not $choice) { return }

  $filesToCombine = @()
  $rootPath = ''

  switch ($choice.Trim().ToUpper()) {
    'W' {
      if (-not $Settings.wordlists -or -not (Test-Path -LiteralPath $Settings.wordlists -PathType Container)) {
        Write-Err "Wordlists path not set or not found."
        Wait-Return
        return
      }
      $rootPath = (Resolve-Path -LiteralPath $Settings.wordlists).Path
      $files = Get-ChildItem -LiteralPath $Settings.wordlists -File -Recurse -ErrorAction SilentlyContinue | Sort-Object FullName
      if ($files.Count -eq 0) { Write-Err "No files found."; Wait-Return; return }
      $filesToCombine = Select-FilesInteractive -Title 'Select Wordlists to Combine' -Files $files -RootPath $rootPath
    }
    'R' {
      if (-not $Settings.rulelists -or -not (Test-Path -LiteralPath $Settings.rulelists -PathType Container)) {
        Write-Err "Rulelists path not set or not found."
        Wait-Return
        return
      }
      $rootPath = (Resolve-Path -LiteralPath $Settings.rulelists).Path
      $files = Get-ChildItem -LiteralPath $Settings.rulelists -File -Recurse -ErrorAction SilentlyContinue | Sort-Object FullName
      if ($files.Count -eq 0) { Write-Err "No files found."; Wait-Return; return }
      $filesToCombine = Select-FilesInteractive -Title 'Select Rulelists to Combine' -Files $files -RootPath $rootPath
    }
    'C' {
      Write-Host ''
      Write-C "  Enter file paths (one per line, blank line to finish):" -Fg white
      while ($true) {
        $p = Read-Host "  path"
        if ([string]::IsNullOrWhiteSpace($p)) { break }
        $p = $p.Trim().Trim('"', "'")
        if (Test-Path -LiteralPath $p -PathType Leaf) {
          $filesToCombine += $p
          Write-Success "    Added: $p"
        } else {
          Write-Warn "    Not found: $p"
        }
      }
    }
    default { Write-Warn "Unknown option."; return }
  }

  if (-not $filesToCombine -or $filesToCombine.Count -lt 2) {
    Write-Warn "Need at least 2 files to combine."
    Wait-Return
    return
  }

  # Output path
  $defaultOut = 'combined-output.txt'
  if ($rootPath) { $defaultOut = Join-Path $rootPath 'combined-output.txt' }
  Write-Host ''
  Write-C "  Output file " -Fg white -NoNewline
  Write-C "(default: $defaultOut)" -Fg brightblack -NoNewline
  Write-C ": " -Fg white -NoNewline
  $outPath = Read-Host
  if ([string]::IsNullOrWhiteSpace($outPath)) { $outPath = $defaultOut }

  Invoke-CombineFiles -InputPaths $filesToCombine -OutputPath $outPath

  Write-Host ''
  Wait-Return
}

# ═══════════════════════════════════════════════════════════════════════
#  MULTI-MODE COMMANDS
# ═══════════════════════════════════════════════════════════════════════

function Handle-ModesCommand([string]$Rest) {
  $rest = $Rest.Trim()

  if ($rest -match '^(clear|reset|off|none)$') {
    $Settings.modes = @()
    Save-Settings $Settings
    $script:Settings = Load-Settings
    Write-Success "Cleared multi-mode. Using single mode: $($Settings.mode)"
    Start-Sleep -Milliseconds 600
    return
  }

  # Parse comma/space separated integers
  $tokens = $rest -split '[,;\s]+' | Where-Object { $_ -match '^\d+$' } | ForEach-Object { [int]$_ } | Sort-Object -Unique
  if ($tokens.Count -eq 0) {
    Write-Warn "Usage: modes <int,int,...>  (e.g. 'modes 1000,22000')"
    Write-Dim "  Or:  modes clear    to revert to single mode"
    Start-Sleep -Milliseconds 900
    return
  }

  $Settings.modes = @($tokens)
  Save-Settings $Settings
  $script:Settings = Load-Settings
  Write-Success "Multi-mode set: $($tokens -join ', ')"
  Write-Info "  Attacks will repeat for each mode."

  # Validate folders
  if ($Settings.hashes) {
    foreach ($m in $tokens) {
      $mf = Join-Path -Path $Settings.hashes -ChildPath ([string]$m)
      if (-not (Test-Path -LiteralPath $mf -PathType Container)) {
        Write-Warn "  hashes/$m/ not found"
      } else {
        $cnt = (Get-ChildItem -LiteralPath $mf -File -ErrorAction SilentlyContinue).Count
        if ($cnt -eq 0) { Write-Warn "  hashes/$m/ is empty" }
        else { Write-Dim "  hashes/$m/ — $cnt hashlist(s)" }
      }
    }
  }
  Start-Sleep -Milliseconds 600
}

# ═══════════════════════════════════════════════════════════════════════
#  ENV FOR SCRIPTS
# ═══════════════════════════════════════════════════════════════════════

function Apply-EnvForScript([object]$Cfg) {
  $eff = $Cfg.effective
  # main vars
  $script:HASHCAT   = $eff.hashcatExe   ?? ''
  $script:KERNEL    = $eff.kernelFlag   ?? ''
  $script:LOOPBACK  = $eff.loopbackFlag ?? ''
  $script:HWMON     = $eff.hwmonFlag    ?? ''
  $script:HASHTYPE  = $eff.hashtype     ?? ''
  $script:RULELISTS = $eff.rulelists    ?? ''
  $script:WORDLISTS = $eff.wordlists    ?? ''
  $script:HASHES    = $eff.hashes       ?? ''

  Add-HashcatDirsToPath -HashcatExePath $script:HASHCAT

  if ($eff.rulePaths) {
    foreach ($entry in $eff.rulePaths.GetEnumerator()) {
      $name = $entry.Key
      $path = $entry.Value
      if ([string]::IsNullOrWhiteSpace($name)) { continue }
      Set-Variable -Name $name -Value ($path ?? '') -Scope Script -Force
    }
    $script:RULEMAP = $eff.rulePaths
  }

  $env:HASHCAT   = $script:HASHCAT
  $env:KERNEL    = $script:KERNEL
  $env:LOOPBACK  = $script:LOOPBACK
  $env:HWMON     = $script:HWMON
  $env:HASHTYPE  = [string]$script:HASHTYPE
  $env:RULELISTS = $script:RULELISTS
  $env:WORDLISTS = $script:WORDLISTS
  $env:HASHES    = $script:HASHES
}

function Invoke-NumericScript([string]$Num, [string]$Path, [object]$Cfg) {
  # Determine modes to run: multi-mode or single
  $modesToRun = @()
  if ($Cfg.modes -and $Cfg.modes.Count -gt 0) {
    $modesToRun = @($Cfg.modes)
  } else {
    $modesToRun = @($Cfg.mode)
  }

  # Identify upfront requirements from the script to prevent pausing mid-execution during multi-mode
  $scriptContent = Get-Content -LiteralPath $Path -Raw -ErrorAction SilentlyContinue

  $global:GH_PreSelectedHashlists = $null
  $global:GH_PreSelectedWordlist = $null
  $global:GH_PreSelectedMultipleWordlists = $null
  $global:GH_PreSelectedWordsInput = $null

  $needsHashlist = $scriptContent -match 'Select-Hashlist'
  $needsWordlist = $scriptContent -match 'Select-Wordlist'
  $needsMultipleWordlists = $scriptContent -match 'Select-MultipleWordlists'
  $needsWordsInput = $scriptContent -match "Read-HostEsc\s+'\s*Words:\s*'"

  # 1. Pre-collect inputs that are NOT mode-specific
  if ($needsWordlist) {
    $wl = Select-Wordlist -WordlistsRoot $Cfg.wordlists
    if (-not $wl) { Write-Warn "Wordlist selection cancelled."; return }
    $global:GH_PreSelectedWordlist = $wl
  }
  if ($needsMultipleWordlists) {
    $wls = Select-MultipleWordlists -WordlistsRoot $Cfg.wordlists
    if (-not $wls -or $wls.Count -eq 0) { Write-Warn "Multi-wordlist selection cancelled."; return }
    $global:GH_PreSelectedMultipleWordlists = $wls
  }
  if ($needsWordsInput) {
    Write-Host ''
    Write-Header "[Pre-Config] Enter seed word(s) for attacks"
    Write-Dim "  Space-separated, e.g. 'acme contoso globex'"
    $wordsInput = Read-HostEsc '  Words: '
    if ($null -eq $wordsInput) { Write-Warn "Words input cancelled."; return }
    $global:GH_PreSelectedWordsInput = $wordsInput
  }

  # 2. Pre-collect mode-specific hashlists
  if ($needsHashlist) {
    $global:GH_PreSelectedHashlists = @{}
    foreach ($m in $modesToRun) {
      if ($modesToRun.Count -gt 1) {
        Write-Host ''
        Write-Header "[Pre-Config] Hashlist for Mode $m"
      }
      $hl = Select-Hashlist -HashesRoot $Cfg.hashes -HashType $m
      if (-not $hl) { Write-Warn "Hashlist config aborted."; return }
      $global:GH_PreSelectedHashlists[[string]$m] = $hl
    }
    # Clear screen after pre-config before attacks begin
    Clear-Host
  }

  $isMultiMode = ($modesToRun.Count -gt 1)
  $isMultiScript = [bool](Get-Variable -Name 'GH_IsMultiScript' -Scope Global -ErrorAction SilentlyContinue -ValueOnly)
  if ($isMultiMode -and -not $isMultiScript) {
    $global:GH_DeferExecution = $true
    $global:GH_DeferredCommands = @()
  }

  for ($mi = 0; $mi -lt $modesToRun.Count; $mi++) {
    $currentMode = $modesToRun[$mi]

    # Override mode for this pass
    $Cfg.mode = $currentMode

    if (-not $isMultiMode) {
      Write-Host ''
      Write-Banner "Running ${Num}.ps1"
      Write-Dim "  $Path"
      Write-Separator
    }

    try {
      $Cfg.effective = Compute-Effective $Cfg
      Apply-EnvForScript $Cfg
      . $Path
    } catch {
      Write-Err "Execution failed: $($_.Exception.Message)"
      Write-Dim "  at: $($_.ScriptStackTrace)"
    }
  }

  if ($isMultiMode -and -not $isMultiScript) {
    $global:GH_DeferExecution = $false
    
    if ($global:GH_DeferredCommands -and $global:GH_DeferredCommands.Count -gt 0) {
      Write-Host ''
      Write-Banner "Queued Multi-Mode Attacks ($($modesToRun.Count) Modes)"
      Write-Dim "  ${Num}.ps1 cross-executed against mode(s): $($modesToRun -join ', ')"
      Write-Separator
      
      $success = Invoke-PlannedCommands -Planned $global:GH_DeferredCommands -HashcatExe $Cfg.effective.hashcatExe -Description "multi-mode sequential commands"
      
      if ($success) {
        Write-Host ''
        Write-Success "All queued multi-mode attacks accomplished."
      }
    } else {
      Write-Warn "No valid hashcat commands generated across chosen modes."
    }
  }

  if (-not $isMultiScript) {
    $global:GH_PreSelectedHashlists = $null
    $global:GH_PreSelectedWordlist = $null
    $global:GH_PreSelectedMultipleWordlists = $null
    $global:GH_PreSelectedWordsInput = $null
    $global:GH_DeferredCommands = $null
  }
}



# ═══════════════════════════════════════════════════════════════════════
#  HANDLE SET COMMAND
# ═══════════════════════════════════════════════════════════════════════

function Handle-SetCommand([string[]]$Tokens) {
  if ($Tokens.Count -ge 2 -and $Tokens[1].ToLowerInvariant() -eq 'all') {
    Run-SetAll
    return
  }

  if ($Tokens.Count -lt 3) {
    Write-Warn "Usage: set <hashcat|rulelists|wordlists|hashes|potfile|mode|loopback|kernel|hwmon|all> <value>"
    Start-Sleep -Milliseconds 900
    return
  }

  $key   = $Tokens[1].ToLowerInvariant()
  $value = ($Tokens[2..($Tokens.Count-1)] -join ' ').Trim()

  switch ($key) {
    'hashcat' {
      $dir = Resolve-ExistingDirectory $value
      if (-not $dir) { Write-Warn "Invalid directory: $value"; break }
      if (-not (Validate-HashcatDir $dir)) { Write-Warn "No hashcat binary in $dir"; break }
      $Settings.hashcat = $dir
      Write-Success "Set hashcat -> $dir"
    }
    'rulelists' {
      $dir = Resolve-ExistingDirectory $value
      if (-not $dir) { Write-Warn "Invalid directory: $value"; break }
      $Settings.rulelists = $dir
      Write-Success "Set rulelists -> $dir"
    }
    'wordlists' {
      $dir = Resolve-ExistingDirectory $value
      if (-not $dir) { Write-Warn "Invalid directory: $value"; break }
      $Settings.wordlists = $dir
      Write-Success "Set wordlists -> $dir"
    }
    'hashes' {
      $dir = Resolve-ExistingDirectory $value
      if (-not $dir) { Write-Warn "Invalid directory: $value"; break }
      $Settings.hashes = $dir
      Write-Success "Set hashes -> $dir"
    }
    'potfile' {
      if (-not (Test-Path -LiteralPath $value -PathType Leaf)) {
        Write-Warn "File not found: $value"
        break
      }
      $Settings.potfile = (Resolve-Path -LiteralPath $value).Path
      Write-Success "Set potfile -> $($Settings.potfile)"
    }
    'mode' {
      if (-not ($value -match '^\d+$')) {
        Write-Warn "Mode must be an integer (e.g. 0, 1000, 22000)"
        Write-Dim "  Tip: use 'search <name>' to find hash modes"
        break
      }
      $Settings.mode = [int]$value
      Write-Success "Set mode -> $($Settings.mode)"

      # Validate hashes folder
      if ($Settings.hashes) {
        $modeFolder = Join-Path -Path $Settings.hashes -ChildPath $value
        if (-not (Test-Path -LiteralPath $modeFolder -PathType Container)) {
          Write-Warn "Note: hashes/$value/ folder not found"
          Write-Dim "  Create it at: $modeFolder"
          Write-Dim "  Tip: use 'search <name>' to verify the hash mode"
        } else {
          $hashCount = (Get-ChildItem -LiteralPath $modeFolder -File -ErrorAction SilentlyContinue).Count
          if ($hashCount -eq 0) { Write-Warn "Note: hashes/$value/ folder is empty" }
          else { Write-Success "  Found $hashCount hashlist(s) in hashes/$value/" }
        }
      }
    }
    'loopback' {
      $yn = Parse-YesNo $value
      if ($yn -eq $null) { Write-Warn "loopback must be y|n"; break }
      $Settings.loopback = [bool]$yn
      Write-Success ("Set loopback -> {0}" -f (if ($Settings.loopback) {'enabled'} else {'disabled'}))
    }
    'kernel' {
      $yn = Parse-YesNo $value
      if ($yn -eq $null) { Write-Warn "kernel must be y|n"; break }
      $Settings.kernel = [bool]$yn
      Write-Success ("Set kernel -> {0}" -f (if ($Settings.kernel) {'enabled (-O)'} else {'disabled'}))
    }
    'hwmon' {
      $yn = Parse-YesNo $value
      if ($yn -eq $null) { Write-Warn "hwmon must be y|n"; break }
      $Settings.hwmon = [bool]$yn
      Write-Success ("Set hwmon -> {0}" -f (if ($Settings.hwmon) {'disabled (--hwmon-disable)'} else {'enabled'}))
    }
    default {
      Write-Warn "Unknown key: $key"
      Write-Dim "  Valid: hashcat, rulelists, wordlists, hashes, potfile, mode, loopback, kernel, hwmon, all"
      return
    }
  }

  Save-Settings $Settings
  $script:Settings = Load-Settings
  Start-Sleep -Milliseconds 600
}

# ═══════════════════════════════════════════════════════════════════════
#  MAIN LOOP
# ═══════════════════════════════════════════════════════════════════════

while ($true) {
  $Settings = Load-Settings
  $map = Get-ScriptMap
  Show-Menu -Map $map -Cfg $Settings

  Write-Host ''
  Write-C '  ghuge' -Fg cyan -Bold -NoNewline
  Write-C ' > ' -Fg white -NoNewline
  $input = Read-HostEsc
  if ($null -eq $input -or [string]::IsNullOrWhiteSpace($input)) { continue }

  if ($input -match '^(q|quit|exit)$')       { Write-Success "Goodbye!"; break }
  if ($input -match '^(r|refresh)$')         { $Settings = Load-Settings; continue }
  if ($input -match '^(\?|help)$')             { Show-Help $Settings;  continue }
  if ($input -match '^\s*show\s*$')          { Show-Params $Settings; continue }
  if ($input -match '^\s*config\s*$')        { Invoke-ConfigMenu; continue }
  if ($input -match '^\s*(stats?|cracked)\s*$') { Invoke-StatsMenu; continue }
  if ($input -match '^\s*audit\s*$')         { Show-Audit; continue }
  if ($input -match '^\s*potgen\s*$')        { Invoke-PotGen; continue }
  if ($input -match '^\s*combine\s*$')       { Invoke-CombineCommand; continue }

  # search <term>
  if ($input -match '^\s*search\s+(.+)$') {
    Search-HashMode -Term $matches[1].Trim()
    continue
  }

  # modes <int,int,...> or modes clear
  if ($input -match '^\s*modes\s+(.+)$') {
    Handle-ModesCommand -Rest $matches[1]
    continue
  }

  if ($input -match '^\s*set\s+') {
    $pattern = '("[^"]*"|''[^'']*''|\S+)'
    $tokens = @()
    foreach ($m in [System.Text.RegularExpressions.Regex]::Matches($input, $pattern)) { $tokens += $m.Value.Trim() }
    Handle-SetCommand -Tokens $tokens
    continue
  }

  if ($input -match '^[\d\s,]+$' -or $input -match '^(a|A|all|All)$') {
    $tokens = @()
    if ($input -match '^(a|A|all|All)$') {
      $tokens = @($map.Keys | Sort-Object { [int]$_ })
    } else {
      $tokens = @($input -split '[,;\s]+' | Where-Object { $_ -match '^\d+$' -and $map.ContainsKey($_) } | Sort-Object -Unique { [int]$_ })
    }

    if ($tokens.Count -eq 0) {
      Write-Warn "No valid scripts selected."
      Start-Sleep -Milliseconds 900
      continue
    }

    if ($tokens.Count -eq 1) {
      $num = $tokens[0]
      Invoke-NumericScript -Num $num -Path $map[$num].Path -Cfg $Settings
    } else {
      $global:GH_IsMultiScript    = $true
      $global:GH_DeferExecution   = $true
      $global:GH_DeferredCommands = @()

      foreach ($num in $tokens) {
        Invoke-NumericScript -Num $num -Path $map[$num].Path -Cfg $Settings
      }

      $global:GH_IsMultiScript  = $false
      $global:GH_DeferExecution = $false

      if ($global:GH_DeferredCommands -and $global:GH_DeferredCommands.Count -gt 0) {
        Write-Host ''
        $modeStr = if ($Settings.modes -and $Settings.modes.Count -gt 0) { "$($Settings.modes.Count) Modes" } else { "Single Mode" }
        Write-Banner "Queued Multi-Script Attacks ($($tokens.Count) Scripts / $modeStr)"
        Write-Dim "  Scripts executing: $($tokens -join ', ')"
        if ($Settings.modes -and $Settings.modes.Count -gt 0) {
           Write-Dim "  Across Mode(s): $($Settings.modes -join ', ')"
        }
        Write-Separator
        
        $success = Invoke-PlannedCommands -Planned $global:GH_DeferredCommands -HashcatExe $Settings.hashcat -Description "multi-script commands"
        
        if ($success) {
          Write-Host ''
          Write-Success "All queued multi-script attacks accomplished."
        }
      } else {
        Write-Warn "No valid hashcat commands generated across chosen scripts."
      }

      $global:GH_PreSelectedHashlists = $null
      $global:GH_PreSelectedWordlist = $null
      $global:GH_PreSelectedMultipleWordlists = $null
      $global:GH_PreSelectedWordsInput = $null
      $global:GH_DeferredCommands = $null
      
      Write-Dim "Press ENTER to return to menu..."
      Wait-Return
    }
  } else {
    Write-Warn "Unknown command: $input"
    Write-Dim "  Type 'help' for available commands"
    Start-Sleep -Milliseconds 900
  }
}




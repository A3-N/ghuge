<# ghuge.ps1 (PowerShell 7+) #>

if (-not $PSVersionTable.PSVersion -or $PSVersionTable.PSVersion.Major -lt 7) {
  Write-Error "ghuge.ps1 requires PowerShell 7+. Detected: $($PSVersionTable.PSVersion)"
  exit 1
}

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ScriptDir    = try { Split-Path -Parent $MyInvocation.MyCommand.Path } catch { (Get-Location).Path }
$Root         = Join-Path -Path $ScriptDir -ChildPath 'TheNumbers'
$SettingsPath = Join-Path -Path $ScriptDir -ChildPath 'settings.json'

if (-not (Test-Path -LiteralPath $Root)) {
  Write-Host "TheNumbers folder not found at: $Root"
  exit 1
}

function New-DefaultSettings {
  [ordered]@{
    hashcat    = $null
    rulelists  = $null
    wordlists  = $null
    hashes     = $null
    mode       = 1000
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
    $input = Read-Host ("Enter {0} path" -f $Label)
    if ([string]::IsNullOrWhiteSpace($input)) { Write-Host "Path cannot be empty."; continue }

    $resolved = Resolve-ExistingDirectory $input
    if (-not $resolved) { Write-Host "Directory not found. Try again."; continue }

    if ($RequireHashcat -and -not (Validate-HashcatDir $resolved)) {
      Write-Host "No hashcat binary found in that folder. Try again."
      continue
    }
    return $resolved
  }
}

function Run-SetAll {
  Write-Host ""
  Write-Host "== Set all paths =="

  $hc = Prompt-For-Dir -Label "hashcat" -RequireHashcat:$true
  $rl = Prompt-For-Dir -Label "rulelists"
  $wl = Prompt-For-Dir -Label "wordlists"
  $hh = Prompt-For-Dir -Label "hashes"

  $Settings.hashcat   = $hc
  $Settings.rulelists = $rl
  $Settings.wordlists = $wl
  $Settings.hashes    = $hh

  Save-Settings $Settings
  $Settings = Load-Settings
  Write-Host "All paths saved."
  Start-Sleep -Milliseconds 600
}

function Resolve-ExistingDirectory([string]$InputPath) {
  if ([string]::IsNullOrWhiteSpace($InputPath)) { return $null }
  $p = $InputPath.Trim()
  $p = $p.Trim('"', "'")
  try {
    $expanded = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($p)
  } catch {
    return $null
  }
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

  [pscustomobject]@{
    kernelFlag   = $kernelFlag
    loopbackFlag = $loopbackFlag
    hwmonFlag    = $hwmonFlag
    hashcatExe   = $hashcatExe
    hashtype     = $cfg.mode
    rulelists    = $cfg.rulelists
    wordlists    = $cfg.wordlists
    hashes       = $cfg.hashes
    rulePaths    = $rulePaths
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
    mode       = [int]$Settings.mode
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
      Write-Warning "settings.json failed JSON validation. Not overwriting; using defaults for this session."
      return $null
    }

    $obj = $raw | ConvertFrom-Json -Depth 10
    if ($obj.PSObject.Properties.Name -contains 'rule_files') {
      $rf = $obj.rule_files
      if ($rf -and -not ($rf -is [hashtable])) {
        $h = @{}
        foreach ($p in $rf.PSObject.Properties) {
          $h[$p.Name] = $p.Value
        }
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
    Write-Warning ("Load-Settings: failed to parse settings.json: {0}" -f $_.Exception.Message)
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
    'y' { return $true }
    'yes' { return $true }
    'true' { return $true }
    '1' { return $true }
    'n' { return $false }
    'no' { return $false }
    'false' { return $false }
    '0' { return $false }
    default { return $null }
  }
}

$Settings = Load-Settings
if (-not $Settings) {
  Write-Host "No settings.json found. Let's configure your environment."
  $Settings = [pscustomobject](New-DefaultSettings)

  try {
    $hc = Get-Command hashcat, hashcat.exe -ErrorAction Stop | Select-Object -First 1
    if ($hc) {
      $Settings.hashcat = Split-Path -Parent $hc.Source
      Write-Host "Auto-detected hashcat at: $($Settings.hashcat)"
    }
  } catch { }

  if (-not $Settings.hashcat) {
    $h = Read-Host "Enter path to hashcat folder (or leave blank)"
    if ($h) {
      $dir = Resolve-ExistingDirectory $h
      if ($dir -and (Validate-HashcatDir $dir)) { $Settings.hashcat = $dir }
      else { Write-Host "Warning: hashcat not found under '$h' - set it later with: set hashcat `<path`>" }
    }
  }

  $r = Read-Host "Enter path to rulelists folder (or leave blank)"; if ($r)  { $Settings.rulelists = Resolve-ExistingDirectory $r }
  $w = Read-Host "Enter path to wordlists folder (or leave blank)"; if ($w)  { $Settings.wordlists = Resolve-ExistingDirectory $w }
  $hs= Read-Host "Enter path to hashes folder (or leave blank)"   ; if ($hs) { $Settings.hashes    = Resolve-ExistingDirectory $hs }

  Save-Settings $Settings
  if (-not (Test-Path -LiteralPath $SettingsPath -PathType Leaf)) {
    Write-Error "Failed to write settings.json at $SettingsPath"
    exit 1
  }
  Write-Host "settings.json created at $SettingsPath"

  $Settings = Load-Settings
} else {
  $Settings = Load-Settings
}

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

function Show-Params([object]$Cfg) {
  Clear-Host
  Write-Host "==== ghuge :: Parameters ===="
  Write-Host ""
  Write-Host "Base paths:"
  Write-Host ("  hashcat   : {0}" -f ($Cfg.hashcat   ?? "(not set)"))
  Write-Host ("  rulelists : {0}" -f ($Cfg.rulelists ?? "(not set)"))
  Write-Host ("  wordlists : {0}" -f ($Cfg.wordlists ?? "(not set)"))
  Write-Host ("  hashes    : {0}" -f ($Cfg.hashes    ?? "(not set)"))
  Write-Host ""
  Write-Host "Flags & mode:"
  $loopbackStatus = if ($Cfg.loopback) { 'enabled (--loopback)' } else { 'disabled' }
  $kernelStatus   = if ($Cfg.kernel)   { 'enabled (-O)' } else { 'disabled' }
  $hwmonStatus    = if ($Cfg.hwmon)    { 'disabled (--hwmon-disable)' } else { 'enabled' }
  Write-Host ("  mode      : {0}" -f ($Cfg.mode ?? 1000))
  Write-Host ("  loopback  : {0}" -f $loopbackStatus)
  Write-Host ("  kernel    : {0}" -f $kernelStatus)
  Write-Host ("  hwmon     : {0}" -f $hwmonStatus)
  Write-Host ""
  Write-Host "Resolved (effective):"
  $eff = $Cfg.effective
  Write-Host ("  HASHCAT exe : {0}" -f ($eff.hashcatExe ?? "(not set)"))
  Write-Host ("  KERNEL flag : {0}" -f ($eff.kernelFlag ?? "(none)"))
  Write-Host ("  LOOPBACK    : {0}" -f ($eff.loopbackFlag ?? "(none)"))
  Write-Host ("  HWMON flag  : {0}" -f ($eff.hwmonFlag ?? "(none)"))
  Write-Host ("  HASHMODE    : {0}" -f ($eff.hashtype ?? "(not set)"))
  Write-Host ""
  Write-Host "Rule files (base: $($Cfg.rulelists ?? '(not set)')):"
  if ($eff.rulePaths -and $eff.rulePaths.Keys.Count -gt 0) {
    $eff.rulePaths.GetEnumerator() |
      Sort-Object Key |
      ForEach-Object {
        $val = $_.Value
        $exists = $false
        if ($val -and (Test-Path -LiteralPath $val -PathType Leaf)) { $exists = $true }
        $status = if ($exists) { '[ok]' } else { '[missing]' }
        Write-Host ("  {0,-14} -> {1} {2}" -f $_.Key, ($val ?? '(filename only)'), $status)
      }
  } else {
    Write-Host "  (none resolved)"
  }
  Write-Host ""
  Write-Host "Press ENTER to return..."
  [void][Console]::ReadLine()
}

function Show-Menu([hashtable]$Map, [object]$Cfg) {
  $Cfg.effective = Compute-Effective $Cfg
  Clear-Host
  Write-Host "==== ghuge :: TheNumbers ===="
  if ($Map.Count -eq 0) {
    Write-Host "No numeric scripts found in: $Root"
  } else {
    Write-Host "Available:"
    foreach ($k in ($Map.Keys | Sort-Object {[int]$_})) {
      Write-Host ("  [{0}] {1}" -f $k, $Map[$k].Display)
    }
  }
  Write-Host ""
  Write-Host "Effective parameters:"
  $eff = $Cfg.effective
  $kernelLine   = if ([string]::IsNullOrWhiteSpace($eff.kernelFlag)) { "KERNEL  : (none)" } else { "KERNEL  : $($eff.kernelFlag)" }
  $loopbackLine = if ([string]::IsNullOrWhiteSpace($eff.loopbackFlag)) { "LOOPBACK: (none)" } else { "LOOPBACK: $($eff.loopbackFlag)" }
  $hwmonLine    = if ([string]::IsNullOrWhiteSpace($eff.hwmonFlag)) { "HWMON   : (none)" } else { "HWMON   : $($eff.hwmonFlag)" }
  $modeLine     = "HASHMODE: $($eff.hashtype)"
  Write-Host "  $modeLine"
  Write-Host "  $kernelLine"
  Write-Host "  $loopbackLine"
  Write-Host "  $hwmonLine"
  Write-Host ""
  Write-Host "Type a number to run, or 'help' / 'show'."
}

function Show-Help([object]$Cfg) {
  Clear-Host
  Write-Host "==== ghuge :: Help ===="
  Write-Host ""
  Write-Host "Commands:"
  Write-Host "  show               # show all params/paths and resolved rules"
  Write-Host "  set all"
  Write-Host "  set hashcat   `<path`>"
  Write-Host "  set rulelists `<path`>"
  Write-Host "  set wordlists `<path`>"
  Write-Host "  set hashes    `<path`>"
  Write-Host "  set mode      <int>"
  Write-Host "  set loopback  <y|n>"
  Write-Host "  set kernel    <y|n>"
  Write-Host "  set hwmon     <y|n>"
  Write-Host "  r | refresh"
  Write-Host "  q | quit"
  Write-Host ""
  Write-Host "Current values:"
  Write-Host ("  hashcat   : {0}" -f ($Cfg.hashcat   ?? "(not set)"))
  Write-Host ("  rulelists : {0}" -f ($Cfg.rulelists ?? "(not set)"))
  Write-Host ("  wordlists : {0}" -f ($Cfg.wordlists ?? "(not set)"))
  Write-Host ("  hashes    : {0}" -f ($Cfg.hashes    ?? "(not set)"))
  Write-Host ("  mode      : {0}" -f ($Cfg.mode      ?? 1000))
  $loopbackStatus = if ($Cfg.loopback) { 'enabled' } else { 'disabled' }
  $kernelStatus   = if ($Cfg.kernel)   { 'enabled' } else { 'disabled' }
  $hwmonStatus    = if ($Cfg.hwmon)    { 'disabled' } else { 'enabled' }
  Write-Host ("  loopback  : {0}" -f $loopbackStatus)
  Write-Host ("  kernel    : {0}" -f $kernelStatus)
  Write-Host ("  hwmon     : {0}" -f $hwmonStatus)
  Write-Host ""
  Write-Host "Press ENTER to return..."
  [void][Console]::ReadLine()
}

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
  Write-Host ""
  Write-Host ("==> Running {0}.ps1" -f $Num)
  Write-Host ("    {0}" -f $Path)
  Write-Host "----------------------------------------"
  try {
    $Cfg.effective = Compute-Effective $Cfg
    Apply-EnvForScript $Cfg
    . $Path
  } catch {
    Write-Host "Execution failed: $($_.Exception.Message)"
  }
  Write-Host "----------------------------------------"
  Write-Host "Press ENTER to return to menu..."
  [void][Console]::ReadLine()
}

function Handle-SetCommand([string[]]$Tokens) {
  if ($Tokens.Count -ge 2 -and $Tokens[1].ToLowerInvariant() -eq 'all') {
    Run-SetAll
    return
  }

  if ($Tokens.Count -lt 3) {
    Write-Host "usage: set `<hashcat|rulelists|wordlists|hashes|mode|loopback|kernel|hwmon|all`> `<value`>"
    Start-Sleep -Milliseconds 900
    return
  }

  $key   = $Tokens[1].ToLowerInvariant()
  $value = ($Tokens[2..($Tokens.Count-1)] -join ' ').Trim()

  switch ($key) {
    'hashcat' {
      $dir = Resolve-ExistingDirectory $value
      if (-not $dir) { Write-Host "Invalid directory: $value"; break }
      if (-not (Validate-HashcatDir $dir)) { Write-Host "No hashcat binary in $dir"; break }
      $Settings.hashcat = $dir
      Write-Host "Set hashcat -> $dir"
    }
    'rulelists' { $dir = Resolve-ExistingDirectory $value; if (-not $dir) {Write-Host "Invalid directory: $value"; break}; $Settings.rulelists = $dir; Write-Host "Set rulelists -> $dir" }
    'wordlists' { $dir = Resolve-ExistingDirectory $value; if (-not $dir) {Write-Host "Invalid directory: $value"; break}; $Settings.wordlists = $dir; Write-Host "Set wordlists -> $dir" }
    'hashes'    { $dir = Resolve-ExistingDirectory $value; if (-not $dir) {Write-Host "Invalid directory: $value"; break}; $Settings.hashes    = $dir; Write-Host "Set hashes -> $dir" }
    'mode' {
      if (-not ($value -match '^\d+$')) { Write-Host "mode must be an integer (e.g., 0, 1000, 22000)"; break }
      $Settings.mode = [int]$value
      Write-Host "Set mode -> $($Settings.mode)"
    }
    'loopback' { $yn = Parse-YesNo $value; if ($yn -eq $null) { Write-Host "loopback must be y|n"; break }; $Settings.loopback = [bool]$yn; Write-Host ("Set loopback -> {0}" -f (if ($Settings.loopback) {'enabled'} else {'disabled'})) }
    'kernel'   { $yn = Parse-YesNo $value; if ($yn -eq $null) { Write-Host "kernel must be y|n"; break };   $Settings.kernel   = [bool]$yn; Write-Host ("Set kernel -> {0}"   -f (if ($Settings.kernel)   {'enabled'} else {'disabled'})) }
    'hwmon'    { $yn = Parse-YesNo $value; if ($yn -eq $null) { Write-Host "hwmon must be y|n"; break };    $Settings.hwmon    = [bool]$yn; Write-Host ("Set hwmon -> {0}"    -f (if ($Settings.hwmon)    {'disabled'} else {'enabled'})) }
    default    { Write-Host "Unknown key: $key"; return }
  }

  Save-Settings $Settings
  $Settings = Load-Settings
  Start-Sleep -Milliseconds 600
}

while ($true) {
  $Settings = Load-Settings
  $map = Get-ScriptMap
  Show-Menu -Map $map -Cfg $Settings

  $input = Read-Host "Select number or command"
  if ([string]::IsNullOrWhiteSpace($input)) { continue }

  if ($input -match '^(q|quit)$')       { break }
  if ($input -match '^(r|refresh)$') { $Settings = Load-Settings; continue }
  if ($input -match '^\s*help\s*$')     { Show-Help $Settings;  continue }
  if ($input -match '^\s*show\s*$')     { Show-Params $Settings; continue }

  if ($input -match '^\s*set\s+') {
    $pattern = '("[^"]*"|''[^'']*''|\S+)'
    $tokens = @()
    foreach ($m in [System.Text.RegularExpressions.Regex]::Matches($input, $pattern)) { $tokens += $m.Value.Trim() }
    Handle-SetCommand -Tokens $tokens
    continue
  }

  if ($input -match '^\d+$' -and $map.ContainsKey($input)) {
    Invoke-NumericScript -Num $input -Path $map[$input].Path -Cfg $Settings
  }
}

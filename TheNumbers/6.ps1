<# hybrid #>

<# 6.ps1 - hybrid / wordlist hybrid passes (PowerShell)
   Expects from ghuge.ps1 (script scope): $HASHCAT, $KERNEL, $HWMON, $HASHTYPE, $HASHES, $WORDLISTS
   Behavior:
     - Sanity checks only (fail early)
     - Choose Single (one wordlist) or Multiple (many)
     - Multiple accepts numbers & ranges (e.g. 93 94, 1-2, 10,12-15)
     - Preview commands, ENTER to run, 'n' to cancel
     - No SHOWCRACKED / POTFILE usage
#>

# ---------- sanity ----------
$required = @('HASHCAT','HASHTYPE','HASHES','WORDLISTS')
foreach ($v in $required) {
  $gv = Get-Variable -Name $v -Scope Script -ErrorAction SilentlyContinue
  if (-not $gv) { Write-Error "$v not found. Make sure ghuge exported variables into the script scope."; return }
  if ([string]::IsNullOrWhiteSpace([string]$gv.Value)) { Write-Error "$v is empty. Check ghuge settings."; return }
}
if (-not (Test-Path -LiteralPath $HASHCAT -PathType Leaf)) { Write-Error "HASHCAT exe not found at: $HASHCAT"; return }
if (-not (Test-Path -LiteralPath $WORDLISTS -PathType Container)) { Write-Error "WORDLISTS folder missing: $WORDLISTS"; return }

# ---------- helpers ----------
function Normalize-Input([string]$s) {
  if ($null -eq $s) { return '' }
  $s = $s -replace '\u00A0', ' '
  $s = $s -replace '[\u2000-\u200B\u202F\u205F\u3000]', ' '
  return $s.Trim()
}

function Parse-SelectionVerbose([string]$input, [int]$max) {
  # Returns PSCustomObject with: Raw, Tokens, ExpandedNumbers, Valid, FallbackValid, Invalid
  $raw = Normalize-Input $input
  $tokens = @()
  if ($raw -ne '') {
    $tokens = $raw -split '[,;\s]+' | Where-Object { $_ -ne '' }
  }

  $expanded = New-Object System.Collections.Generic.List[int]
  $invalid  = New-Object System.Collections.Generic.List[string]

  foreach ($t in $tokens) {
    if ($t -match '^\d+\s*-\s*\d+$') {
      $parts = $t -split '\s*-\s*'
      $a = [int]$parts[0]; $b = [int]$parts[1]
      if ($a -gt $b) { $tmp=$a; $a=$b; $b=$tmp }
      for ($i=$a; $i -le $b; $i++) { $expanded.Add($i) }
    } elseif ($t -match '^\d+$') {
      $expanded.Add([int]$t)
    } else {
      $invalid.Add($t)
    }
  }

  # Build primary valid set (clamped)
  $valid = @()
  $expandedUnique = @()
  if ($expanded.Count -gt 0) {
    $expandedUnique = ($expanded | Select-Object -Unique | Sort-Object)
    foreach ($n in $expandedUnique) {
      if ($n -ge 1 -and $n -le $max) { $valid += $n } else { $invalid.Add([string]$n) }
    }
  }

  # Fallback: grab any digits if nothing valid
  $fallbackValid = @()
  if (-not $valid -or $valid.Count -eq 0) {
    $m = [regex]::Matches($raw, '\d+')
    if ($m.Count -gt 0) {
      foreach ($mt in $m) {
        $n = [int]$mt.Value
        if ($n -ge 1 -and $n -le $max) { $fallbackValid += $n }
      }
      $fallbackValid = $fallbackValid | Sort-Object -Unique
    }
  }

  [pscustomobject]@{
    Raw             = $raw
    Tokens          = $tokens
    ExpandedNumbers = $expandedUnique
    Valid           = ($valid | Sort-Object -Unique)
    FallbackValid   = $fallbackValid
    Invalid         = ($invalid | Select-Object -Unique)
  }
}

function Add-If([ref]$arr, [string]$item) {
  if ($null -ne $item -and $item.Trim() -ne '') { $arr.Value += ,$item }
}

# ---------- choose single or multiple ----------
$mode = Read-Host "Single or Multiple wordlist mode? S/M"
if (-not $mode) { Write-Error "No mode selected; aborting."; return }

# gather candidate wordlists (recursive)
$wlFiles = Get-ChildItem -LiteralPath $WORDLISTS -File -Recurse -ErrorAction SilentlyContinue | Sort-Object FullName
if ($wlFiles.Count -eq 0) { Write-Error "No wordlist files found under $WORDLISTS"; return }

$SelectedWordlists = @()

if ($mode.Trim().ToUpper() -eq 'S') {
  Write-Host "Choose one wordlist under ${WORDLISTS}:"
  for ($i=0; $i -lt $wlFiles.Count; $i++) {
    $rel = $wlFiles[$i].FullName.Substring((Resolve-Path $WORDLISTS).Path.Length).TrimStart([IO.Path]::DirectorySeparatorChar)
    Write-Host ("  [{0}] {1}" -f ($i+1), $rel)
  }
  [int]$sel = 0
  while ($sel -lt 1 -or $sel -gt $wlFiles.Count) {
    $raw = Read-Host ("Enter number (1..{0})" -f $wlFiles.Count)
    [int]::TryParse($raw, [ref]$sel) | Out-Null
  }
  $SelectedWordlists += $wlFiles[$sel-1].FullName
}
elseif ($mode.Trim().ToUpper() -eq 'M') {
  Write-Host "Choose multiple wordlists (numbers and ranges, e.g. '93 94', '1-2', '10,12-15') from ${WORDLISTS}:"
  for ($i=0; $i -lt $wlFiles.Count; $i++) {
    $rel = $wlFiles[$i].FullName.Substring((Resolve-Path $WORDLISTS).Path.Length).TrimStart([IO.Path]::DirectorySeparatorChar)
    Write-Host ("  [{0}] {1}" -f ($i+1), $rel)
  }

  while ($true) {
    $raw = Read-Host ("Enter selections in 1..{0}" -f $wlFiles.Count)
    $res = Parse-SelectionVerbose $raw $wlFiles.Count

    # Debug feedback
    $tokStr = if ($res.Tokens -and $res.Tokens.Count -gt 0) { ($res.Tokens -join ' ') } else { '(none)' }
    $expStr = if ($res.ExpandedNumbers -and $res.ExpandedNumbers.Count -gt 0) { ($res.ExpandedNumbers -join ', ') } else { '(none)' }
    Write-Host ("[debug] tokens:        {0}" -f $tokStr)
    Write-Host ("[debug] expanded nums: {0}" -f $expStr)
    if ($res.Invalid -and $res.Invalid.Count -gt 0) {
      Write-Host ("[!] ignored non-numeric/out-of-range: {0}" -f ($res.Invalid -join ', '))
    }

    $use = @()
    if ($res.Valid -and $res.Valid.Count -gt 0) {
      $use = $res.Valid
    } elseif ($res.FallbackValid -and $res.FallbackValid.Count -gt 0) {
      Write-Host ("[info] fallback accepted: {0}" -f ($res.FallbackValid -join ', '))
      $use = $res.FallbackValid
    }

    if ($use -and $use.Count -gt 0) {
      foreach ($i in $use) { $SelectedWordlists += $wlFiles[$i-1].FullName }
      break
    }

    Write-Host "No valid selection; try again."
  }
}
else {
  Write-Error "Unknown mode: $mode"; return
}

# ---------- pick HASHLIST ----------
$modeFolder = Join-Path -Path $HASHES -ChildPath ([string]$HASHTYPE)
if (-not (Test-Path -LiteralPath $modeFolder -PathType Container)) { Write-Error "No folder for mode ${HASHTYPE} under ${HASHES}"; return }
$hashFiles = Get-ChildItem -LiteralPath $modeFolder -File | Sort-Object Name
if ($hashFiles.Count -eq 0) { Write-Error "No hashlists found in ${modeFolder}"; return }
Write-Host "Select a hashlist for mode ${HASHTYPE}:"
for ($i=0; $i -lt $hashFiles.Count; $i++) { Write-Host ("  [{0}] {1}" -f ($i+1), $hashFiles[$i].Name) }
[int]$hi=0
while ($hi -lt 1 -or $hi -gt $hashFiles.Count) {
  $raw = Read-Host ("Enter number (1..{0})" -f $hashFiles.Count)
  [int]::TryParse($raw, [ref]$hi) | Out-Null
}
$HASHLIST = $hashFiles[$hi-1].FullName
Write-Host "Selected hashlist: $HASHLIST"

# ---------- build planned commands ----------
$argsBase = @()
Add-If -arr ([ref]$argsBase) $KERNEL
if ($KERNEL -and $KERNEL.Trim() -ne '') { $argsBase += '--bitmap-max=24' }
Add-If -arr ([ref]$argsBase) $HWMON
Add-If -arr ([ref]$argsBase) ("-m$HASHTYPE")
Add-If -arr ([ref]$argsBase) $HASHLIST

# WORDLIST arg(s)
$wlArgs = @()
foreach ($w in $SelectedWordlists) { $wlArgs += $w }

$Planned = @()

# 1) -a6 <WORDLIST> -j c '?s?d?d?d?d' --increment
$cmd = @(); $cmd += $argsBase; $cmd += '-a6'; $cmd += $wlArgs; $cmd += '-j'; $cmd += 'c'; $cmd += '?s?d?d?d?d'; $cmd += '--increment'
$cmd1 = $cmd | Where-Object { $_ -ne $null -and $_ -ne '' }; $Planned += [pscustomobject]@{ Args=$cmd1; Pretty="$HASHCAT " + ($cmd1 -join ' ') }

# 2) -a6 <WORDLIST> -j c '?d?d?d?d?s' --increment
$cmd = @(); $cmd += $argsBase; $cmd += '-a6'; $cmd += $wlArgs; $cmd += '-j'; $cmd += 'c'; $cmd += '?d?d?d?d?s'; $cmd += '--increment'
$cmd2 = $cmd | Where-Object { $_ -ne $null -and $_ -ne '' }; $Planned += [pscustomobject]@{ Args=$cmd2; Pretty="$HASHCAT " + ($cmd2 -join ' ') }

# 3) -a6 <WORDLIST> -j c '?a?a' --increment
$cmd = @(); $cmd += $argsBase; $cmd += '-a6'; $cmd += $wlArgs; $cmd += '-j'; $cmd += 'c'; $cmd += '?a?a'; $cmd += '--increment'
$cmd3 = $cmd | Where-Object { $_ -ne $null -and $_ -ne '' }; $Planned += [pscustomobject]@{ Args=$cmd3; Pretty="$HASHCAT " + ($cmd3 -join ' ') }

# 4) -a6 <WORDLIST> '?s?d?d?d?d' --increment
$cmd = @(); $cmd += $argsBase; $cmd += '-a6'; $cmd += $wlArgs; $cmd += '?s?d?d?d?d'; $cmd += '--increment'
$cmd4 = $cmd | Where-Object { $_ -ne $null -and $_ -ne '' }; $Planned += [pscustomobject]@{ Args=$cmd4; Pretty="$HASHCAT " + ($cmd4 -join ' ') }

# 5) -a6 <WORDLIST> '?d?d?d?d?s' --increment
$cmd = @(); $cmd += $argsBase; $cmd += '-a6'; $cmd += $wlArgs; $cmd += '?d?d?d?d?s'; $cmd += '--increment'
$cmd5 = $cmd | Where-Object { $_ -ne $null -and $_ -ne '' }; $Planned += [pscustomobject]@{ Args=$cmd5; Pretty="$HASHCAT " + ($cmd5 -join ' ') }

# 6) -a6 <WORDLIST> '?a?a' --increment
$cmd = @(); $cmd += $argsBase; $cmd += '-a6'; $cmd += $wlArgs; $cmd += '?a?a'; $cmd += '--increment'
$cmd6 = $cmd | Where-Object { $_ -ne $null -and $_ -ne '' }; $Planned += [pscustomobject]@{ Args=$cmd6; Pretty="$HASHCAT " + ($cmd6 -join ' ') }

if ($Planned.Count -eq 0) { Write-Error "No planned commands."; return }

# ---------- preview ----------
Clear-Host
Write-Host "Wordlist(s):"
foreach ($w in $SelectedWordlists) { Write-Host "  $w" }
Write-Host "=== Preview: $($Planned.Count) hashcat commands to run ==="
for ($i = 0; $i -lt $Planned.Count; $i++) {
  Write-Host ("[{0}] {1}" -f ($i+1), $Planned[$i].Pretty)
}
Write-Host ""
$ans = Read-Host "Press ENTER to start execution, or type 'n' to cancel"
if ($ans -and $ans.Trim().ToLower() -eq 'n') {
  Write-Host "Cancelled by user."
  return
}

# ---------- execute ----------
$HashcatDir = Split-Path -Parent $HASHCAT
Write-Host ""
Write-Host ("Running {0} commands against: {1}" -f $Planned.Count, $HASHLIST)
for ($i = 0; $i -lt $Planned.Count; $i++) {
  $item = $Planned[$i]
  Write-Host ""
  Write-Host ("--- Command {0}/{1} ---" -f ($i+1), $Planned.Count)
  Write-Host ("Command: {0}" -f $item.Pretty)
  try {
    Push-Location $HashcatDir
    & $HASHCAT @($item.Args)
  } catch {
    Write-Host "Execution failed: $($_.Exception.Message)"
  } finally {
    Pop-Location
  }
}

Write-Host "`nHybrid processing done`n"
### FIX M
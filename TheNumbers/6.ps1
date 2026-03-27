<# hybrid #>

<# 6.ps1 - hybrid / wordlist hybrid passes (PowerShell)
   Single or Multiple wordlist selection, then hybrid attacks with capitalize + mask combos.
#>

# ── Validation ──
if (-not (Assert-RequiredVars @('HASHCAT','HASHTYPE','HASHES','WORDLISTS'))) { return }
if (-not (Assert-PathExists $HASHCAT 'HASHCAT exe')) { return }
if (-not (Assert-PathExists $WORDLISTS 'WORDLISTS folder' 'Container')) { return }

# ── Single or Multiple mode ──
Write-Header "Wordlist Mode"
Write-C "  [" -Fg brightblack -NoNewline; Write-C "S" -Fg brightyellow -Bold -NoNewline; Write-C "] Single wordlist" -Fg white
Write-C "  [" -Fg brightblack -NoNewline; Write-C "M" -Fg brightyellow -Bold -NoNewline; Write-C "] Multiple wordlists" -Fg white
$mode = Read-HostEsc '  Choose (S/M): '
if ($null -eq $mode) { return }
if (-not $mode) { Write-Err "No mode selected; aborting."; return }

$SelectedWordlists = @()
$modeChar = $mode.Trim().ToUpper()

if ($modeChar -eq 'S') {
  $wl = Select-Wordlist -WordlistsRoot $WORDLISTS
  if (-not $wl) { return }
  $SelectedWordlists = @($wl)
}
elseif ($modeChar -eq 'M') {
  $wls = Select-MultipleWordlists -WordlistsRoot $WORDLISTS
  if (-not $wls -or $wls.Count -eq 0) { return }
  $SelectedWordlists = $wls
}
else {
  Write-Err "Unknown mode: $mode"
  return
}

# ── Select hashlist ──
$HASHLIST = Select-Hashlist -HashesRoot $HASHES -HashType $HASHTYPE
if (-not $HASHLIST) { return }

# ── Build commands ──
$argsBase = Build-BaseArgs -Kernel $KERNEL -Hwmon $HWMON -HashType $HASHTYPE -Hashlist $HASHLIST

$wlArgs = @()
foreach ($w in $SelectedWordlists) { $wlArgs += $w }

$Planned = @()

# 1) -a6 <WORDLIST> -j c '?s?d?d?d?d' --increment
$cmd = @(); $cmd += $argsBase; $cmd += '-a6'; $cmd += $wlArgs; $cmd += '-j'; $cmd += 'c'; $cmd += '?s?d?d?d?d'; $cmd += '--increment'
$Planned += [pscustomobject]@{ Args = ($cmd | Where-Object { $_ -ne $null -and $_ -ne '' }) }

# 2) -a6 <WORDLIST> -j c '?d?d?d?d?s' --increment
$cmd = @(); $cmd += $argsBase; $cmd += '-a6'; $cmd += $wlArgs; $cmd += '-j'; $cmd += 'c'; $cmd += '?d?d?d?d?s'; $cmd += '--increment'
$Planned += [pscustomobject]@{ Args = ($cmd | Where-Object { $_ -ne $null -and $_ -ne '' }) }

# 3) -a6 <WORDLIST> -j c '?a?a' --increment
$cmd = @(); $cmd += $argsBase; $cmd += '-a6'; $cmd += $wlArgs; $cmd += '-j'; $cmd += 'c'; $cmd += '?a?a'; $cmd += '--increment'
$Planned += [pscustomobject]@{ Args = ($cmd | Where-Object { $_ -ne $null -and $_ -ne '' }) }

# 4) -a6 <WORDLIST> '?s?d?d?d?d' --increment  (no capitalize)
$cmd = @(); $cmd += $argsBase; $cmd += '-a6'; $cmd += $wlArgs; $cmd += '?s?d?d?d?d'; $cmd += '--increment'
$Planned += [pscustomobject]@{ Args = ($cmd | Where-Object { $_ -ne $null -and $_ -ne '' }) }

# 5) -a6 <WORDLIST> '?d?d?d?d?s' --increment  (no capitalize)
$cmd = @(); $cmd += $argsBase; $cmd += '-a6'; $cmd += $wlArgs; $cmd += '?d?d?d?d?s'; $cmd += '--increment'
$Planned += [pscustomobject]@{ Args = ($cmd | Where-Object { $_ -ne $null -and $_ -ne '' }) }

# 6) -a6 <WORDLIST> '?a?a' --increment  (no capitalize)
$cmd = @(); $cmd += $argsBase; $cmd += '-a6'; $cmd += $wlArgs; $cmd += '?a?a'; $cmd += '--increment'
$Planned += [pscustomobject]@{ Args = ($cmd | Where-Object { $_ -ne $null -and $_ -ne '' }) }

if ($Planned.Count -eq 0) { Write-Err "No planned commands."; return }

# ── Execute ──
Invoke-PlannedCommands -Planned $Planned -HashcatExe $HASHCAT -Description 'hybrid commands'
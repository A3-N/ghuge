<# heavy rules #>

# ── Validation ──
if (-not (Assert-RequiredVars @('HASHCAT','HASHTYPE','HASHES','WORDLISTS'))) { return }
if (-not (Assert-PathExists $HASHCAT 'HASHCAT exe')) { return }
if (-not (Assert-PathExists $HASHES 'HASHES root' 'Container')) { return }
if (-not (Assert-PathExists $WORDLISTS 'WORDLISTS root' 'Container')) { return }

# ── Resolve rule list (heavy set) ──
$RULELIST = @(
  $tenKrules, $fbfull, $NSAKEYv2, $fordyv1, $pantag, $OUTD,
  $techtrip2, $williamsuper, $digits3, $dive, $robotmyfavorite
) | Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Leaf) }

if ($RULELIST.Count -eq 0) {
  Write-Err "No rule files found. Check rule_files + rulelists in ghuge settings."
  return
}
Write-Info "Resolved $($RULELIST.Count) rule file(s)"

# ── Select hashlist & wordlist ──
$HASHLIST = Select-Hashlist -HashesRoot $HASHES -HashType $HASHTYPE
if (-not $HASHLIST) { return }

$WORDLIST = Select-Wordlist -WordlistsRoot $WORDLISTS
if (-not $WORDLIST) { return }

# ── Build commands ──
$argsBase = Build-BaseArgs -Kernel $KERNEL -Hwmon $HWMON -HashType $HASHTYPE -Hashlist $HASHLIST -Wordlist $WORDLIST

$Planned = @()

# straight wordlist (no rules)
$baseArgs = $argsBase | Where-Object { $_ -ne $null -and $_ -ne '' }
$Planned += [pscustomobject]@{ Args = $baseArgs }

# with each rule
foreach ($rule in $RULELIST) {
  if (-not (Test-Path -LiteralPath $rule -PathType Leaf)) { continue }
  $cmdArgs = @()
  $cmdArgs += $argsBase
  $cmdArgs += '-r'
  $cmdArgs += $rule
  Add-If -arr ([ref]$cmdArgs) $LOOPBACK
  $cmdArgs = $cmdArgs | Where-Object { $_ -ne $null -and $_ -ne '' }
  $Planned += [pscustomobject]@{ Args = $cmdArgs }
}

# ── Execute ──
Invoke-PlannedCommands -Planned $Planned -HashcatExe $HASHCAT -Description 'heavy rule commands'

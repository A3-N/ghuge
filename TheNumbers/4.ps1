<# word-based rule passes #>

# ── Validation ──
if (-not (Assert-RequiredVars @('HASHCAT','HASHTYPE','HASHES'))) { return }
if (-not (Assert-PathExists $HASHCAT 'HASHCAT exe')) { return }
if (-not (Assert-PathExists $HASHES 'HASHES folder' 'Container')) { return }

# ── Resolve rules ──
$RULELIST = @(
  $tenKrules, $NSAKEYv2, $fordyv1, $pantag, $OUTD, $techtrip2, $williamsuper, $digits3, $dive
) | Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Leaf) }

if ($RULELIST.Count -eq 0) {
  Write-Err "No rule files resolved. Check ghuge rule_files/rulelists."
  return
}
Write-Info "Resolved $($RULELIST.Count) rule file(s)"

# ── Select hashlist ──
$HASHLIST = Select-Hashlist -HashesRoot $HASHES -HashType $HASHTYPE
if (-not $HASHLIST) { return }

# ── Get words from user ──
if ($global:GH_PreSelectedWordsInput) {
  $line = $global:GH_PreSelectedWordsInput
} else {
  Write-Header "Enter seed word(s)"
  Write-Dim "  Space-separated, e.g. 'acme contoso globex'"
  $line = Read-HostEsc '  Words: '
}
if ($null -eq $line) { return }

$words = @()
if ($line) {
  $words = @(( $line -split '\s+' ) | Where-Object { $_ -and $_.Trim().Length -gt 0 })
}
if (-not $words -or $words.Count -eq 0) {
  Write-Err "No words provided; aborting."
  return
}

Write-Success "Using $($words.Count) word(s): $($words -join ', ')"

# ── Write temp wordlist ──
$tmp = [System.IO.Path]::GetTempFileName()
try {
  Set-Content -LiteralPath $tmp -Value $words -Encoding UTF8
} catch {
  Write-Err "Failed to write temp file: $($_.Exception.Message)"
  return
}

# ── Build commands ──
$argsBase = Build-BaseArgs -Kernel $KERNEL -Hwmon $HWMON -HashType $HASHTYPE -Hashlist $HASHLIST -Wordlist $tmp

$Planned = @()
foreach ($rule in $RULELIST) {
  $cmdArgs = @()
  $cmdArgs += $argsBase
  $cmdArgs += '-r'
  $cmdArgs += $rule
  Add-If -arr ([ref]$cmdArgs) $LOOPBACK
  $cmdArgs = $cmdArgs | Where-Object { $_ -ne $null -and $_ -ne '' }
  $Planned += [pscustomobject]@{ Args = $cmdArgs }
}

if ($Planned.Count -eq 0) {
  Write-Err "No planned commands."
  Remove-Item -LiteralPath $tmp -ErrorAction SilentlyContinue
  return
}

# ── Execute ──
Invoke-PlannedCommands -Planned $Planned -HashcatExe $HASHCAT -Description 'word-based rule commands'

Remove-Item -LiteralPath $tmp -ErrorAction SilentlyContinue

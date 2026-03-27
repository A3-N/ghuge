<# word-based bruteforces #>

# ── Validation ──
if (-not (Assert-RequiredVars @('HASHCAT','HASHTYPE','HASHES'))) { return }
if (-not (Assert-PathExists $HASHCAT 'HASHCAT exe')) { return }
if (-not (Assert-PathExists $HASHES 'HASHES folder' 'Container')) { return }

# ── Select hashlist ──
$HASHLIST = Select-Hashlist -HashesRoot $HASHES -HashType $HASHTYPE
if (-not $HASHLIST) { return }

# ── Get words from user ──
Write-Header "Enter seed word(s)"
Write-Dim "  Space-separated, e.g. 'acme contoso'"
$line = Read-HostEsc '  Words: '
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

# ── Build base args (no wordlist yet — hybrid modes need specific ordering) ──
$argsBase = Build-BaseArgs -Kernel $KERNEL -Hwmon $HWMON -HashType $HASHTYPE -Hashlist $HASHLIST

$Planned = @()

# 1) -a6 wordlist '?d?d?d?d?d?d?d?d' -i  (append digits)
$cmd = @(); $cmd += $argsBase; $cmd += $tmp; $cmd += '-a6'; $cmd += '?d?d?d?d?d?d?d?d'; $cmd += '-i'
$Planned += [pscustomobject]@{ Args = ($cmd | Where-Object { $_ -ne $null -and $_ -ne '' }) }

# 2) -a6 wordlist '?l?l?l?l?l?l' -i  (append lowercase)
$cmd = @(); $cmd += $argsBase; $cmd += $tmp; $cmd += '-a6'; $cmd += '?l?l?l?l?l?l'; $cmd += '-i'
$Planned += [pscustomobject]@{ Args = ($cmd | Where-Object { $_ -ne $null -and $_ -ne '' }) }

# 3) -a7 '?d?d?d?d?d?d?d?d' wordlist -i  (prepend digits)
$cmd = @(); $cmd += $argsBase; $cmd += '-a7'; $cmd += '?d?d?d?d?d?d?d?d'; $cmd += $tmp; $cmd += '-i'
$Planned += [pscustomobject]@{ Args = ($cmd | Where-Object { $_ -ne $null -and $_ -ne '' }) }

# 4) -a7 '?l?l?l?l?l?l' wordlist -i  (prepend lowercase)
$cmd = @(); $cmd += $argsBase; $cmd += '-a7'; $cmd += '?l?l?l?l?l?l'; $cmd += $tmp; $cmd += '-i'
$Planned += [pscustomobject]@{ Args = ($cmd | Where-Object { $_ -ne $null -and $_ -ne '' }) }

# 5) -a6 wordlist '?a?a?a?a?a' -i  (append any)
$cmd = @(); $cmd += $argsBase; $cmd += '-a6'; $cmd += $tmp; $cmd += '?a?a?a?a?a'; $cmd += '-i'
$Planned += [pscustomobject]@{ Args = ($cmd | Where-Object { $_ -ne $null -and $_ -ne '' }) }

# 6) -a7 '?a?a?a?a?a' wordlist -i  (prepend any)
$cmd = @(); $cmd += $argsBase; $cmd += '-a7'; $cmd += '?a?a?a?a?a'; $cmd += $tmp; $cmd += '-i'
$Planned += [pscustomobject]@{ Args = ($cmd | Where-Object { $_ -ne $null -and $_ -ne '' }) }

# ── Execute ──
Invoke-PlannedCommands -Planned $Planned -HashcatExe $HASHCAT -Description 'word-based hybrid commands'

Remove-Item -LiteralPath $tmp -ErrorAction SilentlyContinue

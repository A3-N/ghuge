<# word-based bruteforces #>

$required = @('HASHCAT','HASHTYPE','HASHES')
foreach ($v in $required) {
  $gv = Get-Variable -Name $v -Scope Script -ErrorAction SilentlyContinue
  if (-not $gv) { Write-Error "$v not found. Make sure ghuge exported variables into the script scope."; return }
  if ([string]::IsNullOrWhiteSpace([string]$gv.Value)) { Write-Error "$v is empty. Check ghuge settings."; return }
}
if (-not (Test-Path -LiteralPath $HASHCAT -PathType Leaf)) { Write-Error "HASHCAT exe not found at: $HASHCAT"; return }
if (-not (Test-Path -LiteralPath $HASHES -PathType Container)) { Write-Error "HASHES folder missing: $HASHES"; return }

$modeFolder = Join-Path -Path $HASHES -ChildPath ([string]$HASHTYPE)
if (-not (Test-Path -LiteralPath $modeFolder -PathType Container)) {
  Write-Error "No folder for mode ${HASHTYPE} under ${HASHES}"
  return
}
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

$line = Read-Host "Enter word(s), space-separated (e.g. 'acme contoso')"
$words = @()
if ($line) {
  $words = @(( $line -split '\s+' ) | Where-Object { $_ -and $_.Trim().Length -gt 0 })
}
if (-not $words -or $words.Count -eq 0) {
  Write-Error "No words provided; aborting."
  return
}

$tmp = [System.IO.Path]::GetTempFileName()
try {
  Set-Content -LiteralPath $tmp -Value $words -Encoding UTF8
} catch {
  Write-Error "Failed to write temp file: $($_.Exception.Message)"
  return
}

function Add-If([ref]$arr, [string]$item) { if ($null -ne $item -and $item.Trim() -ne '') { $arr.Value += ,$item } }

$argsBase = @()
Add-If -arr ([ref]$argsBase) $KERNEL
if ($KERNEL -and $KERNEL.Trim() -ne '') { $argsBase += '--bitmap-max=24' }
Add-If -arr ([ref]$argsBase) $HWMON
Add-If -arr ([ref]$argsBase) ("-m$HASHTYPE")
Add-If -arr ([ref]$argsBase) $HASHLIST

$Planned = @()

# 1) -a6 wordlist '?d?d?d?d?d?d?d?d' -i
$cmd1 = @()
$cmd1 += $argsBase
$cmd1 += $tmp
$cmd1 += '-a6'
$cmd1 += '?d?d?d?d?d?d?d?d'
$cmd1 += '-i'
$Planned += [pscustomobject]@{ Args = ($cmd1 | Where-Object { $_ -ne $null -and $_ -ne '' }); Pretty = "$HASHCAT " + (($cmd1 | Where-Object { $_ -ne $null -and $_ -ne '' }) -join ' ') }

# 2) -a6 wordlist '?l?l?l?l?l?l' -i
$cmd2 = @()
$cmd2 += $argsBase
$cmd2 += $tmp
$cmd2 += '-a6'
$cmd2 += '?l?l?l?l?l?l'
$cmd2 += '-i'
$Planned += [pscustomobject]@{ Args = ($cmd2 | Where-Object { $_ -ne $null -and $_ -ne '' }); Pretty = "$HASHCAT " + (($cmd2 | Where-Object { $_ -ne $null -and $_ -ne '' }) -join ' ') }

# 3) -a7 '?d?d?d?d?d?d?d?d' $tmp -i
$cmd3 = @()
$cmd3 += $argsBase
$cmd3 += '-a7'
$cmd3 += '?d?d?d?d?d?d?d?d'
$cmd3 += $tmp
$cmd3 += '-i'
$Planned += [pscustomobject]@{ Args = ($cmd3 | Where-Object { $_ -ne $null -and $_ -ne '' }); Pretty = "$HASHCAT " + (($cmd3 | Where-Object { $_ -ne $null -and $_ -ne '' }) -join ' ') }

# 4) -a7 '?l?l?l?l?l?l' $tmp -i
$cmd4 = @()
$cmd4 += $argsBase
$cmd4 += '-a7'
$cmd4 += '?l?l?l?l?l?l'
$cmd4 += $tmp
$cmd4 += '-i'
$Planned += [pscustomobject]@{ Args = ($cmd4 | Where-Object { $_ -ne $null -and $_ -ne '' }); Pretty = "$HASHCAT " + (($cmd4 | Where-Object { $_ -ne $null -and $_ -ne '' }) -join ' ') }

# 5) -a6 $tmp '?a?a?a?a?a' -i
$cmd5 = @()
$cmd5 += $argsBase
$cmd5 += '-a6'
$cmd5 += $tmp
$cmd5 += '?a?a?a?a?a'
$cmd5 += '-i'
$Planned += [pscustomobject]@{ Args = ($cmd5 | Where-Object { $_ -ne $null -and $_ -ne '' }); Pretty = "$HASHCAT " + (($cmd5 | Where-Object { $_ -ne $null -and $_ -ne '' }) -join ' ') }

# 6) -a7 '?a?a?a?a?a' $tmp -i
$cmd6 = @()
$cmd6 += $argsBase
$cmd6 += '-a7'
$cmd6 += '?a?a?a?a?a'
$cmd6 += $tmp
$cmd6 += '-i'
$Planned += [pscustomobject]@{ Args = ($cmd6 | Where-Object { $_ -ne $null -and $_ -ne '' }); Pretty = "$HASHCAT " + (($cmd6 | Where-Object { $_ -ne $null -and $_ -ne '' }) -join ' ') }

Clear-Host
Write-Host "Words: $($words -join ', ')"
Write-Host "=== Preview: $($Planned.Count) hashcat commands to run ==="
for ($i = 0; $i -lt $Planned.Count; $i++) {
  Write-Host ("[{0}] {1}" -f ($i+1), $Planned[$i].Pretty)
}
Write-Host ""
$ans = Read-Host "Press ENTER to start execution, or type 'n' to cancel"
if ($ans -and $ans.Trim().ToLower() -eq 'n') {
  Write-Host "Cancelled by user."
  Remove-Item -LiteralPath $tmp -ErrorAction SilentlyContinue
  return
}

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

Remove-Item -LiteralPath $tmp -ErrorAction SilentlyContinue
Write-Host "`nWord processing done`n"

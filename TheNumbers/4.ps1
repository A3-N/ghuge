<# word-based rule passes #>

$required = @('HASHCAT','HASHTYPE','HASHES')
foreach ($v in $required) {
  $gv = Get-Variable -Name $v -Scope Script -ErrorAction SilentlyContinue
  if (-not $gv) { Write-Error "$v not found. Make sure ghuge exported variables into the script scope."; return }
  if ([string]::IsNullOrWhiteSpace([string]$gv.Value)) { Write-Error "$v is empty. Check ghuge settings."; return }
}
if (-not (Test-Path -LiteralPath $HASHCAT -PathType Leaf)) { Write-Error "HASHCAT exe not found at: $HASHCAT"; return }
if (-not (Test-Path -LiteralPath $HASHES -PathType Container)) { Write-Error "HASHES folder missing: $HASHES"; return }

$RULELIST = @(
  $tenKrules, $NSAKEYv2, $fordyv1, $pantag, $OUTD, $techtrip2, $williamsuper, $digits3, $dive
) | Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Leaf) }
if ($RULELIST.Count -eq 0) { Write-Error "No rule files resolved. Check ghuge rule_files/rulelists."; return }

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

$line = Read-Host "Enter word(s), space-separated (e.g. 'acme contoso globex')"

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
Add-If -arr ([ref]$argsBase) $tmp

$HashcatDir = Split-Path -Parent $HASHCAT

$Planned = @()
foreach ($rule in $RULELIST) {
  $args = @()
  $args += $argsBase
  $args += '-r'
  $args += $rule
  Add-If -arr ([ref]$args) $LOOPBACK   # loopback only when using -r
  $args = $args | Where-Object { $_ -ne $null -and $_ -ne '' }
  $Planned += [pscustomobject]@{ Args = $args; Pretty = "$HASHCAT " + ($args -join ' ') }
}

if ($Planned.Count -eq 0) {
  Write-Error "No planned commands."
  Remove-Item -LiteralPath $tmp -ErrorAction SilentlyContinue
  return
}

Clear-Host
Write-Host "Words: $($words -join ', ')"
Write-Host "=== Preview: $($Planned.Count) hashcat commands to run ==="
for ($i = 0; $i -lt $Planned.Count; $i++) { Write-Host ("[{0}] {1}" -f ($i+1), $Planned[$i].Pretty) }
Write-Host ""
$ans = Read-Host "Press ENTER to start execution, or type 'n' to cancel"
if ($ans -and $ans.Trim().ToLower() -eq 'n') {
  Write-Host "Cancelled by user."
  Remove-Item -LiteralPath $tmp -ErrorAction SilentlyContinue
  return
}

Write-Host ""
Write-Host ("Running {0} commands against: {1}" -f $Planned.Count, $HASHLIST)
for ($i = 0; $i -lt $Planned.Count; $i++) {
  $item = $Planned[$i]
  Write-Host ""
  Write-Host ("--- Command {0}/{1} ---" -f ($i+1), $Planned.Count)
  Write-Host ("Command: {0}" -f $item.Pretty)
  try { Push-Location $HashcatDir; & $HASHCAT @($item.Args) } catch { Write-Host "Execution failed: $($_.Exception.Message)" } finally { Pop-Location }
}

Remove-Item -LiteralPath $tmp -ErrorAction SilentlyContinue
Write-Host "`nWord processing done`n"

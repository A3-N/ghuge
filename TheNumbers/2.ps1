<# light rules #>

$required = @('HASHCAT','HASHTYPE','HASHES','WORDLISTS')
foreach ($v in $required) {
  $gv = Get-Variable -Name $v -Scope Script -ErrorAction SilentlyContinue
  if (-not $gv) {
    Write-Error "$v not found. Make sure ghuge exported variables into the script scope."
    return
  }
  $val = [string]$gv.Value
  if ([string]::IsNullOrWhiteSpace($val)) {
    Write-Error "$v is empty. Check ghuge settings."
    return
  }
}
if (-not (Test-Path -LiteralPath $HASHCAT -PathType Leaf)) { Write-Error "HASHCAT exe not found at: $HASHCAT"; return }
if (-not (Test-Path -LiteralPath $HASHES -PathType Container)) { Write-Error "HASHES root not found: $HASHES"; return }
if (-not (Test-Path -LiteralPath $WORDLISTS -PathType Container)) { Write-Error "WORDLISTS root not found: $WORDLISTS"; return }

$RULELIST = @(
  $rule3, $rockyou30000, $ORTRTS, $fbtop, $TOXICSP, $passwordpro,
  $d3ad0ne, $d3adhob0, $generated2, $toprules2020, $digits1, $digits2,
  $hob064, $leetspeak, $toggles1, $toggles2
)

$RULELIST = $RULELIST | Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Leaf) }

if ($RULELIST.Count -eq 0) {
  Write-Error "No rule files found from exported rule vars. Check rule_files + rulelists in ghuge settings."
  return
}

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

$wlFiles = Get-ChildItem -LiteralPath $WORDLISTS -File -Recurse -ErrorAction SilentlyContinue | Sort-Object FullName
if ($wlFiles.Count -eq 0) { Write-Error "No wordlists found under ${WORDLISTS}"; return }

Write-Host "Select a wordlist under ${WORDLISTS}:"
$rootResolved = (Resolve-Path -LiteralPath $WORDLISTS).Path.TrimEnd([IO.Path]::DirectorySeparatorChar)
for ($i=0; $i -lt $wlFiles.Count; $i++) {
  $rel = $wlFiles[$i].FullName
  if ($rel.StartsWith($rootResolved)) {
    $rel = $rel.Substring($rootResolved.Length).TrimStart([IO.Path]::DirectorySeparatorChar)
  }
  Write-Host ("  [{0}] {1}" -f ($i+1), $rel)
}
[int]$wi=0
while ($wi -lt 1 -or $wi -gt $wlFiles.Count) {
  $raw = Read-Host ("Enter number (1..{0})" -f $wlFiles.Count)
  [int]::TryParse($raw, [ref]$wi) | Out-Null
}
$WORDLIST = $wlFiles[$wi-1].FullName
Write-Host "Selected wordlist: $WORDLIST"

function Add-If([ref]$arr, [string]$item) {
  if ($null -ne $item -and $item.Trim() -ne '') { $arr.Value += ,$item }
}
$argsBase = @()
Add-If -arr ([ref]$argsBase) $KERNEL
if ($KERNEL -and $KERNEL.Trim() -ne '') { $argsBase += '--bitmap-max=24' }
Add-If -arr ([ref]$argsBase) $HWMON
$argsBase += "-m$HASHTYPE"
$argsBase += $HASHLIST
$argsBase += $WORDLIST

$HashcatDir = Split-Path -Parent $HASHCAT

$Planned = @()

$baseArgs = $argsBase | Where-Object { $_ -ne $null -and $_ -ne '' }
$Planned += [pscustomobject]@{ Args = $baseArgs; Pretty = "$HASHCAT " + ($baseArgs -join ' ') }

foreach ($rule in $RULELIST) {
  if (-not (Test-Path -LiteralPath $rule -PathType Leaf)) { continue }
  $args = @()
  $args += $argsBase
  Add-If -arr ([ref]$args) $LOOPBACK
  $args += '-r'
  $args += $rule
  $args = $args | Where-Object { $_ -ne $null -and $_ -ne '' }
  $Planned += [pscustomobject]@{ Args = $args; Pretty = "$HASHCAT " + ($args -join ' ') }
}

Clear-Host
Write-Host "=== Preview: $($Planned.Count) hashcat commands to run ==="
for ($i = 0; $i -lt $Planned.Count; $i++) {
  $n = $i + 1
  Write-Host ("[{0}] {1}" -f $n, $Planned[$i].Pretty)
}
Write-Host ""
$ans = Read-Host "Press ENTER to start execution, or type 'n' to cancel"
if ($ans -and $ans.Trim().ToLower() -eq 'n') {
  Write-Host "Cancelled by user."
  return
}

Write-Host ""
Write-Host ("Running {0} commands against: {1}" -f $Planned.Count, $HASHLIST)

for ($i = 0; $i -lt $Planned.Count; $i++) {
  $item = $Planned[$i]
  $args = $item.Args

  Write-Host ""
  Write-Host ("--- Command {0}/{1} ---" -f ($i+1), $Planned.Count)
  Write-Host ("Command: {0}" -f $item.Pretty)

  try {
    Push-Location $HashcatDir
    & $HASHCAT @args
  } catch {
    Write-Host "Execution failed: $($_.Exception.Message)"
  } finally {
    Pop-Location
  }
}

Write-Host "All commands complete."

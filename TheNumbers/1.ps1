<# bruteforce hash #>

if (-not $HASHCAT -or [string]::IsNullOrWhiteSpace($HASHCAT)) {
  Write-Error "HASHCAT not set. Set in ghuge settings before running."
  return
}
if (-not (Test-Path -LiteralPath $HASHCAT -PathType Leaf)) {
  Write-Error "HASHCAT executable not found at: $HASHCAT"
  return
}
if (-not $HASHTYPE) {
  Write-Error "HASHTYPE not set"
  return
}
if (-not $HASHES) {
  Write-Error "HASHES root not set"
  return
}

$modeFolder = Join-Path -Path $HASHES -ChildPath ([string]$HASHTYPE)
if (-not (Test-Path -LiteralPath $modeFolder -PathType Container)) {
  Write-Error "No folder for mode ${HASHTYPE} under ${HASHES}"
  return
}

$files = Get-ChildItem -LiteralPath $modeFolder -File | Sort-Object Name
if (-not $files -or $files.Count -eq 0) {
  Write-Error "No hashlists found in ${modeFolder}"
  return
}

Write-Host "Select a hashlist for mode ${HASHTYPE}:"
for ($i = 0; $i -lt $files.Count; $i++) {
  Write-Host ("  [{0}] {1}" -f ($i+1), $files[$i].Name)
}
[int]$choice = 0
while ($choice -lt 1 -or $choice -gt $files.Count) {
  $raw = Read-Host ("Enter number (1..{0})" -f $files.Count)
  if (-not [int]::TryParse($raw, [ref]$choice)) { $choice = 0 }
}
$HASHLIST = $files[$choice-1].FullName
Write-Host "Selected: $HASHLIST"

function Unquote([object]$s) {
  if ($null -eq $s) { return $null }
  $t = [string]$s

  if ($t.Length -ge 2) {
    $hasSingle = ($t.StartsWith("'") -and $t.EndsWith("'"))
    $hasDouble = ($t.StartsWith('"') -and $t.EndsWith('"'))
    if ($hasSingle -or $hasDouble) {
      $inner = $t.Length - 2
      if ($inner -gt 0) {
        $t = $t.Substring(1, $inner)
      }
    }
  }

  $t = $t -replace '``','`'
  $t = $t -replace '`"','"'
  $t = $t -replace "`'", "'"
  return $t
}

function Pattern-To-Args($pattern) {
  $out = @()
  if ($pattern -is [array]) {
    for ($i = 0; $i -lt $pattern.Count; $i++) {
      $token = [string]$pattern[$i]
      if ($token -like '-*') {
        if ($i+1 -lt $pattern.Count) {
          $class = Unquote ([string]$pattern[$i+1])
          $out += $token
          $out += $class
          $i++
        } else {
          $out += $token
        }
      } else {
        $out += (Unquote $token)
      }
    }
  } else {
    $out += (Unquote ([string]$pattern))
  }
  return $out
}

function Add-If([ref]$arr, [string]$item) {
  if ($null -ne $item -and $item.Trim() -ne '') { $arr.Value += ,$item }
}

$argsBase = @()
Add-If -arr ([ref]$argsBase) $KERNEL
if ($KERNEL -and $KERNEL.Trim() -ne '') { $argsBase += '--bitmap-max=24' }
Add-If -arr ([ref]$argsBase) $HWMON
$modeToken = "-m${HASHTYPE}"

# Masks
$masks = @(
  "?a?a?a?a?a",
  "?l?l?l?l?l?l?l?l",
  "?u?u?u?u?u?u?u?u",
  "?d?d?d?d?d?d?d?d?d?d",
  @("-1","?l?d?u","?1?1?1?1?1?1?d?d"),
  @("-1","?l?u","-2","?d","?1?1?1?1?2?2?2?2?a"),
  @("-1","?d","-2","?l?u","?1?1?1?1?2?2?2?2"),
  "?l?l?l?l?l?d?d?d?d",
  "?u?u?u?u?u?d?d?d?d",
  "?l?l?l?l?l?l?d?d?d",
  "?u?u?u?u?u?u?d?d?d",
  "?d?d?d?d?d?l?l?l?l",
  "?d?d?d?d?d?u?u?u?u",
  "?l?l?d?d?d?d?d?d?d",
  "?u?u?d?d?d?d?d?d?d",
  "?l?l?d?d?d?d?l?l",
  "?u?u?d?d?d?d?u?u",
  "?l?d?d?l?d?d?l?d?d",
  "?u?d?d?u?d?d?u?d?d",
  "?d?d?d?d?d?d?d?d?l?l",
  "?d?d?d?d?d?d?d?d?u?u",
  "?d?d?l?d?d?l?d?d?l",
  "?d?d?u?d?d?u?d?d?u"
)

$HashcatDir = Split-Path -Parent $HASHCAT

$Planned = @()
for ($i = 0; $i -lt $masks.Count; $i++) {
  $maskArgs = Pattern-To-Args $masks[$i]

  $args = @()
  $args += $argsBase
  $args += $modeToken
  $args += $HASHLIST
  $args += '-a3'
  $args += $maskArgs
  $args += '--increment'

  $args = $args | Where-Object { $_ -ne $null -and $_ -ne '' }

  $pretty = "$HASHCAT " + ($args -join ' ')
  $Planned += [pscustomobject]@{ Args = $args; Pretty = $pretty }
}

Clear-Host
Write-Host "=== Preview: $(($Planned.Count)) hashcat commands to run ==="
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
Write-Host ("Running {0} mask commands against: {1}" -f $Planned.Count, $HASHLIST)

for ($i = 0; $i -lt $Planned.Count; $i++) {
  $item = $Planned[$i]
  $args = $item.Args

  Write-Host ""
  Write-Host ("--- Running mask {0}/{1} ---" -f ($i+1), $Planned.Count)
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

Write-Host "All mask commands done."

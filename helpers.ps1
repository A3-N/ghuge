<#
  helpers.ps1 — shared functions for ghuge + TheNumbers scripts
  Dot-source from ghuge.ps1:   . (Join-Path $ScriptDir 'helpers.ps1')
#>

# ── ANSI colour helpers ──────────────────────────────────────────────
$script:ESC = [char]27

function Write-C {
  <# Write coloured text. -NoNewline supported. #>
  param(
    [Parameter(Position=0)] [string]$Text,
    [string]$Fg   = '',
    [string]$Bg   = '',
    [switch]$Bold,
    [switch]$Dim,
    [switch]$NoNewline
  )
  $codes = @()
  if ($Bold) { $codes += '1' }
  if ($Dim)  { $codes += '2' }

  $fgMap = @{
    black='30'; red='31'; green='32'; yellow='33'; blue='34';
    magenta='35'; cyan='36'; white='37';
    brightblack='90'; brightred='91'; brightgreen='92'; brightyellow='93';
    brightblue='94'; brightmagenta='95'; brightcyan='96'; brightwhite='97'
  }
  $bgMap = @{
    black='40'; red='41'; green='42'; yellow='43'; blue='44';
    magenta='45'; cyan='46'; white='47'
  }

  if ($Fg -and $fgMap.ContainsKey($Fg.ToLower()))  { $codes += $fgMap[$Fg.ToLower()] }
  if ($Bg -and $bgMap.ContainsKey($Bg.ToLower()))  { $codes += $bgMap[$Bg.ToLower()] }

  if ($codes.Count -gt 0) {
    $seq = "$($script:ESC)[$($codes -join ';')m"
    $rst = "$($script:ESC)[0m"
    if ($NoNewline) { Write-Host "${seq}${Text}${rst}" -NoNewline }
    else            { Write-Host "${seq}${Text}${rst}" }
  } else {
    if ($NoNewline) { Write-Host $Text -NoNewline }
    else            { Write-Host $Text }
  }
}

function Write-Header  { param([string]$Text) Write-C $Text -Fg cyan    -Bold }
function Write-Success { param([string]$Text) Write-C $Text -Fg green   -Bold }
function Write-Warn    { param([string]$Text) Write-C $Text -Fg yellow  -Bold }
function Write-Err     { param([string]$Text) Write-C $Text -Fg red     -Bold }
function Write-Dim     { param([string]$Text) Write-C $Text -Fg brightblack }
function Write-Info    { param([string]$Text) Write-C $Text -Fg white }
function Write-Accent  { param([string]$Text) Write-C $Text -Fg magenta -Bold }

function Write-Separator {
  $w = [math]::Max(20, [Console]::WindowWidth - 1)
  Write-C ('─' * $w) -Fg brightblack
}

function Write-Banner {
  param([string]$Title)
  $w = [math]::Max(20, [Console]::WindowWidth - 1)
  Write-Host ''
  Write-C ('═' * $w) -Fg cyan
  $pad = [math]::Max(0, [math]::Floor(($w - $Title.Length) / 2))
  Write-C (' ' * $pad + $Title) -Fg brightcyan -Bold
  Write-C ('═' * $w) -Fg cyan
}

# ── Pretty command preview ──────────────────────────────────────────
function Write-CommandPreview {
  param([string]$Exe, [string[]]$CmdArgs, [int]$Index, [int]$Total)
  Write-C "[${Index}/${Total}] " -Fg brightyellow -Bold -NoNewline
  Write-C "$Exe " -Fg cyan -NoNewline
  foreach ($a in $CmdArgs) {
    if ($a -like '-*' -or $a -like '--*') {
      Write-C "$a " -Fg yellow -NoNewline
    } elseif ($a -match '\\.' -and (Test-Path -LiteralPath $a -PathType Leaf -ErrorAction SilentlyContinue)) {
      Write-C "$a " -Fg green -NoNewline
    } else {
      Write-C "$a " -Fg white -NoNewline
    }
  }
  Write-Host ''
}

function Write-RunningBanner {
  param([int]$Index, [int]$Total)
  Write-Host ''
  Write-C "─── Running " -Fg brightblack -NoNewline
  Write-C "${Index}/${Total}" -Fg brightyellow -Bold -NoNewline
  Write-C " ───" -Fg brightblack
}

# ── Shared utilities ────────────────────────────────────────────────

function Add-If([ref]$arr, [string]$item) {
  if ($null -ne $item -and $item.Trim() -ne '') { $arr.Value += ,$item }
}

function Read-HostEsc {
  <# Read-Host replacement: returns $null on Escape, typed string on Enter. #>
  param([string]$Prompt = '')
  if ($Prompt) { Write-Host $Prompt -NoNewline }
  $buf = ''
  while ($true) {
    $key = [Console]::ReadKey($true)
    switch ($key.Key) {
      'Escape'    { Write-Host ''; return $null }
      'Enter'     { Write-Host ''; return $buf }
      'Backspace' {
        if ($buf.Length -gt 0) {
          $buf = $buf.Substring(0, $buf.Length - 1)
          Write-Host "`b `b" -NoNewline
        }
      }
      default {
        $ch = $key.KeyChar
        if ($ch -and [int]$ch -ge 32) {
          $buf += $ch
          Write-Host $ch -NoNewline
        }
      }
    }
  }
}

function Unquote([object]$s) {
  if ($null -eq $s) { return $null }
  $t = [string]$s
  if ($t.Length -ge 2) {
    $hasSingle = ($t.StartsWith("'") -and $t.EndsWith("'"))
    $hasDouble = ($t.StartsWith('"') -and $t.EndsWith('"'))
    if ($hasSingle -or $hasDouble) {
      $inner = $t.Length - 2
      if ($inner -gt 0) { $t = $t.Substring(1, $inner) }
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
        } else { $out += $token }
      } else { $out += (Unquote $token) }
    }
  } else { $out += (Unquote ([string]$pattern)) }
  return $out
}

# ── Reusable pickers ────────────────────────────────────────────────

function Select-Hashlist {
  <# Interactive hashlist picker. Returns full path or $null. #>
  param([string]$HashesRoot, [string]$HashType)
  
  if ($global:GH_PreSelectedHashlists -and $global:GH_PreSelectedHashlists.ContainsKey([string]$HashType)) {
    return $global:GH_PreSelectedHashlists[[string]$HashType]
  }

  $modeFolder = Join-Path -Path $HashesRoot -ChildPath ([string]$HashType)
  if (-not (Test-Path -LiteralPath $modeFolder -PathType Container)) {
    Write-Err "No folder for mode ${HashType} under ${HashesRoot}"
    Write-Dim "  Expected: $modeFolder"
    Write-Dim "  Tip: use 'search <name>' to find the correct hashmode"
    return $null
  }

  $files = Get-ChildItem -LiteralPath $modeFolder -File | Sort-Object Name
  if (-not $files -or $files.Count -eq 0) {
    Write-Err "No hashlists found in ${modeFolder}"
    return $null
  }

  Write-Header "Select hashlist(s) for mode ${HashType} (e.g. 1, 3 or A):"
  for ($i = 0; $i -lt $files.Count; $i++) {
    Write-C "  [" -Fg brightblack -NoNewline
    Write-C "$($i+1)" -Fg brightyellow -Bold -NoNewline
    Write-C "] " -Fg brightblack -NoNewline
    Write-C $files[$i].Name -Fg white
  }
  Write-Dim "  (Esc to go back)"
  while ($true) {
    $raw = Read-HostEsc ("Enter selection(s) (1..{0}): " -f $files.Count)
    if ($null -eq $raw) { return $null }
    
    $tokens = @()
    if ($raw -match '^(a|A|all|All)$') {
      $tokens = @(1..$files.Count)
    } else {
      $tokens = @($raw -split '[,;\s]+' | Where-Object { $_ -match '^\d+$' } | Sort-Object -Unique { [int]$_ })
    }

    $validTokens = @($tokens | Where-Object { [int]$_ -ge 1 -and [int]$_ -le $files.Count })
    if ($validTokens.Count -eq 0) {
      Write-Warn "Invalid selection, try again."
      continue
    }

    if ($validTokens.Count -eq 1) {
      $selected = $files[[int]$validTokens[0] - 1].FullName
      Write-Success "Selected: $selected"
      return $selected
    } else {
      $timestamp = Get-Date -Format "HHmmss"
      $combinedPath = Join-Path $HashesRoot "Combined_1_Auto_$timestamp.txt"
      $allLines = @()
      foreach ($t in $validTokens) {
        $f = $files[[int]$t - 1]
        $content = Get-Content -LiteralPath $f.FullName -ErrorAction SilentlyContinue
        if ($content) { $allLines += $content }
      }
      $allLines = $allLines | Where-Object { $_.Trim() -ne '' } | Sort-Object -Unique
      $allLines | Out-File -FilePath $combinedPath -Encoding UTF8
      $leaf = Split-Path $combinedPath -Leaf
      Write-Success "Combined $($validTokens.Count) hashlists ($($allLines.Count) unique lines) -> $leaf"
      return $combinedPath
    }
  }
}

function Select-Wordlist {
  <# Interactive wordlist picker. Returns full path or $null. #>
  param([string]$WordlistsRoot)

  if ($global:GH_PreSelectedWordlist) {
    return $global:GH_PreSelectedWordlist
  }

  if (-not (Test-Path -LiteralPath $WordlistsRoot -PathType Container)) {
    Write-Err "WORDLISTS root not found: $WordlistsRoot"
    return $null
  }

  $wlFiles = Get-ChildItem -LiteralPath $WordlistsRoot -File -Recurse -ErrorAction SilentlyContinue | Sort-Object FullName
  if ($wlFiles.Count -eq 0) {
    Write-Err "No wordlists found under ${WordlistsRoot}"
    return $null
  }

  $rootResolved = (Resolve-Path -LiteralPath $WordlistsRoot).Path.TrimEnd([IO.Path]::DirectorySeparatorChar)
  Write-Header "Select wordlist(s) (e.g. 1, 3 or A):"
  for ($i = 0; $i -lt $wlFiles.Count; $i++) {
    $rel = $wlFiles[$i].FullName
    if ($rel.StartsWith($rootResolved)) {
      $rel = $rel.Substring($rootResolved.Length).TrimStart([IO.Path]::DirectorySeparatorChar)
    }
    Write-C "  [" -Fg brightblack -NoNewline
    Write-C "$($i+1)" -Fg brightyellow -Bold -NoNewline
    Write-C "] " -Fg brightblack -NoNewline
    Write-C $rel -Fg white
  }
  Write-Dim "  (Esc to go back)"
  while ($true) {
    $raw = Read-HostEsc ("Enter selection(s) (1..{0}): " -f $wlFiles.Count)
    if ($null -eq $raw) { return $null }
    
    $tokens = @()
    if ($raw -match '^(a|A|all|All)$') {
      $tokens = @(1..$wlFiles.Count)
    } else {
      $tokens = @($raw -split '[,;\s]+' | Where-Object { $_ -match '^\d+$' } | Sort-Object -Unique { [int]$_ })
    }

    $validTokens = @($tokens | Where-Object { [int]$_ -ge 1 -and [int]$_ -le $wlFiles.Count })
    if ($validTokens.Count -eq 0) {
      Write-Warn "Invalid selection, try again."
      continue
    }

    $selectedArr = @()
    foreach ($t in $validTokens) {
      $selectedArr += $wlFiles[[int]$t - 1].FullName
    }
    
    if ($selectedArr.Count -eq 1) {
      Write-Success "Selected: $($selectedArr[0])"
      return $selectedArr[0]
    } else {
      Write-Success "Selected $($selectedArr.Count) wordlists:"
      foreach ($s in $selectedArr) { Write-Dim "  $(Split-Path $s -Leaf)" }
      return $selectedArr
    }
  }
}

function Select-MultipleWordlists {
  <# Interactive multi-wordlist picker. Returns array of full paths. #>
  param([string]$WordlistsRoot)

  if ($global:GH_PreSelectedMultipleWordlists) {
    return $global:GH_PreSelectedMultipleWordlists
  }

  if (-not (Test-Path -LiteralPath $WordlistsRoot -PathType Container)) {
    Write-Err "WORDLISTS root not found: $WordlistsRoot"
    return @()
  }

  $wlFiles = Get-ChildItem -LiteralPath $WordlistsRoot -File -Recurse -ErrorAction SilentlyContinue | Sort-Object FullName
  if ($wlFiles.Count -eq 0) {
    Write-Err "No wordlists found under ${WordlistsRoot}"
    return @()
  }

  $rootResolved = (Resolve-Path -LiteralPath $WordlistsRoot).Path.TrimEnd([IO.Path]::DirectorySeparatorChar)
  Write-Header "Select wordlists (numbers/ranges, e.g. '1-3, 5, 8'):"
  for ($i = 0; $i -lt $wlFiles.Count; $i++) {
    $rel = $wlFiles[$i].FullName
    if ($rel.StartsWith($rootResolved)) {
      $rel = $rel.Substring($rootResolved.Length).TrimStart([IO.Path]::DirectorySeparatorChar)
    }
    Write-C "  [" -Fg brightblack -NoNewline
    Write-C "$($i+1)" -Fg brightyellow -Bold -NoNewline
    Write-C "] " -Fg brightblack -NoNewline
    Write-C $rel -Fg white
  }

  Write-Dim "  (Esc to go back)"
  while ($true) {
    $raw = Read-HostEsc ("Enter selections (1..{0}): " -f $wlFiles.Count)
    if ($null -eq $raw) { return @() }
    $selected = @()
    $invalid  = @()
    # parse tokens: splits on comma, semicolon, space
    $tokens = ($raw -replace '[\u00A0\u2000-\u200B\u202F\u205F\u3000]',' ').Trim() -split '[,;\s]+' | Where-Object { $_ -ne '' }
    foreach ($t in $tokens) {
      if ($t -match '^\d+\s*-\s*\d+$') {
        $parts = $t -split '\s*-\s*'
        $a = [int]$parts[0]; $b = [int]$parts[1]
        if ($a -gt $b) { $tmp=$a; $a=$b; $b=$tmp }
        for ($i=$a; $i -le $b; $i++) {
          if ($i -ge 1 -and $i -le $wlFiles.Count) { $selected += $i } else { $invalid += $i }
        }
      } elseif ($t -match '^\d+$') {
        $n = [int]$t
        if ($n -ge 1 -and $n -le $wlFiles.Count) { $selected += $n } else { $invalid += $n }
      } else {
        $invalid += $t
      }
    }
    if ($invalid.Count -gt 0) { Write-Warn "  Ignored invalid: $($invalid -join ', ')" }
    $selected = $selected | Sort-Object -Unique
    if ($selected.Count -gt 0) {
      $paths = @()
      foreach ($i in $selected) { $paths += $wlFiles[$i-1].FullName }
      Write-Success "Selected $($paths.Count) wordlist(s)"
      return $paths
    }
    Write-Warn "No valid selection — try again."
  }
}

# ── Validate required vars ──────────────────────────────────────────

function Assert-RequiredVars {
  param([string[]]$Names)
  foreach ($v in $Names) {
    $gv = Get-Variable -Name $v -Scope Script -ErrorAction SilentlyContinue
    if (-not $gv) {
      Write-Err "$v not found. Make sure ghuge exported variables."
      return $false
    }
    if ([string]::IsNullOrWhiteSpace([string]$gv.Value)) {
      Write-Err "$v is empty. Check ghuge settings."
      return $false
    }
  }
  return $true
}

function Assert-PathExists {
  param([string]$Path, [string]$Label, [string]$Type = 'Leaf')
  $pt = if ($Type -eq 'Leaf') { 'Leaf' } else { 'Container' }
  if (-not (Test-Path -LiteralPath $Path -PathType $pt)) {
    Write-Err "$Label not found at: $Path"
    return $false
  }
  return $true
}

# ── Build base hashcat args ─────────────────────────────────────────

function Build-BaseArgs {
  param(
    [string]$Kernel,
    [string]$Hwmon,
    [string]$HashType,
    [string]$Hashlist,
    [object]$Wordlist = ''
  )
  $cmdArgs = @()
  Add-If -arr ([ref]$cmdArgs) $Kernel
  if ($Kernel -and $Kernel.Trim() -ne '') { $cmdArgs += '--bitmap-max=24' }
  Add-If -arr ([ref]$cmdArgs) $Hwmon
  $cmdArgs += "-m$HashType"
  Add-If -arr ([ref]$cmdArgs) $Hashlist
  
  if ($Wordlist) {
    if ($Wordlist -is [array]) {
      foreach ($w in $Wordlist) { Add-If -arr ([ref]$cmdArgs) [string]$w }
    } else {
      Add-If -arr ([ref]$cmdArgs) [string]$Wordlist
    }
  }
  return $cmdArgs
}

# ── Execute planned commands ────────────────────────────────────────

function Invoke-PlannedCommands {
  param(
    [object[]]$Planned,
    [string]$HashcatExe,
    [string]$Description = 'commands'
  )

  if (Get-Variable -Name 'GH_DeferExecution' -Scope Global -ErrorAction SilentlyContinue -ValueOnly) {
    if ($null -eq $global:GH_DeferredCommands) { $global:GH_DeferredCommands = @() }
    foreach ($p in $Planned) { $global:GH_DeferredCommands += $p }
    return $true
  }

  Write-Banner "Preview: $($Planned.Count) $Description"
  for ($i = 0; $i -lt $Planned.Count; $i++) {
    Write-CommandPreview -Exe $HashcatExe -CmdArgs $Planned[$i].Args -Index ($i+1) -Total $Planned.Count
  }
  Write-Host ''
  Write-C "Press " -Fg white -NoNewline
  Write-C "ENTER" -Fg green -Bold -NoNewline
  Write-C " to start, " -Fg white -NoNewline
  Write-C "Esc" -Fg red -Bold -NoNewline
  Write-C "/" -Fg white -NoNewline
  Write-C "n" -Fg red -Bold -NoNewline
  Write-C " to cancel" -Fg white
  $ans = Read-HostEsc ' '
  if ($null -eq $ans -or ($ans -and $ans.Trim().ToLower() -eq 'n')) {
    Write-Warn "Cancelled by user."
    return $false
  }

  # Prevent $ErrorActionPreference = 'Stop' from turning hashcat stderr
  # or non-zero exits into terminating errors for the entire run section
  $prevEAP = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'

  try {
    $HashcatDir = Split-Path -Parent $HashcatExe
    Write-Host ''
    Write-Info "Running $($Planned.Count) $Description..."
    Write-Separator

    for ($i = 0; $i -lt $Planned.Count; $i++) {
      $item = $Planned[$i]
      Write-RunningBanner -Index ($i+1) -Total $Planned.Count
      Write-C "  $HashcatExe $($item.Args -join ' ')" -Fg cyan -Dim
      try {
        Push-Location $HashcatDir
        & $HashcatExe @($item.Args) | Out-Host
      } catch {
        Write-Err "Command failed: $($_.Exception.Message)"
      } finally {
        Pop-Location
      }
    }

    Write-Host ''
    Write-Success "All $($Planned.Count) $Description complete."
  } finally {
    $ErrorActionPreference = $prevEAP
  }
  return $true
}

# ═══════════════════════════════════════════════════════════════════════
#  INTERACTIVE KEYBOARD MENU
# ═══════════════════════════════════════════════════════════════════════

function Invoke-InteractiveMenu {
  <#
    Arrow-key navigable settings menu (ncurses-style).
    Items is an array of hashtables:
      @{ Label='loopback'; Type='bool';   Get={ $Settings.loopback }; Set={ param($v) $Settings.loopback = $v } }
      @{ Label='mode';     Type='int';    Get={ $Settings.mode };     Set={ param($v) $Settings.mode = $v }; Hint='e.g. 0, 1000, 22000' }
      @{ Label='hashcat';  Type='path';   Get={ $Settings.hashcat };  Set={ param($v) $Settings.hashcat = $v } }
      @{ Label='Show all'; Type='action'; Action={ Show-Params $Settings } }
  #>
  param(
    [string]$Title,
    [object[]]$Items,
    [scriptblock]$OnChange  # called after any change with no args
  )

  $cursor = 0
  $editing = $false
  $editBuffer = ''
  $message = ''       # temporary status message shown at bottom

  function Render {
    [Console]::CursorVisible = $false
    Clear-Host
    Write-Banner $Title
    Write-Host ''

    for ($i = 0; $i -lt $Items.Count; $i++) {
      $item = $Items[$i]
      $isSelected = ($i -eq $cursor)
      $label = $item.Label

      # Build the value display
      $valueStr = ''
      switch ($item.Type) {
        'bool' {
          $val = & $item.Get
          $valueStr = if ($val) { 'ON' } else { 'OFF' }
        }
        'int' {
          $val = & $item.Get
          $valueStr = [string]$val
        }
        'path' {
          $val = & $item.Get
          $valueStr = if ($val) { $val } else { '(not set)' }
        }
        'action' {
          $valueStr = ''
        }
      }

      if ($editing -and $isSelected -and $item.Type -ne 'bool' -and $item.Type -ne 'action') {
        # Editing mode — show input buffer
        $prefix = "$($script:ESC)[1;36m > $($script:ESC)[0m"
        $labelPart = "$($script:ESC)[1;97m$($label.PadRight(14))$($script:ESC)[0m"
        $inputPart = "$($script:ESC)[4;93m${editBuffer}_$($script:ESC)[0m"
        Write-Host "${prefix}${labelPart}: ${inputPart}"
      }
      elseif ($isSelected) {
        # Highlighted (inverted) row
        $indicator = "$($script:ESC)[1;33m > $($script:ESC)[0m"
        $labelPart = "$($script:ESC)[1;97m$($label.PadRight(14))$($script:ESC)[0m"
        switch ($item.Type) {
          'bool' {
            $color = if ($valueStr -eq 'ON') { '1;32' } else { '2;37' }
            $valPart = "$($script:ESC)[${color}m${valueStr}$($script:ESC)[0m"
            Write-Host "${indicator}${labelPart}: ${valPart}  $($script:ESC)[2;37m(Enter to toggle)$($script:ESC)[0m"
          }
          'action' {
            Write-Host "${indicator}${labelPart}  $($script:ESC)[2;37m(Enter to run)$($script:ESC)[0m"
          }
          default {
            $valColor = if ($valueStr -eq '(not set)') { '2;37' } else { '36' }
            $valPart = "$($script:ESC)[${valColor}m${valueStr}$($script:ESC)[0m"
            $hint = if ($item.Hint) { "  $($script:ESC)[2;37m($($item.Hint))$($script:ESC)[0m" } else { "  $($script:ESC)[2;37m(Enter to edit)$($script:ESC)[0m" }
            Write-Host "${indicator}${labelPart}: ${valPart}${hint}"
          }
        }
      }
      else {
        # Normal row
        $indicator = "$($script:ESC)[2;37m   $($script:ESC)[0m"
        $labelPart = "$($script:ESC)[37m$($label.PadRight(14))$($script:ESC)[0m"
        switch ($item.Type) {
          'bool' {
            $color = if ($valueStr -eq 'ON') { '32' } else { '2;37' }
            $valPart = "$($script:ESC)[${color}m${valueStr}$($script:ESC)[0m"
            Write-Host "${indicator}${labelPart}: ${valPart}"
          }
          'action' {
            Write-Host "${indicator}${labelPart}"
          }
          default {
            $valColor = if ($valueStr -eq '(not set)') { '2;37' } else { '36' }
            $valPart = "$($script:ESC)[${valColor}m${valueStr}$($script:ESC)[0m"
            Write-Host "${indicator}${labelPart}: ${valPart}"
          }
        }
      }
    }

    Write-Host ''
    Write-Separator
    Write-Dim "  ↑↓ Navigate   Enter Select/Edit   Esc Exit"
    if ($message) {
      Write-Host ''
      Write-Success "  $message"
    }
  }

  Render

  while ($true) {
    $key = [Console]::ReadKey($true)

    if ($editing) {
      # In edit mode for text/int fields
      $item = $Items[$cursor]
      switch ($key.Key) {
        'Escape' {
          $editing = $false
          $editBuffer = ''
          $message = ''
          Render
        }
        'Enter' {
          $editing = $false
          $newVal = $editBuffer.Trim()
          $editBuffer = ''

          if ($item.Type -eq 'int') {
            if ($newVal -match '^\d+$') {
              & $item.Set ([int]$newVal)
              $message = "Set $($item.Label) -> $newVal"
              if ($OnChange) { & $OnChange }
            }
            elseif ($newVal -match '^\d+[,;\s]') {
              # Comma/space separated integers — multi-value
              $nums = @($newVal -split '[,;\s]+' | Where-Object { $_ -match '^\d+$' } | ForEach-Object { [int]$_ } | Sort-Object -Unique)
              if ($nums.Count -gt 0) {
                & $item.Set ([int]$nums[0])
                if ($item.SetMulti) { & $item.SetMulti $nums }
                $message = "Set $($item.Label) -> $($nums -join ', ')"
                if ($OnChange) { & $OnChange }
              } else {
                $message = "Invalid: no valid numbers found"
              }
            }
            else {
              $message = "Invalid: must be a number (or comma-separated)"
            }
          }
          elseif ($item.Type -eq 'path') {
            if ($newVal) {
              & $item.Set $newVal
              $message = "Set $($item.Label) -> $newVal"
              if ($OnChange) { & $OnChange }
            } else {
              $message = "Empty value, not changed"
            }
          }
          Render
        }
        'Backspace' {
          if ($editBuffer.Length -gt 0) {
            $editBuffer = $editBuffer.Substring(0, $editBuffer.Length - 1)
          }
          Render
        }
        default {
          $ch = $key.KeyChar
          if ($ch -and [int]$ch -ge 32) {
            $editBuffer += $ch
          }
          Render
        }
      }
      continue
    }

    # Normal navigation mode
    switch ($key.Key) {
      'UpArrow' {
        $cursor = if ($cursor -gt 0) { $cursor - 1 } else { $Items.Count - 1 }
        $message = ''
        Render
      }
      'DownArrow' {
        $cursor = if ($cursor -lt ($Items.Count - 1)) { $cursor + 1 } else { 0 }
        $message = ''
        Render
      }
      'Enter' {
        $item = $Items[$cursor]
        switch ($item.Type) {
          'bool' {
            $currentVal = & $item.Get
            & $item.Set (-not $currentVal)
            $newState = if (-not $currentVal) { 'ON' } else { 'OFF' }
            $message = "Toggled $($item.Label) -> $newState"
            if ($OnChange) { & $OnChange }
            Render
          }
          'action' {
            [Console]::CursorVisible = $true
            & $item.Action
            $message = ''
            Render
          }
          default {
            # Enter edit mode
            $editing = $true
            $currentVal = & $item.Get
            $editBuffer = if ($currentVal) { [string]$currentVal } else { '' }
            $message = ''
            Render
          }
        }
      }
      'Escape' {
        [Console]::CursorVisible = $true
        return
      }
      default {
        # ignore other keys
      }
    }
  }
}

# ═══════════════════════════════════════════════════════════════════════
#  INTERACTIVE FILE MULTI-SELECT (Space to toggle, Enter to confirm)
# ═══════════════════════════════════════════════════════════════════════

function Select-FilesInteractive {
  <#
    Arrow-key file picker with Space to toggle selection, Enter to confirm.
    Returns array of selected full paths.
  #>
  param(
    [string]$Title,
    [object[]]$Files,       # FileInfo objects
    [string]$RootPath = ''  # for display: strips prefix to show relative paths
  )

  if (-not $Files -or $Files.Count -eq 0) {
    Write-Warn "No files to select."
    return @()
  }

  $cursor = 0
  $selected = [bool[]]::new($Files.Count)  # all false initially

  # Pagination
  $pageSize = [math]::Max(10, ([Console]::WindowHeight - 10))

  function Get-RelPath($f) {
    if ($RootPath) {
      $rel = $f.FullName
      if ($rel.StartsWith($RootPath)) {
        $rel = $rel.Substring($RootPath.Length).TrimStart([IO.Path]::DirectorySeparatorChar)
      }
      return $rel
    }
    return $f.Name
  }

  function Format-Size($bytes) {
    if ($bytes -ge 1GB) { return "{0:N1} GB" -f ($bytes / 1GB) }
    if ($bytes -ge 1MB) { return "{0:N1} MB" -f ($bytes / 1MB) }
    if ($bytes -ge 1KB) { return "{0:N0} KB" -f ($bytes / 1KB) }
    return "$bytes B"
  }

  function Render {
    [Console]::CursorVisible = $false
    Clear-Host
    Write-Banner $Title
    Write-Host ''

    $selectedCount = ($selected | Where-Object { $_ }).Count
    Write-C "  $selectedCount selected" -Fg brightyellow -Bold -NoNewline
    Write-C "  |  " -Fg brightblack -NoNewline
    Write-C "Space" -Fg cyan -Bold -NoNewline
    Write-C " toggle  " -Fg white -NoNewline
    Write-C "a" -Fg cyan -Bold -NoNewline
    Write-C " all  " -Fg white -NoNewline
    Write-C "n" -Fg cyan -Bold -NoNewline
    Write-C " none  " -Fg white -NoNewline
    Write-C "Enter" -Fg green -Bold -NoNewline
    Write-C " confirm  " -Fg white -NoNewline
    Write-C "Esc" -Fg red -Bold -NoNewline
    Write-C " cancel" -Fg white
    Write-Host ''

    # Calculate page
    $pageStart = [math]::Floor($cursor / $pageSize) * $pageSize
    $pageEnd   = [math]::Min($pageStart + $pageSize, $Files.Count)

    if ($Files.Count -gt $pageSize) {
      $pageNum = [math]::Floor($cursor / $pageSize) + 1
      $totalPages = [math]::Ceiling($Files.Count / $pageSize)
      Write-Dim "  Page $pageNum/$totalPages (${pageStart}-$($pageEnd-1) of $($Files.Count))"
      Write-Host ''
    }

    for ($i = $pageStart; $i -lt $pageEnd; $i++) {
      $f = $Files[$i]
      $isHovered = ($i -eq $cursor)
      $isChecked = $selected[$i]

      $checkbox = if ($isChecked) { "$($script:ESC)[1;32m[x]$($script:ESC)[0m" } else { "$($script:ESC)[2;37m[ ]$($script:ESC)[0m" }

      $relPath = Get-RelPath $f
      $sizeStr = Format-Size $f.Length

      if ($isHovered) {
        Write-Host "  $checkbox $($script:ESC)[1;97m$($relPath)$($script:ESC)[0m  $($script:ESC)[2;36m($sizeStr)$($script:ESC)[0m $($script:ESC)[33m◄$($script:ESC)[0m"
      } else {
        Write-Host "  $checkbox $($script:ESC)[37m$($relPath)$($script:ESC)[0m  $($script:ESC)[2;37m($sizeStr)$($script:ESC)[0m"
      }
    }
  }

  Render

  while ($true) {
    $key = [Console]::ReadKey($true)
    switch ($key.Key) {
      'UpArrow' {
        $cursor = if ($cursor -gt 0) { $cursor - 1 } else { $Files.Count - 1 }
        Render
      }
      'DownArrow' {
        $cursor = if ($cursor -lt ($Files.Count - 1)) { $cursor + 1 } else { 0 }
        Render
      }
      'Spacebar' {
        $selected[$cursor] = -not $selected[$cursor]
        # auto-advance cursor
        if ($cursor -lt ($Files.Count - 1)) { $cursor++ }
        Render
      }
      'Enter' {
        $paths = @()
        for ($i = 0; $i -lt $Files.Count; $i++) {
          if ($selected[$i]) { $paths += $Files[$i].FullName }
        }
        [Console]::CursorVisible = $true
        if ($paths.Count -eq 0) {
          Write-Warn "No files selected."
          return @()
        }
        return $paths
      }
      'Escape' {
        [Console]::CursorVisible = $true
        return @()
      }
      default {
        $ch = $key.KeyChar
        if ($ch -eq 'a' -or $ch -eq 'A') {
          for ($i = 0; $i -lt $selected.Count; $i++) { $selected[$i] = $true }
          Render
        }
        elseif ($ch -eq 'n' -or $ch -eq 'N') {
          for ($i = 0; $i -lt $selected.Count; $i++) { $selected[$i] = $false }
          Render
        }
      }
    }
  }
}

# ═══════════════════════════════════════════════════════════════════════
#  STREAMING FILE COMBINER (memory-efficient for multi-GB files)
# ═══════════════════════════════════════════════════════════════════════

function Invoke-CombineFiles {
  <#
    Streams multiple files into one, deduplicating lines using a HashSet.
    Memory usage: ~60 bytes per unique line for the HashSet entry.
    For very large files (>50M unique lines) it may use several GB of RAM.
    Shows live progress with file names and line counts.
  #>
  param(
    [string[]]$InputPaths,
    [string]$OutputPath,
    [switch]$NoProgress
  )

  if (-not $InputPaths -or $InputPaths.Count -eq 0) {
    Write-Err "No input files specified."
    return $false
  }

  # Estimate total size
  $totalSize = 0
  foreach ($p in $InputPaths) {
    if (Test-Path -LiteralPath $p -PathType Leaf) {
      $totalSize += (Get-Item -LiteralPath $p).Length
    }
  }
  $totalSizeMB = [math]::Round($totalSize / 1MB, 1)

  Write-Host ''
  Write-Info "Combining $($InputPaths.Count) file(s) ($totalSizeMB MB total)..."
  Write-Dim "  Output: $OutputPath"
  Write-Dim "  Method: streaming dedup (HashSet)"
  Write-Host ''

  $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
  $writer = $null
  $totalLines = 0
  $uniqueLines = 0
  $duplicates = 0
  $startTime = [datetime]::Now

  try {
    $writer = [System.IO.StreamWriter]::new($OutputPath, $false, [System.Text.Encoding]::UTF8, 65536)

    for ($fi = 0; $fi -lt $InputPaths.Count; $fi++) {
      $filePath = $InputPaths[$fi]
      $fileName = Split-Path -Leaf $filePath

      if (-not (Test-Path -LiteralPath $filePath -PathType Leaf)) {
        Write-Warn "  Skipping missing: $fileName"
        continue
      }

      $fileSize = (Get-Item -LiteralPath $filePath).Length
      $fileSizeStr = if ($fileSize -ge 1GB) { "{0:N1} GB" -f ($fileSize / 1GB) }
                     elseif ($fileSize -ge 1MB) { "{0:N1} MB" -f ($fileSize / 1MB) }
                     else { "{0:N0} KB" -f ($fileSize / 1KB) }

      Write-C "  [$($fi+1)/$($InputPaths.Count)] " -Fg brightyellow -Bold -NoNewline
      Write-C "$fileName " -Fg cyan -NoNewline
      Write-C "($fileSizeStr)" -Fg brightblack

      $reader = [System.IO.StreamReader]::new($filePath, [System.Text.Encoding]::UTF8, $true, 65536)
      $fileLines = 0
      $fileNew = 0
      try {
        while (-not $reader.EndOfStream) {
          $line = $reader.ReadLine()
          $totalLines++
          $fileLines++
          if ($null -eq $line) { continue }
          if ($line.Length -eq 0) { continue }

          if ($seen.Add($line)) {
            $writer.WriteLine($line)
            $uniqueLines++
            $fileNew++
          } else {
            $duplicates++
          }

          # Progress every 500K lines
          if (-not $NoProgress -and ($fileLines % 500000 -eq 0)) {
            $elapsed = ([datetime]::Now - $startTime).TotalSeconds
            $rate = if ($elapsed -gt 0) { [math]::Round($totalLines / $elapsed / 1000, 0) } else { 0 }
            Write-Host "`r    $($fileLines.ToString('N0')) lines, $($fileNew.ToString('N0')) new ($rate K lines/sec)  " -NoNewline
          }
        }
      } finally {
        $reader.Close()
      }

      Write-Host "`r    $($fileLines.ToString('N0')) lines, $($fileNew.ToString('N0')) new                         "
    }
  } catch {
    Write-Err "Error during combine: $($_.Exception.Message)"
    return $false
  } finally {
    if ($writer) { $writer.Close() }
  }

  $elapsed = ([datetime]::Now - $startTime).TotalSeconds
  $outputSize = if (Test-Path $OutputPath) { (Get-Item $OutputPath).Length } else { 0 }
  $outputSizeMB = [math]::Round($outputSize / 1MB, 1)

  Write-Host ''
  Write-Separator
  Write-Success "Combine complete!"
  Write-C "  Total lines  : " -Fg white -NoNewline; Write-C "$($totalLines.ToString('N0'))" -Fg cyan
  Write-C "  Unique lines : " -Fg white -NoNewline; Write-C "$($uniqueLines.ToString('N0'))" -Fg brightgreen -Bold
  Write-C "  Duplicates   : " -Fg white -NoNewline; Write-C "$($duplicates.ToString('N0'))" -Fg brightblack
  Write-C "  Output size  : " -Fg white -NoNewline; Write-C "$outputSizeMB MB" -Fg cyan
  Write-C "  Time elapsed : " -Fg white -NoNewline; Write-C "$([math]::Round($elapsed, 1))s" -Fg cyan
  Write-C "  Output file  : " -Fg white -NoNewline; Write-C $OutputPath -Fg green

  return $true
}

function Start-StatRecording {
  $temp = [System.IO.Path]::GetTempFileName()
  Start-Transcript -Path $temp -Force -ErrorAction SilentlyContinue | Out-Null
  return $temp
}

function Wait-Return {
  param([string]$LogPrefix, [string]$TempFile)

  Write-Host ''
  if ($LogPrefix -and $TempFile) {
    Write-C "  [" -Fg brightblack -NoNewline; Write-C "ENTER" -Fg brightyellow -Bold -NoNewline; Write-C "] Return  " -Fg white -NoNewline
    Write-C "  [" -Fg brightblack -NoNewline; Write-C "S" -Fg brightgreen -Bold -NoNewline; Write-C "] Save stats to log" -Fg white
  } else {
    Write-Dim "Press ENTER to return..."
  }

  while ([Console]::KeyAvailable) { [void][Console]::ReadKey($true) }

  if (-not $LogPrefix) {
    [void][Console]::ReadLine()
    return
  }

  while ($true) {
    $k = [Console]::ReadKey($true)
    if ($k.Key -eq 'Enter') { break }
    if ($k.Key -eq 'S' -or $k.Key -eq 's') {
      Stop-Transcript -ErrorAction SilentlyContinue | Out-Null
      if (Test-Path $TempFile) {
        $logsDir = Join-Path $PSScriptRoot 'logs'
        if (-not (Test-Path $logsDir)) { New-Item -ItemType Directory -Force -Path $logsDir | Out-Null }
        
        $ts = Get-Date -Format 'yyyyMMdd_HHmmss'
        $finalPath = Join-Path $logsDir "${LogPrefix}_${ts}.txt"
        
        $lines = @(Get-Content -LiteralPath $TempFile -ErrorAction SilentlyContinue)
        
        $start = 0; $end = $lines.Count - 1
        for ($i=0; $i -lt $lines.Count; $i++) { if ($lines[$i] -match '^Transcript started,') { $start = $i + 1; break } }
        for ($i=$lines.Count-1; $i -ge 0; $i--) { if ($lines[$i] -match '^\*+ PowerShell transcript end') { $end = $i - 1; break } }
        
        $lines[$start..$end] | Where-Object { $_ -notmatch '^\*+ PowerShell transcript start' -and $_ -notmatch '^Transcript started,' } | Set-Content -Path $finalPath
        
        Write-Host ''
        Write-Success "Saved to: $finalPath"
        Start-Sleep -Seconds 2
      }
      break
    }
  }
  try { Stop-Transcript -ErrorAction SilentlyContinue | Out-Null } catch {}
  if ($TempFile -and (Test-Path $TempFile)) { Remove-Item $TempFile -Force -ErrorAction SilentlyContinue }
}

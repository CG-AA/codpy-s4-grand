<#
.SYNOPSIS
  codpy-s4 Doctor - diagnose (and optionally auto-fix) the ESP32 workshop environment.

.DESCRIPTION
  A fallback safety net for the slide-based workshop instructions. It checks every stage
  from uv / Python installation through actual ESP32 connectivity, reports exactly what is
  wrong, and offers to auto-fix each detected problem. It mirrors the install logic of
  CG-AA/codpy-s4-setup/setup.ps1 but is diagnosis-first.

  Stages:
    1. uv + Python 3.12
    2. git
    3. grand repo integrity
    4. per-assignment venvs + dependency imports (pi_cake, fractal)
    5. USB-serial driver + COM port enumeration (CH340 / CP210x / FTDI / Espressif)
    6. ESP32 connectivity handshake (esptool read_mac) + optional render.py port patch
    7. PlatformIO smoke build (optional, -IncludeBuild)

.NOTES
  Windows-only (PowerShell 5.1+ / pwsh). Run from inside the grand repo via doctor\doctor.bat.
#>
[CmdletBinding()]
param(
    [switch]$Fix,             # apply every fix without prompting
    [switch]$DiagnoseOnly,    # never modify anything (pure read-only)
    [switch]$IncludeBuild,    # also run the slow PlatformIO smoke build (stage 7)
    [switch]$SkipDrivers,     # skip driver + ESP32 stages
    [switch]$PatchRenderPort, # auto-patch fractal\render.py SERIAL_PORT to the detected port
    [string]$Port,            # force a COM port for the ESP32 handshake
    [string]$GrandDir,        # repo root (default: parent of this script's folder)
    [string]$GrandRepoUrl = 'https://github.com/CG-AA/codpy-s4-grand.git'
)

# --- promote params to script scope so helper functions can read them ---
$script:Fix             = [bool]$Fix
$script:DiagnoseOnly    = [bool]$DiagnoseOnly
$script:IncludeBuild    = [bool]$IncludeBuild
$script:SkipDrivers     = [bool]$SkipDrivers
$script:PatchRenderPort = [bool]$PatchRenderPort
$script:Port            = $Port
$script:GrandDir        = $GrandDir
$script:GrandRepoUrl    = $GrandRepoUrl
$script:DetectedPort    = $null
$script:LogFile         = $null

# Works whether launched via -File (has $PSScriptRoot) or piped via stdin (GPO fallback).
$script:SelfDir = if ($PSScriptRoot) { $PSScriptRoot }
                  elseif ($env:CODPY_DOCTOR_HOME) { $env:CODPY_DOCTOR_HOME }
                  else { (Get-Location).Path }
$script:SelfDir = $script:SelfDir.TrimEnd('\')

# Tell the launcher we actually started (used to decide the stdin GPO fallback).
if ($env:CODPY_DOCTOR_FLAG) { try { New-Item -ItemType File -Path $env:CODPY_DOCTOR_FLAG -Force | Out-Null } catch {} }

# ESP32-class USB-serial vendors (VID -> chip label).
$script:EspVendors = @{
    '1A86' = 'WCH CH340'
    '10C4' = 'Silicon Labs CP210x'
    '0403' = 'FTDI'
    '303A' = 'Espressif (native USB)'
}

# Fallback pins if a requirements.txt is missing (kept in sync with the repo files).
$script:FallbackPins = @{
    'pi_cake' = @('platformio==6.1.19', 'esptool==5.3.0', 'pyserial==3.5')
    'fractal' = @('platformio==6.1.19', 'pyserial==3.5', 'pygame==2.6.1')
}

# ======================================================================
#  Helpers
# ======================================================================

function Write-DoctorLog {
    param([string]$Message)
    if ($script:LogFile) {
        try {
            Add-Content -LiteralPath $script:LogFile -Encoding UTF8 `
                -Value ("[{0}] {1}" -f (Get-Date -Format 'HH:mm:ss'), $Message)
        } catch {}
    }
}

function Say {
    param([string]$Message, [string]$Color = 'Gray')
    Write-Host $Message -ForegroundColor $Color
    Write-DoctorLog $Message
}

function Invoke-Logged {
    # Run an external command; tee its output to console + log; return {Code, Output}.
    param(
        [Parameter(Mandatory)][string]$File,
        [string[]]$Arguments = @()
    )
    Write-DoctorLog ("EXEC: {0} {1}" -f $File, ($Arguments -join ' '))
    try {
        $output = & $File @Arguments 2>&1
        $code = $LASTEXITCODE
        foreach ($line in $output) {
            Write-Host ("    {0}" -f $line) -ForegroundColor DarkGray
            Write-DoctorLog  ("    {0}" -f $line)
        }
        if ($null -eq $code) { $code = 0 }
        return [pscustomobject]@{ Code = $code; Output = ($output -join "`n") }
    } catch {
        Write-DoctorLog ("EXEC ERROR: {0}" -f $_)
        return [pscustomobject]@{ Code = -1; Output = "$_" }
    }
}

function Add-UserPath {
    param([string]$Dir)
    if (-not $Dir) { return }
    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    if (($userPath -split ';') -notcontains $Dir) {
        $newPath = if ($userPath) { "$userPath;$Dir" } else { $Dir }
        [Environment]::SetEnvironmentVariable('Path', $newPath, 'User')
        Write-DoctorLog "Added to user PATH: $Dir"
    }
    if (($env:Path -split ';') -notcontains $Dir) { $env:Path = "$env:Path;$Dir" }
}

function New-Result {
    param(
        [int]$Stage,
        [string]$Name,
        [string]$Status,             # OK | WARN | FAIL | SKIP
        [string]$Detail,
        [string]$FixDesc = '',
        [scriptblock]$Fix = $null,
        [bool]$AutoFix = $false
    )
    [pscustomobject]@{
        Stage = $Stage; Name = $Name; Status = $Status; Detail = $Detail
        FixDesc = $FixDesc; Fix = $Fix; AutoFix = $AutoFix
    }
}

function Get-StatusColor {
    param([string]$Status)
    switch ($Status) {
        'OK'   { 'Green' }
        'WARN' { 'Yellow' }
        'FAIL' { 'Red' }
        'SKIP' { 'DarkGray' }
        default { 'Gray' }
    }
}

function Show-Result {
    param($Result, [switch]$Compact)
    $color = Get-StatusColor $Result.Status
    $tag = "[{0,-4}]" -f $Result.Status
    if ($Compact) {
        Write-Host ("{0} {1}" -f $tag, $Result.Detail) -ForegroundColor $color
        Write-DoctorLog  ("RECHECK {0} {1} :: {2}" -f $tag, $Result.Name, $Result.Detail)
        return
    }
    Write-Host ''
    Write-Host ("{0} Stage {1}: {2}" -f $tag, $Result.Stage, $Result.Name) -ForegroundColor $color
    Write-Host ("       {0}" -f $Result.Detail) -ForegroundColor Gray
    Write-DoctorLog  ("{0} Stage {1} {2} :: {3}" -f $tag, $Result.Stage, $Result.Name, $Result.Detail)
}

function Confirm-Fix {
    param($Result)
    if ($script:Fix -or $Result.AutoFix) {
        Say ("  -> auto-fixing: {0}" -f $Result.FixDesc) 'Yellow'
        return $true
    }
    Write-Host ("  >> {0}? " -f $Result.FixDesc) -ForegroundColor Yellow -NoNewline
    $ans = Read-Host '[Y/n]'
    return ($ans -eq '' -or $ans -match '^(y|yes)$')
}

function Invoke-Check {
    param([scriptblock]$Test)
    $r = & $Test
    Show-Result $r
    if (-not $script:DiagnoseOnly -and $r.Fix -and ($r.Status -eq 'FAIL' -or $r.Status -eq 'WARN')) {
        if (Confirm-Fix $r) {
            Write-DoctorLog ("FIX START: {0}" -f $r.FixDesc)
            try { & $r.Fix } catch { Say ("  Fix error: {0}" -f $_) 'Red'; Write-DoctorLog "FIX ERROR: $_" }
            Write-DoctorLog 'FIX END'
            $r = & $Test
            Write-Host '  re-check -> ' -NoNewline
            Show-Result $r -Compact
        }
    }
    return $r
}

function Get-DeviceProblemCode {
    param([string]$InstanceId)
    try {
        $p = Get-PnpDeviceProperty -InstanceId $InstanceId -KeyName 'DEVPKEY_Device_ProblemCode' -ErrorAction Stop
        return [int]$p.Data
    } catch { return $null }
}

function Resolve-EspPorts {
    # Returns a list of present ESP32-class USB-serial devices with their COM + problem state.
    $devices = @()
    try {
        $pnp = Get-PnpDevice -PresentOnly -ErrorAction Stop |
               Where-Object { $_.InstanceId -match 'VID_([0-9A-Fa-f]{4})' }
    } catch {
        return $devices
    }
    foreach ($d in $pnp) {
        if ($d.InstanceId -match 'VID_([0-9A-Fa-f]{4})') {
            $vid = $Matches[1].ToUpper()
            if ($script:EspVendors.ContainsKey($vid)) {
                $com = $null
                if ($d.FriendlyName -match '\((COM\d+)\)') { $com = $Matches[1] }
                $code = Get-DeviceProblemCode $d.InstanceId   # 28 = drivers not installed
                $devices += [pscustomobject]@{
                    Vid          = $vid
                    Chip         = $script:EspVendors[$vid]
                    Com          = $com
                    FriendlyName = $d.FriendlyName
                    Status       = $d.Status
                    ProblemCode  = $code
                    Problem      = ($d.Status -ne 'OK') -or ($null -ne $code -and $code -ne 0) -or (-not $com)
                }
            }
        }
    }
    return $devices
}

# ======================================================================
#  Stage probes
# ======================================================================

function Test-Uv {
    $uv = Get-Command uv -ErrorAction SilentlyContinue
    if (-not $uv) {
        return New-Result 1 'uv + Python 3.12' 'FAIL' 'uv is not installed (or not on PATH).' `
            'Install uv and Python 3.12' { Repair-Uv }
    }
    $ver = (& uv --version 2>$null) -join ' '
    $py = & uv python find 3.12 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $py) {
        return New-Result 1 'uv + Python 3.12' 'WARN' "uv present ($ver) but Python 3.12 not available to uv." `
            'Install Python 3.12 via uv' { Repair-Uv }
    }
    return New-Result 1 'uv + Python 3.12' 'OK' "$ver; Python 3.12 -> $py"
}

function Repair-Uv {
    if (-not (Get-Command uv -ErrorAction SilentlyContinue)) {
        $installer = Join-Path $script:TmpDir 'uv-install.ps1'
        Say '  Downloading uv installer...' 'Cyan'
        Invoke-WebRequest -Uri 'https://astral.sh/uv/install.ps1' -OutFile $installer -UseBasicParsing
        & powershell -NoProfile -ExecutionPolicy Bypass -File $installer
        Add-UserPath (Join-Path $env:USERPROFILE '.local\bin')
    }
    Invoke-Logged 'uv' @('python', 'install', '3.12') | Out-Null
}

function Test-Git {
    $git = Get-Command git -ErrorAction SilentlyContinue
    if (-not $git) {
        return New-Result 2 'git' 'FAIL' 'git is not installed (or not on PATH).' `
            'Install git (winget, fallback PortableGit)' { Repair-Git }
    }
    $ver = (& git --version 2>$null) -join ' '
    return New-Result 2 'git' 'OK' $ver
}

function Repair-Git {
    $winget = Get-Command winget -ErrorAction SilentlyContinue
    if ($winget) {
        $r = Invoke-Logged 'winget' @('install', '--id', 'Git.Git', '-e', '--source', 'winget',
            '--accept-source-agreements', '--accept-package-agreements', '--scope', 'user')
        if ($r.Code -eq 0) { Add-UserPath 'C:\Program Files\Git\cmd'; return }
    }
    Say '  winget unavailable/failed; using PortableGit fallback...' 'Yellow'
    $url = 'https://github.com/git-for-windows/git/releases/download/v2.54.0.windows.1/PortableGit-2.54.0-64-bit.7z.exe'
    $pg = Join-Path $script:TmpDir 'PortableGit.7z.exe'
    Invoke-WebRequest -Uri $url -OutFile $pg -UseBasicParsing
    $dest = Join-Path $script:WorkRoot 'PortableGit'
    & $pg "-o$dest" '-y'
    Add-UserPath (Join-Path $dest 'cmd')
}

function Test-Grand {
    if (-not (Test-Path (Join-Path $script:GrandDir '.git'))) {
        return New-Result 3 'Grand repo' 'WARN' `
            "No .git at $($script:GrandDir). Re-run the workshop bootstrap (setup) to clone it cleanly." `
            'Clone the grand repo (only into an empty target)' { Repair-GrandClone }
    }
    $missing = @()
    foreach ($sub in 'pi_cake', 'fractal') {
        if (-not (Test-Path (Join-Path $script:GrandDir $sub))) { $missing += $sub }
    }
    if ($missing.Count) {
        return New-Result 3 'Grand repo' 'FAIL' `
            "Repo present but missing: $($missing -join ', '). Working tree may be corrupt; re-clone (your edits are not auto-touched)."
    }
    return New-Result 3 'Grand repo' 'OK' "Intact at $($script:GrandDir) (pi_cake + fractal present)."
}

function Repair-GrandClone {
    # Only clone when the target does not yet exist / is empty - never clobber student work.
    $target = $script:GrandDir
    if ((Test-Path $target) -and (Get-ChildItem -Force $target | Measure-Object).Count -gt 0) {
        Say "  $target is not empty; refusing to clone over it. Re-run the setup bootstrap instead." 'Yellow'
        return
    }
    Invoke-Logged 'git' @('clone', $script:GrandRepoUrl, $target) | Out-Null
}

function Test-Venv {
    param([string]$Assignment, [string[]]$Imports)
    $dir = Join-Path $script:GrandDir $Assignment
    if (-not (Test-Path $dir)) {
        return New-Result 4 "venv: $Assignment" 'SKIP' "$Assignment folder not found."
    }
    $py = Join-Path $dir 'venv\Scripts\python.exe'
    $importArg = ($Imports -join ', ')
    $fix = { Repair-Venv -Assignment $Assignment }.GetNewClosure()
    if (-not (Test-Path $py)) {
        return New-Result 4 "venv: $Assignment" 'FAIL' "No venv at $dir\venv." `
            "Create venv + install requirements for $Assignment" $fix
    }
    $r = Invoke-Logged $py @('-c', "import $importArg")
    if ($r.Code -ne 0) {
        return New-Result 4 "venv: $Assignment" 'FAIL' "venv exists but 'import $importArg' failed." `
            "Reinstall requirements for $Assignment" $fix
    }
    return New-Result 4 "venv: $Assignment" 'OK' "venv OK; import $importArg succeeds."
}

function Repair-Venv {
    param([string]$Assignment)
    $dir = Join-Path $script:GrandDir $Assignment
    $venv = Join-Path $dir 'venv'
    Invoke-Logged 'uv' @('venv', '--python', '3.12', $venv) | Out-Null
    $req = Join-Path $dir 'requirements.txt'
    if (Test-Path $req) {
        Invoke-Logged 'uv' @('pip', 'install', '--python', $venv, '-r', $req) | Out-Null
    } else {
        $pkgArgs = @('pip', 'install', '--python', $venv) + $script:FallbackPins[$Assignment]
        Invoke-Logged 'uv' $pkgArgs | Out-Null
    }
}

function Test-Drivers {
    if ($script:SkipDrivers) {
        return New-Result 5 'USB-serial driver / COM' 'SKIP' 'Skipped (-SkipDrivers).'
    }
    $devs = Resolve-EspPorts
    if (-not $devs -or $devs.Count -eq 0) {
        return New-Result 5 'USB-serial driver / COM' 'WARN' `
            'No ESP32-class USB device detected. Plug the board in with a DATA-capable cable, then re-run.'
    }
    $list = ($devs | ForEach-Object {
        "$($_.Chip) -> $(if ($_.Com) { $_.Com } else { '(no COM)' })$(if ($_.ProblemCode) { " [code $($_.ProblemCode)]" })"
    }) -join '; '
    $bad = $devs | Where-Object { $_.Problem }
    if ($bad) {
        return New-Result 5 'USB-serial driver / COM' 'WARN' "Device present but driver/COM problem: $list" `
            'Install the USB-serial driver(s)' { Repair-Drivers }
    }
    return New-Result 5 'USB-serial driver / COM' 'OK' "Detected: $list"
}

function Repair-Drivers {
    $devs = Resolve-EspPorts
    $infs = @()
    if ($devs | Where-Object { $_.Vid -eq '10C4' -and $_.Problem }) {
        Say '  Downloading CP210x universal driver...' 'Cyan'
        $zip = Join-Path $script:TmpDir 'cp210x.zip'
        Invoke-WebRequest -Uri 'https://www.silabs.com/documents/public/software/CP210x_Universal_Windows_Driver.zip' `
            -OutFile $zip -UseBasicParsing
        $ex = Join-Path $script:TmpDir 'cp210x'
        Expand-Archive -LiteralPath $zip -DestinationPath $ex -Force
        $infs += (Get-ChildItem -Path $ex -Recurse -Filter '*.inf' | Select-Object -ExpandProperty FullName)
    }
    if ($devs | Where-Object { $_.Vid -eq '1A86' -and $_.Problem }) {
        $bundled = Get-ChildItem -Path (Join-Path $script:SelfDir 'drivers') -Recurse -Filter '*.inf' -ErrorAction SilentlyContinue
        if ($bundled) {
            $infs += $bundled.FullName
        } else {
            Say '  CH340 driver not bundled under doctor\drivers\. Install CH341SER from https://www.wch-ic.com/downloads/CH341SER_EXE.html' 'Yellow'
        }
    }
    foreach ($inf in $infs) {
        Say "  Installing driver: $inf" 'Cyan'
        $r = Invoke-Logged 'pnputil' @('/add-driver', $inf, '/install')
        if ($r.Code -ne 0 -and ($r.Output -match 'denied|elevation|0x5')) {
            Say '  Elevation required; relaunching pnputil via UAC...' 'Yellow'
            Start-Process -FilePath 'pnputil' -ArgumentList "/add-driver `"$inf`" /install" -Verb RunAs -Wait
        }
    }
}

function Test-Esp32 {
    if ($script:SkipDrivers) {
        return New-Result 6 'ESP32 handshake' 'SKIP' 'Skipped (-SkipDrivers).'
    }
    $py = Join-Path $script:GrandDir 'pi_cake\venv\Scripts\python.exe'
    if (-not (Test-Path $py)) {
        return New-Result 6 'ESP32 handshake' 'SKIP' 'pi_cake venv missing (fix Stage 4 first); cannot run esptool.'
    }
    $port = $script:Port
    if (-not $port) {
        $cand = Resolve-EspPorts | Where-Object { $_.Com }
        if ($cand) { $port = ($cand | Select-Object -First 1).Com }
    }
    if (-not $port) {
        return New-Result 6 'ESP32 handshake' 'WARN' `
            'No COM port to probe. Plug the board in / fix the driver (Stage 5), then re-run.'
    }
    Say "  Probing $port with esptool read_mac..." 'Cyan'
    $r = Invoke-Logged $py @('-m', 'esptool', '--port', $port, 'read_mac')
    if ($r.Code -eq 0 -and $r.Output -match 'MAC:') {
        $chip = ''
        if ($r.Output -match 'Chip is ([^\r\n]+)') { $chip = " - " + $Matches[1].Trim() }
        $script:DetectedPort = $port
        return New-Result 6 'ESP32 handshake' 'OK' "Talked to the ESP32 on $port$chip."
    }
    if ($r.Output -match 'Access is denied|could not open port|PermissionError|in use') {
        return New-Result 6 'ESP32 handshake' 'FAIL' `
            "$port is busy - a serial monitor or IDE likely has it open. Close other programs, then re-check." `
            'Re-check after closing programs that use the port' { }
    }
    return New-Result 6 'ESP32 handshake' 'FAIL' `
        "esptool could not sync with the board on $port. Use a DATA USB cable, try another port, or hold BOOT while connecting." `
        'Re-check connectivity' { }
}

function Test-RenderPort {
    $render = Join-Path $script:GrandDir 'fractal\render.py'
    if (-not (Test-Path $render)) {
        return New-Result 6 'fractal render.py port' 'SKIP' 'fractal\render.py not found.'
    }
    $content = Get-Content -LiteralPath $render -Raw
    $current = $null
    if ($content -match "SERIAL_PORT\s*=\s*'([^']+)'") { $current = $Matches[1] }

    $detected = $script:DetectedPort
    if (-not $detected) {
        $cand = Resolve-EspPorts | Where-Object { $_.Com }
        if ($cand) { $detected = ($cand | Select-Object -First 1).Com }
    }
    if (-not $detected) {
        return New-Result 6 'fractal render.py port' 'SKIP' "Board port unknown; leaving SERIAL_PORT='$current' as-is."
    }
    if ($current -eq $detected) {
        return New-Result 6 'fractal render.py port' 'OK' "SERIAL_PORT already matches the board ($detected)."
    }
    $fix = { Set-RenderPort -NewPort $detected }.GetNewClosure()
    return New-Result 6 'fractal render.py port' 'WARN' `
        "render.py uses SERIAL_PORT='$current' but the board is on $detected." `
        "Patch render.py SERIAL_PORT to $detected" $fix $script:PatchRenderPort
}

function Set-RenderPort {
    param([string]$NewPort)
    $render = Join-Path $script:GrandDir 'fractal\render.py'
    $content = Get-Content -LiteralPath $render -Raw
    $new = [regex]::Replace($content, "SERIAL_PORT\s*=\s*'[^']+'", "SERIAL_PORT = '$NewPort'")
    Copy-Item -LiteralPath $render -Destination "$render.bak" -Force
    [System.IO.File]::WriteAllText($render, $new, (New-Object System.Text.UTF8Encoding($false)))
    Say "  Patched render.py SERIAL_PORT -> $NewPort (backup: render.py.bak)" 'Green'
}

function Test-Build {
    if (-not $script:IncludeBuild) {
        return New-Result 7 'PlatformIO smoke build' 'SKIP' 'Skipped (pass -IncludeBuild to run; slow, large toolchain download).'
    }
    $problems = @()
    foreach ($a in 'pi_cake', 'fractal') {
        $dir = Join-Path $script:GrandDir $a
        $pio = Join-Path $dir 'venv\Scripts\platformio.exe'
        if (-not (Test-Path $pio)) { $problems += "${a}: no platformio.exe (fix Stage 4)"; continue }
        $inis = Get-ChildItem -Path $dir -Recurse -Filter 'platformio.ini' -ErrorAction SilentlyContinue |
                Where-Object { $_.FullName -notmatch '\\\.pio\\' }
        foreach ($ini in $inis) {
            $proj = Split-Path -Parent $ini.FullName
            Say "  Building $a :: $proj ..." 'Cyan'
            $r = Invoke-Logged $pio @('run', '-d', $proj)
            if ($r.Code -ne 0) { $problems += "${a}: build failed at $proj" }
        }
    }
    if ($problems.Count) {
        return New-Result 7 'PlatformIO smoke build' 'FAIL' ($problems -join '; ')
    }
    return New-Result 7 'PlatformIO smoke build' 'OK' 'All discovered PlatformIO projects build.'
}

# ======================================================================
#  Runner
# ======================================================================

function Initialize-Doctor {
    $script:WorkRoot = 'C:\dev'
    if (-not (Test-Path $script:WorkRoot)) {
        try { New-Item -ItemType Directory -Path $script:WorkRoot -Force -ErrorAction Stop | Out-Null }
        catch { $script:WorkRoot = Join-Path $env:PUBLIC 'codpy-dev' }
    }
    $script:TmpDir = Join-Path $script:SelfDir 'tmp'
    New-Item -ItemType Directory -Path $script:TmpDir -Force | Out-Null
    $logDir = Join-Path $script:SelfDir 'logs'
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $script:LogFile = Join-Path $logDir "doctor_$stamp.log"

    # Match setup.ps1 cache locations so we see the same uv / PlatformIO installs.
    $env:UV_CACHE_DIR          = 'C:\dev\uv\cache'
    $env:UV_PYTHON_INSTALL_DIR = 'C:\dev\uv\python'
    $env:UV_TOOL_DIR           = 'C:\dev\uv\tools'
    $env:PLATFORMIO_CORE_DIR   = 'C:\dev\.platformio'

    if (-not $script:GrandDir) { $script:GrandDir = Split-Path -Parent $script:SelfDir }
}

function Show-Header {
    Write-Host '==========================================' -ForegroundColor Cyan
    Write-Host ' codpy-s4 Doctor  (workshop environment)  ' -ForegroundColor Cyan
    Write-Host '==========================================' -ForegroundColor Cyan
    $mode = if ($script:DiagnoseOnly) { 'diagnose-only' } elseif ($script:Fix) { 'auto-fix (no prompts)' } else { 'interactive' }
    Say "Mode: $mode   GrandDir: $($script:GrandDir)" 'Gray'
    Say "Log:  $($script:LogFile)" 'DarkGray'
}

function Show-Summary {
    param($Results)
    Write-Host "`n================= SUMMARY =================" -ForegroundColor Cyan
    foreach ($r in $Results) {
        Write-Host ("  [{0,-4}] Stage {1}: {2}" -f $r.Status, $r.Stage, $r.Name) -ForegroundColor (Get-StatusColor $r.Status)
    }
    $fail = ($Results | Where-Object { $_.Status -eq 'FAIL' }).Count
    $warn = ($Results | Where-Object { $_.Status -eq 'WARN' }).Count
    Write-Host ''
    if ($fail) { Say "RESULT: $fail problem(s) still need attention. Log: $($script:LogFile)" 'Red' }
    elseif ($warn) { Say "RESULT: usable, with $warn warning(s). Log: $($script:LogFile)" 'Yellow' }
    else { Say "RESULT: all checks passed - you're ready to go. Log: $($script:LogFile)" 'Green' }
}

function Invoke-Doctor {
    Initialize-Doctor
    Show-Header
    $checks = @(
        { Test-Uv },
        { Test-Git },
        { Test-Grand },
        { Test-Venv -Assignment 'pi_cake' -Imports @('serial', 'esptool') },
        { Test-Venv -Assignment 'fractal' -Imports @('serial', 'pygame') },
        { Test-Drivers },
        { Test-Esp32 },
        { Test-RenderPort },
        { Test-Build }
    )
    $results = @()
    foreach ($c in $checks) { $results += Invoke-Check -Test $c }
    Show-Summary $results

    if ($results.Status -contains 'FAIL') { exit 1 }
    elseif ($results.Status -contains 'WARN') { exit 2 }
    else { exit 0 }
}

Invoke-Doctor

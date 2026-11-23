# Installs Microsoft Plus! Dancer LE (Scooby-Doo edition) on Windows 10/11.
# Put this file + Install-ScoobyDancer.cmd next to Scooby_DancerLE.exe and run the .cmd.
$ErrorActionPreference = 'Stop'

# --- elevate ---
$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $admin) {
    Start-Process powershell.exe -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    exit
}

function Step($t) { Write-Host "`n=== $t" -ForegroundColor Cyan }
$here = Split-Path -Parent $PSCommandPath
$work = Join-Path $env:TEMP 'ScoobyDancerSetup'
$pf86 = ${env:ProgramFiles(x86)}; if (-not $pf86) { $pf86 = $env:ProgramFiles }
$appExe   = Join-Path $pf86 'Microsoft Plus! Dancer LE\DncLE.exe'
$dancers  = Join-Path $pf86 'Microsoft Plus! Digital Media Edition\Dancer\Dancers\Downloaded'
$log      = Join-Path $here 'ScoobyDancer-install.log'

try {
    # 1. Windows Media Player Legacy (DncLE.exe hosts the WMP ActiveX control)
    Step 'Checking Windows Media Player Legacy'
    if (Test-Path "$env:SystemRoot\SysWOW64\wmp.dll") {
        Write-Host 'WMP Legacy present.'
    } else {
        $cap = Get-WindowsCapability -Online | Where-Object Name -like 'Media.WindowsMediaPlayer*' | Select-Object -First 1
        if ($cap) {
            Write-Host "Installing $($cap.Name) (needs internet, a few minutes)..."
            Add-WindowsCapability -Online -Name $cap.Name | Out-Null
        } else {
            Enable-WindowsOptionalFeature -Online -FeatureName WindowsMediaPlayer -All -NoRestart | Out-Null
        }
    }

    # 2. Unpack the self-extractor (IExpress/wextract)
    Step 'Unpacking installer'
    # find the installer by content (any file name), in this folder or in Downloads
    $dirs = @($here, (Join-Path $here 'installer'), (Join-Path $env:USERPROFILE 'Downloads'))
    $sfx = $null
    foreach ($d in $dirs) {
        foreach ($f in (Get-ChildItem $d -File -ErrorAction SilentlyContinue | Where-Object { $_.Length -gt 3MB -and $_.Length -lt 10MB })) {
            $txt = [Text.Encoding]::ASCII.GetString([IO.File]::ReadAllBytes($f.FullName))
            if ($txt.Contains('DncTrial.msi')) { $sfx = $f; break }
        }
        if ($sfx) { break }
    }
    if (-not $sfx) {
        Write-Host "Files in ${here}:"; Get-ChildItem $here | Format-Table Name, Length -AutoSize
        throw "Dancer LE installer not found in $here or Downloads."
    }
    Write-Host "Installer: $($sfx.FullName)"
    Unblock-File $sfx.FullName -ErrorAction SilentlyContinue
    if ($sfx.Extension -ne '.exe') { $c = "$work-sfx.exe"; Copy-Item $sfx.FullName $c -Force; $sfx = Get-Item $c }
    if (Test-Path $work) { Remove-Item $work -Recurse -Force }
    New-Item $work -ItemType Directory | Out-Null
    Start-Process $sfx.FullName -ArgumentList "/Q /C /T:`"$work`"" -Wait
    if (-not (Test-Path "$work\DncTrial.msi")) { throw "Unpack failed - DncTrial.msi not found in $work" }
    Get-ChildItem $work | Format-Table Name, Length -AutoSize

    # 3. Stubs for the 'partner content' custom action (deferred, no ignore-error flag;
    #    a missing folder/file can roll back the whole install)
    New-Item "$work\Content" -ItemType Directory -Force | Out-Null
    if (-not (Test-Path "$work\Partner.reg")) { Set-Content "$work\Partner.reg" "Windows Registry Editor Version 5.00`r`n" -Encoding Unicode }

    # 4. Install the MSI
    Step 'Installing MSI'
    $p = Start-Process msiexec.exe -ArgumentList "/i `"$work\DncTrial.msi`" /qb LAUNCHPROGRAM=0 /l*v `"$log`"" -Wait -PassThru
    Write-Host "msiexec exit code: $($p.ExitCode) (0 or 3010 = OK). Log: $log"
    if ($p.ExitCode -notin 0,3010) { throw "MSI install failed, see log." }

    # 5. Make sure the Scooby dancer files are in place
    Step 'Checking Scooby-Doo dancer files'
    New-Item $dancers -ItemType Directory -Force | Out-Null
    foreach ($f in 'ScoobyDoo_L.Dnc','ScoobyDoo_L.Dat') {
        if (-not (Test-Path (Join-Path $dancers $f))) { Copy-Item "$work\$f" $dancers -Force; Write-Host "copied $f" }
    }
    Get-ChildItem $dancers | Format-Table Name, Length -AutoSize

    # 6. Compatibility mode: Windows XP SP3 for DncLE.exe (machine-wide)
    Step 'Setting XP SP3 compatibility mode'
    if (-not (Test-Path $appExe)) { throw "DncLE.exe not found at $appExe" }
    $layers = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Layers'
    New-Item $layers -Force | Out-Null
    Set-ItemProperty $layers -Name $appExe -Value '~ WINXPSP3'
    Write-Host "OK: $appExe"

    # 7. Audio input check - the dancer listens via a RECORDING device (waveIn)
    Step 'Checking loopback recording device (Stereo Mix)'
    $mix = Get-PnpDevice -Class AudioEndpoint -ErrorAction SilentlyContinue |
           Where-Object FriendlyName -match 'Stereo Mix|What U Hear|Wave Out Mix|Stereomix|CABLE Output'
    if ($mix) { $mix | Format-Table Status, FriendlyName -AutoSize }
    else { Write-Host 'No Stereo Mix / loopback device found - the dancer will not hear music yet.' -ForegroundColor Yellow }

    Step 'DONE'
    Write-Host "Run: $appExe"
} catch {
    Write-Host "`nERROR: $_" -ForegroundColor Red
}
Read-Host "`nPress Enter to close"

param(
  [string]$TipDllPath = "",
  [string]$HostExePath = ""
)

$ErrorActionPreference = "Stop"

# Resolve default paths relative to the script location.
if (-not $TipDllPath) {
  $TipDllPath = Join-Path $PSScriptRoot "..\build\tsf-tip\azookey_tsf_tip.dll"
}
if (-not $HostExePath) {
  $HostExePath = Join-Path $PSScriptRoot "..\build\inference-host\azookey_inference_host.exe"
}

$TipDllPath  = [System.IO.Path]::GetFullPath($TipDllPath)
$HostExePath = [System.IO.Path]::GetFullPath($HostExePath)

if (!(Test-Path $TipDllPath)) {
  throw "TIP DLL not found: $TipDllPath"
}

Write-Host "Registering TIP DLL: $TipDllPath"

# regsvr32 calls DllRegisterServer which handles COM + TSF profile keys.
$result = Start-Process -FilePath "regsvr32.exe" -ArgumentList "/s `"$TipDllPath`"" `
  -Wait -PassThru -NoNewWindow
if ($result.ExitCode -ne 0) {
  throw "regsvr32 failed with exit code $($result.ExitCode). Run as the target user (no elevation needed for HKCU registration)."
}

$clsid       = "{71EE04FA-B35D-4EB8-87A1-582D44A9A58C}"
$profileGuid = "{A8F74D91-8DF3-4DA1-B80B-01F7C73D4A90}"
$langId      = "0x00000411"

# Verify that DllRegisterServer wrote the expected profile keys.
$profileKey = "HKCU:\Software\Classes\CLSID\$clsid\Profiles\$langId\$profileGuid"
if (!(Test-Path $profileKey)) {
  # DllRegisterServer should have created these; fall back to manual write.
  Write-Warning "Profile key missing after regsvr32; writing manually."
  New-Item         -Path $profileKey -Force | Out-Null
  New-ItemProperty -Path $profileKey -Name "Description" -Value "azooKey TSF" -PropertyType String -Force | Out-Null
  New-ItemProperty -Path $profileKey -Name "DisplayName"  -Value "azooKey"     -PropertyType String -Force | Out-Null
}

# Register inference host for auto-start (best-effort).
if (Test-Path $HostExePath) {
  $runKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
  try {
    New-ItemProperty -Path $runKey -Name "azooKeyInferenceHost" `
      -Value "`"$HostExePath`" --pipe" -PropertyType String -Force | Out-Null
    Write-Host "Inference host auto-start registered: $HostExePath"
  } catch {
    Write-Warning "Could not register inference host auto-start: $_"
  }
} else {
  Write-Warning "Inference host not found, skipping auto-start registration: $HostExePath"
}

Write-Host "TSF TIP registration complete."

param(
  [string]$TipDllPath = "$(Resolve-Path "$PSScriptRoot/../build/tsf-tip/azookey_tsf_tip.dll")",
  [string]$HostExePath = "$(Resolve-Path "$PSScriptRoot/../build/inference-host/azookey_inference_host.exe")"
)

$ErrorActionPreference = "Stop"

if (!(Test-Path $TipDllPath)) { throw "TIP DLL not found: $TipDllPath" }

$regsvr = Start-Process -FilePath "$env:WINDIR\System32\regsvr32.exe" `
  -ArgumentList @("/s", $TipDllPath) -Wait -PassThru
if ($regsvr.ExitCode -ne 0) {
  throw "regsvr32 failed with exit code $($regsvr.ExitCode): $TipDllPath"
}

$clsid = "{71EE04FA-B35D-4EB8-87A1-582D44A9A58C}"
$profileGuid = "{A8F74D91-8DF3-4DA1-B80B-01F7C73D4A90}"
$langId = "0x00000411"
$profileKey = "HKCU:\Software\Classes\CLSID\$clsid\Profiles\$langId\$profileGuid"
New-Item -Path $profileKey -Force | Out-Null
New-ItemProperty -Path $profileKey -Name "Description" -Value "azooKey TSF" -PropertyType String -Force | Out-Null
New-ItemProperty -Path $profileKey -Name "DisplayName" -Value "azooKey" -PropertyType String -Force | Out-Null

if (Test-Path $HostExePath) {
  $runKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
  New-ItemProperty -Path $runKey -Name "azooKeyInferenceHost" -Value "`"$HostExePath`" --pipe default" -PropertyType String -Force | Out-Null
}

Write-Host "TSF TIP registration complete."

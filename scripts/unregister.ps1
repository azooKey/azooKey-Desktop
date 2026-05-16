param(
  [string]$TipDllPath = "$(Resolve-Path "$PSScriptRoot/../build/tsf-tip/azookey_tsf_tip.dll")"
)

$ErrorActionPreference = "Continue"
if (Test-Path $TipDllPath) {
  $regsvr = Start-Process -FilePath "$env:WINDIR\System32\regsvr32.exe" `
    -ArgumentList @("/u", "/s", $TipDllPath) -Wait -PassThru
  if ($regsvr.ExitCode -ne 0) {
    Write-Warning "regsvr32 /u failed with exit code $($regsvr.ExitCode): $TipDllPath"
  }
}

$clsid = "{71EE04FA-B35D-4EB8-87A1-582D44A9A58C}"
$profileGuid = "{A8F74D91-8DF3-4DA1-B80B-01F7C73D4A90}"
$langId = "0x00000411"
$profileKey = "HKCU:\Software\Classes\CLSID\$clsid\Profiles\$langId\$profileGuid"
if (Test-Path $profileKey) { Remove-Item -Path $profileKey -Recurse -Force }

$runKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
Remove-ItemProperty -Path $runKey -Name "azooKeyInferenceHost" -ErrorAction SilentlyContinue

Write-Host "TSF TIP unregistered."

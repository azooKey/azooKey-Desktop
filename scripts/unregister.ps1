param(
  [string]$TipDllPath = ""
)

$ErrorActionPreference = "Continue"

if (-not $TipDllPath) {
  $TipDllPath = Join-Path $PSScriptRoot "..\build\tsf-tip\azookey_tsf_tip.dll"
}
$TipDllPath = [System.IO.Path]::GetFullPath($TipDllPath)

# regsvr32 /u calls DllUnregisterServer which removes the CLSID subtree.
if (Test-Path $TipDllPath) {
  Write-Host "Unregistering TIP DLL: $TipDllPath"
  $result = Start-Process -FilePath "regsvr32.exe" -ArgumentList "/u /s `"$TipDllPath`"" `
    -Wait -PassThru -NoNewWindow
  if ($result.ExitCode -ne 0) {
    Write-Warning "regsvr32 /u returned exit code $($result.ExitCode)."
  }
} else {
  Write-Warning "TIP DLL not found, skipping regsvr32 /u: $TipDllPath"
}

# Belt-and-suspenders: remove any leftover HKCU keys.
$clsid      = "{71EE04FA-B35D-4EB8-87A1-582D44A9A58C}"
$clsidKey   = "HKCU:\Software\Classes\CLSID\$clsid"
if (Test-Path $clsidKey) {
  Remove-Item -Path $clsidKey -Recurse -Force -ErrorAction SilentlyContinue
}

$runKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
Remove-ItemProperty -Path $runKey -Name "azooKeyInferenceHost" -ErrorAction SilentlyContinue

Write-Host "TSF TIP unregistered."

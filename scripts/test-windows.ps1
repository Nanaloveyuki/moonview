[CmdletBinding()]
param(
  [Parameter(Mandatory)]
  [ValidateNotNullOrEmpty()]
  [string]$WebView2Sdk,

  [ValidateSet("x64", "x86", "arm64")]
  [string]$Architecture = "x64",

  [switch]$SkipSmoke
)

$sdkPath = (Resolve-Path -LiteralPath $WebView2Sdk -ErrorAction Stop).Path
$oldSdk = $env:MOONVIEW_WEBVIEW2_SDK_DIR
$oldArchitecture = $env:MOONVIEW_WEBVIEW2_ARCH

try {
  Push-Location (Join-Path $PSScriptRoot "..")
  $env:MOONVIEW_WEBVIEW2_SDK_DIR = $sdkPath
  $env:MOONVIEW_WEBVIEW2_ARCH = $Architecture

  moon test --target native --frozen
  if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
  }
  if (-not $SkipSmoke) {
    moon run --target native src/examples/windows_smoke --frozen
    if ($LASTEXITCODE -ne 0) {
      exit $LASTEXITCODE
    }
  }
} finally {
  $env:MOONVIEW_WEBVIEW2_SDK_DIR = $oldSdk
  $env:MOONVIEW_WEBVIEW2_ARCH = $oldArchitecture
  Pop-Location
}

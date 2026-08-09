[CmdletBinding()]
param(
  [string]$WebView2Sdk,

  [ValidateSet("x64", "x86", "arm64")]
  [string]$Architecture = "x64",

  [switch]$SkipSmoke
)

$sdkPath = if ($WebView2Sdk) {
  (Resolve-Path -LiteralPath $WebView2Sdk -ErrorAction Stop).Path
} else {
  $null
}
$oldSdk = $env:MOONVIEW_WEBVIEW2_SDK_DIR
$oldArchitecture = $env:MOONVIEW_WEBVIEW2_ARCH

try {
  Push-Location (Join-Path $PSScriptRoot "..")
  if ($sdkPath) {
    $env:MOONVIEW_WEBVIEW2_SDK_DIR = $sdkPath
  } else {
    Remove-Item Env:MOONVIEW_WEBVIEW2_SDK_DIR -ErrorAction SilentlyContinue
  }
  $env:MOONVIEW_WEBVIEW2_ARCH = $Architecture

  node --test tests/build.test.js
  if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
  }
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

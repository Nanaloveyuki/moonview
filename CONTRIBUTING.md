# Contributing To moonview

## Before You Start

Open an issue or discussion before work that changes the public API, native
backend ownership model, or platform support. Small bug fixes, documentation
improvements, and focused tests can be proposed directly.

Keep changes scoped. Do not add a windowing abstraction to `moonview`; host
windows, event loops, and native parent handles belong to the embedding
application or its window-management library.

## Development Setup

Use the native MoonBit toolchain and install dependencies for the platform you
change.

- Windows: Visual Studio Build Tools, Edge WebView2 Runtime, and a WebView2
  SDK supplied through `MOONVIEW_WEBVIEW2_SDK_DIR` or the include/loader
  environment variables documented in the README.
- macOS: Xcode Command Line Tools.
- Linux: GTK 3 and `webkit2gtk-4.1` development packages.

The repository does not commit WebView2 SDK binaries. Local SDK caches and
MoonBit build output are ignored.

## Change And Validate

Run the narrowest useful checks first, then run the native validation chain for
shared MoonBit code or a platform bridge:

```powershell
moon fmt --check
moon check --target native
moon test --target native
```

On Windows, also run:

```powershell
.\scripts\test-windows.ps1 -WebView2Sdk F:\path\to\Microsoft.Web.WebView2.1.0.x
```

Native backend changes require corresponding smoke coverage. GitHub Actions
runs Windows WebView2, macOS WKWebView, and Fedora WebKitGTK checks for pull
requests to `main`.

Update README examples, package documentation, and tests when observable
behavior changes. Do not commit `_build`, `.mooncakes`, `.tools`, local SDK
files, or other generated caches.

## Pull Requests

- Branch from current `main` and keep the PR focused on one change.
- Use a clear title and describe the behavior, platform scope, and validation.
- Rebase or merge current `main` before requesting review when the branch has
  fallen behind.
- All required GitHub Actions checks must pass.
- A pull request targeting `main` requires at least one developer LGTM before
  merge. The author must address requested changes before that approval.

Maintainers may request narrower scope, platform-specific tests, or a follow-up
issue when a proposal is larger than the current review can safely cover.

## Releases

Release instructions are in [docs/releasing.md](docs/releasing.md). Releases
are cut only from a clean, merged `main` after the three native CI workflows
pass.

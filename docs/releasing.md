# Releasing moonview

`moonview` releases are cut from an already merged and clean `main` branch.
The version in `moon.mod`, the changelog heading, Git tag, Mooncake package,
and GitHub release must match exactly.

For `0.1.0-alpha.1`, run the following from the release commit after all three
native CI workflows are green:

```powershell
moon fmt --check
moon check --target native
moon test --target native
moon info
git diff --check
moon package --list --frozen
moon publish --dry-run --frozen
```

Current Moon CLI builds may return a nonzero exit status after the dry-run
server reports `202 Accepted`; treat the accepted server response and extracted
package check as the result, then use a normal `moon publish --frozen` for the
actual release.

Run the Windows host smoke with a configured WebView2 SDK. GitHub Actions then
provides the required macOS WKWebView and Fedora WebKitGTK smoke coverage.

Create and push the annotated tag, publish, then create the GitHub release:

```powershell
git tag -a v0.1.0-alpha.1 -m "moonview 0.1.0-alpha.1"
git push origin v0.1.0-alpha.1
moon publish --frozen
gh release create v0.1.0-alpha.1 --title "moonview 0.1.0-alpha.1" --notes-file CHANGELOG.md
```

After Mooncake accepts the package, create a clean native fixture, add the
exact registry module version, and run `moon check --target native` to verify
the published public API.

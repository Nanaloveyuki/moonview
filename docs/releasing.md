# Releasing moonview

`moonview` releases are cut from an already merged and clean `main` branch.
The version in `moon.mod`, the changelog heading, Git tag, Mooncake package,
and GitHub release must match exactly.

Choose the release version before preparing the release commit. Update
`moon.mod`, add the corresponding `CHANGELOG.md` heading, and update the
install command in `README.md`. Then merge that commit to `main` and wait for
all three native CI workflows to pass.

Run the validation commands from the merged release commit:

```powershell
moon fmt --check
moon check --target native
moon test --target native
moon info
git diff --check
moon package --list
moon publish --dry-run
```

Current Moon CLI builds may return a nonzero exit status after the dry-run
server reports `202 Accepted`; treat the accepted server response and extracted
package check as the result. Do not pass `--frozen` to `moon publish`: the
publisher verifies an extracted package and must resolve its external Mooncake
dependencies there.

Run the Windows host smoke with a configured WebView2 SDK. GitHub Actions then
provides the required macOS WKWebView and Fedora WebKitGTK smoke coverage.

Set the exact version once, then create and push the annotated tag, publish,
and create the GitHub release:

```powershell
$version = "0.1.0-alpha.2"
git tag -a "v$version" -m "moonview $version"
git push origin "v$version"
moon publish
gh release create "v$version" --title "moonview $version" --notes-file CHANGELOG.md
```

After Mooncake accepts the package, create a clean native fixture, add the
exact registry module version, and run `moon check --target native` to verify
the published public API.

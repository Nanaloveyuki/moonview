const fs = require("fs");
const path = require("path");

function readConfig() {
  try {
    const text = fs.readFileSync(0, "utf8").trim();
    return text ? JSON.parse(text) : {};
  } catch (_) {
    return {};
  }
}

function configEnv(config, key) {
  return process.env[key] || config?.env?.[key] || config?.build?.env?.[key] || "";
}

function quote(value) {
  const normalized = value.replace(/\\/g, "/");
  return /^[A-Za-z0-9_./:-]+$/.test(normalized) ? normalized : JSON.stringify(normalized);
}

function findSdkRoot(config) {
  const explicit = configEnv(config, "MOONVIEW_WEBVIEW2_SDK_DIR");
  if (explicit) return path.resolve(explicit);
  return path.resolve(__dirname, ".tools", "webview2");
}

function sdkArchitecture(config) {
  return configEnv(config, "MOONVIEW_WEBVIEW2_ARCH") || "x64";
}

function main() {
  const config = readConfig();
  const sdkRoot = findSdkRoot(config);
  const architecture = sdkArchitecture(config);
  const includeDir = configEnv(config, "MOONVIEW_WEBVIEW2_INCLUDE") ||
    path.join(sdkRoot, "build", "native", "include");
  const loaderLib = configEnv(config, "MOONVIEW_WEBVIEW2_LOADER_LIB") ||
    path.join(sdkRoot, "build", "native", architecture, "WebView2LoaderStatic.lib");
  const header = path.join(includeDir, "WebView2.h");

  if (!fs.existsSync(header) || !fs.existsSync(loaderLib)) {
    throw new Error(
      "moonview requires the WebView2 SDK. Set MOONVIEW_WEBVIEW2_SDK_DIR, " +
      "or set both MOONVIEW_WEBVIEW2_INCLUDE and MOONVIEW_WEBVIEW2_LOADER_LIB. " +
      "A local .tools/webview2/ cache is also supported.",
    );
  }

  const stubFlags = "-I" + quote(includeDir);
  const linkFlags = [
    quote(loaderLib),
    "ole32.lib",
    "oleaut32.lib",
    "user32.lib",
    "version.lib",
    "advapi32.lib",
  ].join(" ");

  console.log(JSON.stringify({
    vars: {
      MOONVIEW_WEBVIEW2_STUB_CC_FLAGS: stubFlags,
      MOONVIEW_WEBVIEW2_CC_LINK_FLAGS: linkFlags,
    },
    link_configs: [{
      package: "Nanaloveyuki/moonview/windows",
      link_flags: linkFlags,
    }],
  }));
}

main();

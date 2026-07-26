const childProcess = require("child_process");
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

function findWebView2Sdk(config) {
  const explicit = configEnv(config, "MOONVIEW_WEBVIEW2_SDK_DIR");
  return explicit ? path.resolve(explicit) : path.resolve(__dirname, ".tools", "webview2");
}

function webView2Config(config) {
  const sdkRoot = findWebView2Sdk(config);
  const architecture = configEnv(config, "MOONVIEW_WEBVIEW2_ARCH") || "x64";
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

  const linkFlags = [
    quote(loaderLib),
    "ole32.lib",
    "oleaut32.lib",
    "user32.lib",
    "version.lib",
    "advapi32.lib",
  ].join(" ");
  return { stubFlags: "-I" + quote(includeDir), linkFlags };
}

function webKitGtkConfig() {
  try {
    return {
      stubFlags: childProcess.execFileSync(
        "pkg-config", ["--cflags", "webkit2gtk-4.1"], { encoding: "utf8" },
      ).trim(),
      linkFlags: childProcess.execFileSync(
        "pkg-config", ["--libs", "webkit2gtk-4.1"], { encoding: "utf8" },
      ).trim() + " -lstdc++",
    };
  } catch (_) {
    throw new Error(
      "moonview requires WebKitGTK 4.1 development files. Install the " +
      "webkit2gtk-4.1 pkg-config package before building on Linux.",
    );
  }
}

function main() {
  const config = readConfig();
  const vars = {
    MOONVIEW_WEBVIEW2_STUB_CC_FLAGS: "",
    MOONVIEW_WEBVIEW2_CC_LINK_FLAGS: "",
    MOONVIEW_WEBKITGTK_STUB_CC_FLAGS: "",
    MOONVIEW_WEBKITGTK_CC_LINK_FLAGS: "",
    MOONVIEW_WKWEBVIEW_STUB_CC_FLAGS: "",
    MOONVIEW_WKWEBVIEW_CC_LINK_FLAGS: "",
    MOONVIEW_WINDOWS_SMOKE_CC_LINK_FLAGS: "",
  };
  const linkConfigs = [];

  if (process.platform === "win32") {
    const native = webView2Config(config);
    vars.MOONVIEW_WEBVIEW2_STUB_CC_FLAGS = native.stubFlags;
    vars.MOONVIEW_WEBVIEW2_CC_LINK_FLAGS = native.linkFlags;
    vars.MOONVIEW_WINDOWS_SMOKE_CC_LINK_FLAGS = "user32.lib";
    linkConfigs.push({
      package: "Nanaloveyuki/moonview/windows",
      link_flags: native.linkFlags,
    });
  } else if (process.platform === "linux") {
    const native = webKitGtkConfig();
    vars.MOONVIEW_WEBKITGTK_STUB_CC_FLAGS = native.stubFlags;
    vars.MOONVIEW_WEBKITGTK_CC_LINK_FLAGS = native.linkFlags;
    linkConfigs.push({
      package: "Nanaloveyuki/moonview/linux",
      link_flags: native.linkFlags,
    });
  } else if (process.platform === "darwin") {
    const linkFlags = "-framework WebKit -framework AppKit -framework Foundation";
    vars.MOONVIEW_WKWEBVIEW_CC_LINK_FLAGS = linkFlags;
    linkConfigs.push({
      package: "Nanaloveyuki/moonview/macos",
      link_flags: linkFlags,
    });
  } else {
    throw new Error(`moonview does not support native builds on ${process.platform}.`);
  }

  console.log(JSON.stringify({ vars, link_configs: linkConfigs }));
}

main();

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

function findArtifact(root, filename) {
  if (!root || !fs.existsSync(root)) {
    return "";
  }
  const pending = [root];
  while (pending.length > 0) {
    const current = pending.pop();
    let entries;
    try {
      entries = fs.readdirSync(current, { withFileTypes: true });
    } catch (_) {
      continue;
    }
    for (const entry of entries) {
      const candidate = path.join(current, entry.name);
      if (entry.isFile() && entry.name === filename) {
        return candidate;
      }
      if (entry.isDirectory() && pending.length < 4096) {
        pending.push(candidate);
      }
    }
  }
  return "";
}

function ohosArkWebConfig(config) {
  const sdkRoot = configEnv(config, "MOONVIEW_OHOS_ARKWEB_SDK_DIR") ||
    configEnv(config, "MOONVIEW_OHOS_NDK_HOME");
  const discoveredHeader = findArtifact(sdkRoot, "arkweb_interface.h");
  const includeDir = configEnv(config, "MOONVIEW_OHOS_ARKWEB_INCLUDE") ||
    (discoveredHeader ? path.dirname(discoveredHeader) : "");
  const library = configEnv(config, "MOONVIEW_OHOS_ARKWEB_LIB") ||
    findArtifact(sdkRoot, "libohweb.so");
  const header = includeDir ? path.join(includeDir, "arkweb_interface.h") : "";

  if (!header || !fs.existsSync(header) || !library || !fs.existsSync(library)) {
    throw new Error(
      "moonview requires the OpenHarmony ArkWeb NDK. Set MOONVIEW_OHOS_ARKWEB_SDK_DIR " +
      "(or MOONVIEW_OHOS_NDK_HOME), or set both MOONVIEW_OHOS_ARKWEB_INCLUDE and " +
      "MOONVIEW_OHOS_ARKWEB_LIB. The SDK is never vendored by moonview.",
    );
  }

  return {
    stubFlags: "-I" + quote(includeDir),
    linkFlags: quote(library),
  };
}

function hasOhosArkWebConfig(config) {
  return Boolean(
    configEnv(config, "MOONVIEW_OHOS_ARKWEB_SDK_DIR") ||
    configEnv(config, "MOONVIEW_OHOS_NDK_HOME") ||
    configEnv(config, "MOONVIEW_OHOS_ARKWEB_INCLUDE") ||
    configEnv(config, "MOONVIEW_OHOS_ARKWEB_LIB"),
  );
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
    MOONVIEW_OHOS_ARKWEB_STUB_CC_FLAGS: "",
    MOONVIEW_OHOS_ARKWEB_CC_LINK_FLAGS: "",
    MOONVIEW_WINDOWS_SMOKE_CC_LINK_FLAGS: "",
  };
  const linkConfigs = [];

  if (hasOhosArkWebConfig(config)) {
    const native = ohosArkWebConfig(config);
    vars.MOONVIEW_OHOS_ARKWEB_STUB_CC_FLAGS = native.stubFlags;
    vars.MOONVIEW_OHOS_ARKWEB_CC_LINK_FLAGS = native.linkFlags;
    linkConfigs.push({
      package: "Nanaloveyuki/moonview/ohos",
      link_flags: native.linkFlags,
    });
  } else if (process.platform === "win32") {
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
    const linkFlags = "-framework WebKit -framework AppKit -framework Foundation -lc++";
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

const childProcess = require("child_process");
const crypto = require("crypto");
const fs = require("fs");
const https = require("https");
const os = require("os");
const path = require("path");
const { pipeline } = require("stream/promises");

const WEBVIEW2_VERSION = "1.0.4078.44";
const WEBVIEW2_PACKAGE_URL =
  "https://api.nuget.org/v3-flatcontainer/microsoft.web.webview2/" +
  `${WEBVIEW2_VERSION}/microsoft.web.webview2.${WEBVIEW2_VERSION}.nupkg`;
const WEBVIEW2_PACKAGE_SHA256 =
  "dc4d1d9168df26b830398303e50210b6e1729f6ce5a7ac69d2c766852f489962";
const WEBVIEW2_ARCHITECTURES = new Set(["x64", "x86", "arm64"]);
const CACHE_MARKER = ".moonview-webview2-sdk.json";
const LOCK_TIMEOUT_MS = 5 * 60 * 1000;
const LOCK_STALE_MS = 15 * 60 * 1000;

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

function randomToken() {
  return `${process.pid}-${Date.now()}-${crypto.randomBytes(6).toString("hex")}`;
}

function sleep(milliseconds) {
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
}

function webView2Artifacts(sdkRoot, architecture) {
  return {
    includeDir: path.join(sdkRoot, "build", "native", "include"),
    loaderLib: path.join(
      sdkRoot, "build", "native", architecture, "WebView2LoaderStatic.lib",
    ),
  };
}

function webView2CacheBase(config) {
  const explicit = configEnv(config, "MOONVIEW_WEBVIEW2_CACHE_DIR");
  if (explicit) return path.resolve(explicit);

  if (process.platform === "win32" && process.env.LOCALAPPDATA) {
    return path.join(process.env.LOCALAPPDATA, "moonview", "webview2");
  }
  const base = process.env.XDG_CACHE_HOME || path.join(os.homedir(), ".cache");
  return path.join(base, "moonview", "webview2");
}

function cacheMarkerIsValid(sdkRoot) {
  try {
    const marker = JSON.parse(fs.readFileSync(path.join(sdkRoot, CACHE_MARKER), "utf8"));
    return marker.version === WEBVIEW2_VERSION &&
      marker.sha256 === WEBVIEW2_PACKAGE_SHA256;
  } catch (_) {
    return false;
  }
}

function sdkHasArtifacts(sdkRoot, architecture, requireMarker = false) {
  const artifacts = webView2Artifacts(sdkRoot, architecture);
  return (!requireMarker || cacheMarkerIsValid(sdkRoot)) &&
    fs.existsSync(path.join(artifacts.includeDir, "WebView2.h")) &&
    fs.existsSync(artifacts.loaderLib);
}

function lockIsStale(lockDir, staleMs) {
  try {
    return Date.now() - fs.statSync(lockDir).mtimeMs > staleMs;
  } catch (_) {
    return false;
  }
}

function reclaimStaleLock(lockDir, token) {
  const staleDir = `${lockDir}.stale-${token}`;
  try {
    fs.renameSync(lockDir, staleDir);
  } catch (error) {
    if (error.code === "ENOENT" || error.code === "EACCES" || error.code === "EPERM") {
      return false;
    }
    throw error;
  }
  fs.rmSync(staleDir, { recursive: true, force: true });
  return true;
}

async function withDirectoryLock(lockDir, action, options = {}) {
  const timeoutMs = options.timeoutMs ?? LOCK_TIMEOUT_MS;
  const staleMs = options.staleMs ?? LOCK_STALE_MS;
  const pollMs = options.pollMs ?? 100;
  const token = randomToken();
  const deadline = Date.now() + timeoutMs;

  for (;;) {
    try {
      fs.mkdirSync(lockDir);
      fs.writeFileSync(path.join(lockDir, "owner"), token, { flag: "wx" });
      break;
    } catch (error) {
      if (error.code !== "EEXIST") throw error;
      if (lockIsStale(lockDir, staleMs) && reclaimStaleLock(lockDir, token)) continue;
      if (Date.now() >= deadline) {
        throw new Error(
          `Timed out waiting for the WebView2 SDK cache lock at ${lockDir}. ` +
          "If no build is running, remove that stale lock directory and retry.",
        );
      }
      await sleep(pollMs);
    }
  }

  try {
    return await action();
  } finally {
    try {
      const owner = fs.readFileSync(path.join(lockDir, "owner"), "utf8");
      if (owner === token) fs.rmSync(lockDir, { recursive: true, force: true });
    } catch (_) {
      // A stale-lock recovery may already have moved this process's lock.
    }
  }
}

async function downloadPackage(url, destination, expectedSha256, redirects = 0) {
  if (redirects > 5) throw new Error("too many HTTPS redirects");
  const parsed = new URL(url);
  if (parsed.protocol !== "https:") throw new Error(`refusing non-HTTPS URL: ${url}`);

  await new Promise((resolve, reject) => {
    const request = https.get(parsed, (response) => {
      if (response.statusCode >= 300 && response.statusCode < 400 && response.headers.location) {
        response.resume();
        resolve(downloadPackage(new URL(response.headers.location, parsed).toString(), destination,
          expectedSha256, redirects + 1));
        return;
      }
      if (response.statusCode !== 200) {
        response.resume();
        reject(new Error(`download returned HTTP ${response.statusCode}`));
        return;
      }

      const digest = crypto.createHash("sha256");
      response.on("data", (chunk) => digest.update(chunk));
      const output = fs.createWriteStream(destination, { flags: "wx" });
      pipeline(response, output).then(() => {
        const actual = digest.digest("hex");
        if (actual !== expectedSha256) {
          reject(new Error(
            `WebView2 SDK checksum mismatch: expected ${expectedSha256}, got ${actual}`,
          ));
          return;
        }
        resolve();
      }, reject);
    });
    request.on("error", reject);
    request.setTimeout(120000, () => request.destroy(new Error("download timed out")));
  });
}

function extractPackage(archive, destination) {
  fs.mkdirSync(destination);
  const result = childProcess.spawnSync(
    "tar", ["-xf", archive, "-C", destination],
    { encoding: "utf8", windowsHide: true },
  );
  if (result.error || result.status !== 0) {
    const detail = result.error?.message || result.stderr?.trim() || `exit code ${result.status}`;
    throw new Error(
      `Failed to extract the WebView2 SDK with tar: ${detail}. ` +
      "Ensure tar is available on PATH, or set MOONVIEW_WEBVIEW2_SDK_DIR (or both " +
      "MOONVIEW_WEBVIEW2_INCLUDE and MOONVIEW_WEBVIEW2_LOADER_LIB).",
    );
  }
}

async function installWebView2Sdk(sdkRoot, architecture, dependencies = {}) {
  const parent = path.dirname(sdkRoot);
  const token = randomToken();
  const archive = path.join(parent, `.webview2-${WEBVIEW2_VERSION}-${token}.nupkg`);
  const staging = path.join(parent, `.webview2-${WEBVIEW2_VERSION}-${token}.tmp`);
  const download = dependencies.downloadPackage || downloadPackage;
  const extract = dependencies.extractPackage || extractPackage;

  try {
    await download(WEBVIEW2_PACKAGE_URL, archive, WEBVIEW2_PACKAGE_SHA256);
    extract(archive, staging);
    if (!sdkHasArtifacts(staging, architecture)) {
      throw new Error(
        `WebView2 SDK ${WEBVIEW2_VERSION} does not contain headers and the ${architecture} ` +
        "static Loader library.",
      );
    }
    fs.writeFileSync(path.join(staging, CACHE_MARKER), JSON.stringify({
      version: WEBVIEW2_VERSION,
      sha256: WEBVIEW2_PACKAGE_SHA256,
      source: WEBVIEW2_PACKAGE_URL,
    }, null, 2) + "\n");
    fs.rmSync(sdkRoot, { recursive: true, force: true });
    fs.renameSync(staging, sdkRoot);
  } finally {
    fs.rmSync(archive, { force: true });
    fs.rmSync(staging, { recursive: true, force: true });
  }
}

async function ensureWebView2Sdk(config, architecture, dependencies = {}) {
  const sdkRoot = path.join(webView2CacheBase(config), WEBVIEW2_VERSION);
  fs.mkdirSync(path.dirname(sdkRoot), { recursive: true });
  if (sdkHasArtifacts(sdkRoot, architecture, true)) return sdkRoot;

  const lockDir = `${sdkRoot}.lock`;
  try {
    await withDirectoryLock(lockDir, async () => {
      if (!sdkHasArtifacts(sdkRoot, architecture, true)) {
        await installWebView2Sdk(sdkRoot, architecture, dependencies);
      }
    }, dependencies.lockOptions);
  } catch (error) {
    throw new Error(
      `Unable to prepare WebView2 SDK ${WEBVIEW2_VERSION} in ${sdkRoot}: ${error.message}`,
    );
  }
  return sdkRoot;
}

async function webView2Config(config, dependencies = {}) {
  const architecture = configEnv(config, "MOONVIEW_WEBVIEW2_ARCH") || "x64";
  if (!WEBVIEW2_ARCHITECTURES.has(architecture)) {
    throw new Error("MOONVIEW_WEBVIEW2_ARCH must be x64, x86, or arm64.");
  }

  const explicitRoot = configEnv(config, "MOONVIEW_WEBVIEW2_SDK_DIR");
  const explicitInclude = configEnv(config, "MOONVIEW_WEBVIEW2_INCLUDE");
  const explicitLoader = configEnv(config, "MOONVIEW_WEBVIEW2_LOADER_LIB");
  let sdkRoot = explicitRoot ? path.resolve(explicitRoot) : "";
  if (!sdkRoot && (!explicitInclude || !explicitLoader)) {
    const localRoot = path.resolve(__dirname, ".tools", "webview2");
    sdkRoot = sdkHasArtifacts(localRoot, architecture)
      ? localRoot
      : await ensureWebView2Sdk(config, architecture, dependencies);
  }

  const defaults = sdkRoot ? webView2Artifacts(sdkRoot, architecture) : {};
  const includeDir = path.resolve(explicitInclude || defaults.includeDir);
  const loaderLib = path.resolve(explicitLoader || defaults.loaderLib);
  const header = path.join(includeDir, "WebView2.h");

  if (!fs.existsSync(header) || !fs.existsSync(loaderLib)) {
    throw new Error(
      `Invalid WebView2 SDK configuration: expected ${header} and ${loaderLib}. ` +
      "Fix MOONVIEW_WEBVIEW2_SDK_DIR, or set both MOONVIEW_WEBVIEW2_INCLUDE and " +
      "MOONVIEW_WEBVIEW2_LOADER_LIB.",
    );
  }

  const linkFlags = [
    quote(loaderLib),
    "ole32.lib",
    "oleaut32.lib",
    "user32.lib",
    "shell32.lib",
    "uuid.lib",
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

function nativeBackend(config) {
  const explicit = configEnv(config, "MOONVIEW_NATIVE_BACKEND").toLowerCase();
  if (explicit) {
    if (["windows", "linux", "macos", "ohos", "android"].includes(explicit)) {
      return explicit;
    }
    throw new Error(
      "MOONVIEW_NATIVE_BACKEND must be windows, linux, macos, ohos, or android.",
    );
  }
  if (hasOhosArkWebConfig(config)) {
    return "ohos";
  }
  if (process.platform === "win32") return "windows";
  if (process.platform === "linux") return "linux";
  if (process.platform === "darwin") return "macos";
  throw new Error(`moonview does not support native builds on ${process.platform}.`);
}

async function main() {
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

  switch (nativeBackend(config)) {
  case "ohos": {
    const native = ohosArkWebConfig(config);
    vars.MOONVIEW_OHOS_ARKWEB_STUB_CC_FLAGS = native.stubFlags;
    vars.MOONVIEW_OHOS_ARKWEB_CC_LINK_FLAGS = native.linkFlags;
    linkConfigs.push({
      package: "Nanaloveyuki/moonview/ohos",
      link_flags: native.linkFlags,
    });
    break;
  }
  case "windows": {
    const native = await webView2Config(config);
    vars.MOONVIEW_WEBVIEW2_STUB_CC_FLAGS = native.stubFlags;
    vars.MOONVIEW_WEBVIEW2_CC_LINK_FLAGS = native.linkFlags;
    vars.MOONVIEW_WINDOWS_SMOKE_CC_LINK_FLAGS = "user32.lib";
    linkConfigs.push({
      package: "Nanaloveyuki/moonview/windows",
      link_flags: native.linkFlags,
    });
    break;
  }
  case "linux": {
    const native = webKitGtkConfig();
    vars.MOONVIEW_WEBKITGTK_STUB_CC_FLAGS = native.stubFlags;
    vars.MOONVIEW_WEBKITGTK_CC_LINK_FLAGS = native.linkFlags;
    linkConfigs.push({
      package: "Nanaloveyuki/moonview/linux",
      link_flags: native.linkFlags,
    });
    break;
  }
  case "macos": {
    const linkFlags = "-framework WebKit -framework AppKit -framework Foundation -lc++";
    vars.MOONVIEW_WKWEBVIEW_CC_LINK_FLAGS = linkFlags;
    linkConfigs.push({
      package: "Nanaloveyuki/moonview/macos",
      link_flags: linkFlags,
    });
    break;
  }
  case "android":
    // The optional moonview/android package owns no desktop SDK linkage.
    // Its Android NDK/JNI inputs are supplied by the consuming application.
    break;
  }

  console.log(JSON.stringify({ vars, link_configs: linkConfigs }));
}

if (require.main === module) {
  main().catch((error) => {
    console.error(`moonview prebuild failed: ${error.message}`);
    process.exitCode = 1;
  });
}

module.exports = {
  WEBVIEW2_PACKAGE_SHA256,
  WEBVIEW2_PACKAGE_URL,
  WEBVIEW2_VERSION,
  cacheMarkerIsValid,
  ensureWebView2Sdk,
  extractPackage,
  sdkHasArtifacts,
  webView2Artifacts,
  webView2CacheBase,
  webView2Config,
  withDirectoryLock,
};

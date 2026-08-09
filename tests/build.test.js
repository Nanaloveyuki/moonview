const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const test = require("node:test");

const build = require("../build.js");

const ENV_KEYS = [
  "MOONVIEW_WEBVIEW2_ARCH",
  "MOONVIEW_WEBVIEW2_CACHE_DIR",
  "MOONVIEW_WEBVIEW2_INCLUDE",
  "MOONVIEW_WEBVIEW2_LOADER_LIB",
  "MOONVIEW_WEBVIEW2_SDK_DIR",
];

function withoutWebView2Environment(action) {
  const previous = new Map(ENV_KEYS.map((key) => [key, process.env[key]]));
  for (const key of ENV_KEYS) delete process.env[key];
  return Promise.resolve().then(action).finally(() => {
    for (const [key, value] of previous) {
      if (value === undefined) delete process.env[key];
      else process.env[key] = value;
    }
  });
}

function temporaryDirectory() {
  return fs.mkdtempSync(path.join(os.tmpdir(), "moonview-build-test-"));
}

function createSdk(root, architecture = "x64") {
  const artifacts = build.webView2Artifacts(root, architecture);
  fs.mkdirSync(artifacts.includeDir, { recursive: true });
  fs.mkdirSync(path.dirname(artifacts.loaderLib), { recursive: true });
  fs.writeFileSync(path.join(artifacts.includeDir, "WebView2.h"), "// fixture\n");
  fs.writeFileSync(artifacts.loaderLib, "fixture\n");
  return artifacts;
}

test("explicit include and Loader paths take priority without a cache install", async () => {
  await withoutWebView2Environment(async () => {
    const root = temporaryDirectory();
    try {
      const artifacts = createSdk(root);
      let downloads = 0;
      const result = await build.webView2Config({ env: {
        MOONVIEW_WEBVIEW2_INCLUDE: artifacts.includeDir,
        MOONVIEW_WEBVIEW2_LOADER_LIB: artifacts.loaderLib,
      } }, {
        downloadPackage: async () => { downloads += 1; },
      });
      assert.equal(downloads, 0);
      assert.match(result.stubFlags, /build\/native\/include/);
      assert.match(result.linkFlags, /WebView2LoaderStatic\.lib/);
    } finally {
      fs.rmSync(root, { recursive: true, force: true });
    }
  });
});

test("an invalid explicit SDK fails instead of silently downloading another SDK", async () => {
  await withoutWebView2Environment(async () => {
    const root = temporaryDirectory();
    try {
      let downloads = 0;
      await assert.rejects(
        build.webView2Config({ env: { MOONVIEW_WEBVIEW2_SDK_DIR: root } }, {
          downloadPackage: async () => { downloads += 1; },
        }),
        /Invalid WebView2 SDK configuration/,
      );
      assert.equal(downloads, 0);
    } finally {
      fs.rmSync(root, { recursive: true, force: true });
    }
  });
});

test("directory lock serializes concurrent cache publishers", async () => {
  const root = temporaryDirectory();
  const lock = path.join(root, "sdk.lock");
  let active = 0;
  let maximumActive = 0;
  try {
    const action = () => build.withDirectoryLock(lock, async () => {
      active += 1;
      maximumActive = Math.max(maximumActive, active);
      await new Promise((resolve) => setTimeout(resolve, 40));
      active -= 1;
    }, { timeoutMs: 2000, staleMs: 1000, pollMs: 5 });
    await Promise.all([action(), action(), action()]);
    assert.equal(maximumActive, 1);
    assert.equal(fs.existsSync(lock), false);
  } finally {
    fs.rmSync(root, { recursive: true, force: true });
  }
});

test("a stale cache lock is reclaimed before publishing", async () => {
  const root = temporaryDirectory();
  const lock = path.join(root, "sdk.lock");
  fs.mkdirSync(lock);
  fs.writeFileSync(path.join(lock, "owner"), "abandoned\n");
  const old = new Date(Date.now() - 60_000);
  fs.utimesSync(lock, old, old);
  let ran = false;
  try {
    await build.withDirectoryLock(lock, async () => { ran = true; }, {
      timeoutMs: 1000,
      staleMs: 100,
      pollMs: 5,
    });
    assert.equal(ran, true);
    assert.equal(fs.existsSync(lock), false);
  } finally {
    fs.rmSync(root, { recursive: true, force: true });
  }
});

test("concurrent first use installs one marked SDK and removes temporary state", async () => {
  await withoutWebView2Environment(async () => {
    const root = temporaryDirectory();
    let downloads = 0;
    const config = { env: { MOONVIEW_WEBVIEW2_CACHE_DIR: root } };
    const dependencies = {
      downloadPackage: async (_url, destination) => {
        downloads += 1;
        await new Promise((resolve) => setTimeout(resolve, 40));
        fs.writeFileSync(destination, "fixture package\n");
      },
      extractPackage: (_archive, destination) => createSdk(destination),
      lockOptions: { timeoutMs: 2000, staleMs: 1000, pollMs: 5 },
    };
    try {
      const [first, second] = await Promise.all([
        build.ensureWebView2Sdk(config, "x64", dependencies),
        build.ensureWebView2Sdk(config, "x64", dependencies),
      ]);
      assert.equal(first, second);
      assert.equal(downloads, 1);
      assert.equal(build.sdkHasArtifacts(first, "x64", true), true);
      assert.deepEqual(fs.readdirSync(root), [build.WEBVIEW2_VERSION]);
    } finally {
      fs.rmSync(root, { recursive: true, force: true });
    }
  });
});

test("missing tar reports the extraction prerequisite and offline overrides", () => {
  const root = temporaryDirectory();
  const archive = path.join(root, "fixture.nupkg");
  const destination = path.join(root, "sdk");
  const previousPath = process.env.PATH;
  fs.writeFileSync(archive, "not used\n");
  process.env.PATH = "";
  try {
    assert.throws(
      () => build.extractPackage(archive, destination),
      /tar.*PATH.*MOONVIEW_WEBVIEW2_SDK_DIR.*MOONVIEW_WEBVIEW2_INCLUDE.*MOONVIEW_WEBVIEW2_LOADER_LIB/s,
    );
  } finally {
    process.env.PATH = previousPath;
    fs.rmSync(root, { recursive: true, force: true });
  }
});

test("architecture input is restricted to NuGet native Loader directories", async () => {
  await withoutWebView2Environment(async () => {
    await assert.rejects(
      build.webView2Config({ env: { MOONVIEW_WEBVIEW2_ARCH: "riscv64" } }),
      /must be x64, x86, or arm64/,
    );
  });
});

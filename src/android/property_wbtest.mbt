///|
test "quickcheck: Android asset URLs stay under the exact trusted origin" {
  @quickcheck.check(
    (input : (Int, String)) => {
      let (host_seed, path) = input
      let origin = "https://app-\{host_seed}.example.test"
      let foreign_origin = "https://app-\{host_seed}.other.test"
      let asset = origin + "/assets/" + path
      is_https_origin(origin) &&
      is_asset_url(asset, origin) &&
      !is_asset_url(foreign_origin + "/assets/" + path, origin) &&
      !is_asset_url(origin + "/asset/" + path, origin) &&
      !is_asset_url(origin + "/assets-extra/" + path, origin)
    },
    count=300,
    max_size=64,
    max_shrinks=200,
    seed=2026082711,
  )
}

///|
test "quickcheck: Android accepts only bare HTTPS authorities" {
  @quickcheck.check(
    (input : (Int, String)) => {
      let (host_seed, suffix) = input
      let host = "app-\{host_seed}.example.test"
      let origin = "https://" + host
      is_https_origin(origin) &&
      !is_https_origin("http://" + host) &&
      !is_https_origin(origin + "/assets/index.html") &&
      !is_https_origin(origin + ":443") &&
      !is_https_origin("https://user@" + host) &&
      !is_https_origin(origin + "?" + suffix) &&
      !is_https_origin(origin + "#" + suffix)
    },
    count=300,
    max_size=64,
    max_shrinks=200,
    seed=2026082712,
  )
}

///|
test "quickcheck: Android initial navigation uses the asset URL policy" {
  @quickcheck.check(
    (input : (Int, String)) => {
      let (host_seed, path) = input
      let origin = "https://app-\{host_seed}.example.test"
      let bounds = AndroidBounds::new(x=0, y=0, width=1, height=1)
      let valid = AndroidWebViewOptions::new(
        bounds~,
        trusted_origin=origin,
        initial_content=Url(origin + "/assets/" + path),
      )
      let invalid = AndroidWebViewOptions::new(
        bounds~,
        trusted_origin=origin,
        initial_content=Url(origin + "/outside/" + path),
      )
      let valid_result = validate_options(valid) == None
      let invalid_result = validate_options(invalid)
      let invalid_valid = match invalid_result {
        Some(_) => true
        None => false
      }
      valid_result && invalid_valid
    },
    count=300,
    max_size=64,
    max_shrinks=200,
    seed=2026082713,
  )
}

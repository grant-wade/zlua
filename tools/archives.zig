/// A pinned `.tar.gz` that `fetch_archive.zig` downloads and unpacks into `.zlua-deps/<dir>`.
pub const Archive = struct {
    url: []const u8,
    sha256: []const u8,
    dir: []const u8,
    /// Environment variable that overrides `url`.
    url_env: []const u8,
};

pub const deps_root = ".zlua-deps";

pub const lua: Archive = .{
    .url = "https://www.lua.org/ftp/lua-5.5.1.tar.gz",
    .sha256 = "1c4b4068d67061f2a2231ad2b5422e77acea1487ea9890f6320af614f4373dce",
    .dir = "lua-5.5.1",
    .url_env = "ZLUA_LUA_URL",
};

pub const lua_tests: Archive = .{
    .url = "https://www.lua.org/tests/lua-5.5.1-tests.tar.gz",
    .sha256 = "da07b543872dc0bb2ff12aabd0c248578d78df3eb6b67efdc537a46d455c7f31",
    .dir = "lua-5.5.1-tests",
    .url_env = "ZLUA_LUA_TESTS_URL",
};

pub const toml_test: Archive = .{
    .url = "https://github.com/toml-lang/toml-test/archive/96fd088448ec0f4d9f061c730ed7854399c46faf.tar.gz",
    .sha256 = "ff1b1ad5d50d9650789ff90552bb79bada60a040bfca1ce6d7a8a8271518c982",
    .dir = "toml-test",
    .url_env = "ZLUA_TOML_TEST_URL",
};

pub const csv_spectrum: Archive = .{
    .url = "https://github.com/maxogden/csv-spectrum/archive/d30e80f8b99d2eecb3778f1d7b9ed1cb425502ec.tar.gz",
    .sha256 = "5b8ddb407b11fc44cf363041a5372c003adc801f13078a279ba726e81850a7ed",
    .dir = "csv-spectrum",
    .url_env = "ZLUA_CSV_SPECTRUM_URL",
};

pub const msgpack_test_suite: Archive = .{
    .url = "https://github.com/kawanet/msgpack-test-suite/archive/e04f6edeaae589c768d6b70fcce80aa786b7800e.tar.gz",
    .sha256 = "88d0c5f7bde72802239970540ec4a528a2de48e48f1d26338e792d8fe77f8679",
    .dir = "msgpack-test-suite",
    .url_env = "ZLUA_MSGPACK_TEST_SUITE_URL",
};

const std = @import("std");

const lua_deps_root = ".zlua-deps";
const lua_source_root = lua_deps_root ++ "/lua-5.5.0/src";

const EmbeddingExample = struct {
    key: []const u8,
    name: []const u8,
    path: []const u8,
};

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const default_official_memory_limit_mb: u64 = if (b.graph.host.result.os.tag == .linux) 256 else 0;
    const official_memory_limit_mb = b.option(u64, "official-memory-limit-mb", "Memory cap per official-suite child process in MiB (0 disables; Linux only)") orelse default_official_memory_limit_mb;
    const official_timeout_ms = b.option(u64, "official-timeout-ms", "Timeout per official-suite child process in milliseconds (0 disables)") orelse 120_000;
    const example_filters = b.args orelse &[_][]const u8{};

    const lua_deps_step = addFetchLuaStep(b);
    const zerde_dep = b.dependency("zerde", .{
        .target = target,
        .optimize = optimize,
    });
    const zerde_mod = zerde_dep.module("zerde");

    const clua_optimize: std.builtin.OptimizeMode = .ReleaseSafe;
    const bench_optimize: std.builtin.OptimizeMode = .ReleaseFast;
    const clua_lib = addCluaLib(b, target, clua_optimize, lua_deps_step, "lua5.5-core");
    const clua_exe = addClua(b, target, clua_optimize, clua_lib);
    const clua_bench_lib = addCluaLib(b, target, bench_optimize, lua_deps_step, "lua5.5-bench");
    const clua_bench_exe = addClua(b, target, bench_optimize, clua_bench_lib);
    b.installArtifact(clua_exe);

    const mod = b.addModule("zlua", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "zerde", .module = zerde_mod }},
    });
    const zerde_bench_dep = b.dependency("zerde", .{
        .target = target,
        .optimize = bench_optimize,
    });
    const zerde_bench_mod = zerde_bench_dep.module("zerde");
    const bench_mod = b.addModule("zlua-bench-release-fast", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = bench_optimize,
        .imports = &.{.{ .name = "zerde", .module = zerde_bench_mod }},
    });
    const freestanding_target = b.resolveTargetQuery(.{
        .cpu_arch = .x86_64,
        .os_tag = .freestanding,
        .abi = .none,
    });
    const freestanding_zerde_dep = b.dependency("zerde", .{
        .target = freestanding_target,
        .optimize = optimize,
    });
    const freestanding_mod = b.addModule("zlua-freestanding", .{
        .root_source_file = b.path("src/root.zig"),
        .target = freestanding_target,
        .optimize = optimize,
        .imports = &.{.{ .name = "zerde", .module = freestanding_zerde_dep.module("zerde") }},
    });

    const exe = b.addExecutable(.{
        .name = "zlua",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{.{ .name = "zlua", .module = mod }},
        }),
    });
    b.installArtifact(exe);

    const bench_zlua_exe = b.addExecutable(.{
        .name = "zlua-bench-release-fast",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = bench_optimize,
            .imports = &.{.{ .name = "zlua", .module = bench_mod }},
        }),
    });

    const snapshot_bench_exe = b.addExecutable(.{
        .name = "zlua-bench-snapshot",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/bench_snapshot_main.zig"),
            .target = target,
            .optimize = bench_optimize,
            .imports = &.{.{ .name = "zlua", .module = bench_mod }},
        }),
    });
    b.installArtifact(snapshot_bench_exe);

    const clua_startup_bench_exe = addCStartupBench(b, target, bench_optimize, clua_bench_lib, "clua-bench-startup-c-api");

    const diff_exe = b.addExecutable(.{
        .name = "zlua-test-diff",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/test_diff_main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{.{ .name = "zlua", .module = mod }},
        }),
    });
    b.installArtifact(diff_exe);

    const extensions_exe = b.addExecutable(.{
        .name = "zlua-test-extensions",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/test_extensions_main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{.{ .name = "zlua", .module = mod }},
        }),
    });
    b.installArtifact(extensions_exe);

    const official_exe = b.addExecutable(.{
        .name = "zlua-test-official",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/test_official_main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{.{ .name = "zlua", .module = mod }},
        }),
    });
    b.installArtifact(official_exe);

    const bench_exe = b.addExecutable(.{
        .name = "zlua-test-bench",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/test_bench_main.zig"),
            .target = target,
            .optimize = bench_optimize,
            .imports = &.{.{ .name = "zlua", .module = bench_mod }},
        }),
    });
    b.installArtifact(bench_exe);

    const embedding_examples = [_]EmbeddingExample{
        .{ .key = "snapshot_adventure", .name = "zlua-embed-snapshot-adventure", .path = "examples/snapshot_adventure.zig" },
        .{ .key = "snapshot_adversarial", .name = "zlua-embed-snapshot-adversarial", .path = "examples/snapshot_adversarial.zig" },
        .{ .key = "snapshot_reset", .name = "zlua-embed-snapshot-reset", .path = "examples/snapshot_reset.zig" },
        .{ .key = "run_script", .name = "zlua-embed-run-script", .path = "examples/run_script.zig" },
        .{ .key = "select_libraries", .name = "zlua-embed-select-libraries", .path = "examples/select_libraries.zig" },
        .{ .key = "register_function", .name = "zlua-embed-register-function", .path = "examples/register_function.zig" },
        .{ .key = "typed_host_function", .name = "zlua-embed-typed-host-function", .path = "examples/typed_host_function.zig" },
        .{ .key = "plugin_sandbox", .name = "zlua-embed-plugin-sandbox", .path = "examples/plugin_sandbox.zig" },
        .{ .key = "bytecode_roundtrip", .name = "zlua-embed-bytecode-roundtrip", .path = "examples/bytecode_roundtrip.zig" },
        .{ .key = "memory_rw_files", .name = "zlua-embed-memory-rw-files", .path = "examples/memory_rw_files.zig" },
        .{ .key = "userdata_counter", .name = "zlua-embed-userdata-counter", .path = "examples/userdata_counter.zig" },
        .{ .key = "userdata_auto", .name = "zlua-embed-userdata-auto", .path = "examples/userdata_auto.zig" },
        .{ .key = "typed_userdata_initializer", .name = "zlua-embed-typed-userdata-initializer", .path = "examples/typed_userdata_initializer.zig" },
        .{ .key = "preload_module", .name = "zlua-embed-preload-module", .path = "examples/preload_module.zig" },
    };

    const examples_step = b.step("examples", "Compile and run all embedding examples, requiring exit code 0");
    const run_example_step = b.step("run-example", "Run embedding examples, or selected examples passed after --");
    for (embedding_examples) |example| {
        const example_exe = b.addExecutable(.{
            .name = example.name,
            .root_module = b.createModule(.{
                .root_source_file = b.path(example.path),
                .target = target,
                .optimize = optimize,
                .imports = &.{.{ .name = "zlua", .module = mod }},
            }),
        });
        const run_example = b.addRunArtifact(example_exe);
        // Inherit output and run on every invocation, even when compilation
        // is cached. Run treats nonzero exits and abnormal termination as errors.
        run_example.stdio = .inherit;
        examples_step.dependOn(&run_example.step);

        if (example_filters.len == 0 or exampleMatchesAny(example, example_filters)) {
            run_example_step.dependOn(&run_example.step);
        }
    }
    const run_step = b.step("run", "Run zlua");
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);
    run_step.dependOn(&run_cmd.step);

    const run_diff_step = b.step("run-test-diff", "Run CLua differential harness");
    const run_diff_cmd = b.addRunArtifact(diff_exe);
    run_diff_cmd.step.dependOn(b.getInstallStep());
    run_diff_cmd.addArg("--clua");
    run_diff_cmd.addArtifactArg(clua_exe);
    if (b.args) |args| run_diff_cmd.addArgs(args);
    run_diff_step.dependOn(&run_diff_cmd.step);

    const run_extensions_step = b.step("run-test-extensions", "Run zlua extension fixture harness");
    const run_extensions_cmd = b.addRunArtifact(extensions_exe);
    run_extensions_cmd.step.dependOn(b.getInstallStep());
    run_extensions_cmd.addArg("--zlua");
    run_extensions_cmd.addArtifactArg(exe);
    if (b.args) |args| run_extensions_cmd.addArgs(args);
    run_extensions_step.dependOn(&run_extensions_cmd.step);

    const run_official_step = b.step("run-test-official", "Run official Lua 5.5 suite harness");
    const run_official_cmd = b.addRunArtifact(official_exe);
    run_official_cmd.step.dependOn(b.getInstallStep());
    run_official_cmd.addArg("--clua");
    run_official_cmd.addArtifactArg(clua_exe);
    run_official_cmd.addArg("--zlua");
    run_official_cmd.addArtifactArg(exe);
    if (b.args) |args| run_official_cmd.addArgs(args);
    run_official_step.dependOn(&run_official_cmd.step);

    const bench_step = b.step("bench", "Run all benchmark families sequentially");
    const run_bench = b.addRunArtifact(bench_exe);
    run_bench.addArg("--clua");
    run_bench.addArtifactArg(clua_bench_exe);
    run_bench.addArg("--zlua");
    run_bench.addArtifactArg(bench_zlua_exe);
    run_bench.addArg("--zlua-snapshot");
    run_bench.addArtifactArg(snapshot_bench_exe);
    run_bench.addArg("--snapshot-build=ReleaseFast");
    run_bench.addArgs(&.{ "--zlua-build=ReleaseFast", "--clua-build=ReleaseFast" });
    run_bench.addArg("--clua-c");
    run_bench.addArtifactArg(clua_startup_bench_exe);
    run_bench.addArg("--c-build=ReleaseFast");
    if (b.args) |args| run_bench.addArgs(args);
    bench_step.dependOn(&run_bench.step);

    const test_step = b.step("test", "Run unit tests");
    if (target.result.os.tag != .freestanding) {
        const mod_tests = b.addTest(.{ .root_module = mod });
        const run_mod_tests = b.addRunArtifact(mod_tests);

        const exe_tests = b.addTest(.{ .root_module = exe.root_module });
        const run_exe_tests = b.addRunArtifact(exe_tests);

        test_step.dependOn(&run_mod_tests.step);
        test_step.dependOn(&run_exe_tests.step);
    }

    const freestanding_test_exe = b.addExecutable(.{
        .name = "zlua-test-freestanding",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/test_freestanding_main.zig"),
            .target = freestanding_target,
            .optimize = optimize,
            .imports = &.{.{ .name = "zlua", .module = freestanding_mod }},
        }),
    });
    const freestanding_test_step = b.step("test-freestanding", "Build and run x86_64 freestanding custom host smoke test");
    if (b.graph.host.result.cpu.arch == .x86_64 and b.graph.host.result.os.tag == .linux) {
        const run_freestanding_test = b.addRunArtifact(freestanding_test_exe);
        run_freestanding_test.skip_foreign_checks = true;
        freestanding_test_step.dependOn(&run_freestanding_test.step);
    } else {
        freestanding_test_step.dependOn(&freestanding_test_exe.step);
    }
    test_step.dependOn(freestanding_test_step);

    const wasm_target = b.resolveTargetQuery(.{ .cpu_arch = .wasm32, .os_tag = .freestanding });
    const wasm_zerde = b.dependency("zerde", .{ .target = wasm_target, .optimize = optimize });
    const wasm_mod = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = wasm_target,
        .optimize = optimize,
        .imports = &.{.{ .name = "zerde", .module = wasm_zerde.module("zerde") }},
    });
    const wasm_test = b.addExecutable(.{
        .name = "zlua-test-wasm",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/test_freestanding_main.zig"),
            .target = wasm_target,
            .optimize = optimize,
            .imports = &.{.{ .name = "zlua", .module = wasm_mod }},
        }),
    });
    wasm_test.entry = .disabled;
    wasm_test.rdynamic = true;
    wasm_test.stack_size = 4 * 1024 * 1024;
    test_step.dependOn(&wasm_test.step);
    const run_wasm_test = b.addSystemCommand(&.{
        "node",
        "-e",
        \\WebAssembly.instantiate(require('node:fs').readFileSync(process.argv[1]), {})
        \\  .then(({instance}) => { require('node:assert/strict').equal(instance.exports.smoke(), 1); })
        \\  .catch(error => { console.error(error); process.exitCode = 1; });
    });
    run_wasm_test.addArtifactArg(wasm_test);
    b.step("test-wasm", "Run the freestanding smoke test in wasm32 (Node.js)").dependOn(&run_wasm_test.step);

    const diff_step = b.step("test-diff", "Run CLua differential tests");
    const diff_cmd = b.addRunArtifact(diff_exe);
    diff_cmd.step.dependOn(b.getInstallStep());
    diff_cmd.addArg("--clua");
    diff_cmd.addArtifactArg(clua_exe);
    diff_step.dependOn(&diff_cmd.step);

    const extensions_step = b.step("test-extensions", "Run zlua extension tests");
    const extensions_cmd = b.addRunArtifact(extensions_exe);
    extensions_cmd.step.dependOn(b.getInstallStep());
    extensions_cmd.addArg("--zlua");
    extensions_cmd.addArtifactArg(exe);
    if (b.args) |args| extensions_cmd.addArgs(args);
    extensions_step.dependOn(&extensions_cmd.step);

    const official_step = b.step("test-official", "Run full official Lua 5.5 suite dashboard under a memory cap");
    const official_cmd = b.addRunArtifact(official_exe);
    official_cmd.step.dependOn(b.getInstallStep());
    official_cmd.addArg("--clua");
    official_cmd.addArtifactArg(clua_exe);
    official_cmd.addArg("--zlua");
    official_cmd.addArtifactArg(exe);
    official_cmd.addArg(b.fmt("--timeout-ms={d}", .{official_timeout_ms}));
    if (official_memory_limit_mb != 0) {
        official_cmd.addArg(b.fmt("--memory-limit-mb={d}", .{official_memory_limit_mb}));
    }
    official_step.dependOn(&official_cmd.step);

    const ci_step = b.step("ci", "Run CI checks");
    ci_step.dependOn(test_step);
    ci_step.dependOn(examples_step);
    ci_step.dependOn(extensions_step);
    ci_step.dependOn(diff_step);
    ci_step.dependOn(official_step);

    const docs_lib = b.addLibrary(.{
        .name = "zlua",
        .root_module = mod,
    });
    const install_docs = b.addInstallDirectory(.{
        .source_dir = docs_lib.getEmittedDocs(),
        .install_dir = .prefix,
        .install_subdir = "docs",
    });

    const docs_step = b.step("docs", "Generate project documentation");
    docs_step.dependOn(&install_docs.step);

    const md_docgen = b.addExecutable(.{
        .name = "zig-md-docs",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tools/zig-md-docs.zig"),
            .target = b.graph.host,
            .optimize = optimize,
        }),
    });
    const run_md_docgen = b.addRunArtifact(md_docgen);
    run_md_docgen.addArgs(&.{
        "--root",         "src/root.zig",
        "--out",          "docs/api",
        "--project-root", ".",
        "--name",         "zlua",
        "--emit-index",   "--follow-imports",
    });

    const docs_md_step = b.step("docs-md", "Generate Markdown API documentation");
    docs_md_step.dependOn(&run_md_docgen.step);

    const doc_server = b.addExecutable(.{
        .name = "doc-server",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tools/doc_server.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    const run_doc_server = b.addRunArtifact(doc_server);
    run_doc_server.step.dependOn(&install_docs.step);
    if (b.args) |args| run_doc_server.addArgs(args);

    const doc_serve_step = b.step("docs-serve", "Generate docs and serve zig-out/docs over HTTP");
    doc_serve_step.dependOn(&run_doc_server.step);
}

fn addFetchLuaStep(b: *std.Build) *std.Build.Step {
    const fetch_cmd = b.addSystemCommand(&.{ "sh", "tools/fetch-lua.sh", lua_deps_root });
    const fetch_step = b.step("fetch-lua", "Download and extract Lua 5.5 source and official tests");
    fetch_step.dependOn(&fetch_cmd.step);
    return fetch_step;
}

fn addClua(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    clua_lib: *std.Build.Step.Compile,
) *std.Build.Step.Compile {
    const clua_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    clua_mod.addCSourceFiles(.{
        .root = b.path(lua_source_root),
        .files = &.{"lua.c"},
        .flags = cluaCFlags(target),
    });
    clua_mod.linkLibrary(clua_lib);

    const exe = b.addExecutable(.{
        .name = "lua5.5",
        .root_module = clua_mod,
    });
    exe.step.dependOn(&clua_lib.step);
    return exe;
}

fn addCluaLib(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    lua_deps_step: *std.Build.Step,
    name: []const u8,
) *std.Build.Step.Compile {
    const lua_sources = [_][]const u8{
        "lapi.c",
        "lauxlib.c",
        "lbaselib.c",
        "lcode.c",
        "lcorolib.c",
        "lctype.c",
        "ldblib.c",
        "ldebug.c",
        "ldo.c",
        "ldump.c",
        "lfunc.c",
        "lgc.c",
        "linit.c",
        "liolib.c",
        "llex.c",
        "lmathlib.c",
        "lmem.c",
        "loadlib.c",
        "lobject.c",
        "lopcodes.c",
        "loslib.c",
        "lparser.c",
        "lstate.c",
        "lstring.c",
        "lstrlib.c",
        "ltable.c",
        "ltablib.c",
        "ltm.c",
        "lundump.c",
        "lutf8lib.c",
        "lvm.c",
        "lzio.c",
    };

    const clua_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    clua_mod.addCSourceFiles(.{
        .root = b.path(lua_source_root),
        .files = &lua_sources,
        .flags = cluaCFlags(target),
    });
    if (target.result.os.tag != .windows) {
        clua_mod.linkSystemLibrary("m", .{});
    }
    if (target.result.os.tag == .linux) {
        clua_mod.linkSystemLibrary("dl", .{});
    }

    const lib = b.addLibrary(.{
        .name = name,
        .linkage = .static,
        .root_module = clua_mod,
    });
    lib.step.dependOn(lua_deps_step);
    return lib;
}

fn addCStartupBench(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    library: *std.Build.Step.Compile,
    name: []const u8,
) *std.Build.Step.Compile {
    const module = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    module.addIncludePath(b.path(lua_source_root));
    module.addCSourceFile(.{
        .file = b.path("tools/bench_c_api_startup.c"),
        .flags = &.{"-std=c11"},
    });
    module.linkLibrary(library);
    if (target.result.os.tag != .windows) module.linkSystemLibrary("m", .{});
    if (target.result.os.tag == .linux) module.linkSystemLibrary("dl", .{});
    return b.addExecutable(.{ .name = name, .root_module = module });
}

fn cluaCFlags(target: std.Build.ResolvedTarget) []const []const u8 {
    return switch (target.result.os.tag) {
        .linux => &.{ "-std=gnu99", "-DLUA_USE_LINUX" },
        .macos, .freebsd, .netbsd, .openbsd, .dragonfly, .illumos => &.{ "-std=gnu99", "-DLUA_USE_POSIX" },
        else => &.{"-std=gnu99"},
    };
}

fn exampleMatches(example: EmbeddingExample, filter: []const u8) bool {
    if (std.mem.eql(u8, filter, example.key)) return true;
    if (std.mem.eql(u8, filter, example.name)) return true;
    if (std.mem.eql(u8, filter, example.path)) return true;

    const basename = std.fs.path.basename(example.path);
    if (std.mem.eql(u8, filter, basename)) return true;
    if (std.mem.endsWith(u8, basename, ".zig")) {
        return std.mem.eql(u8, filter, basename[0 .. basename.len - ".zig".len]);
    }
    return false;
}

fn exampleMatchesAny(example: EmbeddingExample, filters: []const []const u8) bool {
    for (filters) |filter| {
        if (exampleMatches(example, filter)) return true;
    }
    return false;
}

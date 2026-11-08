#!/bin/sh
set -eu

root=${1:-.zlua-deps}
version=5.5.1

lua_url=${ZLUA_LUA_URL:-https://www.lua.org/ftp/lua-${version}.tar.gz}
tests_url=${ZLUA_LUA_TESTS_URL:-https://www.lua.org/tests/lua-${version}-tests.tar.gz}

lua_sha=1c4b4068d67061f2a2231ad2b5422e77acea1487ea9890f6320af614f4373dce
tests_sha=da07b543872dc0bb2ff12aabd0c248578d78df3eb6b67efdc537a46d455c7f31

lua_archive=${root}/lua-${version}.tar.gz
tests_archive=${root}/lua-${version}-tests.tar.gz
lua_dir=${root}/lua-${version}
tests_dir=${root}/lua-${version}-tests

mkdir -p "$root"

sha256_file() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | awk '{print $1}'
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$1" | awk '{print $1}'
    else
        echo "fetch-lua: need sha256sum or shasum" >&2
        exit 1
    fi
}

download() {
    url=$1
    path=$2
    if [ -f "$path" ]; then
        return
    fi

    tmp=${path}.tmp
    rm -f "$tmp"
    if command -v curl >/dev/null 2>&1; then
        curl -L --fail --output "$tmp" "$url"
    elif command -v wget >/dev/null 2>&1; then
        wget -O "$tmp" "$url"
    elif command -v fetch >/dev/null 2>&1; then
        fetch -o "$tmp" "$url"
    else
        echo "fetch-lua: need curl, wget, or fetch" >&2
        exit 1
    fi
    mv "$tmp" "$path"
}

verify() {
    path=$1
    expected=$2
    actual=$(sha256_file "$path")
    if [ "$actual" != "$expected" ]; then
        echo "fetch-lua: checksum mismatch for $path" >&2
        echo "  expected: $expected" >&2
        echo "  actual:   $actual" >&2
        exit 1
    fi
}

download "$lua_url" "$lua_archive"
download "$tests_url" "$tests_archive"

verify "$lua_archive" "$lua_sha"
verify "$tests_archive" "$tests_sha"

if [ ! -f "$lua_dir/src/lua.h" ]; then
    rm -rf "$lua_dir"
    tar -xzf "$lua_archive" -C "$root"
fi

if [ ! -f "$tests_dir/all.lua" ]; then
    rm -rf "$tests_dir"
    tar -xzf "$tests_archive" -C "$root"
fi

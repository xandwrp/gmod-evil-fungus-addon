set positional-arguments

default:
    @just --list

# syntax check and lint every lua file
test: check lint

# parse every lua file the way gmod's luajit does
check:
    @lua5.1 tools/syntax_check.lua $(find lua -name '*.lua')

# lint against the gmod api: undefined globals, typos, unused and shadowed locals
lint *args:
    @luacheck lua "$@"

# rebuild tools/gmod_std.lua from the latest gmod wiki dump
gmod-std:
    #!/usr/bin/env bash
    set -euo pipefail
    tmp=$(mktemp -d)
    trap 'rm -rf "$tmp"' EXIT
    gh release download -R luttje/glua-api-snippets -p '*.lua.zip' -D "$tmp"
    unzip -q "$tmp"/*.lua.zip -d "$tmp/api"
    uv run tools/gmod_std.py "$tmp/api" tools/gmod_std.lua

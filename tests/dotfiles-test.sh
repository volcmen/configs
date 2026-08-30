#!/usr/bin/env bash
set -u

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
TEST_TMP=""
PASS_COUNT=0
FAIL_COUNT=0
CLI_STATUS=0
CLI_OUTPUT=""
SELECTED_TESTS=("$@")

cleanup() {
    if [[ -n "$TEST_TMP" && -d "$TEST_TMP" ]]; then
        rm -rf -- "$TEST_TMP"
    fi
}
trap cleanup EXIT INT TERM

fail() { printf 'FAIL: %s\n' "$*" >&2; return 1; }
assert_status() { [[ "$CLI_STATUS" -eq "$1" ]] || fail "status $CLI_STATUS != $1; output: $CLI_OUTPUT"; }
assert_contains() { [[ "$CLI_OUTPUT" == *"$1"* ]] || fail "missing <$1>; output: $CLI_OUTPUT"; }
assert_not_exists() { [[ ! -e "$1" && ! -L "$1" ]] || fail "unexpected path: $1"; }

new_fixture() {
    cleanup
    TEST_TMP="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-test.XXXXXX")"
    TEST_TMP="$(cd "$TEST_TMP" && pwd -P)"
    mkdir -p "$TEST_TMP/repo/bin" "$TEST_TMP/repo/home" "$TEST_TMP/home"
    cp "$PROJECT_ROOT/bin/dotfiles" "$TEST_TMP/repo/bin/dotfiles"
    chmod +x "$TEST_TMP/repo/bin/dotfiles"
}

run_cli() {
    local test_uname="${DOTFILES_TEST_UNAME:-Darwin}"
    local test_os_release="${DOTFILES_TEST_OS_RELEASE:-$TEST_TMP/os-release}"
    if CLI_OUTPUT="$(DOTFILES_TESTING=1 \
        DOTFILES_TEST_HOME="$TEST_TMP/home" \
        DOTFILES_TEST_STATE="${DOTFILES_TEST_STATE:-$TEST_TMP/state}" \
        DOTFILES_TEST_UNAME="$test_uname" \
        DOTFILES_TEST_OS_RELEASE="$test_os_release" \
        DOTFILES_TEST_FAIL_AFTER="${DOTFILES_TEST_FAIL_AFTER:-}" \
        DOTFILES_TEST_INSTALL_HOOK="${DOTFILES_TEST_INSTALL_HOOK:-}" \
        PATH="${DOTFILES_TEST_PATH:-$PATH}" \
        "$TEST_TMP/repo/bin/dotfiles" "$@" 2>&1)"; then
        CLI_STATUS=0
    else
        CLI_STATUS=$?
    fi
}

write_os_release() {
    printf '%s\n' "$1" >"$TEST_TMP/os-release"
}

write_manifest() {
    printf '%s\n' "$1" >"$TEST_TMP/repo/dotfiles.manifest"
}

run_detect() {
    if CLI_OUTPUT="$(DOTFILES_TESTING=1 \
        DOTFILES_TEST_HOME="$TEST_TMP/home" \
        DOTFILES_TEST_UNAME="$1" \
        DOTFILES_TEST_OS_RELEASE="$TEST_TMP/os-release" \
        DOTFILES_TARGET="${2:-}" \
        "$TEST_TMP/repo/bin/dotfiles" detect 2>&1)"; then
        CLI_STATUS=0
    else
        CLI_STATUS=$?
    fi
}

run_test() {
    local name=$1 selected selected_name
    if [[ ${#SELECTED_TESTS[@]} -gt 0 ]]; then
        selected=0
        for selected_name in "${SELECTED_TESTS[@]}"; do
            [[ "$selected_name" == "$name" ]] && selected=1
        done
        [[ $selected -eq 1 ]] || return 0
    fi
    if "$name"; then
        PASS_COUNT=$((PASS_COUNT + 1))
        printf 'ok - %s\n' "$name"
    else
        FAIL_COUNT=$((FAIL_COUNT + 1))
        printf 'not ok - %s\n' "$name"
    fi
}

test_help() {
    new_fixture
    run_cli help
    assert_status 0 && assert_contains 'Usage: dotfiles'
}

test_unknown_command_fails() {
    new_fixture
    run_cli explode
    assert_status 64 && assert_contains 'unknown command: explode'
}

test_detects_macos_and_ignores_target() {
    new_fixture; write_os_release 'ID=arch'; run_detect Darwin arch
    assert_status 0 && [[ "$CLI_OUTPUT" == macos ]]
}

test_detects_exact_arch() {
    new_fixture; write_os_release 'ID="arch"'; run_detect Linux
    assert_status 0 && [[ "$CLI_OUTPUT" == arch ]]
}

test_rejects_arch_derivative_and_other_linux() {
    new_fixture; write_os_release $'ID=manjaro\nID_LIKE=arch'; run_detect Linux
    assert_status 69 && assert_contains 'unsupported host'
}

test_manifest_accepts_valid_row() {
    new_fixture
    mkdir -p "$TEST_TMP/repo/home/.config/fish"
    : >"$TEST_TMP/repo/home/.config/fish/config.fish"
    write_manifest 'fish|macos,arch|file|.config/fish/config.fish|fish|yes|4.8.1'
    run_cli check --target macos
    [[ "$CLI_STATUS" -ne 65 ]] || fail "$CLI_OUTPUT"
}

test_manifest_rejects_bad_columns_absolute_traversal_and_duplicate() {
    local content
    for content in \
        'fish|macos|file|.config/fish/config.fish|fish|yes' \
        'fish|macos|file|/etc/passwd|plain|yes|1' \
        'fish|macos|file|.config/../passwd|plain|yes|1' \
        $'a|macos|file|.config/a|plain|yes|1\nb|arch|file|.config/a|plain|yes|1'
    do
        new_fixture; write_manifest "$content"; run_cli check --target macos
        assert_status 65 && assert_contains 'manifest line' || return 1
    done
}

test_manifest_rejects_unknown_platform() {
    new_fixture; write_manifest 'fish|linux|file|.config/fish/config.fish|fish|yes|4.8.1'
    run_cli check --target macos
    assert_status 65 && assert_contains 'manifest line 1'
}

test_manifest_rejects_unknown_kind() {
    new_fixture; write_manifest 'fish|macos|directory|.config/fish/config.fish|fish|yes|4.8.1'
    run_cli check --target macos
    assert_status 65 && assert_contains 'manifest line 1'
}

test_manifest_rejects_unknown_validator() {
    new_fixture; write_manifest 'fish|macos|file|.config/fish/config.fish|unknown|yes|4.8.1'
    run_cli check --target macos
    assert_status 65 && assert_contains 'manifest line 1'
}

test_manifest_rejects_unknown_required_value() {
    new_fixture; write_manifest 'fish|macos|file|.config/fish/config.fish|fish|maybe|4.8.1'
    run_cli check --target macos
    assert_status 65 && assert_contains 'manifest line 1'
}

test_check_blocks_malformed_files_with_available_validators() {
    local validator_bin
    new_fixture
    validator_bin="$TEST_TMP/validator-bin"
    mkdir -p "$validator_bin" "$TEST_TMP/repo/home/.config/demo"
    printf 'if then\n' >"$TEST_TMP/repo/home/.config/demo/bad.sh"
    printf 'malformed\n' >"$TEST_TMP/repo/home/.config/demo/bad.fish"
    printf 'malformed\n' >"$TEST_TMP/repo/home/.config/demo/bad.gitconfig"
    printf 'malformed\n' >"$TEST_TMP/repo/home/.config/demo/bad.xml"
    printf 'malformed\n' >"$TEST_TMP/repo/home/.config/demo/bad.lua"
    printf 'malformed\n' >"$TEST_TMP/repo/home/.config/demo/bad.jsonc"
    write_manifest $'shell-app|macos|file|.config/demo/bad.sh|shell|yes|1\nfish-app|macos|file|.config/demo/bad.fish|fish|yes|1\ngit-app|macos|file|.config/demo/bad.gitconfig|git|yes|1\nxml-app|macos|file|.config/demo/bad.xml|xml|yes|1\nlua-app|macos|file|.config/demo/bad.lua|lua|yes|1\njson-app|macos|file|.config/demo/bad.jsonc|jsonc|yes|1'
    for command in fish git xmllint luac bun; do
        cat >"$validator_bin/$command" <<STUB
#!/bin/sh
case "${command}" in
    git) file=\$3 ;;
    *) for argument do file=\$argument; done ;;
esac
printf '%s %s\\n' "${command}" "\$*" >>"$TEST_TMP/validator-args"
if /usr/bin/grep -q malformed "\$file"; then exit 9; fi
exit 0
STUB
        chmod +x "$validator_bin/$command"
    done
    DOTFILES_TEST_PATH="$validator_bin:/usr/bin:/bin" run_cli check --target macos
    assert_status 1 && \
        assert_contains 'BLOCKED shell-app .config/demo/bad.sh:' && \
        assert_contains 'BLOCKED fish-app .config/demo/bad.fish:' && \
        assert_contains 'BLOCKED git-app .config/demo/bad.gitconfig:' && \
        assert_contains 'BLOCKED xml-app .config/demo/bad.xml:' && \
        assert_contains 'BLOCKED lua-app .config/demo/bad.lua:' && \
        assert_contains 'BLOCKED json-app .config/demo/bad.jsonc:' && \
        [[ "$(wc -l <"$TEST_TMP/validator-args")" -eq 5 ]]
}

test_check_passes_valid_file() {
    new_fixture
    mkdir -p "$TEST_TMP/repo/home/.config/demo"
    printf 'true\n' >"$TEST_TMP/repo/home/.config/demo/good.sh"
    write_manifest 'shell-app|macos|file|.config/demo/good.sh|shell|yes|1'
    run_cli check --target macos
    assert_status 0 && assert_contains 'PASS shell-app .config/demo/good.sh:'
}

test_check_marks_missing_native_validator_runtime_unverified() {
    new_fixture
    mkdir -p "$TEST_TMP/repo/home/.config/demo"
    printf 'set -g demo true\n' >"$TEST_TMP/repo/home/.config/demo/config.fish"
    write_manifest 'fish-app|macos|file|.config/demo/config.fish|fish|yes|1'
    DOTFILES_TEST_PATH='/usr/bin:/bin' run_cli check --target macos
    assert_status 0 && \
        assert_contains 'RUNTIME UNVERIFIED fish-app .config/demo/config.fish:' && \
        [[ "$CLI_OUTPUT" != *'PASS fish-app .config/demo/config.fish:'* ]]
}

test_check_marks_arch_hyprland_static_only_on_macos() {
    local validator_bin
    new_fixture
    validator_bin="$TEST_TMP/validator-bin"
    mkdir -p "$validator_bin" "$TEST_TMP/repo/home/.config/hypr"
    printf 'return {}\n' >"$TEST_TMP/repo/home/.config/hypr/hyprland.lua"
    write_manifest 'hyprland|arch|file|.config/hypr/hyprland.lua|hyprland-lua|yes|1'
    cat >"$validator_bin/luac" <<'STUB'
#!/bin/sh
exit 0
STUB
    chmod +x "$validator_bin/luac"
    DOTFILES_TEST_PATH="$validator_bin:/usr/bin:/bin" run_cli check --target arch
    assert_status 0 && \
        assert_contains 'STATIC PASS hyprland .config/hypr/hyprland.lua:' && \
        assert_contains 'RUNTIME UNVERIFIED hyprland .config/hypr/hyprland.lua: requires an Arch Hyprland session'
}

test_check_caches_clean_hyprland_runtime_probe() {
    local validator_bin
    new_fixture
    validator_bin="$TEST_TMP/validator-bin"
    mkdir -p "$validator_bin" "$TEST_TMP/repo/home/.config/hypr"
    printf 'return {}\n' >"$TEST_TMP/repo/home/.config/hypr/one.lua"
    printf 'return {}\n' >"$TEST_TMP/repo/home/.config/hypr/two.lua"
    printf 'return {}\n' >"$TEST_TMP/repo/home/.config/hypr/three.lua"
    write_os_release 'ID=arch'
    write_manifest $'hyprland|arch|file|.config/hypr/one.lua|hyprland-lua|yes|1\nhyprland|arch|file|.config/hypr/two.lua|hyprland-lua|yes|1\nhyprland|arch|file|.config/hypr/three.lua|hyprland-lua|yes|1'
    cat >"$validator_bin/luac" <<'STUB'
#!/bin/sh
exit 0
STUB
    cat >"$validator_bin/hyprctl" <<STUB
#!/bin/sh
printf '%s\\n' "\$*" >>"$TEST_TMP/hyprctl-calls"
exit 0
STUB
    chmod +x "$validator_bin/luac" "$validator_bin/hyprctl"
    DOTFILES_TEST_UNAME=Linux DOTFILES_TEST_OS_RELEASE="$TEST_TMP/os-release" DOTFILES_TEST_PATH="$validator_bin:/usr/bin:/bin" HYPRLAND_INSTANCE_SIGNATURE=active run_cli check --target arch
    assert_status 0 && \
        [[ "$(wc -l <"$TEST_TMP/hyprctl-calls")" -eq 1 ]] && \
        [[ "$(printf '%s\n' "$CLI_OUTPUT" | /usr/bin/grep -c 'Hyprland runtime validation passed')" -eq 3 ]]
}

test_check_blocks_hyprland_runtime_error_text_with_success_status() {
    local validator_bin
    new_fixture
    validator_bin="$TEST_TMP/validator-bin"
    mkdir -p "$validator_bin" "$TEST_TMP/repo/home/.config/hypr"
    printf 'return {}\n' >"$TEST_TMP/repo/home/.config/hypr/one.lua"
    printf 'return {}\n' >"$TEST_TMP/repo/home/.config/hypr/two.lua"
    printf 'return {}\n' >"$TEST_TMP/repo/home/.config/hypr/three.lua"
    write_os_release 'ID=arch'
    write_manifest $'hyprland|arch|file|.config/hypr/one.lua|hyprland-lua|yes|1\nhyprland|arch|file|.config/hypr/two.lua|hyprland-lua|yes|1\nhyprland|arch|file|.config/hypr/three.lua|hyprland-lua|yes|1'
    cat >"$validator_bin/luac" <<'STUB'
#!/bin/sh
exit 0
STUB
    cat >"$validator_bin/hyprctl" <<STUB
#!/bin/sh
printf '%s\\n' "\$*" >>"$TEST_TMP/hyprctl-calls"
printf 'Config error: invalid monitor rule\\n'
exit 0
STUB
    chmod +x "$validator_bin/luac" "$validator_bin/hyprctl"
    DOTFILES_TEST_UNAME=Linux DOTFILES_TEST_OS_RELEASE="$TEST_TMP/os-release" DOTFILES_TEST_PATH="$validator_bin:/usr/bin:/bin" HYPRLAND_INSTANCE_SIGNATURE=active run_cli check --target arch
    assert_status 1 && \
        [[ "$(wc -l <"$TEST_TMP/hyprctl-calls")" -eq 1 ]] && \
        [[ "$(printf '%s\n' "$CLI_OUTPUT" | /usr/bin/grep -c '^BLOCKED hyprland')" -eq 3 ]] && \
        assert_contains 'Config error: invalid monitor rule'
}

test_check_blocks_newline_only_hyprland_runtime_output() {
    local validator_bin
    new_fixture
    validator_bin="$TEST_TMP/validator-bin"
    mkdir -p "$validator_bin" "$TEST_TMP/repo/home/.config/hypr"
    printf 'return {}\n' >"$TEST_TMP/repo/home/.config/hypr/one.lua"
    write_os_release 'ID=arch'
    write_manifest 'hyprland|arch|file|.config/hypr/one.lua|hyprland-lua|yes|1'
    cat >"$validator_bin/luac" <<'STUB'
#!/bin/sh
exit 0
STUB
    cat >"$validator_bin/hyprctl" <<STUB
#!/bin/sh
printf '%s\\n' "\$*" >>"$TEST_TMP/hyprctl-calls"
printf '\\n'
exit 0
STUB
    chmod +x "$validator_bin/luac" "$validator_bin/hyprctl"
    DOTFILES_TEST_UNAME=Linux DOTFILES_TEST_OS_RELEASE="$TEST_TMP/os-release" DOTFILES_TEST_PATH="$validator_bin:/usr/bin:/bin" HYPRLAND_INSTANCE_SIGNATURE=active run_cli check --target arch
    assert_status 1 && \
        [[ "$(wc -l <"$TEST_TMP/hyprctl-calls")" -eq 1 ]] && \
        assert_contains 'BLOCKED hyprland .config/hypr/one.lua: validator reported diagnostic output'
}

test_check_blocks_nul_only_hyprland_runtime_output() {
    local validator_bin
    new_fixture
    validator_bin="$TEST_TMP/validator-bin"
    mkdir -p "$validator_bin" "$TEST_TMP/repo/home/.config/hypr"
    printf 'return {}\n' >"$TEST_TMP/repo/home/.config/hypr/one.lua"
    write_os_release 'ID=arch'
    write_manifest 'hyprland|arch|file|.config/hypr/one.lua|hyprland-lua|yes|1'
    cat >"$validator_bin/luac" <<'STUB'
#!/bin/sh
exit 0
STUB
    cat >"$validator_bin/hyprctl" <<STUB
#!/bin/sh
printf '%s\\n' "\$*" >>"$TEST_TMP/hyprctl-calls"
printf '\\000'
exit 0
STUB
    chmod +x "$validator_bin/luac" "$validator_bin/hyprctl"
    DOTFILES_TEST_UNAME=Linux DOTFILES_TEST_OS_RELEASE="$TEST_TMP/os-release" DOTFILES_TEST_PATH="$validator_bin:/usr/bin:/bin" HYPRLAND_INSTANCE_SIGNATURE=active run_cli check --target arch
    assert_status 1 && \
        [[ "$(wc -l <"$TEST_TMP/hyprctl-calls")" -eq 1 ]] && \
        assert_contains 'BLOCKED hyprland .config/hypr/one.lua: validator reported diagnostic output'
}

test_check_sanitizes_validator_control_diagnostics() {
    local validator_bin
    new_fixture
    validator_bin="$TEST_TMP/validator-bin"
    mkdir -p "$validator_bin" "$TEST_TMP/repo/home/.config/demo"
    printf 'malformed\n' >"$TEST_TMP/repo/home/.config/demo/config.fish"
    write_manifest 'fish-app|macos|file|.config/demo/config.fish|fish|yes|1'
    cat >"$validator_bin/fish" <<'STUB'
#!/bin/sh
printf 'useful diagnostic \033[31mwith control\001\007\n' >&2
exit 9
STUB
    chmod +x "$validator_bin/fish"
    DOTFILES_TEST_PATH="$validator_bin:/usr/bin:/bin" run_cli check --target macos
    assert_status 1 && \
        assert_contains 'useful diagnostic' && \
        [[ "$CLI_OUTPUT" != *$'\033'* && "$CLI_OUTPUT" != *$'\001'* && "$CLI_OUTPUT" != *$'\007'* ]] && \
        ! LC_ALL=C /usr/bin/printf '%s' "$CLI_OUTPUT" | /usr/bin/grep -q '[[:cntrl:]]'
}

test_check_never_executes_manifest_validator_text() {
    new_fixture
    mkdir -p "$TEST_TMP/repo/home/.config/demo"
    printf 'safe\n' >"$TEST_TMP/repo/home/.config/demo/config"
    write_manifest "demo|macos|file|.config/demo/config|plain;touch $TEST_TMP/manifest-executed|yes|1"
    run_cli check --target macos
    assert_status 65 && \
        assert_contains 'unknown validator' && \
        assert_not_exists "$TEST_TMP/manifest-executed"
}

test_diff_classifies_every_target_state() {
    local linked_source
    new_fixture
    mkdir -p "$TEST_TMP/repo/home/.config/demo" "$TEST_TMP/home/.config/demo"
    printf 'canonical\n' >"$TEST_TMP/repo/home/.config/demo/missing"
    printf 'canonical\n' >"$TEST_TMP/repo/home/.config/demo/match"
    printf 'canonical\n' >"$TEST_TMP/repo/home/.config/demo/drift"
    printf 'canonical\n' >"$TEST_TMP/repo/home/.config/demo/linked"
    printf 'canonical\n' >"$TEST_TMP/repo/home/.config/demo/foreign"
    printf 'canonical\n' >"$TEST_TMP/repo/home/.config/demo/conflict"
    printf 'foreign\n' >"$TEST_TMP/home/.config/demo/not-managed"
    write_manifest $'demo|macos|file|.config/demo/missing|plain|yes|1\ndemo|macos|file|.config/demo/match|plain|yes|1\ndemo|macos|file|.config/demo/drift|plain|yes|1\ndemo|macos|file|.config/demo/linked|plain|yes|1\ndemo|macos|file|.config/demo/foreign|plain|yes|1\ndemo|macos|file|.config/demo/conflict|plain|yes|1'
    printf 'canonical\n' >"$TEST_TMP/home/.config/demo/match"
    printf 'different\n' >"$TEST_TMP/home/.config/demo/drift"
    linked_source="$(cd "$TEST_TMP/repo/home/.config/demo" && pwd -P)/linked"
    ln -s "$linked_source" "$TEST_TMP/home/.config/demo/linked"
    ln -s "$TEST_TMP/home/.config/demo/not-managed" "$TEST_TMP/home/.config/demo/foreign"
    mkdir "$TEST_TMP/home/.config/demo/conflict"
    run_cli diff
    assert_status 1 && \
        assert_contains 'MISSING demo .config/demo/missing' && \
        assert_contains 'MATCH demo .config/demo/match' && \
        assert_contains 'DRIFT demo .config/demo/drift' && \
        assert_contains 'LINKED demo .config/demo/linked' && \
        assert_contains 'FOREIGN_LINK demo .config/demo/foreign' && \
        assert_contains 'TYPE_CONFLICT demo .config/demo/conflict' && \
        assert_contains '@@'
}

test_diff_never_prints_binary_drift() {
    new_fixture
    mkdir -p "$TEST_TMP/repo/home/.config/demo" "$TEST_TMP/home/.config/demo"
    printf 'canonical\000' >"$TEST_TMP/repo/home/.config/demo/binary"
    printf 'different\000' >"$TEST_TMP/home/.config/demo/binary"
    write_manifest 'demo|macos|file|.config/demo/binary|plain|yes|1'
    run_cli diff
    assert_status 1 && assert_contains 'DRIFT demo .config/demo/binary' && [[ "$CLI_OUTPUT" != *'canonical'* ]] && [[ "$CLI_OUTPUT" != *'different'* ]]
}

test_diff_never_prints_non_nul_binary_drift() {
    new_fixture
    mkdir -p "$TEST_TMP/repo/home/.config/demo" "$TEST_TMP/home/.config/demo"
    printf 'source-payload\001\002\377\n' >"$TEST_TMP/repo/home/.config/demo/binary"
    printf 'target-payload\001\002\377\n' >"$TEST_TMP/home/.config/demo/binary"
    write_manifest 'demo|macos|file|.config/demo/binary|plain|yes|1'
    run_cli diff
    assert_status 1 && \
        assert_contains 'DRIFT demo .config/demo/binary' && \
        [[ "$CLI_OUTPUT" != *'source-payload'* ]] && \
        [[ "$CLI_OUTPUT" != *'target-payload'* ]] && \
        [[ "$CLI_OUTPUT" != *'@@'* ]] && \
        [[ "$CLI_OUTPUT" != *'--- '* ]]
}

test_diff_prints_text_drift_at_hex_byte_boundary() {
    new_fixture
    mkdir -p "$TEST_TMP/repo/home/.config/demo" "$TEST_TMP/home/.config/demo"
    printf '0\n' >"$TEST_TMP/repo/home/.config/demo/text"
    printf '1\n' >"$TEST_TMP/home/.config/demo/text"
    write_manifest 'demo|macos|file|.config/demo/text|plain|yes|1'
    run_cli diff
    assert_status 1 && assert_contains 'DRIFT demo .config/demo/text' && assert_contains '@@'
}

test_diff_refuses_cross_platform_live_home() {
    new_fixture
    mkdir -p "$TEST_TMP/repo/home/.config/demo"
    printf 'canonical\n' >"$TEST_TMP/repo/home/.config/demo/config"
    write_manifest 'demo|arch|file|.config/demo/config|plain|yes|1'
    DOTFILES_TARGET=arch run_cli diff
    assert_status 64 && assert_contains 'requires --staging-home' || return 1
    assert_not_exists "$TEST_TMP/home/.config/demo/config"
}

test_diff_allows_read_only_cross_platform_staging() {
    new_fixture
    mkdir -p "$TEST_TMP/repo/home/.config/demo" "$TEST_TMP/staging"
    printf 'canonical\n' >"$TEST_TMP/repo/home/.config/demo/config"
    write_manifest 'demo|arch|file|.config/demo/config|plain|yes|1'
    run_cli diff --target arch --staging-home "$TEST_TMP/staging"
    assert_status 1 && assert_contains 'MISSING demo .config/demo/config' || return 1
    assert_not_exists "$TEST_TMP/staging/.config/demo/config"
}

test_diff_rejects_live_home_as_cross_platform_staging() {
    local alias_home
    new_fixture
    mkdir -p "$TEST_TMP/repo/home/.config/demo"
    printf 'canonical\n' >"$TEST_TMP/repo/home/.config/demo/config"
    write_manifest 'demo|arch|file|.config/demo/config|plain|yes|1'

    run_cli diff --target arch --staging-home "$TEST_TMP/home"
    assert_status 64 && assert_contains 'staging home must not resolve to live home' || return 1

    run_cli diff --target arch --staging-home "$TEST_TMP/home/."
    assert_status 64 && assert_contains 'staging home must not resolve to live home' || return 1

    alias_home="$TEST_TMP/home-alias"
    ln -s "$TEST_TMP/home" "$alias_home"
    run_cli diff --target arch --staging-home "$alias_home"
    assert_status 64 && assert_contains 'staging home must not resolve to live home'
}

test_diff_fails_closed_without_canonical_source_root() {
    new_fixture
    rm -rf -- "$TEST_TMP/repo/home"
    write_manifest 'demo|macos|file|.config/demo/config|plain|yes|1'
    run_cli diff
    assert_status 65 && assert_contains 'canonical source root is unavailable'
}

test_diff_blocks_unsafe_source_paths() {
    new_fixture
    mkdir -p "$TEST_TMP/repo/home/.config/demo" "$TEST_TMP/home/.config/demo" "$TEST_TMP/outside"
    printf 'canonical\n' >"$TEST_TMP/outside/config"
    ln -s "$TEST_TMP/outside/config" "$TEST_TMP/repo/home/.config/demo/symlink-file"
    ln -s "$TEST_TMP/outside" "$TEST_TMP/repo/home/.config/escaped-parent"
    write_manifest $'demo|macos|file|.config/demo/symlink-file|plain|yes|1\ndemo|macos|file|.config/escaped-parent/config|plain|yes|1'
    run_cli diff
    assert_status 65 && \
        assert_contains 'BLOCKED demo .config/demo/symlink-file' && \
        assert_contains 'BLOCKED demo .config/escaped-parent/config'
}

test_diff_blocks_unsafe_target_ancestors() {
    new_fixture
    mkdir -p "$TEST_TMP/repo/home/.config/demo" "$TEST_TMP/outside"
    printf 'canonical\n' >"$TEST_TMP/repo/home/.config/demo/config"
    write_manifest 'demo|macos|file|.config/demo/config|plain|yes|1'
    ln -s "$TEST_TMP/outside" "$TEST_TMP/home/.config"
    run_cli diff
    assert_status 65 && assert_contains 'BLOCKED demo .config/demo/config' || return 1

    new_fixture
    mkdir -p "$TEST_TMP/repo/home/.config/demo"
    printf 'canonical\n' >"$TEST_TMP/repo/home/.config/demo/config"
    write_manifest 'demo|macos|file|.config/demo/config|plain|yes|1'
    printf 'not a directory\n' >"$TEST_TMP/home/.config"
    run_cli diff
    assert_status 65 && assert_contains 'BLOCKED demo .config/demo/config'
}

test_install_rejects_target_and_staging_options() {
    new_fixture
    run_cli install --target arch
    assert_status 64 && assert_contains 'install does not accept --target'
    run_cli install --staging-home "$TEST_TMP/staging"
    assert_status 64 && assert_contains 'install does not accept --staging-home'
}

test_install_is_dry_run_by_default() {
    new_fixture
    mkdir -p "$TEST_TMP/repo/home/.config/demo"
    printf 'x\n' >"$TEST_TMP/repo/home/.config/demo/config"
    write_manifest 'demo|macos|file|.config/demo/config|plain|yes|1'
    run_cli install
    assert_status 0 && assert_contains 'CREATE demo .config/demo/config' && \
        assert_not_exists "$TEST_TMP/home/.config/demo/config"
}

test_install_apply_links_and_is_idempotent() {
    new_fixture
    mkdir -p "$TEST_TMP/repo/home/.config/demo"
    printf 'x\n' >"$TEST_TMP/repo/home/.config/demo/config"
    write_manifest 'demo|macos|file|.config/demo/config|plain|yes|1'
    run_cli install --apply
    assert_status 0 || return 1
    [[ "$(readlink "$TEST_TMP/home/.config/demo/config")" == "$TEST_TMP/repo/home/.config/demo/config" ]] || return 1
    run_cli install --apply
    assert_status 0 && assert_contains 'NOOP demo .config/demo/config'
}

test_install_conflict_aborts_complete_plan() {
    new_fixture
    mkdir -p "$TEST_TMP/repo/home/.config/demo" "$TEST_TMP/home/.config/demo"
    printf 'new-a\n' >"$TEST_TMP/repo/home/.config/demo/a"
    printf 'new-b\n' >"$TEST_TMP/repo/home/.config/demo/b"
    printf 'old-a\n' >"$TEST_TMP/home/.config/demo/a"
    write_manifest $'demo|macos|file|.config/demo/a|plain|yes|1\ndemo|macos|file|.config/demo/b|plain|yes|1'
    run_cli install --apply
    [[ "$CLI_STATUS" -ne 0 ]] || { fail 'conflicting install unexpectedly succeeded'; return 1; }
    assert_contains 'CONFLICT demo .config/demo/a' || return 1
    assert_contains 'CREATE demo .config/demo/b' || return 1
    assert_not_exists "$TEST_TMP/home/.config/demo/b"
}

test_install_refuses_non_directory_parent() {
    new_fixture
    mkdir -p "$TEST_TMP/repo/home/.config/demo" "$TEST_TMP/home/.config"
    printf 'new\n' >"$TEST_TMP/repo/home/.config/demo/config"
    printf 'parent-is-a-file\n' >"$TEST_TMP/home/.config/demo"
    write_manifest 'demo|macos|file|.config/demo/config|plain|yes|1'
    run_cli install --apply
    [[ "$CLI_STATUS" -ne 0 ]] || { fail 'install ignored a non-directory parent'; return 1; }
    [[ -f "$TEST_TMP/home/.config/demo" ]] || return 1
}

test_install_selects_only_physical_platform() {
    new_fixture
    mkdir -p "$TEST_TMP/repo/home/.config/demo"
    printf 'mac\n' >"$TEST_TMP/repo/home/.config/demo/mac"
    printf 'arch\n' >"$TEST_TMP/repo/home/.config/demo/arch"
    write_manifest $'demo|macos|file|.config/demo/mac|plain|yes|1\ndemo|arch|file|.config/demo/arch|plain|yes|1'
    run_cli install --apply
    assert_status 0 || return 1
    [[ -L "$TEST_TMP/home/.config/demo/mac" ]] || return 1
    assert_not_exists "$TEST_TMP/home/.config/demo/arch"
}

test_install_rejects_backup_without_apply_and_unknown_options() {
    new_fixture
    mkdir -p "$TEST_TMP/repo/home/.config/demo"
    printf 'x\n' >"$TEST_TMP/repo/home/.config/demo/config"
    write_manifest 'demo|macos|file|.config/demo/config|plain|yes|1'
    run_cli install --backup
    assert_status 64 || return 1
    run_cli install --apply --unknown
    assert_status 64 || return 1
    run_cli install --apply --backup
    assert_status 0 && [[ -L "$TEST_TMP/home/.config/demo/config" ]]
}

test_install_backup_preserves_regular_file_relative_path() {
    local backup
    new_fixture
    mkdir -p "$TEST_TMP/repo/home/.config/demo" "$TEST_TMP/home/.config/demo"
    printf 'canonical\n' >"$TEST_TMP/repo/home/.config/demo/config"
    printf 'existing\n' >"$TEST_TMP/home/.config/demo/config"
    write_manifest 'demo|macos|file|.config/demo/config|plain|yes|1'

    run_cli install
    assert_status 1 && assert_contains 'CONFLICT demo .config/demo/config' || return 1
    run_cli install --apply
    assert_status 1 && assert_contains 'CONFLICT demo .config/demo/config' || return 1
    run_cli install --apply --backup
    assert_status 0 && assert_contains 'BACKUP demo .config/demo/config' || return 1
    [[ -L "$TEST_TMP/home/.config/demo/config" ]] || return 1
    backup="$(find "$TEST_TMP/state/backups" -path '*/files/.config/demo/config' -type f -print)"
    [[ -n "$backup" && "$(<"$backup")" == existing ]]
}

test_install_backup_preserves_foreign_symlink() {
    local backup
    new_fixture
    mkdir -p "$TEST_TMP/repo/home/.config/demo" "$TEST_TMP/home/.config/demo"
    printf 'canonical\n' >"$TEST_TMP/repo/home/.config/demo/config"
    printf 'foreign\n' >"$TEST_TMP/home/.config/demo/foreign"
    ln -s "$TEST_TMP/home/.config/demo/foreign" "$TEST_TMP/home/.config/demo/config"
    write_manifest 'demo|macos|file|.config/demo/config|plain|yes|1'

    run_cli install --apply --backup
    assert_status 0 && assert_contains 'BACKUP demo .config/demo/config' || return 1
    [[ "$(readlink "$TEST_TMP/home/.config/demo/config")" == "$TEST_TMP/repo/home/.config/demo/config" ]] || return 1
    backup="$(find "$TEST_TMP/state/backups" -path '*/files/.config/demo/config' -type l -print)"
    [[ -n "$backup" && "$(readlink "$backup")" == "$TEST_TMP/home/.config/demo/foreign" ]]
}

test_install_backup_blocks_directory_conflict() {
    new_fixture
    mkdir -p "$TEST_TMP/repo/home/.config/demo" "$TEST_TMP/home/.config/demo/config"
    printf 'canonical\n' >"$TEST_TMP/repo/home/.config/demo/config"
    write_manifest 'demo|macos|file|.config/demo/config|plain|yes|1'

    run_cli install --apply --backup
    assert_status 65 && assert_contains 'BLOCKED demo .config/demo/config' || return 1
    [[ -d "$TEST_TMP/home/.config/demo/config" && ! -L "$TEST_TMP/home/.config/demo/config" ]] || return 1
    assert_not_exists "$TEST_TMP/state/install.lock"
}

test_install_existing_lock_refuses_mutation() {
    new_fixture
    mkdir -p "$TEST_TMP/repo/home/.config/demo" "$TEST_TMP/state/install.lock"
    printf 'canonical\n' >"$TEST_TMP/repo/home/.config/demo/config"
    write_manifest 'demo|macos|file|.config/demo/config|plain|yes|1'

    run_cli install --apply
    assert_status 75 && assert_contains 'another install is active' || return 1
    assert_not_exists "$TEST_TMP/home/.config/demo/config"
}

test_install_releases_lock_after_success_and_failure() {
    new_fixture
    mkdir -p "$TEST_TMP/repo/home/.config/demo"
    printf 'canonical\n' >"$TEST_TMP/repo/home/.config/demo/config"
    write_manifest 'demo|macos|file|.config/demo/config|plain|yes|1'

    run_cli install --apply
    assert_status 0 || return 1
    assert_not_exists "$TEST_TMP/state/install.lock" || return 1

    rm "$TEST_TMP/home/.config/demo/config"
    DOTFILES_TEST_FAIL_AFTER=1 run_cli install --apply
    assert_status 70 || return 1
    assert_not_exists "$TEST_TMP/state/install.lock" || return 1
    assert_not_exists "$TEST_TMP/home/.config/demo/config"
}

test_install_backup_report_records_move_and_link_rows() {
    local report expected_move expected_link
    new_fixture
    mkdir -p "$TEST_TMP/repo/home/.config/demo" "$TEST_TMP/home/.config/demo"
    printf 'canonical\n' >"$TEST_TMP/repo/home/.config/demo/config"
    printf 'existing\n' >"$TEST_TMP/home/.config/demo/config"
    write_manifest 'demo|macos|file|.config/demo/config|plain|yes|1'

    run_cli install --apply --backup
    assert_status 0 || return 1
    report="$(find "$TEST_TMP/state/backups" -name report.tsv -type f -print)"
    [[ -n "$report" ]] || return 1
    expected_move=$'MOVE\t.config/demo/config\t'"$TEST_TMP/home/.config/demo/config"$'\t'"${report%/report.tsv}/files/.config/demo/config"
    expected_link=$'LINK\t.config/demo/config\t'"$TEST_TMP/repo/home/.config/demo/config"$'\t'"$TEST_TMP/home/.config/demo/config"
    grep -Fqx "$expected_move" "$report" || return 1
    grep -Fqx "$expected_link" "$report"
}

test_install_injected_failure_rolls_back_partial_work() {
    new_fixture
    mkdir -p "$TEST_TMP/repo/home/.config/demo" "$TEST_TMP/home/.config/demo"
    printf 'new-a\n' >"$TEST_TMP/repo/home/.config/demo/a"
    printf 'new-b\n' >"$TEST_TMP/repo/home/.config/demo/b"
    printf 'old-a\n' >"$TEST_TMP/home/.config/demo/a"
    printf 'old-b\n' >"$TEST_TMP/home/.config/demo/b"
    write_manifest $'demo|macos|file|.config/demo/a|plain|yes|1\ndemo|macos|file|.config/demo/b|plain|yes|1'

    DOTFILES_TEST_FAIL_AFTER=3 run_cli install --apply --backup
    assert_status 70 || return 1
    [[ ! -L "$TEST_TMP/home/.config/demo/a" && ! -L "$TEST_TMP/home/.config/demo/b" ]] || return 1
    [[ "$(<"$TEST_TMP/home/.config/demo/a")" == old-a ]] || return 1
    [[ "$(<"$TEST_TMP/home/.config/demo/b")" == old-b ]] || return 1
    assert_not_exists "$TEST_TMP/state/install.lock"
}

test_install_rollback_refuses_unrelated_replacement() {
    local hook backup
    new_fixture
    mkdir -p "$TEST_TMP/repo/home/.config/demo" "$TEST_TMP/home/.config/demo"
    printf 'canonical\n' >"$TEST_TMP/repo/home/.config/demo/config"
    printf 'existing\n' >"$TEST_TMP/home/.config/demo/config"
    write_manifest 'demo|macos|file|.config/demo/config|plain|yes|1'
    hook="$TEST_TMP/replace-before-rollback"
    cat >"$hook" <<STUB
#!/bin/sh
    if [ "\$1" = rollback_link_before_quarantine ]; then
    /bin/rm -- "$TEST_TMP/home/.config/demo/config"
    printf 'unrelated\n' >"$TEST_TMP/home/.config/demo/config"
fi
STUB
    chmod +x "$hook"

    DOTFILES_TEST_INSTALL_HOOK="$hook" DOTFILES_TEST_FAIL_AFTER=2 run_cli install --apply --backup
    assert_status 70 && assert_contains 'ROLLBACK_REFUSED .config/demo/config' || return 1
    [[ ! -L "$TEST_TMP/home/.config/demo/config" && "$(<"$TEST_TMP/home/.config/demo/config")" == unrelated ]] || return 1
    backup="$(find "$TEST_TMP/state/backups" -path '*/files/.config/demo/config' -type f -print)"
    [[ -n "$backup" && "$(<"$backup")" == existing ]] || return 1
    assert_not_exists "$TEST_TMP/state/install.lock"
}

test_install_backup_managed_report_tsv_uses_files_namespace() {
    local backup report
    new_fixture
    printf 'canonical\n' >"$TEST_TMP/repo/home/report.tsv"
    printf 'existing\n' >"$TEST_TMP/home/report.tsv"
    write_manifest 'demo|macos|file|report.tsv|plain|yes|1'

    run_cli install --apply --backup
    assert_status 0 || return 1
    backup="$(find "$TEST_TMP/state/backups" -path '*/files/report.tsv' -type f -print)"
    report="${backup%/files/report.tsv}/report.tsv"
    [[ -n "$report" && -n "$backup" && "$report" != "$backup" ]] || return 1
    [[ "$(<"$backup")" == existing ]] || return 1
    grep -Fq $'MOVE\treport.tsv\t' "$report"
}

test_install_backup_destination_gap_never_clobbers() {
    local hook backup
    new_fixture
    mkdir -p "$TEST_TMP/repo/home/.config/demo" "$TEST_TMP/home/.config/demo"
    printf 'canonical\n' >"$TEST_TMP/repo/home/.config/demo/config"
    printf 'existing\n' >"$TEST_TMP/home/.config/demo/config"
    write_manifest 'demo|macos|file|.config/demo/config|plain|yes|1'
    hook="$TEST_TMP/occupy-backup-destination"
    cat >"$hook" <<'STUB'
#!/bin/sh
if [ "$1" = before_backup_move ]; then
    printf 'arrived\n' >"$3"
fi
STUB
    chmod +x "$hook"

    DOTFILES_TEST_INSTALL_HOOK="$hook" run_cli install --apply --backup
    assert_status 74 || return 1
    [[ "$(<"$TEST_TMP/home/.config/demo/config")" == existing ]] || return 1
    backup="$(find "$TEST_TMP/state/backups" -path '*/files/.config/demo/config' -type f -print)"
    [[ -n "$backup" && "$(<"$backup")" == arrived ]] || return 1
    assert_not_exists "$TEST_TMP/state/install.lock"
}

test_install_rollback_restore_gap_never_overwrites() {
    local hook backup
    new_fixture
    mkdir -p "$TEST_TMP/repo/home/.config/demo" "$TEST_TMP/home/.config/demo"
    printf 'canonical\n' >"$TEST_TMP/repo/home/.config/demo/config"
    printf 'existing\n' >"$TEST_TMP/home/.config/demo/config"
    write_manifest 'demo|macos|file|.config/demo/config|plain|yes|1'
    hook="$TEST_TMP/occupy-rollback-target"
    cat >"$hook" <<'STUB'
#!/bin/sh
if [ "$1" = rollback_move_before_restore ]; then
    printf 'arrived\n' >"$2"
fi
STUB
    chmod +x "$hook"

    DOTFILES_TEST_INSTALL_HOOK="$hook" DOTFILES_TEST_FAIL_AFTER=2 run_cli install --apply --backup
    assert_status 70 || return 1
    [[ ! -L "$TEST_TMP/home/.config/demo/config" && "$(<"$TEST_TMP/home/.config/demo/config")" == arrived ]] || return 1
    backup="$(find "$TEST_TMP/state/backups" -path '*/files/.config/demo/config' -type f -print)"
    [[ -n "$backup" && "$(<"$backup")" == existing ]] || return 1
    assert_not_exists "$TEST_TMP/state/install.lock"
}

test_install_signal_after_backup_move_rolls_back_intent() {
    local hook
    new_fixture
    mkdir -p "$TEST_TMP/repo/home/.config/demo" "$TEST_TMP/home/.config/demo"
    printf 'canonical\n' >"$TEST_TMP/repo/home/.config/demo/config"
    printf 'existing\n' >"$TEST_TMP/home/.config/demo/config"
    write_manifest 'demo|macos|file|.config/demo/config|plain|yes|1'
    hook="$TEST_TMP/signal-after-backup"
    cat >"$hook" <<'STUB'
#!/bin/sh
if [ "$1" = after_backup_move ]; then
    kill -TERM "$PPID"
fi
STUB
    chmod +x "$hook"

    DOTFILES_TEST_INSTALL_HOOK="$hook" run_cli install --apply --backup
    assert_status 143 || return 1
    [[ ! -L "$TEST_TMP/home/.config/demo/config" && "$(<"$TEST_TMP/home/.config/demo/config")" == existing ]] || return 1
    assert_not_exists "$TEST_TMP/state/install.lock"
}

test_install_signal_after_link_temp_cleans_intent() {
    local hook identity
    new_fixture
    mkdir -p "$TEST_TMP/repo/home/.config/demo"
    printf 'canonical\n' >"$TEST_TMP/repo/home/.config/demo/config"
    write_manifest 'demo|macos|file|.config/demo/config|plain|yes|1'
    hook="$TEST_TMP/signal-after-link-temp"
    cat >"$hook" <<STUB
#!/bin/sh
if [ "\$1" = after_link_temp ]; then
    printf '%s\n' "\$4" >"$TEST_TMP/signal-link-identity"
    kill -TERM "\$PPID"
fi
STUB
    chmod +x "$hook"

    DOTFILES_TEST_INSTALL_HOOK="$hook" run_cli install --apply
    assert_status 143 || return 1
    identity="$(<"$TEST_TMP/signal-link-identity")"
    [[ "$identity" == *:* ]] || return 1
    assert_not_exists "$TEST_TMP/home/.config/demo/config" || return 1
    [[ -z "$(find "$TEST_TMP/home" -name '.dotfiles-link-*' -print)" ]] || return 1
    assert_not_exists "$TEST_TMP/state/install.lock"
}

test_install_identity_capture_failure_refuses_identityless_temp() {
    local stub_path temp
    new_fixture
    mkdir -p "$TEST_TMP/repo/home/.config/demo" "$TEST_TMP/stub-bin"
    printf 'canonical\n' >"$TEST_TMP/repo/home/.config/demo/config"
    write_manifest 'demo|macos|file|.config/demo/config|plain|yes|1'
    stub_path="$TEST_TMP/stub-bin/stat"
    cat >"$stub_path" <<'STUB'
#!/bin/sh
for argument in "$@"; do
    case "$argument" in
        *.dotfiles-link-*) exit 1 ;;
    esac
done
exec /usr/bin/stat "$@"
STUB
    chmod +x "$stub_path"

    DOTFILES_TEST_PATH="$TEST_TMP/stub-bin:$PATH" run_cli install --apply
    assert_status 65 && assert_contains 'ROLLBACK_REFUSED .config/demo/config' || return 1
    temp="$(find "$TEST_TMP/home" -name '.dotfiles-link-*' -type l -print)"
    [[ -n "$temp" && "$(readlink "$temp")" == "$TEST_TMP/repo/home/.config/demo/config" ]] || return 1
    assert_not_exists "$TEST_TMP/state/install.lock"
}

test_install_failure_after_link_identity_uses_recorded_owner() {
    local hook identity quarantine
    new_fixture
    mkdir -p "$TEST_TMP/repo/home/.config/demo"
    printf 'canonical\n' >"$TEST_TMP/repo/home/.config/demo/config"
    write_manifest 'demo|macos|file|.config/demo/config|plain|yes|1'
    hook="$TEST_TMP/fail-after-link-identity"
    cat >"$hook" <<STUB
#!/bin/sh
if [ "\$1" = after_link_temp ]; then
    printf '%s\n' "\$4" >"$TEST_TMP/recorded-link-identity"
    exit 71
fi
STUB
    chmod +x "$hook"

    DOTFILES_TEST_INSTALL_HOOK="$hook" run_cli install --apply
    assert_status 71 || return 1
    identity="$(<"$TEST_TMP/recorded-link-identity")"
    [[ "$identity" == *:* ]] || return 1
    assert_not_exists "$TEST_TMP/home/.config/demo/config" || return 1
    [[ -z "$(find "$TEST_TMP/home" -name '.dotfiles-link-*' -print)" ]] || return 1
    quarantine="$(find "$TEST_TMP/state/transactions" -path '*/quarantine/link-*/temp' -type l -print)"
    [[ -n "$quarantine" && "$(readlink "$quarantine")" == "$TEST_TMP/repo/home/.config/demo/config" ]] || return 1
    assert_not_exists "$TEST_TMP/state/install.lock"
}

test_install_signal_after_link_publish_rolls_back_intent() {
    local hook
    new_fixture
    mkdir -p "$TEST_TMP/repo/home/.config/demo" "$TEST_TMP/home/.config/demo"
    printf 'canonical\n' >"$TEST_TMP/repo/home/.config/demo/config"
    printf 'existing\n' >"$TEST_TMP/home/.config/demo/config"
    write_manifest 'demo|macos|file|.config/demo/config|plain|yes|1'
    hook="$TEST_TMP/signal-after-link-publish"
    cat >"$hook" <<'STUB'
#!/bin/sh
if [ "$1" = after_link_publish ]; then
    kill -TERM "$PPID"
fi
STUB
    chmod +x "$hook"

    DOTFILES_TEST_INSTALL_HOOK="$hook" run_cli install --apply --backup
    assert_status 143 || return 1
    [[ ! -L "$TEST_TMP/home/.config/demo/config" && "$(<"$TEST_TMP/home/.config/demo/config")" == existing ]] || return 1
    assert_not_exists "$TEST_TMP/state/install.lock"
}

test_install_signal_at_lock_acquisition_releases_lock() {
    local hook
    new_fixture
    mkdir -p "$TEST_TMP/repo/home/.config/demo"
    printf 'canonical\n' >"$TEST_TMP/repo/home/.config/demo/config"
    write_manifest 'demo|macos|file|.config/demo/config|plain|yes|1'
    hook="$TEST_TMP/signal-after-lock"
    cat >"$hook" <<'STUB'
#!/bin/sh
if [ "$1" = after_lock_acquire ]; then
    kill -TERM "$PPID"
fi
STUB
    chmod +x "$hook"

    DOTFILES_TEST_INSTALL_HOOK="$hook" run_cli install --apply
    assert_status 143 || return 1
    assert_not_exists "$TEST_TMP/home/.config/demo/config" || return 1
    assert_not_exists "$TEST_TMP/state/install.lock"
}

test_install_signal_during_cleanup_preserves_failure_status() {
    local hook
    new_fixture
    mkdir -p "$TEST_TMP/repo/home/.config/demo"
    printf 'canonical\n' >"$TEST_TMP/repo/home/.config/demo/config"
    write_manifest 'demo|macos|file|.config/demo/config|plain|yes|1'
    hook="$TEST_TMP/signal-during-cleanup"
    cat >"$hook" <<STUB
#!/bin/sh
if [ "\$1" = during_cleanup ]; then
    : >"$TEST_TMP/cleanup-hook-ran"
    kill -TERM "\$PPID"
fi
STUB
    chmod +x "$hook"

    DOTFILES_TEST_INSTALL_HOOK="$hook" DOTFILES_TEST_FAIL_AFTER=1 run_cli install --apply
    assert_status 70 || return 1
    [[ -f "$TEST_TMP/cleanup-hook-ran" ]] || return 1
    assert_not_exists "$TEST_TMP/home/.config/demo/config" || return 1
    assert_not_exists "$TEST_TMP/state/install.lock"
}

test_install_state_root_swap_never_redirects_transaction() {
    local hook
    new_fixture
    mkdir -p "$TEST_TMP/repo/home/.config/demo" "$TEST_TMP/home/.config/demo" "$TEST_TMP/outside-state"
    printf 'canonical\n' >"$TEST_TMP/repo/home/.config/demo/config"
    printf 'existing\n' >"$TEST_TMP/home/.config/demo/config"
    write_manifest 'demo|macos|file|.config/demo/config|plain|yes|1'
    hook="$TEST_TMP/swap-state-root"
    cat >"$hook" <<STUB
#!/bin/sh
if [ "\$1" = after_lock_acquire ]; then
    /bin/mv "\$2" "\$2.pinned"
    /bin/ln -s "$TEST_TMP/outside-state" "\$2"
fi
STUB
    chmod +x "$hook"

    DOTFILES_TEST_INSTALL_HOOK="$hook" run_cli install --apply --backup
    [[ "$CLI_STATUS" -ne 0 ]] || return 1
    [[ "$(<"$TEST_TMP/home/.config/demo/config")" == existing ]] || return 1
    assert_not_exists "$TEST_TMP/outside-state/install.lock" || return 1
    assert_not_exists "$TEST_TMP/outside-state/backups" || return 1
    assert_not_exists "$TEST_TMP/state.pinned/install.lock"
}

test_install_rollback_restores_same_target_different_identity() {
    local hook backup replacement_identity
    new_fixture
    mkdir -p "$TEST_TMP/repo/home/.config/demo" "$TEST_TMP/home/.config/demo"
    printf 'canonical\n' >"$TEST_TMP/repo/home/.config/demo/config"
    printf 'existing\n' >"$TEST_TMP/home/.config/demo/config"
    write_manifest 'demo|macos|file|.config/demo/config|plain|yes|1'
    hook="$TEST_TMP/replace-with-same-target-link"
    cat >"$hook" <<STUB
#!/bin/sh
if [ "\$1" = rollback_link_before_quarantine ]; then
    /bin/rm -- "$TEST_TMP/home/.config/demo/config"
    /bin/ln -s "$TEST_TMP/repo/home/.config/demo/config" "$TEST_TMP/home/.config/demo/config"
    /bin/ls -di "$TEST_TMP/home/.config/demo/config" >"$TEST_TMP/replacement-identity"
fi
STUB
    chmod +x "$hook"

    DOTFILES_TEST_INSTALL_HOOK="$hook" DOTFILES_TEST_FAIL_AFTER=2 run_cli install --apply --backup
    assert_status 70 && assert_contains 'ROLLBACK_REFUSED .config/demo/config' || return 1
    replacement_identity="$(<"$TEST_TMP/replacement-identity")"
    [[ -L "$TEST_TMP/home/.config/demo/config" ]] || return 1
    [[ "$(readlink "$TEST_TMP/home/.config/demo/config")" == "$TEST_TMP/repo/home/.config/demo/config" ]] || return 1
    [[ "$(ls -di "$TEST_TMP/home/.config/demo/config")" == "$replacement_identity" ]] || return 1
    backup="$(find "$TEST_TMP/state/backups" -path '*/files/.config/demo/config' -type f -print)"
    [[ -n "$backup" && "$(<"$backup")" == existing ]]
}

test_install_backup_directory_arrival_recovers_source() {
    local hook backup_dir
    new_fixture
    mkdir -p "$TEST_TMP/repo/home/.config/demo" "$TEST_TMP/home/.config/demo"
    printf 'canonical\n' >"$TEST_TMP/repo/home/.config/demo/config"
    printf 'existing\n' >"$TEST_TMP/home/.config/demo/config"
    write_manifest 'demo|macos|file|.config/demo/config|plain|yes|1'
    hook="$TEST_TMP/backup-directory-arrival"
    cat >"$hook" <<'STUB'
#!/bin/sh
if [ "$1" = before_backup_move ]; then
    mkdir "$3"
fi
STUB
    chmod +x "$hook"

    DOTFILES_TEST_INSTALL_HOOK="$hook" run_cli install --apply --backup
    assert_status 74 || return 1
    [[ ! -L "$TEST_TMP/home/.config/demo/config" && "$(<"$TEST_TMP/home/.config/demo/config")" == existing ]] || return 1
    backup_dir="$(find "$TEST_TMP/state/backups" -path '*/files/.config/demo/config' -type d -print)"
    [[ -n "$backup_dir" && -z "$(find "$backup_dir" ! -path "$backup_dir" -print)" ]] || return 1
    assert_not_exists "$TEST_TMP/state/install.lock"
}

test_install_backup_stage_directory_arrival_is_recovered() {
    local hook stage
    new_fixture
    mkdir -p "$TEST_TMP/repo/home/.config/demo" "$TEST_TMP/home/.config/demo"
    printf 'canonical\n' >"$TEST_TMP/repo/home/.config/demo/config"
    printf 'existing\n' >"$TEST_TMP/home/.config/demo/config"
    write_manifest 'demo|macos|file|.config/demo/config|plain|yes|1'
    hook="$TEST_TMP/backup-stage-directory-arrival"
    cat >"$hook" <<'STUB'
#!/bin/sh
if [ "$1" = before_backup_stage ]; then
    mkdir "$3"
fi
STUB
    chmod +x "$hook"

    DOTFILES_TEST_INSTALL_HOOK="$hook" run_cli install --apply --backup
    assert_status 74 || return 1
    [[ ! -L "$TEST_TMP/home/.config/demo/config" && "$(<"$TEST_TMP/home/.config/demo/config")" == existing ]] || return 1
    stage="$(find "$TEST_TMP/home/.config/demo" -maxdepth 1 -name '.dotfiles-backup-*' -type d -print)"
    [[ -n "$stage" && -z "$(find "$stage" ! -path "$stage" -print)" ]] || return 1
    assert_not_exists "$TEST_TMP/state/install.lock"
}

test_install_backup_stage_recovery_directory_tracks_nested_entry() {
    local hook stage recovery
    new_fixture
    mkdir -p "$TEST_TMP/repo/home/.config/demo" "$TEST_TMP/home/.config/demo"
    printf 'canonical\n' >"$TEST_TMP/repo/home/.config/demo/config"
    printf 'existing\n' >"$TEST_TMP/home/.config/demo/config"
    write_manifest 'demo|macos|file|.config/demo/config|plain|yes|1'
    hook="$TEST_TMP/backup-stage-recovery-directory-arrival"
    cat >"$hook" <<'STUB'
#!/bin/sh
if [ "$1" = before_backup_stage ]; then
    mkdir "$3" "$4"
fi
STUB
    chmod +x "$hook"

    DOTFILES_TEST_INSTALL_HOOK="$hook" run_cli install --apply --backup
    assert_status 74 || return 1
    [[ ! -L "$TEST_TMP/home/.config/demo/config" && "$(<"$TEST_TMP/home/.config/demo/config")" == existing ]] || return 1
    stage="$(find "$TEST_TMP/home/.config/demo" -maxdepth 1 -name '.dotfiles-backup-*' ! -name '*recovery*' -type d -print)"
    recovery="$(find "$TEST_TMP/home/.config/demo" -maxdepth 1 -name '.dotfiles-backup-recovery-*' -type d -print)"
    [[ -n "$stage" && -z "$(find "$stage" ! -path "$stage" -print)" ]] || return 1
    [[ -n "$recovery" && -z "$(find "$recovery" ! -path "$recovery" -print)" ]] || return 1
    assert_not_exists "$TEST_TMP/state/install.lock"
}

test_install_backup_stage_symlink_directories_never_escape_target_tree() {
    local hook target
    new_fixture
    mkdir -p "$TEST_TMP/repo/home/.config/demo" "$TEST_TMP/home/.config/demo" \
        "$TEST_TMP/external-stage" "$TEST_TMP/external-recovery"
    printf 'canonical\n' >"$TEST_TMP/repo/home/.config/demo/config"
    printf 'existing\n' >"$TEST_TMP/home/.config/demo/config"
    printf 'stage-sentinel\n' >"$TEST_TMP/external-stage/sentinel"
    printf 'recovery-sentinel\n' >"$TEST_TMP/external-recovery/sentinel"
    write_manifest 'demo|macos|file|.config/demo/config|plain|yes|1'
    hook="$TEST_TMP/backup-stage-symlink-arrivals"
    cat >"$hook" <<STUB
#!/bin/sh
if [ "\$1" = before_backup_stage ]; then
    /bin/ln -s "$TEST_TMP/external-stage" "\$3"
    /bin/ln -s "$TEST_TMP/external-recovery" "\$4"
fi
STUB
    chmod +x "$hook"

    DOTFILES_TEST_INSTALL_HOOK="$hook" run_cli install --apply --backup
    assert_status 74 || return 1
    target="$TEST_TMP/home/.config/demo/config"
    [[ -f "$target" && ! -L "$target" && "$(<"$target")" == existing ]] || return 1
    [[ "$(<"$TEST_TMP/external-stage/sentinel")" == stage-sentinel ]] || return 1
    [[ "$(<"$TEST_TMP/external-recovery/sentinel")" == recovery-sentinel ]] || return 1
    [[ -z "$(find "$TEST_TMP/external-stage" -mindepth 1 ! -name sentinel -print)" ]] || return 1
    [[ -z "$(find "$TEST_TMP/external-recovery" -mindepth 1 ! -name sentinel -print)" ]] || return 1
    assert_not_exists "$TEST_TMP/state/install.lock"
}

test_install_backup_recovery_symlink_directory_never_escapes_target_tree() {
    local hook target
    new_fixture
    mkdir -p "$TEST_TMP/repo/home/.config/demo" "$TEST_TMP/home/.config/demo" \
        "$TEST_TMP/external-recovery"
    printf 'canonical\n' >"$TEST_TMP/repo/home/.config/demo/config"
    printf 'existing\n' >"$TEST_TMP/home/.config/demo/config"
    printf 'recovery-sentinel\n' >"$TEST_TMP/external-recovery/sentinel"
    write_manifest 'demo|macos|file|.config/demo/config|plain|yes|1'
    hook="$TEST_TMP/backup-recovery-symlink-arrival"
    cat >"$hook" <<STUB
#!/bin/sh
if [ "\$1" = before_backup_stage ]; then
    /bin/mkdir "\$3"
    /bin/ln -s "$TEST_TMP/external-recovery" "\$4"
fi
STUB
    chmod +x "$hook"

    DOTFILES_TEST_INSTALL_HOOK="$hook" run_cli install --apply --backup
    assert_status 74 || return 1
    target="$TEST_TMP/home/.config/demo/config"
    [[ -f "$target" && ! -L "$target" && "$(<"$target")" == existing ]] || return 1
    [[ "$(<"$TEST_TMP/external-recovery/sentinel")" == recovery-sentinel ]] || return 1
    [[ -z "$(find "$TEST_TMP/external-recovery" -mindepth 1 ! -name sentinel -print)" ]] || return 1
    assert_not_exists "$TEST_TMP/state/install.lock"
}

test_install_restore_directory_arrival_preserves_backup() {
    local hook backup target
    new_fixture
    mkdir -p "$TEST_TMP/repo/home/.config/demo" "$TEST_TMP/home/.config/demo"
    printf 'canonical\n' >"$TEST_TMP/repo/home/.config/demo/config"
    printf 'existing\n' >"$TEST_TMP/home/.config/demo/config"
    write_manifest 'demo|macos|file|.config/demo/config|plain|yes|1'
    hook="$TEST_TMP/restore-directory-arrival"
    cat >"$hook" <<'STUB'
#!/bin/sh
if [ "$1" = rollback_move_before_restore ]; then
    mkdir "$2"
fi
STUB
    chmod +x "$hook"

    DOTFILES_TEST_INSTALL_HOOK="$hook" DOTFILES_TEST_FAIL_AFTER=2 run_cli install --apply --backup
    assert_status 70 || return 1
    target="$TEST_TMP/home/.config/demo/config"
    [[ -d "$target" && -z "$(find "$target" ! -path "$target" -print)" ]] || return 1
    backup="$(find "$TEST_TMP/state/backups" -path '*/files/.config/demo/config' -type f -print)"
    [[ -n "$backup" && "$(<"$backup")" == existing ]] || return 1
    assert_not_exists "$TEST_TMP/state/install.lock"
}

test_install_state_swap_after_check_keeps_pinned_backup() {
    local hook backup
    new_fixture
    mkdir -p "$TEST_TMP/repo/home/.config/demo" "$TEST_TMP/home/.config/demo" "$TEST_TMP/outside-state"
    printf 'canonical\n' >"$TEST_TMP/repo/home/.config/demo/config"
    printf 'existing\n' >"$TEST_TMP/home/.config/demo/config"
    write_manifest 'demo|macos|file|.config/demo/config|plain|yes|1'
    hook="$TEST_TMP/swap-state-after-check"
    cat >"$hook" <<STUB
#!/bin/sh
if [ "\$1" = backup_move_after_state_check ]; then
    /bin/mv "$TEST_TMP/state" "$TEST_TMP/state.pinned"
    /bin/ln -s "$TEST_TMP/outside-state" "$TEST_TMP/state"
fi
STUB
    chmod +x "$hook"

    DOTFILES_TEST_INSTALL_HOOK="$hook" run_cli install --apply --backup
    assert_status 0 || return 1
    backup="$(find "$TEST_TMP/state.pinned/backups" -path '*/files/.config/demo/config' -type f -print)"
    [[ -n "$backup" && "$(<"$backup")" == existing ]] || return 1
    assert_not_exists "$TEST_TMP/outside-state/install.lock" || return 1
    assert_not_exists "$TEST_TMP/outside-state/backups"
}

test_install_link_publication_directory_arrival_is_recovered() {
    local hook target backup
    new_fixture
    mkdir -p "$TEST_TMP/repo/home/.config/demo" "$TEST_TMP/home/.config/demo"
    printf 'canonical\n' >"$TEST_TMP/repo/home/.config/demo/config"
    printf 'existing\n' >"$TEST_TMP/home/.config/demo/config"
    write_manifest 'demo|macos|file|.config/demo/config|plain|yes|1'
    hook="$TEST_TMP/link-publication-directory-arrival"
    cat >"$hook" <<'STUB'
#!/bin/sh
if [ "$1" = link_publish_after_check ]; then
    mkdir "$2"
fi
STUB
    chmod +x "$hook"

    DOTFILES_TEST_INSTALL_HOOK="$hook" run_cli install --apply --backup
    [[ "$CLI_STATUS" -ne 0 ]] || return 1
    target="$TEST_TMP/home/.config/demo/config"
    [[ -d "$target" && -z "$(find "$target" ! -path "$target" -print)" ]] || return 1
    backup="$(find "$TEST_TMP/state/backups" -path '*/files/.config/demo/config' -type f -print)"
    [[ -n "$backup" && "$(<"$backup")" == existing ]] || return 1
    assert_not_exists "$TEST_TMP/state/install.lock"
}

test_install_link_recovery_directory_arrival_tracks_nested_publication() {
    local hook target recovery backup
    new_fixture
    mkdir -p "$TEST_TMP/repo/home/.config/demo" "$TEST_TMP/home/.config/demo"
    printf 'canonical\n' >"$TEST_TMP/repo/home/.config/demo/config"
    printf 'existing\n' >"$TEST_TMP/home/.config/demo/config"
    write_manifest 'demo|macos|file|.config/demo/config|plain|yes|1'
    hook="$TEST_TMP/link-recovery-directory-arrival"
    cat >"$hook" <<'STUB'
#!/bin/sh
if [ "$1" = link_publish_after_check ]; then
    mkdir "$2" "$4"
    printf 'unrelated\n' >"$4/unrelated"
fi
STUB
    chmod +x "$hook"

    DOTFILES_TEST_INSTALL_HOOK="$hook" run_cli install --apply --backup
    assert_status 74 || return 1
    target="$TEST_TMP/home/.config/demo/config"
    recovery="$(find "$TEST_TMP/home/.config/demo" -maxdepth 1 -name '.dotfiles-link-recovery-*' -type d -print)"
    [[ -d "$target" && -z "$(find "$target" ! -path "$target" -print)" ]] || return 1
    [[ -n "$recovery" && "$(<"$recovery/unrelated")" == unrelated ]] || return 1
    [[ -z "$(find "$TEST_TMP/home" -type l -print)" ]] || return 1
    backup="$(find "$TEST_TMP/state/backups" -path '*/files/.config/demo/config' -type f -print)"
    [[ -n "$backup" && "$(<"$backup")" == existing ]] || return 1
    assert_not_exists "$TEST_TMP/state/install.lock"
}

test_install_link_publication_symlink_directory_never_escapes_target_tree() {
    local hook target backup
    new_fixture
    mkdir -p "$TEST_TMP/repo/home/.config/demo" "$TEST_TMP/home/.config/demo" \
        "$TEST_TMP/external-publication"
    printf 'canonical\n' >"$TEST_TMP/repo/home/.config/demo/config"
    printf 'existing\n' >"$TEST_TMP/home/.config/demo/config"
    printf 'publication-sentinel\n' >"$TEST_TMP/external-publication/sentinel"
    write_manifest 'demo|macos|file|.config/demo/config|plain|yes|1'
    hook="$TEST_TMP/link-publication-symlink-arrival"
    cat >"$hook" <<STUB
#!/bin/sh
if [ "\$1" = link_publish_after_check ]; then
    /bin/ln -s "$TEST_TMP/external-publication" "\$2"
fi
STUB
    chmod +x "$hook"

    DOTFILES_TEST_INSTALL_HOOK="$hook" run_cli install --apply --backup
    assert_status 74 || return 1
    target="$TEST_TMP/home/.config/demo/config"
    [[ -L "$target" && "$(readlink "$target")" == "$TEST_TMP/external-publication" ]] || return 1
    [[ "$(<"$TEST_TMP/external-publication/sentinel")" == publication-sentinel ]] || return 1
    [[ -z "$(find "$TEST_TMP/external-publication" -mindepth 1 ! -name sentinel -print)" ]] || return 1
    backup="$(find "$TEST_TMP/state/backups" -path '*/files/.config/demo/config' -type f -print)"
    [[ -n "$backup" && "$(<"$backup")" == existing ]] || return 1
    assert_not_exists "$TEST_TMP/state/install.lock"
}

test_install_success_cleanup_swap_preserves_unrelated_content() {
    local hook unrelated
    new_fixture
    mkdir -p "$TEST_TMP/repo/home/.config/demo"
    printf 'canonical\n' >"$TEST_TMP/repo/home/.config/demo/config"
    write_manifest 'demo|macos|file|.config/demo/config|plain|yes|1'
    hook="$TEST_TMP/swap-success-cleanup-directory"
    cat >"$hook" <<'STUB'
#!/bin/sh
if [ "$1" = success_cleanup_before_transaction_rmdir ]; then
    mv "$2" "$2.owned"
    mkdir "$2"
    printf 'unrelated\n' >"$2/unrelated"
fi
STUB
    chmod +x "$hook"

    DOTFILES_TEST_INSTALL_HOOK="$hook" run_cli install --apply
    assert_status 74 || return 1
    [[ -L "$TEST_TMP/home/.config/demo/config" ]] || return 1
    unrelated="$(find "$TEST_TMP/state/transactions" -name unrelated -type f -print)"
    [[ -n "$unrelated" && "$(<"$unrelated")" == unrelated ]] || return 1
    assert_not_exists "$TEST_TMP/state/install.lock"
}

test_install_success_transactions_are_pruned() {
    local i
    new_fixture
    mkdir -p "$TEST_TMP/repo/home/.config/demo" "$TEST_TMP/home/.config/demo"
    printf 'canonical\n' >"$TEST_TMP/repo/home/.config/demo/config"
    write_manifest 'demo|macos|file|.config/demo/config|plain|yes|1'

    for i in 1 2 3; do
        printf 'existing-%s\n' "$i" >"$TEST_TMP/home/.config/demo/config"
        run_cli install --apply --backup
        assert_status 0 || return 1
        rm "$TEST_TMP/home/.config/demo/config"
    done
    [[ -z "$(find "$TEST_TMP/state/transactions" -mindepth 1 -print 2>/dev/null)" ]]
}

test_install_blocks_symlinked_parent() {
    new_fixture
    mkdir -p "$TEST_TMP/repo/home/.config/demo" "$TEST_TMP/outside"
    printf 'x\n' >"$TEST_TMP/repo/home/.config/demo/config"
    write_manifest 'demo|macos|file|.config/demo/config|plain|yes|1'
    ln -s "$TEST_TMP/outside" "$TEST_TMP/home/.config"
    run_cli install --apply
    assert_status 65 && assert_contains 'BLOCKED demo .config/demo/config' && \
        assert_not_exists "$TEST_TMP/outside/demo/config"
}

test_install_rechecks_source_after_parent_preparation() {
    local hook_dir
    new_fixture
    mkdir -p "$TEST_TMP/repo/home/.config/demo" "$TEST_TMP/outside"
    printf 'canonical\n' >"$TEST_TMP/repo/home/.config/demo/config"
    printf 'outside\n' >"$TEST_TMP/outside/config"
    write_manifest 'demo|macos|file|.config/demo/config|plain|yes|1'
    hook_dir="$TEST_TMP/mkdir-hook"
    mkdir "$hook_dir"
    cat >"$hook_dir/mkdir" <<STUB
#!/bin/sh
if [ ! -e "$TEST_TMP/mkdir-hook-ran" ]; then
    : >"$TEST_TMP/mkdir-hook-ran"
    /bin/rm -rf -- "$TEST_TMP/repo/home/.config/demo"
    /bin/ln -s "$TEST_TMP/outside" "$TEST_TMP/repo/home/.config/demo"
fi
exec /bin/mkdir "\$@"
STUB
    chmod +x "$hook_dir/mkdir"
    DOTFILES_TEST_PATH="$hook_dir:$PATH" run_cli install --apply
    [[ "$CLI_STATUS" -ne 0 ]] || { fail 'install linked a source changed during parent preparation'; return 1; }
    assert_not_exists "$TEST_TMP/home/.config/demo/config"
}

test_install_does_not_follow_parent_swapped_before_mkdir() {
    local hook_dir
    new_fixture
    mkdir -p "$TEST_TMP/repo/home/.config/demo" "$TEST_TMP/outside"
    printf 'canonical\n' >"$TEST_TMP/repo/home/.config/demo/config"
    write_manifest 'demo|macos|file|.config/demo/config|plain|yes|1'
    hook_dir="$TEST_TMP/mkdir-hook"
    mkdir "$hook_dir"
    cat >"$hook_dir/mkdir" <<STUB
#!/bin/sh
if [ ! -e "$TEST_TMP/mkdir-hook-ran" ]; then
    : >"$TEST_TMP/mkdir-hook-ran"
    /bin/mv "$TEST_TMP/home" "$TEST_TMP/original-home"
    /bin/ln -s "$TEST_TMP/outside" "$TEST_TMP/home"
fi
exec /bin/mkdir "\$@"
STUB
    chmod +x "$hook_dir/mkdir"
    DOTFILES_TEST_PATH="$hook_dir:$PATH" run_cli install --apply
    [[ "$CLI_STATUS" -ne 0 ]] || { fail 'install accepted a swapped target ancestor'; return 1; }
    assert_not_exists "$TEST_TMP/outside/.config"
}

test_install_rejects_home_swapped_before_pinning() {
    local hook
    new_fixture
    mkdir -p "$TEST_TMP/repo/home/.config/demo" "$TEST_TMP/outside"
    printf 'canonical\n' >"$TEST_TMP/repo/home/.config/demo/config"
    write_manifest 'demo|macos|file|.config/demo/config|plain|yes|1'
    hook="$TEST_TMP/swap-home-before-pin"
    cat >"$hook" <<STUB
#!/bin/sh
if [ "\$1" = before_prepare_parent ]; then
    /bin/mv "\$2" "\$2.original"
    /bin/ln -s "$TEST_TMP/outside" "\$2"
fi
STUB
    chmod +x "$hook"
    DOTFILES_TEST_INSTALL_HOOK="$hook" run_cli install --apply
    [[ "$CLI_STATUS" -ne 0 ]] || { fail 'install accepted a home swapped before physical pinning'; return 1; }
    assert_not_exists "$TEST_TMP/outside/.config"
}

test_dotfiles_copy_dispatches_portably() {
    local helper="$PROJECT_ROOT/home/.local/bin/dotfiles-copy"
    local stub_path empty_path output status
    new_fixture
    stub_path="$TEST_TMP/clipboard-bin"
    empty_path="$TEST_TMP/empty-bin"
    mkdir -p "$stub_path" "$empty_path"
    cat >"$stub_path/pbcopy" <<'STUB'
#!/bin/sh
printf 'pbcopy:'
/bin/cat
STUB
    cat >"$stub_path/wl-copy" <<'STUB'
#!/bin/sh
printf 'wl-copy:'
/bin/cat
STUB
    chmod +x "$stub_path/pbcopy" "$stub_path/wl-copy"

    output="$(printf 'payload' | PATH="$stub_path" "$helper")" || return 1
    [[ "$output" == 'pbcopy:payload' ]] || { fail "pbcopy was not preferred: $output"; return 1; }
    rm "$stub_path/pbcopy"
    output="$(printf 'payload' | PATH="$stub_path" "$helper")" || return 1
    [[ "$output" == 'wl-copy:payload' ]] || { fail "wl-copy fallback failed: $output"; return 1; }

    if PATH="$empty_path" "$helper" </dev/null >/dev/null 2>&1; then
        fail 'clipboard helper unexpectedly succeeded without a backend'
        return 1
    else
        status=$?
    fi
    [[ "$status" -eq 127 ]] || fail "missing-backend status $status != 127"
}

test_shared_terminal_behavior_is_canonical() {
    local kitty="$PROJECT_ROOT/home/.config/kitty/kitty.conf"
    local zellij="$PROJECT_ROOT/home/.config/zellij/config.kdl"
    grep -Fq 'font_size 13.0' "$kitty" || return 1
    grep -Fq 'scrollback_pager ${HOME}/.config/kitty/pager.sh' "$kitty" || return 1
    grep -Fq 'map ctrl+shift+u no_op' "$kitty" || return 1
    grep -Fq 'shell_integration enabled' "$kitty" || return 1
    grep -Fq 'bind "Alt 0" { GoToTab 10; }' "$zellij" || return 1
    grep -Fq 'bind "Alt d" { HalfPageScrollDown; }' "$zellij" || return 1
    grep -Fq 'copy_command "dotfiles-copy"' "$zellij" || return 1
}

test_shared_fish_yazi_and_fontconfig_are_portable() {
    local fish_config="$PROJECT_ROOT/home/.config/fish/config.fish"
    local yazi_keymap="$PROJECT_ROOT/home/.config/yazi/keymap.toml"
    local fonts_conf="$PROJECT_ROOT/home/.config/fontconfig/fonts.conf"
    local readability_conf="$PROJECT_ROOT/home/.config/fontconfig/conf.d/99-readability.conf"
    local readability_backup="$PROJECT_ROOT/home/.config/fontconfig/conf.d/99-readability.conf.backup"
    local tool

    grep -Fq 'if test -d /opt/homebrew/bin' "$fish_config" || return 1
    for tool in eza bat zoxide fd nvim lazygit; do
        grep -Fq "if command -q $tool" "$fish_config" || return 1
    done
    grep -Fq 'for = "linux"' "$yazi_keymap" || return 1
    grep -Fq 'wl-copy -t text/uri-list' "$yazi_keymap" || return 1
    grep -Fq 'for = "macos"' "$yazi_keymap" || return 1
    grep -Fq 'pbcopy' "$yazi_keymap" || return 1
    assert_not_exists "$readability_backup" || return 1
    xmllint --noout "$fonts_conf" "$readability_conf"
}

run_test test_help
run_test test_unknown_command_fails
run_test test_detects_macos_and_ignores_target
run_test test_detects_exact_arch
run_test test_rejects_arch_derivative_and_other_linux
run_test test_manifest_accepts_valid_row
run_test test_manifest_rejects_bad_columns_absolute_traversal_and_duplicate
run_test test_manifest_rejects_unknown_platform
run_test test_manifest_rejects_unknown_kind
run_test test_manifest_rejects_unknown_validator
run_test test_manifest_rejects_unknown_required_value
run_test test_check_blocks_malformed_files_with_available_validators
run_test test_check_passes_valid_file
run_test test_check_marks_missing_native_validator_runtime_unverified
run_test test_check_marks_arch_hyprland_static_only_on_macos
run_test test_check_caches_clean_hyprland_runtime_probe
run_test test_check_blocks_hyprland_runtime_error_text_with_success_status
run_test test_check_blocks_newline_only_hyprland_runtime_output
run_test test_check_blocks_nul_only_hyprland_runtime_output
run_test test_check_sanitizes_validator_control_diagnostics
run_test test_check_never_executes_manifest_validator_text
run_test test_diff_classifies_every_target_state
run_test test_diff_never_prints_binary_drift
run_test test_diff_never_prints_non_nul_binary_drift
run_test test_diff_prints_text_drift_at_hex_byte_boundary
run_test test_diff_refuses_cross_platform_live_home
run_test test_diff_allows_read_only_cross_platform_staging
run_test test_diff_rejects_live_home_as_cross_platform_staging
run_test test_diff_fails_closed_without_canonical_source_root
run_test test_diff_blocks_unsafe_source_paths
run_test test_diff_blocks_unsafe_target_ancestors
run_test test_install_rejects_target_and_staging_options
run_test test_install_is_dry_run_by_default
run_test test_install_apply_links_and_is_idempotent
run_test test_install_conflict_aborts_complete_plan
run_test test_install_refuses_non_directory_parent
run_test test_install_selects_only_physical_platform
run_test test_install_rejects_backup_without_apply_and_unknown_options
run_test test_install_backup_preserves_regular_file_relative_path
run_test test_install_backup_preserves_foreign_symlink
run_test test_install_backup_blocks_directory_conflict
run_test test_install_existing_lock_refuses_mutation
run_test test_install_releases_lock_after_success_and_failure
run_test test_install_backup_report_records_move_and_link_rows
run_test test_install_injected_failure_rolls_back_partial_work
run_test test_install_rollback_refuses_unrelated_replacement
run_test test_install_backup_managed_report_tsv_uses_files_namespace
run_test test_install_backup_destination_gap_never_clobbers
run_test test_install_rollback_restore_gap_never_overwrites
run_test test_install_signal_after_backup_move_rolls_back_intent
run_test test_install_signal_after_link_temp_cleans_intent
run_test test_install_failure_after_link_identity_uses_recorded_owner
run_test test_install_identity_capture_failure_refuses_identityless_temp
run_test test_install_signal_after_link_publish_rolls_back_intent
run_test test_install_signal_at_lock_acquisition_releases_lock
run_test test_install_signal_during_cleanup_preserves_failure_status
run_test test_install_state_root_swap_never_redirects_transaction
run_test test_install_rollback_restores_same_target_different_identity
run_test test_install_backup_directory_arrival_recovers_source
run_test test_install_backup_stage_directory_arrival_is_recovered
run_test test_install_backup_stage_recovery_directory_tracks_nested_entry
run_test test_install_backup_stage_symlink_directories_never_escape_target_tree
run_test test_install_backup_recovery_symlink_directory_never_escapes_target_tree
run_test test_install_restore_directory_arrival_preserves_backup
run_test test_install_state_swap_after_check_keeps_pinned_backup
run_test test_install_link_publication_directory_arrival_is_recovered
run_test test_install_link_recovery_directory_arrival_tracks_nested_publication
run_test test_install_link_publication_symlink_directory_never_escapes_target_tree
run_test test_install_success_cleanup_swap_preserves_unrelated_content
run_test test_install_success_transactions_are_pruned
run_test test_install_blocks_symlinked_parent
run_test test_install_rechecks_source_after_parent_preparation
run_test test_install_does_not_follow_parent_swapped_before_mkdir
run_test test_install_rejects_home_swapped_before_pinning
run_test test_dotfiles_copy_dispatches_portably
run_test test_shared_terminal_behavior_is_canonical
run_test test_shared_fish_yazi_and_fontconfig_are_portable
printf '%s passed; %s failed\n' "$PASS_COUNT" "$FAIL_COUNT"
[[ "$FAIL_COUNT" -eq 0 ]]

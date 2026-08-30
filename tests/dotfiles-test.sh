#!/usr/bin/env bash
set -u

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
TEST_TMP=""
PASS_COUNT=0
FAIL_COUNT=0
CLI_STATUS=0
CLI_OUTPUT=""

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
    mkdir -p "$TEST_TMP/repo/bin" "$TEST_TMP/repo/home" "$TEST_TMP/home"
    cp "$PROJECT_ROOT/bin/dotfiles" "$TEST_TMP/repo/bin/dotfiles"
    chmod +x "$TEST_TMP/repo/bin/dotfiles"
}

run_cli() {
    local test_uname="${DOTFILES_TEST_UNAME:-Darwin}"
    local test_os_release="${DOTFILES_TEST_OS_RELEASE:-$TEST_TMP/os-release}"
    if CLI_OUTPUT="$(DOTFILES_TESTING=1 \
        DOTFILES_TEST_HOME="$TEST_TMP/home" \
        DOTFILES_TEST_UNAME="$test_uname" \
        DOTFILES_TEST_OS_RELEASE="$test_os_release" \
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
    local name=$1
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
run_test test_dotfiles_copy_dispatches_portably
printf '%s passed; %s failed\n' "$PASS_COUNT" "$FAIL_COUNT"
[[ "$FAIL_COUNT" -eq 0 ]]

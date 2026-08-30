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
        DOTFILES_TEST_UNAME="$test_uname" \
        DOTFILES_TEST_OS_RELEASE="$test_os_release" \
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

test_install_backup_does_not_replace_conflicts() {
    new_fixture
    mkdir -p "$TEST_TMP/repo/home/.config/demo" "$TEST_TMP/home/.config/demo"
    printf 'canonical\n' >"$TEST_TMP/repo/home/.config/demo/config"
    printf 'existing\n' >"$TEST_TMP/home/.config/demo/config"
    write_manifest 'demo|macos|file|.config/demo/config|plain|yes|1'
    run_cli install --apply --backup
    [[ "$CLI_STATUS" -ne 0 ]] || { fail 'backup install unexpectedly replaced a conflict'; return 1; }
    [[ "$(<"$TEST_TMP/home/.config/demo/config")" == existing ]]
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
run_test test_install_backup_does_not_replace_conflicts
run_test test_install_blocks_symlinked_parent
run_test test_install_rechecks_source_after_parent_preparation
run_test test_install_does_not_follow_parent_swapped_before_mkdir
run_test test_install_rejects_home_swapped_before_pinning
run_test test_dotfiles_copy_dispatches_portably
printf '%s passed; %s failed\n' "$PASS_COUNT" "$FAIL_COUNT"
[[ "$FAIL_COUNT" -eq 0 ]]

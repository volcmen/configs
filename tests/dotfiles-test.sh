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
        DOTFILES_TEST_TRANSACTION_KERNEL="${DOTFILES_TEST_TRANSACTION_KERNEL:-}" \
        DOTFILES_TEST_STAT_COMMAND="${DOTFILES_TEST_STAT_COMMAND:-}" \
        DOTFILES_TEST_MOVE_COMMAND="${DOTFILES_TEST_MOVE_COMMAND:-}" \
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

test_manifest_rejects_ascii_controls_and_crlf_without_status_spoofing() {
    local kind result_rows
    for kind in crlf escape tab; do
        new_fixture
        case "$kind" in
            crlf)
                printf '# header\ndemo|macos|file|.config/demo/config|plain|yes|1\r\n' >"$TEST_TMP/repo/dotfiles.manifest"
                ;;
            escape)
                printf '# header\ndemo|macos|file|.config/demo/config|plain|yes|1\033[2J\n' >"$TEST_TMP/repo/dotfiles.manifest"
                ;;
            tab)
                printf '# header\ndemo|macos|file|.config/demo/config\tFORGED_STATUS|plain|yes|1\n' >"$TEST_TMP/repo/dotfiles.manifest"
                ;;
        esac
        run_cli check --target macos
        assert_status 65 && \
            assert_contains 'manifest line 2: ASCII control byte is forbidden; manifest must use LF line endings' || return 1
        [[ "$CLI_OUTPUT" != *'FORGED_STATUS'* ]] || return 1
        ! LC_ALL=C /usr/bin/printf '%s' "$CLI_OUTPUT" | /usr/bin/grep -q '[[:cntrl:]]' || return 1
        result_rows=$(/usr/bin/printf '%s\n' "$CLI_OUTPUT" | /usr/bin/grep -Ec '^(VERSION|PASS|STATIC PASS|RUNTIME UNVERIFIED|SKIPPED|BLOCKED) ')
        [[ "$result_rows" -eq 0 ]] || return 1
    done
}

test_manifest_rejects_unsafe_tested_version_tokens_without_execution() {
    local kind tested result_rows
    for kind in space slash execution; do
        new_fixture
        case "$kind" in
            space) tested='1 BLOCKED_FORGED' ;;
            slash) tested='1/2' ;;
            execution) tested='v1;touch$IFS'"$TEST_TMP"'/manifest-version-executed' ;;
        esac
        printf '# header\ndemo|macos|file|.config/demo/config|plain|yes|%s\n' "$tested" >"$TEST_TMP/repo/dotfiles.manifest"
        run_cli check --target macos
        assert_status 65 && assert_contains 'manifest line 2: invalid tested_version' || return 1
        [[ "$CLI_OUTPUT" != *'BLOCKED_FORGED'* ]] || return 1
        result_rows=$(/usr/bin/printf '%s\n' "$CLI_OUTPUT" | /usr/bin/grep -Ec '^(VERSION|PASS|STATIC PASS|RUNTIME UNVERIFIED|SKIPPED|BLOCKED) ')
        [[ "$result_rows" -eq 0 ]] || return 1
        assert_not_exists "$TEST_TMP/manifest-version-executed" || return 1
    done
}

test_manifest_rejects_whitespace_in_identity_path_before_output() {
    local result_rows
    new_fixture
    printf '# header\ndemo|macos|file|.config/demo/config VERSION_FORGED|plain|yes|1\n' >"$TEST_TMP/repo/dotfiles.manifest"
    run_cli check --target macos
    assert_status 65 && assert_contains 'manifest line 2: unsafe path' || return 1
    [[ "$CLI_OUTPUT" != *'VERSION_FORGED'* ]] || return 1
    result_rows=$(/usr/bin/printf '%s\n' "$CLI_OUTPUT" | /usr/bin/grep -Ec '^(VERSION|PASS|STATIC PASS|RUNTIME UNVERIFIED|SKIPPED|BLOCKED) ')
    [[ "$result_rows" -eq 0 ]]
}

test_manifest_rejects_control_path_before_recovery_tsv_mutation() {
    local relative_path
    new_fixture
    relative_path=$'.config/demo/bad\tpath'
    mkdir -p "$TEST_TMP/repo/home/.config/demo" "$TEST_TMP/home/.config/demo"
    printf 'canonical\n' >"$TEST_TMP/repo/home/$relative_path"
    printf 'existing\n' >"$TEST_TMP/home/$relative_path"
    printf 'demo|macos|file|%s|plain|yes|1\n' "$relative_path" >"$TEST_TMP/repo/dotfiles.manifest"

    run_cli install --apply --backup
    assert_status 65 && \
        assert_contains 'manifest line 1: ASCII control byte is forbidden; manifest must use LF line endings' || return 1
    [[ -f "$TEST_TMP/home/$relative_path" && ! -L "$TEST_TMP/home/$relative_path" ]] || return 1
    [[ "$(<"$TEST_TMP/home/$relative_path")" == existing ]] || return 1
    assert_not_exists "$TEST_TMP/state"
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

test_check_reports_clean_hyprland_session_separately_from_candidates() {
    local validator_bin
    new_fixture
    validator_bin="$TEST_TMP/validator-bin"
    mkdir -p "$validator_bin" "$TEST_TMP/repo/home/.config/hypr"
    printf 'return { candidate = "one" }\n' >"$TEST_TMP/repo/home/.config/hypr/one.lua"
    printf 'return { candidate = "different-from-live-session" }\n' >"$TEST_TMP/repo/home/.config/hypr/different.lua"
    printf 'return { candidate = "three" }\n' >"$TEST_TMP/repo/home/.config/hypr/three.lua"
    write_os_release 'ID=arch'
    write_manifest $'hyprland|arch|file|.config/hypr/one.lua|hyprland-lua|yes|1\nhyprland|arch|file|.config/hypr/different.lua|hyprland-lua|yes|1\nhyprland|arch|file|.config/hypr/three.lua|hyprland-lua|yes|1'
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
        [[ "$(<"$TEST_TMP/hyprctl-calls")" == configerrors ]] && \
        [[ "$(printf '%s\n' "$CLI_OUTPUT" | /usr/bin/grep -c '^RUNTIME UNVERIFIED hyprland .config/hypr/.*: canonical candidate provenance and freshness are unverified$')" -eq 3 ]] && \
        [[ "$(printf '%s\n' "$CLI_OUTPUT" | /usr/bin/grep -c '^PASS hyprland live-session: hyprctl configerrors reported no diagnostics$')" -eq 1 ]] && \
        [[ "$CLI_OUTPUT" != *'PASS hyprland .config/hypr/one.lua: Hyprland runtime validation passed'* ]] && \
        [[ "$CLI_OUTPUT" != *'PASS hyprland .config/hypr/different.lua: Hyprland runtime validation passed'* ]] && \
        [[ "$CLI_OUTPUT" != *'PASS hyprland .config/hypr/three.lua: Hyprland runtime validation passed'* ]]
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
        [[ "$(printf '%s\n' "$CLI_OUTPUT" | /usr/bin/grep -c '^RUNTIME UNVERIFIED hyprland .config/hypr/.*: canonical candidate provenance and freshness are unverified$')" -eq 3 ]] && \
        [[ "$(printf '%s\n' "$CLI_OUTPUT" | /usr/bin/grep -c '^BLOCKED hyprland live-session:')" -eq 1 ]] && \
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
        assert_contains 'RUNTIME UNVERIFIED hyprland .config/hypr/one.lua: canonical candidate provenance and freshness are unverified' && \
        assert_contains 'BLOCKED hyprland live-session: validator reported diagnostic output'
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
        assert_contains 'RUNTIME UNVERIFIED hyprland .config/hypr/one.lua: canonical candidate provenance and freshness are unverified' && \
        assert_contains 'BLOCKED hyprland live-session: validator reported diagnostic output'
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

test_check_missing_source_uses_required_semantics() {
    new_fixture
    write_manifest 'optional|macos|file|.config/demo/optional|plain|no|1'
    run_cli check --target macos
    assert_status 0 && \
        assert_contains 'SKIPPED optional .config/demo/optional: optional canonical source is absent; validation unverified' || return 1

    new_fixture
    write_manifest 'required|macos|file|.config/demo/required|plain|yes|1'
    run_cli check --target macos
    assert_status 1 && \
        assert_contains 'BLOCKED required .config/demo/required: required canonical source is absent' || return 1

    new_fixture
    mkdir -p "$TEST_TMP/repo/home/.config/demo" "$TEST_TMP/outside"
    ln -s "$TEST_TMP/outside/missing" "$TEST_TMP/repo/home/.config/demo/unsafe"
    write_manifest 'optional|macos|file|.config/demo/unsafe|plain|no|1'
    run_cli check --target macos
    assert_status 1 && \
        assert_contains 'BLOCKED optional .config/demo/unsafe: canonical source is unsafe'
}

test_check_reports_reviewed_and_safe_installed_versions() {
    local version_bin
    new_fixture
    version_bin="$TEST_TMP/version-bin"
    mkdir -p "$version_bin" "$TEST_TMP/repo/home/.config/demo"
    printf 'set demo true\n' >"$TEST_TMP/repo/home/.config/demo/fish"
    printf 'safe\n' >"$TEST_TMP/repo/home/.config/demo/zellij"
    printf 'safe\n' >"$TEST_TMP/repo/home/.config/demo/demo"
    printf 'safe\n' >"$TEST_TMP/repo/home/.config/demo/brew"
    write_manifest "fish|macos|file|.config/demo/fish|fish|yes|v1.2.3-rc.1+build.7
zellij|macos|file|.config/demo/zellij|plain|yes|0.45.1
demo|macos|file|.config/demo/demo|plain|yes|7
brew|macos|file|.config/demo/brew|plain|yes|8"
    cat >"$version_bin/fish" <<STUB
#!/bin/sh
printf '%s\n' "\$*" >>"$TEST_TMP/fish-calls"
case "\$1" in
    --version) printf 'fish, version 9.8.7\n'; exit 0 ;;
    -n) exit 0 ;;
esac
exit 9
STUB
    for command in brew pacman; do
        cat >"$version_bin/$command" <<STUB
#!/bin/sh
printf '%s %s\n' "$command" "\$*" >>"$TEST_TMP/package-manager-calls"
exit 0
STUB
        chmod +x "$version_bin/$command"
    done
    chmod +x "$version_bin/fish"

    DOTFILES_TEST_PATH="$version_bin:/usr/bin:/bin" run_cli check --target macos
    assert_status 0 && \
        assert_contains 'VERSION fish .config/demo/fish reviewed=v1.2.3-rc.1+build.7' && \
        assert_contains 'installed=9.8.7' && \
        assert_contains 'VERSION zellij .config/demo/zellij reviewed=0.45.1 installed=unavailable' && \
        assert_contains 'VERSION demo .config/demo/demo reviewed=7 installed=not-applicable' && \
        assert_contains 'VERSION brew .config/demo/brew reviewed=8 installed=not-applicable' || return 1
    [[ "$(/usr/bin/grep -c '^--version$' "$TEST_TMP/fish-calls")" -eq 1 ]] || return 1
    assert_not_exists "$TEST_TMP/package-manager-calls"
}

test_check_version_observation_is_not_applicable_off_platform() {
    local version_bin
    new_fixture
    version_bin="$TEST_TMP/version-bin"
    mkdir -p "$version_bin" "$TEST_TMP/repo/home/.config/demo"
    printf 'set demo true\n' >"$TEST_TMP/repo/home/.config/demo/fish"
    write_manifest 'fish|arch|file|.config/demo/fish|fish|yes|4.8.1'
    cat >"$version_bin/fish" <<STUB
#!/bin/sh
printf '%s\n' "\$*" >>"$TEST_TMP/fish-calls"
case "\$1" in
    --version) printf 'fish, version 9.8.7\n'; exit 0 ;;
    -n) exit 0 ;;
esac
exit 9
STUB
    chmod +x "$version_bin/fish"

    DOTFILES_TEST_PATH="$version_bin:/usr/bin:/bin" run_cli check --target arch
    assert_status 0 && \
        assert_contains 'VERSION fish .config/demo/fish reviewed=4.8.1 installed=not-applicable' || return 1
    [[ "$(/usr/bin/grep -c '^--version$' "$TEST_TMP/fish-calls")" -eq 0 ]]
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

test_diff_missing_source_uses_required_semantics() {
    new_fixture
    write_manifest 'optional|macos|file|.config/demo/optional|plain|no|1'
    run_cli diff
    assert_status 0 && \
        assert_contains 'SKIPPED optional .config/demo/optional: optional canonical source is absent; validation unverified' || return 1

    new_fixture
    write_manifest 'required|macos|file|.config/demo/required|plain|yes|1'
    run_cli diff
    assert_status 65 && \
        assert_contains 'BLOCKED required .config/demo/required: required canonical source is absent' || return 1

    new_fixture
    mkdir -p "$TEST_TMP/repo/home/.config/demo" "$TEST_TMP/outside"
    ln -s "$TEST_TMP/outside/missing" "$TEST_TMP/repo/home/.config/demo/unsafe"
    write_manifest 'optional|macos|file|.config/demo/unsafe|plain|no|1'
    run_cli diff
    assert_status 65 && \
        assert_contains 'BLOCKED optional .config/demo/unsafe: canonical source is unsafe'
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

test_install_validator_failure_blocks_preview_and_apply_before_mutation() {
    new_fixture
    mkdir -p "$TEST_TMP/repo/home/.config/demo"
    printf 'if then\n' >"$TEST_TMP/repo/home/.config/demo/bad.sh"
    printf 'safe\n' >"$TEST_TMP/repo/home/.config/demo/good"
    write_manifest $'shell-app|macos|file|.config/demo/bad.sh|shell|yes|1\nplain-app|macos|file|.config/demo/good|plain|yes|1'

    run_cli install
    assert_status 65 && \
        assert_contains 'CREATE shell-app .config/demo/bad.sh' && \
        assert_contains 'CREATE plain-app .config/demo/good' && \
        assert_contains 'BLOCKED shell-app .config/demo/bad.sh:' || return 1
    assert_not_exists "$TEST_TMP/home/.config/demo/bad.sh" || return 1
    assert_not_exists "$TEST_TMP/home/.config/demo/good" || return 1
    assert_not_exists "$TEST_TMP/state" || return 1

    run_cli install --apply
    assert_status 65 && \
        assert_contains 'CREATE shell-app .config/demo/bad.sh' && \
        assert_contains 'CREATE plain-app .config/demo/good' && \
        assert_contains 'BLOCKED shell-app .config/demo/bad.sh:' || return 1
    assert_not_exists "$TEST_TMP/home/.config/demo/bad.sh" || return 1
    assert_not_exists "$TEST_TMP/home/.config/demo/good" || return 1
    assert_not_exists "$TEST_TMP/state"
}

test_install_unavailable_validator_is_visible_and_nonblocking() {
    new_fixture
    mkdir -p "$TEST_TMP/repo/home/.config/kitty"
    printf 'font_size 13\n' >"$TEST_TMP/repo/home/.config/kitty/kitty.conf"
    write_manifest 'kitty|macos|file|.config/kitty/kitty.conf|kitty|yes|1'

    run_cli install
    assert_status 0 && \
        assert_contains 'CREATE kitty .config/kitty/kitty.conf' && \
        assert_contains 'RUNTIME UNVERIFIED kitty .config/kitty/kitty.conf: validator unavailable or intentionally unsafe on macos' || return 1
    assert_not_exists "$TEST_TMP/home/.config/kitty/kitty.conf" || return 1
    assert_not_exists "$TEST_TMP/state" || return 1

    run_cli install --apply
    assert_status 0 && \
        assert_contains 'CREATE kitty .config/kitty/kitty.conf' && \
        assert_contains 'RUNTIME UNVERIFIED kitty .config/kitty/kitty.conf: validator unavailable or intentionally unsafe on macos' || return 1
    [[ "$(readlink "$TEST_TMP/home/.config/kitty/kitty.conf")" == "$TEST_TMP/repo/home/.config/kitty/kitty.conf" ]]
}

test_install_runs_static_validator_without_runtime_probe() {
    local validator_bin
    new_fixture
    validator_bin="$TEST_TMP/validator-bin"
    mkdir -p "$validator_bin" "$TEST_TMP/repo/home/.config/hypr"
    printf 'return {}\n' >"$TEST_TMP/repo/home/.config/hypr/hyprland.lua"
    write_os_release 'ID=arch'
    write_manifest 'hyprland|arch|file|.config/hypr/hyprland.lua|hyprland-lua|yes|1'
    cat >"$validator_bin/luac" <<STUB
#!/bin/sh
printf '%s\n' "\$*" >>"$TEST_TMP/luac-calls"
exit 0
STUB
    cat >"$validator_bin/hyprctl" <<STUB
#!/bin/sh
printf '%s\n' "\$*" >>"$TEST_TMP/hyprctl-calls"
exit 0
STUB
    chmod +x "$validator_bin/luac" "$validator_bin/hyprctl"

    DOTFILES_TEST_UNAME=Linux DOTFILES_TEST_OS_RELEASE="$TEST_TMP/os-release" \
        DOTFILES_TEST_PATH="$validator_bin:/usr/bin:/bin" HYPRLAND_INSTANCE_SIGNATURE=active \
        run_cli install --apply
    assert_status 0 && assert_contains 'CREATE hyprland .config/hypr/hyprland.lua' || return 1
    [[ -f "$TEST_TMP/luac-calls" && "$(wc -l <"$TEST_TMP/luac-calls")" -eq 1 ]] || return 1
    assert_not_exists "$TEST_TMP/hyprctl-calls" || return 1
    [[ "$(readlink "$TEST_TMP/home/.config/hypr/hyprland.lua")" == "$TEST_TMP/repo/home/.config/hypr/hyprland.lua" ]]
}

test_install_missing_source_uses_required_semantics() {
    new_fixture
    write_manifest 'optional|macos|file|.config/demo/optional|plain|no|1'
    run_cli install
    assert_status 0 && \
        assert_contains 'SKIPPED optional .config/demo/optional: optional canonical source is absent; validation unverified' || return 1
    assert_not_exists "$TEST_TMP/home/.config/demo/optional" || return 1
    assert_not_exists "$TEST_TMP/state" || return 1
    run_cli install --apply
    assert_status 0 && \
        assert_contains 'SKIPPED optional .config/demo/optional: optional canonical source is absent; validation unverified' || return 1
    assert_not_exists "$TEST_TMP/home/.config/demo/optional" || return 1

    new_fixture
    write_manifest $'required|macos|file|.config/demo/required|plain|yes|1\noptional|macos|file|.config/demo/optional|plain|no|1'
    run_cli install --apply
    assert_status 65 && \
        assert_contains 'BLOCKED required .config/demo/required: required canonical source is absent' && \
        assert_contains 'SKIPPED optional .config/demo/optional: optional canonical source is absent; validation unverified' || return 1
    assert_not_exists "$TEST_TMP/home/.config/demo/required" || return 1
    assert_not_exists "$TEST_TMP/home/.config/demo/optional" || return 1
    assert_not_exists "$TEST_TMP/state" || return 1

    new_fixture
    mkdir -p "$TEST_TMP/repo/home/.config/demo" "$TEST_TMP/outside"
    ln -s "$TEST_TMP/outside/missing" "$TEST_TMP/repo/home/.config/demo/unsafe"
    write_manifest 'optional|macos|file|.config/demo/unsafe|plain|no|1'
    run_cli install --apply
    assert_status 65 && \
        assert_contains 'BLOCKED optional .config/demo/unsafe: canonical source is unsafe' || return 1
    assert_not_exists "$TEST_TMP/home/.config/demo/unsafe" || return 1
    assert_not_exists "$TEST_TMP/state"
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

test_install_root_swap_back_cannot_false_succeed() {
    local hook planned_sentinel foreign_sentinel
    new_fixture
    mkdir -p "$TEST_TMP/repo/home/.config/demo"
    printf 'canonical\n' >"$TEST_TMP/repo/home/.config/demo/config"
    printf 'planned-root\n' >"$TEST_TMP/home/planned-root"
    write_manifest 'demo|macos|file|.config/demo/config|plain|yes|1'
    hook="$TEST_TMP/root-swap-back"
    cat >"$hook" <<STUB
#!/bin/sh
if [ "\$1" = before_prepare_parent ] && [ ! -e "$TEST_TMP/root-replaced" ]; then
    : >"$TEST_TMP/root-replaced"
    /bin/mv "$TEST_TMP/home" "$TEST_TMP/home.planned"
    /bin/mkdir "$TEST_TMP/home"
    printf 'foreign-root\n' >"$TEST_TMP/home/foreign-root"
elif [ "\$1" = link_publish_after_check ]; then
    /bin/mv "$TEST_TMP/home" "$TEST_TMP/home.detached"
    /bin/mv "$TEST_TMP/home.planned" "$TEST_TMP/home"
fi
STUB
    chmod +x "$hook"

    DOTFILES_TEST_INSTALL_HOOK="$hook" run_cli install --apply
    [[ "$CLI_STATUS" -ne 0 ]] || fail 'root replacement/swap-back falsely succeeded' || return 1
    planned_sentinel="$(find "$TEST_TMP" -maxdepth 2 -name planned-root -type f -print)"
    foreign_sentinel="$(find "$TEST_TMP" -maxdepth 2 -name foreign-root -type f -print)"
    [[ -n "$planned_sentinel" && "$(<"$planned_sentinel")" == planned-root ]] || return 1
    [[ -n "$foreign_sentinel" && "$(<"$foreign_sentinel")" == foreign-root ]] || return 1
    assert_not_exists "$TEST_TMP/home/.config/demo/config"
}

test_install_nested_ancestor_swap_back_cannot_false_succeed() {
    local hook planned_sentinel foreign_sentinel
    new_fixture
    mkdir -p "$TEST_TMP/repo/home/.config/demo" "$TEST_TMP/home/.config"
    printf 'canonical\n' >"$TEST_TMP/repo/home/.config/demo/config"
    printf 'planned-ancestor\n' >"$TEST_TMP/home/.config/planned-ancestor"
    write_manifest 'demo|macos|file|.config/demo/config|plain|yes|1'
    hook="$TEST_TMP/ancestor-swap-back"
    cat >"$hook" <<STUB
#!/bin/sh
if [ "\$1" = before_prepare_parent ] && [ ! -e "$TEST_TMP/ancestor-replaced" ]; then
    : >"$TEST_TMP/ancestor-replaced"
    /bin/mv "$TEST_TMP/home/.config" "$TEST_TMP/home/.config.planned"
    /bin/mkdir "$TEST_TMP/home/.config"
    printf 'foreign-ancestor\n' >"$TEST_TMP/home/.config/foreign-ancestor"
elif [ "\$1" = link_publish_after_check ]; then
    /bin/mv "$TEST_TMP/home/.config" "$TEST_TMP/home/.config.detached"
    /bin/mv "$TEST_TMP/home/.config.planned" "$TEST_TMP/home/.config"
fi
STUB
    chmod +x "$hook"

    DOTFILES_TEST_INSTALL_HOOK="$hook" run_cli install --apply
    [[ "$CLI_STATUS" -ne 0 ]] || fail 'ancestor replacement/swap-back falsely succeeded' || return 1
    planned_sentinel="$(find "$TEST_TMP/home" -maxdepth 3 -name planned-ancestor -type f -print)"
    foreign_sentinel="$(find "$TEST_TMP/home" -maxdepth 3 -name foreign-ancestor -type f -print)"
    [[ -n "$planned_sentinel" && "$(<"$planned_sentinel")" == planned-ancestor ]] || return 1
    [[ -n "$foreign_sentinel" && "$(<"$foreign_sentinel")" == foreign-ancestor ]] || return 1
    assert_not_exists "$TEST_TMP/home/.config/demo/config"
}

test_install_final_verification_rejects_changed_noop_without_deleting_arrival() {
    local hook
    new_fixture
    mkdir -p "$TEST_TMP/repo/home/.config/demo" "$TEST_TMP/home/.config/demo"
    printf 'create-source\n' >"$TEST_TMP/repo/home/.config/demo/create"
    printf 'noop-source\n' >"$TEST_TMP/repo/home/.config/demo/noop"
    ln -s "$TEST_TMP/repo/home/.config/demo/noop" "$TEST_TMP/home/.config/demo/noop"
    write_manifest $'demo|macos|file|.config/demo/create|plain|yes|1\ndemo|macos|file|.config/demo/noop|plain|yes|1'
    hook="$TEST_TMP/change-noop-after-publication"
    cat >"$hook" <<STUB
#!/bin/sh
if [ "\$1" = after_link_publish ]; then
    /bin/rm "$TEST_TMP/home/.config/demo/noop"
    printf 'foreign-arrival\n' >"$TEST_TMP/home/.config/demo/noop"
fi
STUB
    chmod +x "$hook"

    DOTFILES_TEST_INSTALL_HOOK="$hook" run_cli install --apply
    [[ "$CLI_STATUS" -ne 0 ]] || fail 'changed NOOP row falsely succeeded' || return 1
    assert_not_exists "$TEST_TMP/home/.config/demo/create" || return 1
    [[ -f "$TEST_TMP/home/.config/demo/noop" && ! -L "$TEST_TMP/home/.config/demo/noop" ]] || return 1
    [[ "$(<"$TEST_TMP/home/.config/demo/noop")" == foreign-arrival ]]
}

test_install_final_verification_accepts_mixed_create_backup_and_noop() {
    local backup
    new_fixture
    mkdir -p "$TEST_TMP/repo/home/.config/demo" "$TEST_TMP/home/.config/demo"
    printf 'create-source\n' >"$TEST_TMP/repo/home/.config/demo/create"
    printf 'backup-source\n' >"$TEST_TMP/repo/home/.config/demo/backup"
    printf 'noop-source\n' >"$TEST_TMP/repo/home/.config/demo/noop"
    printf 'backup-original\n' >"$TEST_TMP/home/.config/demo/backup"
    ln -s "$TEST_TMP/repo/home/.config/demo/noop" "$TEST_TMP/home/.config/demo/noop"
    write_manifest $'demo|macos|file|.config/demo/create|plain|yes|1\ndemo|macos|file|.config/demo/backup|plain|yes|1\ndemo|macos|file|.config/demo/noop|plain|yes|1'

    run_cli install --apply --backup
    assert_status 0 || return 1
    [[ "$(readlink "$TEST_TMP/home/.config/demo/create")" == "$TEST_TMP/repo/home/.config/demo/create" ]] || return 1
    [[ "$(readlink "$TEST_TMP/home/.config/demo/backup")" == "$TEST_TMP/repo/home/.config/demo/backup" ]] || return 1
    [[ "$(readlink "$TEST_TMP/home/.config/demo/noop")" == "$TEST_TMP/repo/home/.config/demo/noop" ]] || return 1
    backup="$(find "$TEST_TMP/state/backups" -path '*/files/.config/demo/backup' -type f -print)"
    [[ -n "$backup" && "$(<"$backup")" == backup-original ]]
}

test_install_final_verification_revalidates_source_and_rolls_back() {
    local hook
    new_fixture
    mkdir -p "$TEST_TMP/repo/home/.config/demo" "$TEST_TMP/outside"
    printf 'canonical\n' >"$TEST_TMP/repo/home/.config/demo/config"
    printf 'foreign-source\n' >"$TEST_TMP/outside/config"
    write_manifest 'demo|macos|file|.config/demo/config|plain|yes|1'
    hook="$TEST_TMP/replace-source-after-publication"
    cat >"$hook" <<STUB
#!/bin/sh
if [ "\$1" = after_link_publish ]; then
    /bin/rm "$TEST_TMP/repo/home/.config/demo/config"
    /bin/ln -s "$TEST_TMP/outside/config" "$TEST_TMP/repo/home/.config/demo/config"
fi
STUB
    chmod +x "$hook"

    DOTFILES_TEST_INSTALL_HOOK="$hook" run_cli install --apply
    [[ "$CLI_STATUS" -ne 0 ]] || fail 'unsafe source replacement falsely succeeded' || return 1
    assert_not_exists "$TEST_TMP/home/.config/demo/config" || return 1
    [[ -L "$TEST_TMP/repo/home/.config/demo/config" ]] || return 1
    [[ "$(readlink "$TEST_TMP/repo/home/.config/demo/config")" == "$TEST_TMP/outside/config" ]] || return 1
    [[ "$(<"$TEST_TMP/outside/config")" == foreign-source ]]
}

test_install_final_verification_revalidates_backup_without_deleting_foreign_data() {
    local hook backup owned_identity
    new_fixture
    mkdir -p "$TEST_TMP/repo/home/.config/demo" "$TEST_TMP/home/.config/demo"
    printf 'canonical\n' >"$TEST_TMP/repo/home/.config/demo/config"
    printf 'original\n' >"$TEST_TMP/home/.config/demo/config"
    write_manifest 'demo|macos|file|.config/demo/config|plain|yes|1'
    hook="$TEST_TMP/replace-backup-after-publication"
    cat >"$hook" <<STUB
#!/bin/sh
if [ "\$1" = after_link_publish ]; then
    : >"$TEST_TMP/backup-sibling-relocation-reached"
    backup=\$(find "$TEST_TMP/state/backups" -path '*/files/.config/demo/config' -type f -print)
    /bin/mv "\$backup" "\$backup.owned"
    /usr/bin/stat -f '%d:%i' "\$backup.owned" >"$TEST_TMP/backup-sibling-owned-identity"
    printf 'foreign-backup\n' >"\$backup"
fi
STUB
    chmod +x "$hook"

    DOTFILES_TEST_INSTALL_HOOK="$hook" run_cli install --apply --backup
    [[ "$CLI_STATUS" -ne 0 ]] || fail 'changed backup outcome falsely succeeded' || return 1
    [[ -f "$TEST_TMP/backup-sibling-relocation-reached" ]] || fail 'backup sibling relocation hook was not reached' || return 1
    owned_identity="$(<"$TEST_TMP/backup-sibling-owned-identity")"
    [[ -f "$TEST_TMP/home/.config/demo/config" && ! -L "$TEST_TMP/home/.config/demo/config" ]] || return 1
    [[ "$(/usr/bin/stat -f '%d:%i' "$TEST_TMP/home/.config/demo/config")" == "$owned_identity" ]] || return 1
    [[ "$(<"$TEST_TMP/home/.config/demo/config")" == original ]] || return 1
    backup="$(find "$TEST_TMP/state/backups" -path '*/files/.config/demo/config' -type f -print)"
    [[ -n "$backup" && "$(<"$backup")" == foreign-backup ]] || return 1
    [[ -z "$(find "$TEST_TMP/state/backups" -path '*/files/.config/demo/config.owned' -type f -print)" ]] || return 1
    [[ "$CLI_OUTPUT" != *"recorded recovery location=$backup"* ]]
}

test_install_cleanup_window_mutation_cannot_false_succeed() {
    local hook
    new_fixture
    mkdir -p "$TEST_TMP/repo/home/.config/demo" "$TEST_TMP/home/.config/demo"
    printf 'canonical\n' >"$TEST_TMP/repo/home/.config/demo/config"
    write_manifest 'demo|macos|file|.config/demo/config|plain|yes|1'
    hook="$TEST_TMP/mutate-during-cleanup"
    cat >"$hook" <<STUB
#!/bin/sh
if [ "\$1" = during_cleanup ]; then
    : >"$TEST_TMP/cleanup-window-reached"
    /bin/rm -- "$TEST_TMP/home/.config/demo/config"
    printf 'foreign-cleanup-arrival\n' >"$TEST_TMP/home/.config/demo/config"
fi
STUB
    chmod +x "$hook"

    DOTFILES_TEST_INSTALL_HOOK="$hook" run_cli install --apply
    [[ "$CLI_STATUS" -ne 0 ]] || fail 'cleanup-window target replacement falsely succeeded' || return 1
    [[ -f "$TEST_TMP/cleanup-window-reached" ]] || fail 'cleanup-window hook was not reached' || return 1
    [[ -f "$TEST_TMP/home/.config/demo/config" && ! -L "$TEST_TMP/home/.config/demo/config" ]] || return 1
    [[ "$(<"$TEST_TMP/home/.config/demo/config")" == foreign-cleanup-arrival ]]
}

test_install_last_precommit_mutation_cannot_false_succeed() {
    local hook
    new_fixture
    mkdir -p "$TEST_TMP/repo/home/.config/demo" "$TEST_TMP/home/.config/demo"
    printf 'canonical\n' >"$TEST_TMP/repo/home/.config/demo/config"
    write_manifest 'demo|macos|file|.config/demo/config|plain|yes|1'
    hook="$TEST_TMP/mutate-at-last-precommit"
    cat >"$hook" <<STUB
#!/bin/sh
if [ "\$1" = last_precommit ]; then
    : >"$TEST_TMP/last-precommit-reached"
    /bin/rm -- "$TEST_TMP/home/.config/demo/config"
    printf 'foreign-precommit-arrival\n' >"$TEST_TMP/home/.config/demo/config"
fi
STUB
    chmod +x "$hook"

    DOTFILES_TEST_INSTALL_HOOK="$hook" run_cli install --apply
    [[ "$CLI_STATUS" -ne 0 ]] || fail 'last-precommit target replacement falsely succeeded' || return 1
    [[ -f "$TEST_TMP/last-precommit-reached" ]] || fail 'last-precommit hook was not reached' || return 1
    [[ -f "$TEST_TMP/home/.config/demo/config" && ! -L "$TEST_TMP/home/.config/demo/config" ]] || return 1
    [[ "$(<"$TEST_TMP/home/.config/demo/config")" == foreign-precommit-arrival ]]
}

test_install_link_post_move_root_detach_recovers_owned_publication() {
    local hook quarantine
    new_fixture
    mkdir -p "$TEST_TMP/repo/home/.config/demo" "$TEST_TMP/home/.config/demo"
    printf 'canonical\n' >"$TEST_TMP/repo/home/.config/demo/config"
    write_manifest 'demo|macos|file|.config/demo/config|plain|yes|1'
    hook="$TEST_TMP/detach-root-after-link-move"
    cat >"$hook" <<STUB
#!/bin/sh
if [ "\$1" = link_publish_after_move ]; then
    : >"$TEST_TMP/link-root-post-move-reached"
    /bin/mv -- "\$5" "\$5.detached"
    /bin/mkdir -- "\$5"
    printf 'foreign-root\n' >"\$5/foreign-root"
fi
STUB
    chmod +x "$hook"

    DOTFILES_TEST_INSTALL_HOOK="$hook" run_cli install --apply
    [[ "$CLI_STATUS" -ne 0 ]] || fail 'detached root link publication falsely succeeded' || return 1
    [[ -f "$TEST_TMP/link-root-post-move-reached" ]] || fail 'link post-move root hook was not reached' || return 1
    [[ "$(<"$TEST_TMP/home/foreign-root")" == foreign-root ]] || return 1
    assert_not_exists "$TEST_TMP/home/.config/demo/config" || return 1
    assert_not_exists "$TEST_TMP/home.detached/.config/demo/config" || return 1
    quarantine="$(find "$TEST_TMP/state/transactions" -path '*/quarantine/link-*/actual' -type l -print)"
    [[ -n "$quarantine" && "$(readlink "$quarantine")" == "$TEST_TMP/repo/home/.config/demo/config" ]]
}

test_install_link_post_move_nested_detach_recovers_owned_publication() {
    local hook quarantine
    new_fixture
    mkdir -p "$TEST_TMP/repo/home/.config/demo" "$TEST_TMP/home/.config/demo"
    printf 'canonical\n' >"$TEST_TMP/repo/home/.config/demo/config"
    write_manifest 'demo|macos|file|.config/demo/config|plain|yes|1'
    hook="$TEST_TMP/detach-parent-after-link-move"
    cat >"$hook" <<STUB
#!/bin/sh
if [ "\$1" = link_publish_after_move ]; then
    : >"$TEST_TMP/link-nested-post-move-reached"
    parent=\${3%/*}
    /bin/mv -- "\$parent" "\$parent.detached"
    /bin/mkdir -- "\$parent"
    printf 'foreign-parent\n' >"\$parent/foreign-parent"
fi
STUB
    chmod +x "$hook"

    DOTFILES_TEST_INSTALL_HOOK="$hook" run_cli install --apply
    [[ "$CLI_STATUS" -ne 0 ]] || fail 'detached nested link publication falsely succeeded' || return 1
    [[ -f "$TEST_TMP/link-nested-post-move-reached" ]] || fail 'link post-move nested hook was not reached' || return 1
    [[ "$(<"$TEST_TMP/home/.config/demo/foreign-parent")" == foreign-parent ]] || return 1
    assert_not_exists "$TEST_TMP/home/.config/demo/config" || return 1
    assert_not_exists "$TEST_TMP/home/.config/demo.detached/config" || fail "nested detach output: $CLI_OUTPUT" || return 1
    quarantine="$(find "$TEST_TMP/state/transactions" -path '*/quarantine/link-*/actual' -type l -print)"
    [[ -n "$quarantine" && "$(readlink "$quarantine")" == "$TEST_TMP/repo/home/.config/demo/config" ]]
}

test_install_backup_post_move_state_root_detach_restores_owned_backup() {
    local hook
    new_fixture
    mkdir -p "$TEST_TMP/repo/home/.config/demo" "$TEST_TMP/home/.config/demo"
    printf 'canonical\n' >"$TEST_TMP/repo/home/.config/demo/config"
    printf 'original\n' >"$TEST_TMP/home/.config/demo/config"
    write_manifest 'demo|macos|file|.config/demo/config|plain|yes|1'
    hook="$TEST_TMP/detach-state-after-backup-move"
    cat >"$hook" <<STUB
#!/bin/sh
if [ "\$1" = backup_publish_after_move ]; then
    : >"$TEST_TMP/backup-root-post-move-reached"
    /bin/mv -- "\$5" "\$5.detached"
    /bin/mkdir -- "\$5"
    printf 'foreign-state\n' >"\$5/foreign-state"
fi
STUB
    chmod +x "$hook"

    DOTFILES_TEST_INSTALL_HOOK="$hook" run_cli install --apply --backup
    [[ "$CLI_STATUS" -ne 0 ]] || fail 'detached state-root backup publication falsely succeeded' || return 1
    [[ -f "$TEST_TMP/backup-root-post-move-reached" ]] || fail 'backup post-move root hook was not reached' || return 1
    [[ "$(<"$TEST_TMP/state/foreign-state")" == foreign-state ]] || return 1
    [[ -f "$TEST_TMP/home/.config/demo/config" && ! -L "$TEST_TMP/home/.config/demo/config" ]] || return 1
    [[ "$(<"$TEST_TMP/home/.config/demo/config")" == original ]]
}

test_install_backup_post_move_nested_detach_restores_owned_backup() {
    local hook
    new_fixture
    mkdir -p "$TEST_TMP/repo/home/.config/demo" "$TEST_TMP/home/.config/demo"
    printf 'canonical\n' >"$TEST_TMP/repo/home/.config/demo/config"
    printf 'original\n' >"$TEST_TMP/home/.config/demo/config"
    write_manifest 'demo|macos|file|.config/demo/config|plain|yes|1'
    hook="$TEST_TMP/detach-parent-after-backup-move"
    cat >"$hook" <<STUB
#!/bin/sh
if [ "\$1" = backup_publish_after_move ]; then
    : >"$TEST_TMP/backup-nested-post-move-reached"
    parent=\${3%/*}
    /bin/mv -- "\$parent" "\$parent.detached"
    /bin/mkdir -- "\$parent"
    printf 'foreign-backup-parent\n' >"\$parent/foreign-parent"
fi
STUB
    chmod +x "$hook"

    DOTFILES_TEST_INSTALL_HOOK="$hook" run_cli install --apply --backup
    [[ "$CLI_STATUS" -ne 0 ]] || fail 'detached nested backup publication falsely succeeded' || return 1
    [[ -f "$TEST_TMP/backup-nested-post-move-reached" ]] || fail 'backup post-move nested hook was not reached' || return 1
    [[ -f "$TEST_TMP/home/.config/demo/config" && ! -L "$TEST_TMP/home/.config/demo/config" ]] || return 1
    [[ "$(<"$TEST_TMP/home/.config/demo/config")" == original ]] || return 1
    [[ -n "$(find "$TEST_TMP/state" -path '*/files/.config/demo/foreign-parent' -type f -print)" ]]
}

test_install_backup_stage_post_move_root_detach_restores_in_recorded_parent() {
    local hook
    new_fixture
    mkdir -p "$TEST_TMP/repo/home/.config/demo" "$TEST_TMP/home/.config/demo"
    printf 'canonical\n' >"$TEST_TMP/repo/home/.config/demo/config"
    printf 'original\n' >"$TEST_TMP/home/.config/demo/config"
    write_manifest 'demo|macos|file|.config/demo/config|plain|yes|1'
    hook="$TEST_TMP/detach-root-after-backup-stage-move"
    cat >"$hook" <<STUB
#!/bin/sh
if [ "\$1" = backup_stage_after_move ]; then
    : >"$TEST_TMP/backup-stage-root-post-move-reached"
    /bin/mv -- "\$5" "\$5.detached"
    /bin/mkdir -- "\$5"
    printf 'foreign-root\n' >"\$5/foreign-root"
fi
STUB
    chmod +x "$hook"

    DOTFILES_TEST_INSTALL_HOOK="$hook" run_cli install --apply --backup
    [[ "$CLI_STATUS" -ne 0 ]] || fail 'detached root backup staging falsely succeeded' || return 1
    [[ -f "$TEST_TMP/backup-stage-root-post-move-reached" ]] || fail 'backup stage root post-move hook was not reached' || return 1
    [[ "$(<"$TEST_TMP/home/foreign-root")" == foreign-root ]] || return 1
    assert_not_exists "$TEST_TMP/home/.config/demo/config" || return 1
    [[ -f "$TEST_TMP/home.detached/.config/demo/config" && ! -L "$TEST_TMP/home.detached/.config/demo/config" ]] || return 1
    [[ "$(<"$TEST_TMP/home.detached/.config/demo/config")" == original ]]
}

test_install_backup_stage_post_move_nested_detach_restores_in_recorded_parent() {
    local hook
    new_fixture
    mkdir -p "$TEST_TMP/repo/home/.config/demo" "$TEST_TMP/home/.config/demo"
    printf 'canonical\n' >"$TEST_TMP/repo/home/.config/demo/config"
    printf 'original\n' >"$TEST_TMP/home/.config/demo/config"
    write_manifest 'demo|macos|file|.config/demo/config|plain|yes|1'
    hook="$TEST_TMP/detach-parent-after-backup-stage-move"
    cat >"$hook" <<STUB
#!/bin/sh
if [ "\$1" = backup_stage_after_move ]; then
    : >"$TEST_TMP/backup-stage-nested-post-move-reached"
    parent=\${3%/*}
    /bin/mv -- "\$parent" "\$parent.detached"
    /bin/mkdir -- "\$parent"
    printf 'foreign-parent\n' >"\$parent/foreign-parent"
fi
STUB
    chmod +x "$hook"

    DOTFILES_TEST_INSTALL_HOOK="$hook" run_cli install --apply --backup
    [[ "$CLI_STATUS" -ne 0 ]] || fail 'detached nested backup staging falsely succeeded' || return 1
    [[ -f "$TEST_TMP/backup-stage-nested-post-move-reached" ]] || fail 'backup stage nested post-move hook was not reached' || return 1
    [[ "$(<"$TEST_TMP/home/.config/demo/foreign-parent")" == foreign-parent ]] || return 1
    assert_not_exists "$TEST_TMP/home/.config/demo/config" || return 1
    [[ -f "$TEST_TMP/home/.config/demo.detached/config" && ! -L "$TEST_TMP/home/.config/demo.detached/config" ]] || return 1
    [[ "$(<"$TEST_TMP/home/.config/demo.detached/config")" == original ]]
}

test_install_backup_stage_replacement_is_not_published_or_deleted() {
    local hook recorded identity
    new_fixture
    mkdir -p "$TEST_TMP/repo/home/.config/demo" "$TEST_TMP/home/.config/demo"
    printf 'canonical\n' >"$TEST_TMP/repo/home/.config/demo/config"
    printf 'original\n' >"$TEST_TMP/home/.config/demo/config"
    write_manifest 'demo|macos|file|.config/demo/config|plain|yes|1'
    hook="$TEST_TMP/replace-owned-backup-stage"
    cat >"$hook" <<STUB
#!/bin/sh
if [ "\$1" = backup_stage_after_move ]; then
    printf '%s\n' "\$3" >"$TEST_TMP/recorded-backup-stage"
    printf '%s\n' "\$4" >"$TEST_TMP/recorded-backup-stage-identity"
elif [ "\$1" = after_backup_stage ]; then
    : >"$TEST_TMP/backup-stage-replacement-reached"
    /bin/mv -- "\$3" "\$3.owned"
    printf 'foreign-stage\n' >"\$3"
fi
STUB
    chmod +x "$hook"

    DOTFILES_TEST_INSTALL_HOOK="$hook" run_cli install --apply --backup
    [[ "$CLI_STATUS" -ne 0 ]] || fail 'foreign backup stage replacement was published' || return 1
    [[ -f "$TEST_TMP/backup-stage-replacement-reached" ]] || fail 'backup stage replacement hook was not reached' || return 1
    recorded="$(<"$TEST_TMP/recorded-backup-stage")"
    identity="$(<"$TEST_TMP/recorded-backup-stage-identity")"
    [[ -f "$recorded" && "$(<"$recorded")" == foreign-stage ]] || return 1
    assert_not_exists "$recorded.owned" || return 1
    [[ -f "$TEST_TMP/home/.config/demo/config" && ! -L "$TEST_TMP/home/.config/demo/config" ]] || return 1
    [[ "$(/usr/bin/stat -f '%d:%i' "$TEST_TMP/home/.config/demo/config")" == "$identity" ]] || return 1
    [[ "$(<"$TEST_TMP/home/.config/demo/config")" == original ]] || return 1
    [[ "$CLI_OUTPUT" != *"recorded recovery location=$recorded"* ]] || return 1
    [[ -z "$(find "$TEST_TMP/state/backups" -path '*/files/.config/demo/config' -type f -print)" ]]
}

test_install_backup_source_same_fingerprint_new_inode_is_never_moved() {
    local hook substitute_identity
    new_fixture
    mkdir -p "$TEST_TMP/repo/home/.config/demo" "$TEST_TMP/home/.config/demo"
    printf 'canonical\n' >"$TEST_TMP/repo/home/.config/demo/config"
    printf 'same-payload\n' >"$TEST_TMP/home/.config/demo/config"
    write_manifest 'demo|macos|file|.config/demo/config|plain|yes|1'
    hook="$TEST_TMP/replace-backup-source-with-same-fingerprint"
    cat >"$hook" <<STUB
#!/bin/sh
if [ "\$1" = before_backup_stage ]; then
    : >"$TEST_TMP/backup-source-substitution-reached"
    /bin/mv -- "\$2" "\$2.pre-inspection-owned"
    printf 'same-payload\n' >"\$2"
    /usr/bin/stat -f '%d:%i' "\$2" >"$TEST_TMP/backup-source-substitute-identity"
fi
STUB
    chmod +x "$hook"

    DOTFILES_TEST_INSTALL_HOOK="$hook" run_cli install --apply --backup
    [[ "$CLI_STATUS" -ne 0 ]] || fail 'same-fingerprint substitute was treated as the inspected backup source' || return 1
    [[ -f "$TEST_TMP/backup-source-substitution-reached" ]] || fail 'backup source substitution hook was not reached' || return 1
    substitute_identity="$(<"$TEST_TMP/backup-source-substitute-identity")"
    [[ -f "$TEST_TMP/home/.config/demo/config" && ! -L "$TEST_TMP/home/.config/demo/config" ]] || return 1
    [[ "$(/usr/bin/stat -f '%d:%i' "$TEST_TMP/home/.config/demo/config")" == "$substitute_identity" ]] || return 1
    [[ "$(<"$TEST_TMP/home/.config/demo/config")" == same-payload ]] || return 1
    [[ "$(<"$TEST_TMP/home/.config/demo/config.pre-inspection-owned")" == same-payload ]] || return 1
    [[ -z "$(find "$TEST_TMP/state/backups" -path '*/files/.config/demo/config' -type f -print)" ]]
}

test_install_final_verification_rejects_replaced_report_without_deleting_arrival() {
    local hook report owned
    new_fixture
    mkdir -p "$TEST_TMP/repo/home/.config/demo" "$TEST_TMP/home/.config/demo"
    printf 'canonical\n' >"$TEST_TMP/repo/home/.config/demo/config"
    printf 'original\n' >"$TEST_TMP/home/.config/demo/config"
    write_manifest 'demo|macos|file|.config/demo/config|plain|yes|1'
    hook="$TEST_TMP/replace-report-after-link"
    cat >"$hook" <<STUB
#!/bin/sh
if [ "\$1" = after_link_publish ]; then
    : >"$TEST_TMP/report-replacement-reached"
    report=\$(find "$TEST_TMP/state/backups" -name report.tsv -type f -print)
    /bin/mv -- "\$report" "\$report.owned"
    printf 'foreign-report\n' >"\$report"
fi
STUB
    chmod +x "$hook"

    DOTFILES_TEST_INSTALL_HOOK="$hook" run_cli install --apply --backup
    [[ "$CLI_STATUS" -ne 0 ]] || fail 'replaced report falsely passed final verification' || return 1
    [[ -f "$TEST_TMP/report-replacement-reached" ]] || return 1
    report="$(find "$TEST_TMP/state/backups" -name report.tsv -type f -print)"
    owned="$(find "$TEST_TMP/state/backups" -name report.tsv.owned -type f -print)"
    [[ -n "$report" && "$(<"$report")" == foreign-report ]] || return 1
    [[ -n "$owned" ]] || return 1
    grep -Fq $'MOVE\t.config/demo/config\t' "$owned" || return 1
    grep -Fq $'LINK\t.config/demo/config\t' "$owned"
}

test_install_signal_at_final_verification_rolls_back_before_commit() {
    local hook
    new_fixture
    mkdir -p "$TEST_TMP/repo/home/.config/demo" "$TEST_TMP/home/.config/demo"
    printf 'canonical\n' >"$TEST_TMP/repo/home/.config/demo/config"
    write_manifest 'demo|macos|file|.config/demo/config|plain|yes|1'
    hook="$TEST_TMP/signal-final-verification"
    cat >"$hook" <<STUB
#!/bin/sh
if [ "\$1" = final_verification_started ]; then
    : >"$TEST_TMP/final-verification-reached"
    kill -TERM "\$PPID"
fi
STUB
    chmod +x "$hook"

    DOTFILES_TEST_INSTALL_HOOK="$hook" run_cli install --apply
    assert_status 143 || return 1
    [[ -f "$TEST_TMP/final-verification-reached" ]] || fail 'final verification signal hook was not reached' || return 1
    assert_not_exists "$TEST_TMP/home/.config/demo/config" || return 1
    assert_not_exists "$TEST_TMP/state/install.lock"
}

test_install_after_link_publish_root_detach_refreshes_owned_location() {
    local hook quarantine
    new_fixture
    mkdir -p "$TEST_TMP/repo/home/.config/demo" "$TEST_TMP/home/.config/demo"
    printf 'canonical\n' >"$TEST_TMP/repo/home/.config/demo/config"
    write_manifest 'demo|macos|file|.config/demo/config|plain|yes|1'
    hook="$TEST_TMP/detach-root-after-late-link-hook"
    cat >"$hook" <<STUB
#!/bin/sh
if [ "\$1" = after_link_publish ]; then
    : >"$TEST_TMP/late-link-root-detach-reached"
    /bin/mv -- "$TEST_TMP/home" "$TEST_TMP/home.detached"
    /bin/mkdir -- "$TEST_TMP/home"
    printf 'foreign-root\n' >"$TEST_TMP/home/foreign-root"
fi
STUB
    chmod +x "$hook"

    DOTFILES_TEST_INSTALL_HOOK="$hook" run_cli install --apply
    [[ "$CLI_STATUS" -ne 0 ]] || fail 'late link root detach falsely succeeded' || return 1
    [[ -f "$TEST_TMP/late-link-root-detach-reached" ]] || fail 'late link root detach hook was not reached' || return 1
    [[ "$(<"$TEST_TMP/home/foreign-root")" == foreign-root ]] || return 1
    assert_not_exists "$TEST_TMP/home.detached/.config/demo/config" || return 1
    quarantine="$(find "$TEST_TMP/state/transactions" -path '*/quarantine/link-*/actual' -type l -print)"
    [[ -n "$quarantine" && "$(readlink "$quarantine")" == "$TEST_TMP/repo/home/.config/demo/config" ]]
}

test_install_after_backup_stage_nested_detach_refreshes_restore_location() {
    local hook
    new_fixture
    mkdir -p "$TEST_TMP/repo/home/.config/demo" "$TEST_TMP/home/.config/demo"
    printf 'canonical\n' >"$TEST_TMP/repo/home/.config/demo/config"
    printf 'original\n' >"$TEST_TMP/home/.config/demo/config"
    write_manifest 'demo|macos|file|.config/demo/config|plain|yes|1'
    hook="$TEST_TMP/detach-nested-parent-after-late-backup-stage"
    cat >"$hook" <<STUB
#!/bin/sh
if [ "\$1" = after_backup_stage ]; then
    : >"$TEST_TMP/late-backup-stage-nested-detach-reached"
    parent=\${3%/*}
    /bin/mv -- "\$parent" "\$parent.detached"
    /bin/mkdir -- "\$parent"
    printf 'foreign-target\n' >"\$parent/config"
fi
STUB
    chmod +x "$hook"

    DOTFILES_TEST_INSTALL_HOOK="$hook" run_cli install --apply --backup
    [[ "$CLI_STATUS" -ne 0 ]] || fail 'late backup-stage nested detach falsely succeeded' || return 1
    [[ -f "$TEST_TMP/late-backup-stage-nested-detach-reached" ]] || fail 'late backup-stage nested hook was not reached' || return 1
    [[ -f "$TEST_TMP/home/.config/demo/config" && "$(<"$TEST_TMP/home/.config/demo/config")" == foreign-target ]] || return 1
    [[ -f "$TEST_TMP/home/.config/demo.detached/config" && ! -L "$TEST_TMP/home/.config/demo.detached/config" ]] || return 1
    [[ "$(<"$TEST_TMP/home/.config/demo.detached/config")" == original ]]
}

test_install_after_backup_move_state_detach_refreshes_report_and_publication() {
    local hook backup backup_parent actual_backup report expected_row
    new_fixture
    mkdir -p "$TEST_TMP/repo/home/.config/demo" "$TEST_TMP/home/.config/demo"
    printf 'canonical\n' >"$TEST_TMP/repo/home/.config/demo/config"
    printf 'original\n' >"$TEST_TMP/home/.config/demo/config"
    write_manifest 'demo|macos|file|.config/demo/config|plain|yes|1'
    hook="$TEST_TMP/detach-state-after-late-backup-hook"
    cat >"$hook" <<STUB
#!/bin/sh
if [ "\$1" = after_backup_move ]; then
    : >"$TEST_TMP/late-backup-state-detach-reached"
    /bin/mv -- "$TEST_TMP/state" "$TEST_TMP/state.after-backup"
    /bin/mkdir -- "$TEST_TMP/state"
    printf 'foreign-state\n' >"$TEST_TMP/state/foreign-state"
fi
STUB
    chmod +x "$hook"

    DOTFILES_TEST_INSTALL_HOOK="$hook" run_cli install --apply --backup
    assert_status 0 || return 1
    [[ -f "$TEST_TMP/late-backup-state-detach-reached" ]] || fail 'late backup state detach hook was not reached' || return 1
    [[ "$(<"$TEST_TMP/state/foreign-state")" == foreign-state ]] || return 1
    backup="$(find "$TEST_TMP/state.after-backup/backups" -path '*/files/.config/demo/config' -type f -print)"
    [[ -n "$backup" && "$(<"$backup")" == original ]] || return 1
    backup_parent="$(cd "${backup%/*}" && /bin/pwd -P)" || return 1
    actual_backup="$backup_parent/${backup##*/}"
    report="$(find "$TEST_TMP/state.after-backup/backups" -name report.tsv -type f -print)"
    expected_row="$(printf 'MOVE\t.config/demo/config\t%s\t%s' \
        "$TEST_TMP/home/.config/demo/config" "$actual_backup")"
    grep -Fqx "$expected_row" "$report" || return 1
}

test_install_last_precommit_mixed_nested_detach_reports_path_unavailable() {
    local hook owned_identity foreign_identity quarantine
    new_fixture
    mkdir -p "$TEST_TMP/repo/home/.config/one" "$TEST_TMP/repo/home/.config/two" \
        "$TEST_TMP/home/.config/one" "$TEST_TMP/home/.config/two"
    printf 'one\n' >"$TEST_TMP/repo/home/.config/one/config"
    printf 'two\n' >"$TEST_TMP/repo/home/.config/two/config"
    write_manifest $'one|macos|file|.config/one/config|plain|yes|1\ntwo|macos|file|.config/two/config|plain|yes|1'
    hook="$TEST_TMP/detach-one-mixed-parent-at-last-precommit"
    cat >"$hook" <<STUB
#!/bin/sh
if [ "\$1" = last_precommit ]; then
    : >"$TEST_TMP/mixed-last-precommit-detach-reached"
    /usr/bin/stat -f '%d:%i' "$TEST_TMP/home/.config/two/config" >"$TEST_TMP/mixed-owned-identity"
    /bin/mv -- "$TEST_TMP/home/.config/two" "$TEST_TMP/home/.config/two.detached"
    /bin/mkdir -- "$TEST_TMP/home/.config/two"
    printf 'foreign-two\n' >"$TEST_TMP/home/.config/two/config"
    /usr/bin/stat -f '%d:%i' "$TEST_TMP/home/.config/two/config" >"$TEST_TMP/mixed-foreign-identity"
fi
STUB
    chmod +x "$hook"

    DOTFILES_TEST_INSTALL_HOOK="$hook" run_cli install --apply
    [[ "$CLI_STATUS" -ne 0 ]] || fail 'mixed last-precommit nested detach falsely succeeded' || return 1
    [[ -f "$TEST_TMP/mixed-last-precommit-detach-reached" ]] || fail 'mixed last-precommit detach hook was not reached' || return 1
    owned_identity="$(<"$TEST_TMP/mixed-owned-identity")"
    foreign_identity="$(<"$TEST_TMP/mixed-foreign-identity")"
    [[ "$(/usr/bin/stat -f '%d:%i' "$TEST_TMP/home/.config/two/config")" == "$foreign_identity" ]] || return 1
    [[ "$(<"$TEST_TMP/home/.config/two/config")" == foreign-two ]] || return 1
    [[ -L "$TEST_TMP/home/.config/two.detached/config" ]] || return 1
    [[ "$(/usr/bin/stat -f '%d:%i' "$TEST_TMP/home/.config/two.detached/config")" == "$owned_identity" ]] || return 1
    assert_contains "recovery path unavailable identity=$owned_identity" || return 1
    [[ "$CLI_OUTPUT" != *"recorded recovery location=$TEST_TMP/home/.config/two/config"* ]] || return 1
    quarantine="$(find "$TEST_TMP/state/transactions" -path '*/quarantine/link-*/actual' -type l -print)"
    [[ -n "$quarantine" && "$(readlink "$quarantine")" == "$TEST_TMP/repo/home/.config/one/config" ]]
}

test_install_production_ignores_path_and_test_primitive_overrides() {
    local stub_bin status output
    new_fixture
    mkdir -p "$TEST_TMP/repo/home/.config/demo" "$TEST_TMP/stub-bin"
    printf 'canonical\n' >"$TEST_TMP/repo/home/.config/demo/config"
    write_manifest 'demo|macos|file|.config/demo/config|plain|yes|1'
    stub_bin="$TEST_TMP/stub-bin"
    cat >"$stub_bin/stat" <<STUB
#!/bin/sh
: >"$TEST_TMP/path-stat-ran"
exit 99
STUB
    cat >"$stub_bin/mv" <<STUB
#!/bin/sh
: >"$TEST_TMP/path-mv-ran"
exit 99
STUB
    cat >"$stub_bin/override-stat" <<STUB
#!/bin/sh
: >"$TEST_TMP/override-stat-ran"
exit 99
STUB
    cat >"$stub_bin/override-mv" <<STUB
#!/bin/sh
: >"$TEST_TMP/override-mv-ran"
exit 99
STUB
    chmod +x "$stub_bin/stat" "$stub_bin/mv" "$stub_bin/override-stat" "$stub_bin/override-mv"

    if output="$(HOME="$TEST_TMP/home" XDG_STATE_HOME="$TEST_TMP/state" \
        DOTFILES_TEST_TRANSACTION_KERNEL=Linux \
        DOTFILES_TEST_STAT_COMMAND="$stub_bin/override-stat" \
        DOTFILES_TEST_MOVE_COMMAND="$stub_bin/override-mv" \
        PATH="$stub_bin:/usr/bin:/bin" "$TEST_TMP/repo/bin/dotfiles" install --apply 2>&1)"; then
        status=0
    else
        status=$?
    fi
    [[ "$status" -eq 0 ]] || fail "production primitive pinning failed with status $status: $output" || return 1
    [[ "$(readlink "$TEST_TMP/home/.config/demo/config")" == "$TEST_TMP/repo/home/.config/demo/config" ]] || return 1
    assert_not_exists "$TEST_TMP/path-stat-ran" || return 1
    assert_not_exists "$TEST_TMP/path-mv-ran" || return 1
    assert_not_exists "$TEST_TMP/override-stat-ran" || return 1
    assert_not_exists "$TEST_TMP/override-mv-ran"
}

test_install_test_mode_exercises_bsd_and_gnu_primitive_arguments() {
    local style stub_bin stat_log move_log
    for style in bsd gnu; do
        new_fixture
        mkdir -p "$TEST_TMP/repo/home/.config/demo" "$TEST_TMP/stub-bin"
        printf 'canonical\n' >"$TEST_TMP/repo/home/.config/demo/config"
        write_manifest 'demo|macos|file|.config/demo/config|plain|yes|1'
        stub_bin="$TEST_TMP/stub-bin"
        stat_log="$TEST_TMP/$style-stat-args"
        move_log="$TEST_TMP/$style-move-args"
        cat >"$stub_bin/stat" <<STUB
#!/bin/sh
printf '%s\n' "\$*" >>"$stat_log"
if [ "$style" = bsd ]; then
    [ "\$1" = -f ] && [ "\$2" = %d:%i ] || exit 91
    shift 2
else
    [ "\$1" = -c ] && [ "\$2" = %d:%i ] && [ "\$3" = -- ] || exit 92
    shift 3
fi
exec /usr/bin/stat -f '%d:%i' "\$1"
STUB
        cat >"$stub_bin/mv" <<STUB
#!/bin/sh
printf '%s\n' "\$*" >>"$move_log"
if [ "$style" = bsd ]; then
    [ "\$1" = -h ] && [ "\$2" = -n ] && [ "\$3" = -- ] || exit 93
    shift 3
else
    [ "\$1" = -n ] && [ "\$2" = -T ] && [ "\$3" = -- ] || exit 94
    shift 3
fi
exec /bin/mv -h -n -- "\$1" "\$2"
STUB
        chmod +x "$stub_bin/stat" "$stub_bin/mv"

        if [[ "$style" == bsd ]]; then
            DOTFILES_TEST_TRANSACTION_KERNEL=Darwin DOTFILES_TEST_STAT_COMMAND="$stub_bin/stat" \
                DOTFILES_TEST_MOVE_COMMAND="$stub_bin/mv" run_cli install --apply
        else
            DOTFILES_TEST_TRANSACTION_KERNEL=Linux DOTFILES_TEST_STAT_COMMAND="$stub_bin/stat" \
                DOTFILES_TEST_MOVE_COMMAND="$stub_bin/mv" run_cli install --apply
        fi
        assert_status 0 || return 1
        [[ -s "$stat_log" && -s "$move_log" ]] || return 1
    done
}

test_install_rejects_malformed_and_multiline_path_identities() {
    local mode stub
    for mode in malformed multiline; do
        new_fixture
        mkdir -p "$TEST_TMP/repo/home/.config/demo" "$TEST_TMP/stub-bin"
        printf 'canonical\n' >"$TEST_TMP/repo/home/.config/demo/config"
        write_manifest 'demo|macos|file|.config/demo/config|plain|yes|1'
        stub="$TEST_TMP/stub-bin/stat"
        cat >"$stub" <<STUB
#!/bin/sh
if [ "$mode" = malformed ]; then
    printf 'not-an-identity\n'
else
    printf '1:2\n3:4\n'
fi
STUB
        chmod +x "$stub"

        DOTFILES_TEST_TRANSACTION_KERNEL=Darwin DOTFILES_TEST_STAT_COMMAND="$stub" run_cli install --apply
        [[ "$CLI_STATUS" -ne 0 ]] || fail "$mode identity was accepted" || return 1
        assert_not_exists "$TEST_TMP/home/.config/demo/config" || return 1
    done
}

test_install_gnu_stat_selector_avoids_literal_format_operand_collision() {
    local stub move_stub
    new_fixture
    mkdir -p "$TEST_TMP/repo/home/.config/demo" "$TEST_TMP/stub-bin"
    printf 'canonical\n' >"$TEST_TMP/repo/home/.config/demo/config"
    write_manifest 'demo|macos|file|.config/demo/config|plain|yes|1'
    stub="$TEST_TMP/stub-bin/stat"
    move_stub="$TEST_TMP/stub-bin/mv"
    cat >"$stub" <<STUB
#!/bin/sh
if [ "\$1" = -f ]; then
    printf 'literal-format-file\n9:9\n'
    exit 0
fi
[ "\$1" = -c ] && [ "\$2" = %d:%i ] && [ "\$3" = -- ] || exit 95
shift 3
printf '%s\n' "\$*" >>"$TEST_TMP/gnu-stat-operands"
exec /usr/bin/stat -f '%d:%i' "\$1"
STUB
    cat >"$move_stub" <<'STUB'
#!/bin/sh
[ "$1" = -n ] && [ "$2" = -T ] && [ "$3" = -- ] || exit 96
shift 3
exec /bin/mv -h -n -- "$1" "$2"
STUB
    chmod +x "$stub" "$move_stub"

    DOTFILES_TEST_TRANSACTION_KERNEL=Linux DOTFILES_TEST_STAT_COMMAND="$stub" \
        DOTFILES_TEST_MOVE_COMMAND="$move_stub" run_cli install --apply
    assert_status 0 || return 1
    [[ -s "$TEST_TMP/gnu-stat-operands" ]] || return 1
    [[ "$(readlink "$TEST_TMP/home/.config/demo/config")" == "$TEST_TMP/repo/home/.config/demo/config" ]]
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

    DOTFILES_TEST_STAT_COMMAND="$stub_path" run_cli install --apply
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
    local hook backup backup_parent actual_backup report expected_row
    new_fixture
    mkdir -p "$TEST_TMP/repo/home/.config/demo" "$TEST_TMP/home/.config/demo" "$TEST_TMP/outside-state"
    printf 'canonical\n' >"$TEST_TMP/repo/home/.config/demo/config"
    printf 'existing\n' >"$TEST_TMP/home/.config/demo/config"
    write_manifest 'demo|macos|file|.config/demo/config|plain|yes|1'
    hook="$TEST_TMP/swap-state-after-check"
    cat >"$hook" <<STUB
#!/bin/sh
if [ "\$1" = backup_move_after_state_check ]; then
    : >"$TEST_TMP/state-detach-report-path-reached"
    /bin/mv "$TEST_TMP/state" "$TEST_TMP/state.pinned"
    /bin/ln -s "$TEST_TMP/outside-state" "$TEST_TMP/state"
fi
STUB
    chmod +x "$hook"

    DOTFILES_TEST_INSTALL_HOOK="$hook" run_cli install --apply --backup
    assert_status 0 || return 1
    [[ -f "$TEST_TMP/state-detach-report-path-reached" ]] || fail 'state detach report-path hook was not reached' || return 1
    backup="$(find "$TEST_TMP/state.pinned/backups" -path '*/files/.config/demo/config' -type f -print)"
    [[ -n "$backup" && "$(<"$backup")" == existing ]] || return 1
    backup_parent="$(cd "${backup%/*}" && /bin/pwd -P)" || return 1
    actual_backup="$backup_parent/${backup##*/}"
    report="$(find "$TEST_TMP/state.pinned/backups" -name report.tsv -type f -print)"
    expected_row="$(printf 'MOVE\t.config/demo/config\t%s\t%s' \
        "$TEST_TMP/home/.config/demo/config" "$actual_backup")"
    [[ -n "$report" ]] || return 1
    grep -Fqx "$expected_row" "$report" || fail "report did not name actual backup $actual_backup: $(<"$report")" || return 1
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

test_hyprland_animations_preserve_values_and_curve_types() {
    local looknfeel="$PROJECT_ROOT/home/.config/hypr/hyprland/looknfeel.lua"
    local actual expected

    actual="$(grep '^hl\.animation' "$looknfeel")"
    expected='hl.animation({ leaf = "global", enabled = true, speed = 10, bezier = "default" })
hl.animation({ leaf = "border", enabled = true, speed = 5.39, bezier = "easeOutQuint" })
hl.animation({ leaf = "windows", enabled = true, speed = 4.79, spring = "easy" })
hl.animation({ leaf = "windowsIn", enabled = true, speed = 4.1, spring = "easy", style = "popin 87%" })
hl.animation({ leaf = "windowsOut", enabled = true, speed = 1.49, bezier = "linear", style = "popin 87%" })
hl.animation({ leaf = "fadeIn", enabled = true, speed = 1.73, bezier = "almostLinear" })
hl.animation({ leaf = "fadeOut", enabled = true, speed = 1.46, bezier = "almostLinear" })
hl.animation({ leaf = "fade", enabled = true, speed = 3.03, bezier = "quick" })
hl.animation({ leaf = "layers", enabled = true, speed = 3.81, bezier = "easeOutQuint" })
hl.animation({ leaf = "layersIn", enabled = true, speed = 4, bezier = "easeOutQuint", style = "fade" })
hl.animation({ leaf = "layersOut", enabled = true, speed = 1.5, bezier = "linear", style = "fade" })
hl.animation({ leaf = "fadeLayersIn", enabled = true, speed = 1.79, bezier = "almostLinear" })
hl.animation({ leaf = "fadeLayersOut", enabled = true, speed = 1.39, bezier = "almostLinear" })
hl.animation({ leaf = "workspaces", enabled = true, speed = 1.94, bezier = "almostLinear", style = "fade" })
hl.animation({ leaf = "workspacesIn", enabled = true, speed = 1.21, bezier = "almostLinear", style = "fade" })
hl.animation({ leaf = "workspacesOut", enabled = true, speed = 1.94, bezier = "almostLinear", style = "fade" })
hl.animation({ leaf = "zoomFactor", enabled = true, speed = 7, bezier = "quick" })'
    [[ "$actual" == "$expected" ]] || fail "Hyprland animation contract changed; actual: $actual"
}

test_hypridle_uses_lua_dpms_dispatch() {
    local hypridle="$PROJECT_ROOT/home/.config/hypr/hypridle.conf"

    ! grep -Fq 'hyprctl dispatch dpms' "$hypridle" || return 1
    grep -Fq 'hyprctl dispatch '\''hl.dsp.dpms({ action = "disable" })'\''' "$hypridle" || return 1
    grep -Fq 'hyprctl dispatch '\''hl.dsp.dpms({ action = "enable" })'\''' "$hypridle"
}

test_waybar_uses_lua_workspace_dispatch_and_uwsm_logout() {
    local waybar="$PROJECT_ROOT/home/.config/waybar/config.jsonc"

    grep -Fq '"on-scroll-up": "hyprctl dispatch '\''hl.dsp.focus({ workspace = \"e+1\" })'\''",' "$waybar" || return 1
    grep -Fq '"on-scroll-down": "hyprctl dispatch '\''hl.dsp.focus({ workspace = \"e-1\" })'\''"' "$waybar" || return 1
    grep -Fq '"logout":   "uwsm stop",' "$waybar"
}

test_documentation_records_operations_and_compatibility_evidence() {
    local readme="$PROJECT_ROOT/README.md"
    local audit="$PROJECT_ROOT/docs/compatibility/2026-08-30-platform-audit.md"
    local heading evidence

    for heading in \
        'Requirements' \
        'Quick start' \
        'Detect and check' \
        'Preview and install' \
        'Backups and recovery' \
        'Using doti' \
        'Updating versions' \
        'Arch/Hyprland runtime verification'
    do
        grep -Fqx "## $heading" "$readme" || return 1
    done

    for evidence in \
        'STATIC PASS' \
        'RUNTIME UNVERIFIED' \
        'Fish 4.8.1' \
        'Git 2.55.0' \
        'Starship 1.26.0' \
        'Kitty 0.47.2' \
        'Zellij 0.45.1' \
        'Yazi 26.8.15' \
        'mpv 0.41.0' \
        'Fontconfig 2.18.3' \
        'home/.config/kitty/kitty.conf' \
        'home/.config/kitty/kitty-kitten-search/search.py' \
        'home/.config/kitty/kitty-kitten-search/scroll_mark.py' \
        'home/.config/zellij/config.kdl' \
        'https://wiki.hypr.land/Configuring/Start/' \
        'https://fishshell.com/docs/4.4/relnotes.html' \
        'https://sw.kovidgoyal.net/kitty/conf/' \
        'https://zellij.dev/documentation/options.html' \
        'https://yazi-rs.github.io/docs/configuration/keymap/' \
        'https://man.archlinux.org/man/fuzzel.1.en' \
        'https://man.archlinux.org/man/mako.5'
    do
        grep -Fq "$evidence" "$audit" || return 1
    done
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
run_test test_manifest_rejects_ascii_controls_and_crlf_without_status_spoofing
run_test test_manifest_rejects_unsafe_tested_version_tokens_without_execution
run_test test_manifest_rejects_whitespace_in_identity_path_before_output
run_test test_manifest_rejects_control_path_before_recovery_tsv_mutation
run_test test_check_blocks_malformed_files_with_available_validators
run_test test_check_passes_valid_file
run_test test_check_marks_missing_native_validator_runtime_unverified
run_test test_check_marks_arch_hyprland_static_only_on_macos
run_test test_check_reports_clean_hyprland_session_separately_from_candidates
run_test test_check_blocks_hyprland_runtime_error_text_with_success_status
run_test test_check_blocks_newline_only_hyprland_runtime_output
run_test test_check_blocks_nul_only_hyprland_runtime_output
run_test test_check_sanitizes_validator_control_diagnostics
run_test test_check_never_executes_manifest_validator_text
run_test test_check_missing_source_uses_required_semantics
run_test test_check_reports_reviewed_and_safe_installed_versions
run_test test_check_version_observation_is_not_applicable_off_platform
run_test test_diff_classifies_every_target_state
run_test test_diff_never_prints_binary_drift
run_test test_diff_never_prints_non_nul_binary_drift
run_test test_diff_prints_text_drift_at_hex_byte_boundary
run_test test_diff_refuses_cross_platform_live_home
run_test test_diff_allows_read_only_cross_platform_staging
run_test test_diff_rejects_live_home_as_cross_platform_staging
run_test test_diff_fails_closed_without_canonical_source_root
run_test test_diff_blocks_unsafe_source_paths
run_test test_diff_missing_source_uses_required_semantics
run_test test_diff_blocks_unsafe_target_ancestors
run_test test_install_rejects_target_and_staging_options
run_test test_install_is_dry_run_by_default
run_test test_install_validator_failure_blocks_preview_and_apply_before_mutation
run_test test_install_unavailable_validator_is_visible_and_nonblocking
run_test test_install_runs_static_validator_without_runtime_probe
run_test test_install_missing_source_uses_required_semantics
run_test test_install_apply_links_and_is_idempotent
run_test test_install_conflict_aborts_complete_plan
run_test test_install_refuses_non_directory_parent
run_test test_install_selects_only_physical_platform
run_test test_install_rejects_backup_without_apply_and_unknown_options
run_test test_install_backup_preserves_regular_file_relative_path
run_test test_install_backup_preserves_foreign_symlink
run_test test_install_backup_blocks_directory_conflict
run_test test_install_root_swap_back_cannot_false_succeed
run_test test_install_nested_ancestor_swap_back_cannot_false_succeed
run_test test_install_final_verification_rejects_changed_noop_without_deleting_arrival
run_test test_install_final_verification_accepts_mixed_create_backup_and_noop
run_test test_install_final_verification_revalidates_source_and_rolls_back
run_test test_install_final_verification_revalidates_backup_without_deleting_foreign_data
run_test test_install_cleanup_window_mutation_cannot_false_succeed
run_test test_install_last_precommit_mutation_cannot_false_succeed
run_test test_install_link_post_move_root_detach_recovers_owned_publication
run_test test_install_link_post_move_nested_detach_recovers_owned_publication
run_test test_install_backup_post_move_state_root_detach_restores_owned_backup
run_test test_install_backup_post_move_nested_detach_restores_owned_backup
run_test test_install_backup_stage_post_move_root_detach_restores_in_recorded_parent
run_test test_install_backup_stage_post_move_nested_detach_restores_in_recorded_parent
run_test test_install_backup_stage_replacement_is_not_published_or_deleted
run_test test_install_backup_source_same_fingerprint_new_inode_is_never_moved
run_test test_install_final_verification_rejects_replaced_report_without_deleting_arrival
run_test test_install_signal_at_final_verification_rolls_back_before_commit
run_test test_install_after_link_publish_root_detach_refreshes_owned_location
run_test test_install_after_backup_stage_nested_detach_refreshes_restore_location
run_test test_install_after_backup_move_state_detach_refreshes_report_and_publication
run_test test_install_last_precommit_mixed_nested_detach_reports_path_unavailable
run_test test_install_production_ignores_path_and_test_primitive_overrides
run_test test_install_test_mode_exercises_bsd_and_gnu_primitive_arguments
run_test test_install_rejects_malformed_and_multiline_path_identities
run_test test_install_gnu_stat_selector_avoids_literal_format_operand_collision
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
run_test test_hyprland_animations_preserve_values_and_curve_types
run_test test_hypridle_uses_lua_dpms_dispatch
run_test test_waybar_uses_lua_workspace_dispatch_and_uwsm_logout
run_test test_dotfiles_copy_dispatches_portably
run_test test_shared_terminal_behavior_is_canonical
run_test test_shared_fish_yazi_and_fontconfig_are_portable
run_test test_documentation_records_operations_and_compatibility_evidence
printf '%s passed; %s failed\n' "$PASS_COUNT" "$FAIL_COUNT"
[[ "$FAIL_COUNT" -eq 0 ]]

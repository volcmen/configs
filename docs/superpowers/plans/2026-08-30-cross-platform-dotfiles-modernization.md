# Cross-Platform Dotfiles Modernization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build and adopt a dependency-free, preview-first dotfiles manager while modernizing the existing macOS and Arch/Hyprland configs without changing the user’s theme, keybindings, layout, or workflow.

**Architecture:** Keep `home/` as the only doti-compatible source tree. A Bash 3.2-compatible `bin/dotfiles` reads a fixed, pipe-delimited `dotfiles.manifest`, separates physical-host detection from read-only validation targets, and implements check/diff/install through allowlisted functions. Shared config portability is expressed inside the canonical app files or through one small shared clipboard helper; Arch-only files remain canonical but are selected only on Arch.

**Tech Stack:** Bash 3.2-compatible shell, standard macOS/Arch utilities, application-native validators, dependency-free shell tests, Git.

**Spec:** `docs/superpowers/specs/2026-08-30-cross-platform-dotfiles-modernization-design.md`

## Global Constraints

- Targets are exactly `macos` and `arch`; unsupported hosts fail closed.
- `home/` remains the only application-config source and remains doti-compatible.
- No `macos/`, `linux/`, `common/`, generated overlay, or templating tree.
- Preserve all existing visual styling, fonts, keybindings, layouts, animations, rules, and startup workflow.
- Do not install or upgrade Homebrew, Pacman, AUR, applications, services, shells, or compositors.
- Do not enable, restart, reload, or kill UWSM, systemd user units, Hyprland, or desktop services automatically.
- `DOTFILES_TARGET` and `--target` are read-only validation controls and never authorize installation.
- Plain `install` is a dry run; mutation requires `install --apply`.
- Never overwrite a regular file, foreign symlink, or directory conflict without the exact safety behavior in the spec.
- Missing native binaries are `RUNTIME UNVERIFIED`, not false passes and not automatic install blockers.
- Static macOS checks never claim Arch/Hyprland runtime validity.
- Compatibility archives are historical reference artifacts outside `home/`;
  they are excluded from `dotfiles.manifest` and never deployed.
- Secrets, credentials, credential stores, private keys, and auth state are out of scope.
- Work in small commits and run the task-specific test before every commit.

## File Responsibility Map

| File | Responsibility |
| --- | --- |
| `.gitignore` | Keep the local Agent Board workspace and generated test/runtime artifacts out of Git. |
| `bin/dotfiles` | Sole repository-native CLI, parser, planner, installer, rollback engine, and validator registry. |
| `dotfiles.manifest` | Sole declarative platform/ownership/validator/version inventory. |
| `tests/dotfiles-test.sh` | Dependency-free end-to-end fixture tests for every CLI contract. |
| `home/.local/bin/dotfiles-copy` | One clipboard stdin dispatcher used by Zellij on both target platforms. |
| `home/.config/fish/config.fish` | Shared shell initialization with guarded platform/tool paths. |
| `home/.config/kitty/kitty.conf` | Canonical Kitty behavior reconciled with the active macOS config. |
| `home/.config/kitty/kitty-kitten-search/*.py` | Existing search kitten, normalized without semantic changes. |
| `home/.config/zellij/config.kdl` | Canonical bindings plus platform-neutral clipboard command. |
| `home/.config/yazi/keymap.toml` | Canonical keymap with native per-OS clipboard bindings. |
| `docs/compatibility/archive/fontconfig-99-readability-alternative.conf` | Preserve the exact bytes of the inactive, materially distinct Fontconfig alternative without deploying it. |
| `home/.config/hypr/hyprland/looknfeel.lua` | Current Hyprland Lua animation selector fields while preserving curve values. |
| `home/.config/hypr/hypridle.conf` | Current Lua-dispatch DPMS commands with unchanged timeouts. |
| `home/.config/waybar/config.jsonc` | Current Lua-dispatch workspace actions and UWSM logout. |
| `docs/compatibility/2026-08-30-platform-audit.md` | Evidence, versions, static/runtime boundaries, live drift, and Arch handoff results. |
| `README.md` | User-facing detect/check/diff/install, doti, backup, recovery, and upgrade workflow. |

---

### Task 1: Establish the CLI and dependency-free test harness

**Files:**
- Create: `bin/dotfiles`
- Create: `tests/dotfiles-test.sh`
- Modify: `.gitignore`

**Interfaces:**
- Consumes: repository location derived from `bin/dotfiles` itself.
- Produces: executable CLI dispatch; test helpers `new_fixture`, `run_cli`, `assert_status`, `assert_contains`, `assert_not_exists`, and `run_test`.

- [ ] **Step 1: Write the failing CLI contract test**

Create `tests/dotfiles-test.sh` with a small runner and the first contract tests:

```bash
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

run_test test_help
run_test test_unknown_command_fails
printf '%s passed; %s failed\n' "$PASS_COUNT" "$FAIL_COUNT"
[[ "$FAIL_COUNT" -eq 0 ]]
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bash tests/dotfiles-test.sh`

Expected: FAIL because `bin/dotfiles` does not exist.

- [ ] **Step 3: Add the minimal CLI skeleton**

Create `bin/dotfiles`:

```bash
#!/usr/bin/env bash
set -u

PROGRAM=${0##*/}
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
MANIFEST="$REPO_ROOT/dotfiles.manifest"
SOURCE_ROOT="$REPO_ROOT/home"

usage() {
    cat <<'USAGE'
Usage: dotfiles <command> [options]

Commands:
  detect                  print the physical host platform
  check [--target NAME]   validate canonical configuration
  diff                    compare canonical and live state
  install [--apply] [--backup]
                          preview or apply the installation plan
  help                    show this help
USAGE
}

die() {
    local status=$1
    shift
    printf '%s: %s\n' "$PROGRAM" "$*" >&2
    exit "$status"
}

main() {
    local command=${1:-help}
    [[ $# -eq 0 ]] || shift
    case "$command" in
        help|-h|--help) usage ;;
        detect|check|diff|install) die 69 "$command is not implemented" ;;
        *) die 64 "unknown command: $command" ;;
    esac
}

main "$@"
```

- [ ] **Step 4: Ignore only local/generated workspace state**

Append these exact entries to `.gitignore`:

```gitignore
/board/
/.dotfiles-test/
```

- [ ] **Step 5: Run the test and static shell parse**

Run: `bash -n bin/dotfiles && bash -n tests/dotfiles-test.sh && bash tests/dotfiles-test.sh`

Expected: both parse checks and both tests PASS.

- [ ] **Step 6: Commit**

```bash
git add .gitignore bin/dotfiles tests/dotfiles-test.sh
git commit -m "✨ add dotfiles CLI test harness"
```

---

### Task 2: Implement strict physical-host detection

**Files:**
- Modify: `bin/dotfiles`
- Modify: `tests/dotfiles-test.sh`

**Interfaces:**
- Consumes: test-only `DOTFILES_TESTING=1`, `DOTFILES_TEST_UNAME`, and `DOTFILES_TEST_OS_RELEASE`.
- Produces: `detect_host() -> stdout macos|arch`, exit `69` for unsupported hosts; `detect` ignores `DOTFILES_TARGET`.

- [ ] **Step 1: Add failing detection tests**

Add test helpers that write an isolated os-release file, then add these cases:

```bash
write_os_release() {
    printf '%s\n' "$1" >"$TEST_TMP/os-release"
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
```

Register all three cases with `run_test`.

- [ ] **Step 2: Run the focused tests to verify failure**

Run: `bash tests/dotfiles-test.sh`

Expected: new detection tests FAIL with `detect is not implemented`.

- [ ] **Step 3: Implement test-seam isolation and detection**

Add these functions before `main`:

```bash
test_value() {
    [[ ${DOTFILES_TESTING:-0} == 1 ]] || return 1
    case "$1" in
        DOTFILES_TEST_UNAME) printf '%s' "${DOTFILES_TEST_UNAME:-}" ;;
        DOTFILES_TEST_OS_RELEASE) printf '%s' "${DOTFILES_TEST_OS_RELEASE:-}" ;;
        *) return 1 ;;
    esac
}

kernel_name() {
    local value
    value=$(test_value DOTFILES_TEST_UNAME) || true
    if [[ -n "$value" ]]; then printf '%s\n' "$value"; else uname -s; fi
}

os_release_path() {
    local value
    value=$(test_value DOTFILES_TEST_OS_RELEASE) || true
    if [[ -n "$value" ]]; then printf '%s\n' "$value"; else printf '/etc/os-release\n'; fi
}

os_release_id() {
    local file key value
    file=$(os_release_path)
    [[ -r "$file" ]] || return 1
    while IFS='=' read -r key value; do
        [[ "$key" == ID ]] || continue
        value=${value#\"}; value=${value%\"}
        value=${value#\'}; value=${value%\'}
        printf '%s\n' "$value"
        return 0
    done <"$file"
    return 1
}

detect_host() {
    local kernel id
    kernel=$(kernel_name)
    case "$kernel" in
        Darwin) printf 'macos\n' ;;
        Linux)
            id=$(os_release_id) || die 69 'unsupported host: Linux without readable ID'
            [[ "$id" == arch ]] || die 69 "unsupported host: Linux ID=$id"
            printf 'arch\n'
            ;;
        *) die 69 "unsupported host kernel: $kernel" ;;
    esac
}
```

Change the `detect` branch in `main` to `detect_host`.

- [ ] **Step 4: Run detection tests**

Run: `bash -n bin/dotfiles && bash tests/dotfiles-test.sh`

Expected: all tests PASS.

- [ ] **Step 5: Commit**

```bash
git add bin/dotfiles tests/dotfiles-test.sh
git commit -m "✨ detect macOS and Arch hosts safely"
```

---

### Task 3: Add the manifest parser and complete ownership inventory

**Files:**
- Create: `dotfiles.manifest`
- Create: `home/.local/bin/dotfiles-copy`
- Modify: `bin/dotfiles`
- Modify: `tests/dotfiles-test.sh`

**Interfaces:**
- Consumes: the seven-field v1 grammar from the spec.
- Produces: indexed arrays `MF_APP`, `MF_PLATFORMS`, `MF_KIND`, `MF_PATH`, `MF_VALIDATOR`, `MF_REQUIRED`, `MF_TESTED`; `parse_manifest FILE`; `platform_selected LIST TARGET`.

- [ ] **Step 1: Add failing parser tests**

Add fixture helpers and tests for one valid row plus each fail-closed rule:

```bash
write_manifest() { printf '%s\n' "$1" >"$TEST_TMP/repo/dotfiles.manifest"; }

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
        assert_status 65 || return 1
    done
}
```

Add equivalent single-case tests for unknown platform, kind, validator, and
required value. Every invalid case must expect exit `65` and an error containing
the manifest line number.

- [ ] **Step 2: Run the tests to verify parser failures**

Run: `bash tests/dotfiles-test.sh`

Expected: parser cases FAIL because `check` and manifest parsing do not exist.

- [ ] **Step 3: Implement the fixed grammar and allowlists**

Add Bash 3.2 indexed arrays and `parse_manifest`:

```bash
MF_APP=(); MF_PLATFORMS=(); MF_KIND=(); MF_PATH=()
MF_VALIDATOR=(); MF_REQUIRED=(); MF_TESTED=()

manifest_error() { die 65 "manifest line $1: $2"; }

valid_platforms() {
    case "$1" in macos|arch|macos,arch|arch,macos) return 0 ;; *) return 1 ;; esac
}

valid_validator() {
    case "$1" in
        plain|shell|fish|fontconfig|fuzzel|git|hyprconf|hyprland-lua|ini|jsonc|kitty|lua|mako|mpv|python|starship|toml|uwsm-shell|xml|zellij|css) return 0 ;;
        *) return 1 ;;
    esac
}

safe_relative_path() {
    [[ -n "$1" && "$1" != /* && "$1" != *'|'* ]] || return 1
    case "/$1/" in *'/../'*|*'/./'*|*'//'*) return 1 ;; esac
    return 0
}

parse_manifest() {
    local file=$1 line line_no=0 app platforms kind path validator required tested extra separators i
    MF_APP=(); MF_PLATFORMS=(); MF_KIND=(); MF_PATH=()
    MF_VALIDATOR=(); MF_REQUIRED=(); MF_TESTED=()
    [[ -r "$file" ]] || die 65 "manifest is not readable: $file"
    while IFS= read -r line || [[ -n "$line" ]]; do
        line_no=$((line_no + 1))
        [[ -z "$line" || "$line" == \#* ]] && continue
        separators=${line//[!|]/}
        [[ "$separators" == '||||||' ]] || manifest_error "$line_no" 'expected seven fields'
        IFS='|' read -r app platforms kind path validator required tested extra <<<"$line"
        [[ -n "$app" && "$app" =~ ^[a-z0-9][a-z0-9-]*$ ]] || manifest_error "$line_no" 'invalid app'
        valid_platforms "$platforms" || manifest_error "$line_no" 'invalid platforms'
        [[ "$kind" == file ]] || manifest_error "$line_no" 'schema v1 kind must be file'
        safe_relative_path "$path" || manifest_error "$line_no" 'unsafe path'
        valid_validator "$validator" || manifest_error "$line_no" 'unknown validator'
        [[ "$required" == yes || "$required" == no ]] || manifest_error "$line_no" 'required must be yes or no'
        [[ -n "$tested" ]] || manifest_error "$line_no" 'tested_version is empty'
        for ((i=0; i<${#MF_PATH[@]}; i++)); do
            [[ "${MF_PATH[$i]}" != "$path" ]] || manifest_error "$line_no" "duplicate path: $path"
        done
        i=${#MF_APP[@]}
        MF_APP[$i]=$app; MF_PLATFORMS[$i]=$platforms; MF_KIND[$i]=$kind
        MF_PATH[$i]=$path; MF_VALIDATOR[$i]=$validator
        MF_REQUIRED[$i]=$required; MF_TESTED[$i]=$tested
    done <"$file"
}

platform_selected() {
    case ",$1," in *",$2,"*) return 0 ;; *) return 1 ;; esac
}
```

The first line of `check` must call `parse_manifest "$MANIFEST"`. Test-only
fixtures locate their manifest through the copied script’s repository root; do
not add a production manifest override.

- [ ] **Step 4: Create the complete v1 manifest**

Create `dotfiles.manifest` with this exact inventory. The inactive Fontconfig
alternative is intentionally excluded because its preserved archive is outside
the managed home tree; the new clipboard helper is included:

```text
# app|platforms|kind|path|validator|required|tested_version
clipboard|macos,arch|file|.local/bin/dotfiles-copy|shell|yes|1
fish|macos,arch|file|.config/fish/config.fish|fish|yes|4.8.1
fontconfig|macos,arch|file|.config/fontconfig/fonts.conf|fontconfig|yes|2.18.3
fontconfig|macos,arch|file|.config/fontconfig/conf.d/99-readability.conf|fontconfig|yes|2.18.3
git|macos,arch|file|.config/git/config|git|yes|2.55.0
kitty|macos,arch|file|.config/kitty/current-theme.conf|kitty|yes|0.47.2
kitty|macos,arch|file|.config/kitty/kitty.conf|kitty|yes|0.47.2
kitty|macos,arch|file|.config/kitty/pager.sh|shell|yes|0.47.2
kitty|macos,arch|file|.config/kitty/kitty-kitten-search/search.py|python|yes|0.47.2
kitty|macos,arch|file|.config/kitty/kitty-kitten-search/scroll_mark.py|python|yes|0.47.2
mpv|macos,arch|file|.config/mpv/mpv.conf|mpv|yes|0.41.0
starship|macos,arch|file|.config/starship.toml|starship|yes|1.26.0
yazi|macos,arch|file|.config/yazi/keymap.toml|toml|yes|26.8.15
yazi|macos,arch|file|.config/yazi/package.toml|toml|yes|26.8.15
yazi|macos,arch|file|.config/yazi/plugins/m-recycle-bin.yazi/README.md|plain|yes|26.8.15
yazi|macos,arch|file|.config/yazi/plugins/m-recycle-bin.yazi/main.lua|lua|yes|26.8.15
zellij|macos,arch|file|.config/zellij/config.kdl|zellij|yes|0.45.1
chromium|arch|file|.config/chromium-flags.conf|plain|yes|unverified
electron|arch|file|.config/electron-flags.conf|plain|yes|unverified
fuzzel|arch|file|.config/fuzzel/fuzzel.ini|fuzzel|yes|unverified
hypridle|arch|file|.config/hypr/hypridle.conf|hyprconf|yes|0.1.7
hyprland|arch|file|.config/hypr/hyprland.lua|hyprland-lua|yes|0.56.2
hyprland|arch|file|.config/hypr/hyprland/execs.lua|hyprland-lua|yes|0.56.2
hyprland|arch|file|.config/hypr/hyprland/general.lua|hyprland-lua|yes|0.56.2
hyprland|arch|file|.config/hypr/hyprland/input.lua|hyprland-lua|yes|0.56.2
hyprland|arch|file|.config/hypr/hyprland/keybinds.lua|hyprland-lua|yes|0.56.2
hyprland|arch|file|.config/hypr/hyprland/looknfeel.lua|hyprland-lua|yes|0.56.2
hyprland|arch|file|.config/hypr/hyprland/rules.lua|hyprland-lua|yes|0.56.2
hyprland|arch|file|.config/hypr/hyprland/shared.lua|hyprland-lua|yes|0.56.2
hyprland|arch|file|.config/hypr/hyprland/bindings/apps.lua|hyprland-lua|yes|0.56.2
hyprland|arch|file|.config/hypr/hyprland/bindings/clipboard.lua|hyprland-lua|yes|0.56.2
hyprland|arch|file|.config/hypr/hyprland/bindings/groups.lua|hyprland-lua|yes|0.56.2
hyprland|arch|file|.config/hypr/hyprland/bindings/media.lua|hyprland-lua|yes|0.56.2
hyprland|arch|file|.config/hypr/hyprland/bindings/mouse.lua|hyprland-lua|yes|0.56.2
hyprland|arch|file|.config/hypr/hyprland/bindings/tiling.lua|hyprland-lua|yes|0.56.2
hyprlock|arch|file|.config/hypr/hyprlock.conf|hyprconf|yes|unverified
hyprpaper|arch|file|.config/hypr/hyprpaper.conf|hyprconf|yes|0.8.4
hyprsunset|arch|file|.config/hypr/hyprsunset.conf|hyprconf|yes|unverified
mako|arch|file|.config/mako/config|mako|yes|1.11.0
mimeapps|arch|file|.config/mimeapps.list|ini|yes|unverified
uwsm|arch|file|.config/uwsm/default|uwsm-shell|yes|unverified
uwsm|arch|file|.config/uwsm/env|uwsm-shell|yes|unverified
uwsm|arch|file|.config/uwsm/env-hyprland|uwsm-shell|yes|unverified
waybar|arch|file|.config/waybar/config.jsonc|jsonc|yes|0.15.0
waybar|arch|file|.config/waybar/power-menu.xml|xml|yes|0.15.0
waybar|arch|file|.config/waybar/style.css|css|yes|0.15.0
xdg-portal|arch|file|.config/xdg-desktop-portal/hyprland-portals.conf|ini|yes|unverified
```

- [ ] **Step 5: Add a failing portability test for the shared clipboard source**

Add the source-level behavior test before creating the helper:

```bash
test_dotfiles_copy_dispatches_portably() {
    local helper="$PROJECT_ROOT/home/.local/bin/dotfiles-copy"
    local stub_path="$TEST_TMP/clipboard-bin"
    local empty_path="$TEST_TMP/empty-bin"
    local output status
    new_fixture
    mkdir -p "$stub_path" "$empty_path"
    cat >"$stub_path/pbcopy" <<'STUB'
#!/bin/sh
printf 'pbcopy:'
cat
STUB
    cat >"$stub_path/wl-copy" <<'STUB'
#!/bin/sh
printf 'wl-copy:'
cat
STUB
    chmod +x "$stub_path/pbcopy" "$stub_path/wl-copy"

    output="$(printf 'payload' | PATH="$stub_path:/usr/bin:/bin" "$helper")" || return 1
    [[ "$output" == 'pbcopy:payload' ]] || fail "pbcopy was not preferred: $output"
    rm "$stub_path/pbcopy"
    output="$(printf 'payload' | PATH="$stub_path:/usr/bin:/bin" "$helper")" || return 1
    [[ "$output" == 'wl-copy:payload' ]] || fail "wl-copy fallback failed: $output"

    if PATH="$empty_path" "$helper" </dev/null >/dev/null 2>&1; then
        fail 'clipboard helper unexpectedly succeeded without a backend'
    else
        status=$?
    fi
    [[ "$status" -eq 127 ]] || fail "missing-backend status $status != 127"
}
```

Run: `bash tests/dotfiles-test.sh`

Expected: the clipboard test FAILS because the manifest-owned helper does not
exist yet.

- [ ] **Step 6: Create the shared clipboard dispatcher**

Create executable `home/.local/bin/dotfiles-copy`:

```sh
#!/bin/sh
set -u

if command -v pbcopy >/dev/null 2>&1; then
    exec pbcopy
fi
if command -v wl-copy >/dev/null 2>&1; then
    exec wl-copy
fi
printf 'dotfiles-copy: neither pbcopy nor wl-copy is available\n' >&2
exit 127
```

Run: `chmod +x home/.local/bin/dotfiles-copy`

- [ ] **Step 7: Run parser and inventory tests**

Run: `bash tests/dotfiles-test.sh`

Expected: all parser, inventory, and clipboard portability tests PASS.

- [ ] **Step 8: Commit**

```bash
git add bin/dotfiles dotfiles.manifest home/.local/bin/dotfiles-copy tests/dotfiles-test.sh
git commit -m "✨ declare cross-platform dotfile ownership"
```

---

### Task 4: Implement read-only target selection and drift reporting

**Files:**
- Modify: `bin/dotfiles`
- Modify: `tests/dotfiles-test.sh`

**Interfaces:**
- Consumes: parsed manifest arrays and `detect_host`.
- Produces: `validation_target ARGS`, `effective_home`, `artifact_status SOURCE TARGET`, and `command_diff`; status tokens `MISSING`, `LINKED`, `FOREIGN_LINK`, `MATCH`, `DRIFT`, `TYPE_CONFLICT`, `BLOCKED`.

- [ ] **Step 1: Add failing drift classification tests**

Create one two-file macOS fixture and test missing, matching regular file,
different regular file, correct absolute symlink, foreign symlink, and directory
conflict. Example assertions:

```bash
test_diff_classifies_every_target_state() {
    new_fixture
    mkdir -p "$TEST_TMP/repo/home/.config/demo" "$TEST_TMP/home/.config/demo"
    printf 'canonical\n' >"$TEST_TMP/repo/home/.config/demo/a"
    printf 'canonical\n' >"$TEST_TMP/repo/home/.config/demo/b"
    write_manifest $'demo|macos|file|.config/demo/a|plain|yes|1\ndemo|macos|file|.config/demo/b|plain|yes|1'
    printf 'different\n' >"$TEST_TMP/home/.config/demo/a"
    ln -s "$TEST_TMP/repo/home/.config/demo/b" "$TEST_TMP/home/.config/demo/b"
    run_cli diff
    assert_status 1 && assert_contains 'DRIFT demo .config/demo/a' && assert_contains 'LINKED demo .config/demo/b'
}

test_diff_refuses_cross_platform_live_home() {
    new_fixture
    mkdir -p "$TEST_TMP/repo/home/.config/demo"
    printf 'canonical\n' >"$TEST_TMP/repo/home/.config/demo/config"
    write_manifest 'demo|arch|file|.config/demo/config|plain|yes|1'
    DOTFILES_TARGET=arch run_cli diff
    assert_status 64 && assert_contains 'requires --staging-home'
    assert_not_exists "$TEST_TMP/home/.config/demo/config"
}

test_diff_allows_read_only_cross_platform_staging() {
    new_fixture
    mkdir -p "$TEST_TMP/repo/home/.config/demo" "$TEST_TMP/staging"
    printf 'canonical\n' >"$TEST_TMP/repo/home/.config/demo/config"
    write_manifest 'demo|arch|file|.config/demo/config|plain|yes|1'
    run_cli diff --target arch --staging-home "$TEST_TMP/staging"
    assert_status 1 && assert_contains 'MISSING demo .config/demo/config'
    assert_not_exists "$TEST_TMP/staging/.config/demo/config"
}
```

- [ ] **Step 2: Run tests to verify failure**

Run: `bash tests/dotfiles-test.sh`

Expected: drift tests FAIL because `diff` is not implemented.

- [ ] **Step 3: Implement safe target/home selection**

Add argument parsing that accepts `--target` for `check`, and accepts a
mismatched target for `diff` only when `--staging-home` is present. Production
`install` rejects both options. `effective_home` uses `$HOME`; only
`DOTFILES_TESTING=1` may use `DOTFILES_TEST_HOME`.

Implement status classification with these exact rules:

```bash
artifact_status() {
    local source=$1 target=$2 link
    [[ -e "$source" ]] || { printf 'BLOCKED\n'; return; }
    if [[ -L "$target" ]]; then
        link=$(readlink "$target")
        [[ "$link" == "$source" ]] && printf 'LINKED\n' || printf 'FOREIGN_LINK\n'
    elif [[ -d "$target" ]]; then
        printf 'TYPE_CONFLICT\n'
    elif [[ -f "$target" ]]; then
        cmp -s "$source" "$target" && printf 'MATCH\n' || printf 'DRIFT\n'
    elif [[ -e "$target" ]]; then
        printf 'TYPE_CONFLICT\n'
    else
        printf 'MISSING\n'
    fi
}
```

`command_diff` prints exactly `STATUS app path` in manifest order. It prints a
unified `diff -u` only for text `DRIFT` artifacts and never prints binary data.
Exit `0` only when every selected path is `LINKED` or `MATCH`; exit `1` for
drift/missing/foreign links and `65` for blocked/unsafe input.

- [ ] **Step 4: Run drift tests and a real macOS read-only diff**

Run:

```bash
bash tests/dotfiles-test.sh
./bin/dotfiles diff
```

Expected: tests PASS. The real diff reports existing regular files and known
Kitty/Zellij drift but performs no writes.

- [ ] **Step 5: Commit**

```bash
git add bin/dotfiles tests/dotfiles-test.sh
git commit -m "✨ report dotfile drift without mutation"
```

---

### Task 5: Add preview-first installation and idempotent linking

**Files:**
- Modify: `bin/dotfiles`
- Modify: `tests/dotfiles-test.sh`

**Interfaces:**
- Consumes: manifest selection and `artifact_status`.
- Produces: `build_install_plan`, plan rows `CREATE|NOOP|CONFLICT|BLOCKED`, `command_install`; only `--apply` mutates.

- [ ] **Step 1: Add failing install tests**

Add cases proving:

```bash
test_install_is_dry_run_by_default() {
    new_fixture
    mkdir -p "$TEST_TMP/repo/home/.config/demo"
    printf 'x\n' >"$TEST_TMP/repo/home/.config/demo/config"
    write_manifest 'demo|macos|file|.config/demo/config|plain|yes|1'
    run_cli install
    assert_status 0 && assert_contains 'CREATE demo .config/demo/config'
    assert_not_exists "$TEST_TMP/home/.config/demo/config"
}

test_install_apply_links_and_is_idempotent() {
    new_fixture
    mkdir -p "$TEST_TMP/repo/home/.config/demo"
    printf 'x\n' >"$TEST_TMP/repo/home/.config/demo/config"
    write_manifest 'demo|macos|file|.config/demo/config|plain|yes|1'
    run_cli install --apply
    assert_status 0 || return 1
    [[ "$(readlink "$TEST_TMP/home/.config/demo/config")" == "$TEST_TMP/repo/home/.config/demo/config" ]]
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
    [[ "$CLI_STATUS" -ne 0 ]] || fail 'conflicting install unexpectedly succeeded'
    assert_contains 'CONFLICT demo .config/demo/a' || return 1
    assert_not_exists "$TEST_TMP/home/.config/demo/b"
}

test_install_refuses_non_directory_parent() {
    new_fixture
    mkdir -p "$TEST_TMP/repo/home/.config/demo" "$TEST_TMP/home/.config"
    printf 'new\n' >"$TEST_TMP/repo/home/.config/demo/config"
    printf 'parent-is-a-file\n' >"$TEST_TMP/home/.config/demo"
    write_manifest 'demo|macos|file|.config/demo/config|plain|yes|1'
    run_cli install --apply
    [[ "$CLI_STATUS" -ne 0 ]] || fail 'install ignored a non-directory parent'
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
```

- [ ] **Step 2: Run tests to verify failure**

Run: `bash tests/dotfiles-test.sh`

Expected: install tests FAIL because `install` is unimplemented.

- [ ] **Step 3: Implement complete preflight and basic apply**

Build the whole plan before the first `mkdir` or `ln`. If any row is
`CONFLICT` or `BLOCKED`, print all rows and exit nonzero without mutation.
On `--apply`, create parents with `mkdir -p --`, recheck that each parent is a
directory, then create absolute symlinks with `ln -s -- "$source" "$target"`.

Accept only these install arguments:

```text
install
install --apply
install --apply --backup
```

Reject `--backup` without `--apply`, `--target`, `--staging-home`, and unknown
flags with exit `64`.

- [ ] **Step 4: Run install tests**

Run: `bash tests/dotfiles-test.sh`

Expected: dry-run, apply, idempotence, atomic preflight, and platform-selection
tests PASS.

- [ ] **Step 5: Commit**

```bash
git add bin/dotfiles tests/dotfiles-test.sh
git commit -m "✨ install dotfile links with dry-run safety"
```

---

### Task 6: Add backup, locking, journaling, and rollback

**Files:**
- Modify: `bin/dotfiles`
- Modify: `tests/dotfiles-test.sh`

**Interfaces:**
- Consumes: a conflict-free or explicitly backup-approved install plan.
- Produces: `state_root`, `acquire_lock`, `release_lock`, `begin_backup`, `journal_move`, `journal_link`, `rollback_transaction`; test-only `DOTFILES_TEST_FAIL_AFTER`.

- [ ] **Step 1: Add failing transaction tests**

Add tests for all destructive boundaries:

```bash
test_backup_preserves_relative_path() {
    new_fixture
    mkdir -p "$TEST_TMP/repo/home/.config/demo" "$TEST_TMP/home/.config/demo"
    printf 'new\n' >"$TEST_TMP/repo/home/.config/demo/config"
    printf 'old\n' >"$TEST_TMP/home/.config/demo/config"
    write_manifest 'demo|macos|file|.config/demo/config|plain|yes|1'
    DOTFILES_TESTING=1 DOTFILES_TEST_HOME="$TEST_TMP/home" DOTFILES_TEST_UNAME=Darwin \
        DOTFILES_TEST_STATE="$TEST_TMP/state" "$TEST_TMP/repo/bin/dotfiles" install --apply --backup
    [[ -L "$TEST_TMP/home/.config/demo/config" ]]
    [[ "$(find "$TEST_TMP/state/backups" -path '*/.config/demo/config' -type f | wc -l | tr -d ' ')" == 1 ]]
}

test_injected_failure_rolls_back_everything() {
    local status
    new_fixture
    mkdir -p "$TEST_TMP/repo/home/.config/demo" "$TEST_TMP/home/.config/demo"
    printf 'new-a\n' >"$TEST_TMP/repo/home/.config/demo/a"
    printf 'new-b\n' >"$TEST_TMP/repo/home/.config/demo/b"
    printf 'old-a\n' >"$TEST_TMP/home/.config/demo/a"
    printf 'old-b\n' >"$TEST_TMP/home/.config/demo/b"
    write_manifest $'demo|macos|file|.config/demo/a|plain|yes|1\ndemo|macos|file|.config/demo/b|plain|yes|1'
    if DOTFILES_TESTING=1 DOTFILES_TEST_HOME="$TEST_TMP/home" \
        DOTFILES_TEST_UNAME=Darwin DOTFILES_TEST_STATE="$TEST_TMP/state" \
        DOTFILES_TEST_FAIL_AFTER=3 \
        "$TEST_TMP/repo/bin/dotfiles" install --apply --backup; then
        fail 'injected transaction failure unexpectedly succeeded'
    else
        status=$?
    fi
    [[ "$status" -eq 70 ]] || fail "injected-failure status $status != 70"
    [[ ! -L "$TEST_TMP/home/.config/demo/a" && ! -L "$TEST_TMP/home/.config/demo/b" ]] || return 1
    [[ "$(cat "$TEST_TMP/home/.config/demo/a")" == 'old-a' ]] || return 1
    [[ "$(cat "$TEST_TMP/home/.config/demo/b")" == 'old-b' ]] || return 1
}

test_existing_lock_refuses_installer() {
    local status
    new_fixture
    mkdir -p "$TEST_TMP/repo/home/.config/demo" "$TEST_TMP/state/install.lock"
    printf 'new\n' >"$TEST_TMP/repo/home/.config/demo/config"
    write_manifest 'demo|macos|file|.config/demo/config|plain|yes|1'
    if DOTFILES_TESTING=1 DOTFILES_TEST_HOME="$TEST_TMP/home" \
        DOTFILES_TEST_UNAME=Darwin DOTFILES_TEST_STATE="$TEST_TMP/state" \
        "$TEST_TMP/repo/bin/dotfiles" install --apply; then
        fail 'installer ignored an existing lock'
    else
        status=$?
    fi
    [[ "$status" -eq 75 ]] || fail "lock status $status != 75"
    assert_not_exists "$TEST_TMP/home/.config/demo/config"
}

test_backup_never_replaces_target_directory() {
    local status
    new_fixture
    mkdir -p "$TEST_TMP/repo/home/.config/demo" "$TEST_TMP/home/.config/demo/config"
    printf 'new\n' >"$TEST_TMP/repo/home/.config/demo/config"
    write_manifest 'demo|macos|file|.config/demo/config|plain|yes|1'
    if DOTFILES_TESTING=1 DOTFILES_TEST_HOME="$TEST_TMP/home" \
        DOTFILES_TEST_UNAME=Darwin DOTFILES_TEST_STATE="$TEST_TMP/state" \
        "$TEST_TMP/repo/bin/dotfiles" install --apply --backup; then
        fail 'installer replaced a target directory'
    else
        status=$?
    fi
    [[ "$status" -ne 0 ]] || return 1
    [[ -d "$TEST_TMP/home/.config/demo/config" && ! -L "$TEST_TMP/home/.config/demo/config" ]]
}
```

- [ ] **Step 2: Run tests to verify failure**

Run: `bash tests/dotfiles-test.sh`

Expected: backup/rollback/lock tests FAIL.

- [ ] **Step 3: Implement the transaction state machine**

Use `${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles` in production and
`DOTFILES_TEST_STATE` only when `DOTFILES_TESTING=1`. Acquire a lock with atomic
`mkdir "$STATE_ROOT/install.lock"`; a failed `mkdir` exits `75`.

Create backups under `backups/$(date -u +%Y%m%dT%H%M%SZ)-$$`. For each approved
regular file or foreign symlink, create the backup parent then `mv` the target
to its preserved relative path. Append tab-separated `MOVE` and `LINK` records
to an in-memory indexed journal and a `report.tsv` inside the backup set.

Install a trap only while mutating:

```bash
TRANSACTION_ACTIVE=0
transaction_trap() {
    local status=$?
    if [[ "$TRANSACTION_ACTIVE" == 1 && "$status" -ne 0 ]]; then
        rollback_transaction
    fi
    release_lock
    exit "$status"
}
trap transaction_trap EXIT INT TERM
```

Rollback journal records in reverse order: remove only symlinks created by this
transaction, then move backup paths back to their original targets. Never delete
an unrelated path that appeared after the transaction started; report it and
leave the backup intact.

`DOTFILES_TEST_FAIL_AFTER=N` is read only in test mode and forces `return 70`
after the Nth mutation so rollback is deterministic.

- [ ] **Step 4: Run transaction tests**

Run: `bash tests/dotfiles-test.sh`

Expected: all transaction tests PASS, including zero surviving partial links
after injected failure.

- [ ] **Step 5: Commit**

```bash
git add bin/dotfiles tests/dotfiles-test.sh
git commit -m "✨ back up and roll back dotfile installs"
```

---

### Task 7: Implement layered, allowlisted validation

**Files:**
- Modify: `bin/dotfiles`
- Modify: `tests/dotfiles-test.sh`

**Interfaces:**
- Consumes: `MF_VALIDATOR`, source paths, physical host, validation target.
- Produces: `run_validator ID PATH TARGET`, result lines `PASS|STATIC PASS|RUNTIME UNVERIFIED|BLOCKED app path: detail`, and `command_check` summary exit status.

- [ ] **Step 1: Add failing validation tests**

Add fixture tests proving:

- malformed Fish, shell, XML, Git config, Lua, and JSON fail when their safe
  parser exists;
- a valid file passes;
- a missing native binary yields `RUNTIME UNVERIFIED` rather than `PASS`;
- Fuzzel uses the real manifest row and exact argument vector
  `--check-config --config=PATH`;
- a nonzero Fuzzel candidate check blocks `check`, install preview, and install
  apply before home, state, or outside mutation;
- an Arch Hyprland Lua file checked on macOS yields `STATIC PASS` followed by
  `RUNTIME UNVERIFIED`;
- validator IDs cannot execute manifest text.

Use PATH stubs in the fixture rather than assuming every CI host has every app.
For example, the fake native validator writes its received arguments to a test
file and exits the requested status.

- [ ] **Step 2: Run tests to verify failure**

Run: `bash tests/dotfiles-test.sh`

Expected: validator tests FAIL because `check` only parses the manifest.

- [ ] **Step 3: Implement the validator registry**

Implement a `case` dispatch—not `eval`—with these safe commands:

```bash
run_validator() {
    local id=$1 file=$2 target=$3
    case "$id" in
        plain) return 0 ;;
        shell) bash -n "$file" ;;
        fish) command -v fish >/dev/null 2>&1 || return 125; fish -n "$file" ;;
        fuzzel)
            command -v fuzzel >/dev/null 2>&1 || return 125
            fuzzel --check-config --config="$file"
            ;;
        git) command -v git >/dev/null 2>&1 || return 125; git config --file "$file" --list >/dev/null ;;
        lua|hyprland-lua) command -v luac >/dev/null 2>&1 || return 125; luac -p "$file" ;;
        python)
            command -v python3 >/dev/null 2>&1 || return 125
            python3 -c 'import pathlib,sys; p=pathlib.Path(sys.argv[1]); compile(p.read_bytes(), str(p), "exec")' "$file"
            ;;
        xml|fontconfig) command -v xmllint >/dev/null 2>&1 || return 125; xmllint --noout "$file" ;;
        uwsm-shell) sh -n "$file" ;;
        zellij)
            command -v zellij >/dev/null 2>&1 || return 125
            zellij --config "$file" setup --check >/dev/null
            ;;
        starship)
            command -v starship >/dev/null 2>&1 || return 125
            STARSHIP_CONFIG="$file" STARSHIP_LOG=error starship print-config >/dev/null
            ;;
        jsonc) validate_jsonc "$file" ;;
        toml) validate_toml "$file" ;;
        kitty|mpv|hyprconf|ini|mako|css) return 125 ;;
        *) return 64 ;;
    esac
}
```

Define the two parser helpers exactly as follows. Bun supplies a real JSONC
parser; Python 3.11+ supplies a real TOML parser. A missing parser returns
`125`; do not add a partial comment stripper or install a dependency:

```bash
validate_jsonc() {
    local file=$1
    command -v bun >/dev/null 2>&1 || return 125
    bun -e 'const file = process.argv[1]; Bun.JSONC.parse(await Bun.file(file).text());' "$file"
}

validate_toml() {
    local file=$1
    command -v python3 >/dev/null 2>&1 || return 125
    python3 -c 'import tomllib' >/dev/null 2>&1 || return 125
    python3 -c 'import sys,tomllib; f=open(sys.argv[1], "rb"); tomllib.load(f); f.close()' "$file"
}
```

Interpret return codes as:

```text
0   PASS on-host, STATIC PASS off-host
125 RUNTIME UNVERIFIED (validator unavailable or intentionally unsafe offline)
other BLOCKED with validator stderr summarized
```

For `hyprland-lua`, `0` on macOS still emits both `STATIC PASS` and
`RUNTIME UNVERIFIED ... requires an Arch Hyprland session`. On Arch, run
`hyprctl configerrors` only when `$HYPRLAND_INSTANCE_SIGNATURE` is non-empty;
otherwise report runtime unverified. Treat this as one global live-session
probe: every canonical Lua candidate remains `RUNTIME UNVERIFIED` unless its
loaded provenance and freshness are established, a clean probe is reported
once as a separate `PASS hyprland live-session` result, and any diagnostic or
probe error is reported once as a global `BLOCKED hyprland live-session`
result. Never reload.

- [ ] **Step 4: Run the manager checkpoint**

Run:

```bash
bash -n bin/dotfiles
bash tests/dotfiles-test.sh
./bin/dotfiles detect
./bin/dotfiles check --target macos
./bin/dotfiles check --target arch
./bin/dotfiles diff
./bin/dotfiles install
git status --short
```

Expected: shell/tests PASS; host prints `macos`; Arch results explicitly include
runtime-unverified lines; `diff` and `install` are read-only; only planned source
files are modified.

- [ ] **Step 5: Commit**

```bash
git add bin/dotfiles tests/dotfiles-test.sh
git commit -m "✨ validate dotfiles with explicit confidence levels"
```

---

### Task 8: Reconcile the active Kitty and Zellij behavior

**Files:**
- Modify: `home/.config/kitty/kitty.conf`
- Modify: `home/.config/kitty/kitty-kitten-search/search.py`
- Modify: `home/.config/kitty/kitty-kitten-search/scroll_mark.py`
- Modify: `home/.config/zellij/config.kdl`
- Modify: `tests/dotfiles-test.sh`

**Interfaces:**
- Consumes: the observed repo/live diffs from 2026-08-30.
- Produces: `dotfiles-copy` stdin command; canonical Kitty size/pager/macOS shortcuts; canonical direct Zellij tab/scroll bindings.

- [ ] **Step 1: Add failing behavior-preservation tests**

Add source assertions that fail until the live behavior is represented:

```bash
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
```

Keep the Task 3 clipboard portability test in the suite so the Zellij command
continues to have a verified backend dispatcher.

- [ ] **Step 2: Run tests to verify failure**

Run: `bash tests/dotfiles-test.sh`

Expected: terminal behavior tests FAIL while the existing clipboard portability
test remains green.

- [ ] **Step 3: Reconcile Kitty exactly with active macOS behavior**

Apply the observed live changes while removing the hard-coded username:

- change `font_size 12.0` to `font_size 13.0`;
- use `scrollback_pager ${HOME}/.config/kitty/pager.sh`;
- remove the old inline Neovim pager command;
- add `map ctrl+shift+u no_op`;
- add `macos_option_as_alt yes` and `hide_window_decorations titlebar-only`;
- add `shell_integration enabled`;
- remove the obsolete explicit `term xterm-kitty` override;
- correct the `Default shell` comment typo;
- add the missing final newline to both Python kitten files without changing
  their code.

- [ ] **Step 4: Reconcile Zellij bindings and clipboard behavior**

Add the active `Alt 1` through `Alt 0`, `Alt d`, and `Alt u` bindings under
`shared_among "normal" "locked"`. Replace the platform-specific
`copy_command "wl-copy"`/`pbcopy` choice with:

```kdl
copy_command "dotfiles-copy"
```

Do not alter any other binding, theme, mode, layout, or option.

- [ ] **Step 5: Validate and compare**

Run:

```bash
bash tests/dotfiles-test.sh
zellij --config "$PWD/home/.config/zellij/config.kdl" setup --check
python3 -c 'import pathlib; [compile(p.read_bytes(), str(p), "exec") for p in map(pathlib.Path, ["home/.config/kitty/kitty-kitten-search/search.py", "home/.config/kitty/kitty-kitten-search/scroll_mark.py"])]'
```

Expected: tests and Zellij/Python validation PASS.

- [ ] **Step 6: Commit**

```bash
git add home/.config/kitty home/.config/zellij/config.kdl tests/dotfiles-test.sh
git commit -m "♻️ preserve Kitty and Zellij behavior cross-platform"
```

---

### Task 9: Make Fish and Yazi portable and archive the inactive Fontconfig alternative

**Files:**
- Create: `.gitattributes`
- Modify: `home/.config/fish/config.fish`
- Modify: `home/.config/yazi/keymap.toml`
- Delete: `home/.config/fontconfig/conf.d/99-readability.conf.backup`
- Create: `docs/compatibility/archive/fontconfig-99-readability-alternative.conf`
- Modify: `tests/dotfiles-test.sh`

**Interfaces:**
- Consumes: Fish `command -q`/directory checks and Yazi’s native `for = "linux"|"macos"` selector.
- Produces: no broken aliases when optional tools are absent; equivalent `y`
  clipboard behavior on each OS; one active Fontconfig source plus one exact,
  non-deployable historical alternative under the compatibility archive.

- [ ] **Step 1: Add failing portability tests**

Add assertions that:

- `/opt/homebrew/bin` is guarded by `test -d`;
- aliases for `eza`, `bat`, `zoxide`, `fd`, `nvim`, and `lazygit` are guarded by
  `command -q`;
- the Linux Yazi `y` mapping contains `for = "linux"` and `wl-copy`;
- the macOS Yazi `y` mapping contains `for = "macos"` and `pbcopy`;
- the `.backup` file no longer exists under managed `home/`;
- the compatibility archive exists, is excluded from the manifest, and matches
  the historical alternative byte-for-byte;
- the manifest exactly covers the managed home files and deploys exactly one
  readability config;
- `xmllint --noout` succeeds on both active Fontconfig XML files and the archive;
- the archive materially differs from the active readability config, whose
  bytes remain unchanged.

- [ ] **Step 2: Run tests to verify failure**

Run: `bash tests/dotfiles-test.sh`

Expected: Fish/Yazi/archive checks FAIL.

- [ ] **Step 3: Guard Fish paths and optional aliases without changing successful behavior**

Keep the current initialization order. Build the common path list once, and add
Homebrew only when present:

```fish
set --export BUN_INSTALL "$HOME/.bun"
fish_add_path --path --move --prepend \
    "$HOME/.local/bin" \
    "$BUN_INSTALL/bin" \
    "$HOME/.opencode/bin" \
    "$HOME/.lmstudio/bin"

if test -d /opt/homebrew/bin
    fish_add_path --path --move --prepend /opt/homebrew/bin
end
```

Wrap each replacement/shorthand alias in its matching `command -q` condition.
Keep the Starship, Zoxide, Kitty-only Zellij startup, `y` function, Claude alias,
and greeting behavior unchanged.

- [ ] **Step 4: Add native per-OS Yazi clipboard mappings**

Keep the same `y` key and final `yank` action. The Linux rule uses the existing
URI list and `wl-copy -t text/uri-list`; the macOS rule sends the same URI text
to `pbcopy`. Both rules live in the same `keymap.toml` and differ only by
`for = "linux"` versus `for = "macos"`.

- [ ] **Step 5: Prove and archive the inactive alternative**

Run `xmllint --noout` against the active and backup XML. Record that only files
ending in `.conf` under the managed Fontconfig tree are deployed. Because the
backup is valid XML but materially differs from the active config, preserve its
exact bytes as
`docs/compatibility/archive/fontconfig-99-readability-alternative.conf`, then
remove `99-readability.conf.backup` from `home/`. Exclude the archive from
`dotfiles.manifest`, retain exact manifest coverage of `home/`, and do not
change either active Fontconfig file. Because the historical bytes end with an
intentional blank line, add a path-scoped `.gitattributes` exception for only
the archive's `blank-at-eof` check.

- [ ] **Step 6: Run shared-config validation**

Run:

```bash
fish -n home/.config/fish/config.fish
xmllint --noout home/.config/fontconfig/fonts.conf
xmllint --noout home/.config/fontconfig/conf.d/99-readability.conf
xmllint --noout docs/compatibility/archive/fontconfig-99-readability-alternative.conf
STARSHIP_CONFIG="$PWD/home/.config/starship.toml" STARSHIP_LOG=error starship print-config >/dev/null
git config --file home/.config/git/config --list >/dev/null
bash tests/dotfiles-test.sh
```

Expected: every command PASS.

- [ ] **Step 7: Commit**

```bash
git add .gitattributes home/.config/fish/config.fish home/.config/yazi/keymap.toml home/.config/fontconfig docs/compatibility/archive/fontconfig-99-readability-alternative.conf tests/dotfiles-test.sh
git commit -m "♻️ make shared shell and file configs portable"
```

---

### Task 10: Apply verified Hyprland 0.56-era syntax updates

**Files:**
- Modify: `home/.config/hypr/hyprland/looknfeel.lua`
- Modify: `home/.config/hypr/hypridle.conf`
- Modify: `home/.config/waybar/config.jsonc`
- Modify: `tests/dotfiles-test.sh`
- Create: `docs/compatibility/2026-08-30-platform-audit.md`

**Interfaces:**
- Consumes: current Hyprland Lua configuration and official 0.55+ APIs.
- Produces: current `bezier`/`spring` animation selector fields, Lua DPMS dispatch expressions, UWSM logout; no binding or visual-value changes.

- [ ] **Step 1: Capture behavior-sensitive hashes and add failing syntax assertions**

Before editing, create `docs/compatibility/2026-08-30-platform-audit.md` with a
`# Cross-platform compatibility audit — 2026-08-30` heading and a
`## Behavior-preservation baseline` table containing these observed SHA-256
values:

```text
41513a965353073a44e023f233e3b2f21daddab7186fc4db26b7c4c30d40d120  home/.config/hypr/hyprland/bindings/apps.lua
c2c7d7555536a4d8c211c557197aeee8fe82e0157dc7053cf1e3a63d2380581a  home/.config/hypr/hyprland/bindings/clipboard.lua
464e0f2c8b5d9f6321de19d22aff51aa7b6907bb4205f0a724a98b37285cfa8f  home/.config/hypr/hyprland/bindings/groups.lua
6d897a990f2b3b84987806898e43f26f79b0451b713a45b1bda65f97a8025454  home/.config/hypr/hyprland/bindings/media.lua
de68d9533583b9c02ac6bd8abecf7f757f38c8155f417dc45788cd10eca7daf5  home/.config/hypr/hyprland/bindings/mouse.lua
abeb9cc90405b1156c01a53c1f8d80173832daf00f9c350d232321e0d7cc942b  home/.config/hypr/hyprland/bindings/tiling.lua
69009fa215ff05141f4b22004ca08f3e134eecf9c94b0c8cfec7a2fb921df16e  home/.config/hypr/hyprland/general.lua
a901c3da6e0ce600adf3fbe543fcd5fe2ff87a9aab27d58e75723d39f3933c84  home/.config/hypr/hyprland/input.lua
393b6e0fe71d0b660ff7852ddc5cfeeab75e92985522e718d825ccb2ec3dce31  home/.config/hypr/hyprland/rules.lua
efaf26481d442ef1d9712b85d88b96d79cb107f90ba95320a1e6d426678a4efd  home/.config/hypr/hyprland/shared.lua
```

Verify the baseline with the same `shasum -a 256` command before editing. Stop
if any value differs, because the preservation baseline has changed. Add a test
that compares every `hl.animation` row with the preserved ordered baseline,
rejects `curve =` inside `hl.animation`, and requires `bezier =` for every
Bézier name and `spring = "easy"` for the existing spring. Also reject
`hyprctl dispatch dpms` and require:

```text
hyprctl dispatch 'hl.dsp.dpms({ action = "disable" })'
hyprctl dispatch 'hl.dsp.dpms({ action = "enable" })'
uwsm stop
```

- [ ] **Step 2: Run tests to verify failure**

Run: `bash tests/dotfiles-test.sh`

Expected: Hyprland syntax assertions FAIL.

- [ ] **Step 3: Update animation field names only**

In every `hl.animation` call in `looknfeel.lua`, use `bezier` for the existing
Bézier names and `spring` for the existing `easy` spring. Preserve the leaf,
enabled value, speed, curve-name string, style, order, and comments exactly.

- [ ] **Step 4: Update only DPMS and logout command syntax**

In `hypridle.conf`, preserve 300/600/900 second timeouts and replace old DPMS
commands with the quoted Lua dispatcher expressions above.

In Waybar, replace workspace scroll commands with:

```json
"on-scroll-up": "hyprctl dispatch 'hl.dsp.focus({ workspace = \"e+1\" })'",
"on-scroll-down": "hyprctl dispatch 'hl.dsp.focus({ workspace = \"e-1\" })'"
```

Replace the power-menu logout action `loginctl kill-session
$XDG_SESSION_ID` with `uwsm stop`. Leave every Waybar module, label, icon,
position, style, and other action unchanged.

- [ ] **Step 5: Run static Arch validation and binding-hash comparison**

Run:

```bash
find home/.config/hypr -name '*.lua' -print0 | xargs -0 -n1 luac -p
xmllint --noout home/.config/waybar/power-menu.xml
bash tests/dotfiles-test.sh
./bin/dotfiles check --target arch
```

Recompute the behavior-sensitive hashes and confirm every untouched file still
matches the pre-edit hash. Expected: Lua/XML/tests PASS; Arch runtime remains
explicitly unverified on macOS.

- [ ] **Step 6: Commit**

```bash
git add home/.config/hypr/hyprland/looknfeel.lua home/.config/hypr/hypridle.conf home/.config/waybar/config.jsonc docs/compatibility/2026-08-30-platform-audit.md tests/dotfiles-test.sh
git commit -m "♻️ update Hyprland Lua-era command syntax"
```

---

### Task 11: Write the evidence-backed compatibility audit and README

**Files:**
- Modify: `docs/compatibility/2026-08-30-platform-audit.md`
- Modify: `README.md`

**Interfaces:**
- Consumes: observed versions, official-source findings, task commits, and validation output.
- Produces: durable source/version matrix, exact confidence boundaries, user setup/recovery instructions.

- [ ] **Step 1: Add a documentation contract test**

Add a test requiring README sections named:

```text
Requirements
Quick start
Detect and check
Preview and install
Backups and recovery
Using doti
Updating versions
Arch/Hyprland runtime verification
```

Require the audit to include the strings `STATIC PASS`, `RUNTIME UNVERIFIED`,
the 2026-08-30 macOS versions, the known Kitty/Zellij live drift, and direct
official links for Hyprland, Fish, Kitty, Zellij, Yazi, Fuzzel, and Mako.

- [ ] **Step 2: Run the test to verify failure**

Run: `bash tests/dotfiles-test.sh`

Expected: documentation test FAIL.

- [ ] **Step 3: Write the compatibility audit**

Document this observed macOS baseline:

```text
Fish 4.8.1
Git 2.55.0 (Homebrew; Apple Git may differ outside configured Fish)
Starship 1.26.0 (Homebrew; stale /usr/local 1.25.1 remains shadowed)
Kitty 0.47.2
Zellij 0.45.1
Yazi 26.8.15
mpv 0.41.0
Fontconfig 2.18.3
```

Include required/recommended/optional findings, the exact four live drift files,
the behavior-sensitive pre/post hashes, the Fontconfig preservation
disposition, and an
`unverified` row for every Arch binary whose installed version was unavailable.
Use only official URLs already referenced by the spec/research; label every
unconfirmed claim as unverified.

- [ ] **Step 4: Rewrite README around the repository-native workflow**

Use clone destination `$HOME/.dotfiles` as an example, not a hard-coded personal
directory. Show:

```bash
./bin/dotfiles detect
./bin/dotfiles check
./bin/dotfiles diff
./bin/dotfiles install
./bin/dotfiles install --apply --backup
```

Explain that the first four are read-only except the explicit apply command;
explain backup location/report/manual recovery; keep doti as an optional
alternative using the same `home/`; state that package updates and compositor
reloads are never automatic.

- [ ] **Step 5: Run documentation and link checks**

Run:

```bash
bash tests/dotfiles-test.sh
rg -n 'Development/personal/configs|doti init' README.md
rg -n 'TBD|TODO|FIXME|unconfirmed latest' README.md docs/compatibility/2026-08-30-platform-audit.md
```

Expected: tests PASS; the two `rg` commands produce no output.

- [ ] **Step 6: Commit**

```bash
git add README.md docs/compatibility/2026-08-30-platform-audit.md tests/dotfiles-test.sh
git commit -m "📝 document cross-platform dotfiles operations"
```

---

### Task 12: Adopt the canonical files safely on macOS

**Files:**
- Modify only if verification exposes a defect: manager/tests/shared configs from earlier tasks.
- Runtime backup output: `${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles/backups/...` (never commit).

**Interfaces:**
- Consumes: completed CLI, canonical shared configs, current macOS live files.
- Produces: reviewed backup plan and canonical symlinks for macOS-selected files.

- [ ] **Step 1: Run the full read-only macOS gate**

Run:

```bash
bash tests/dotfiles-test.sh
./bin/dotfiles detect
./bin/dotfiles check --target macos
./bin/dotfiles diff
./bin/dotfiles install
```

Expected: `detect` prints `macos`; tests and source validators PASS; diff/install
show the exact files that would be backed up or linked. Save the preview output
for comparison.

- [ ] **Step 2: Verify the plan has no Linux-only target**

Run:

```bash
./bin/dotfiles install | rg 'hypr|waybar|fuzzel|mako|uwsm|chromium-flags|electron-flags'
```

Expected: no output.

- [ ] **Step 3: Apply with backup**

Run: `./bin/dotfiles install --apply --backup`

Expected: every pre-existing regular shared config is moved into one timestamped
backup set and replaced by a canonical absolute symlink; no directory conflict
is moved.

- [ ] **Step 4: Verify idempotence and active behavior**

Run:

```bash
./bin/dotfiles diff
./bin/dotfiles install
fish -c 'type -a git; type -a starship; git --version; starship --version'
zellij --config "$HOME/.config/zellij/config.kdl" setup --check
STARSHIP_CONFIG="$HOME/.config/starship.toml" STARSHIP_LOG=error starship print-config >/dev/null
```

Expected: diff is clean; install is all `NOOP`; Fish selects Homebrew Git and
Starship; Zellij and Starship validate. Launching/reloading Kitty is not
automated—report that a new Kitty window is required to observe startup-only
options.

- [ ] **Step 5: Record the macOS result**

Append backup-set path, command exit statuses, and any `RUNTIME UNVERIFIED`
items to `docs/compatibility/2026-08-30-platform-audit.md`. Do not include home
contents, secrets, or backup file bodies.

- [ ] **Step 6: Commit only if the audit changed**

```bash
git add docs/compatibility/2026-08-30-platform-audit.md
git commit -m "📝 record macOS dotfiles adoption"
```

---

### Task 13: Validate on the real Arch/Hyprland host and finalize

**Files:**
- Modify: `docs/compatibility/2026-08-30-platform-audit.md`
- Modify only for verified Arch defects: the exact owning config and its test.

**Interfaces:**
- Consumes: repository commits from Tasks 1–12 on the actual Arch host.
- Produces: real binary versions, native config results, Hyprland error output summary, behavior-preservation result, final review/push decision.

- [ ] **Step 1: Run the Arch read-only gate before applying**

On the Arch machine, run:

```bash
./bin/dotfiles detect
./bin/dotfiles check --target arch
./bin/dotfiles diff
./bin/dotfiles install
hyprctl configerrors
fuzzel --check-config --config="$PWD/home/.config/fuzzel/fuzzel.ini"
zellij --config "$PWD/home/.config/zellij/config.kdl" setup --check
```

Expected: `detect` prints `arch`; no macOS-only deployment decisions; Fuzzel and
Zellij exit `0`; `hyprctl configerrors` output is byte-empty. Any output,
including documented or pre-existing diagnostics, blocks acceptance. This is
global running-session evidence, not proof that
any canonical candidate was loaded or is fresh. Do not reload Hyprland.

- [ ] **Step 2: Record actual Arch versions and resolve only verified defects**

Record output of:

```bash
hyprctl version
hyprpaper --version
hypridle --version
hyprlock --version
hyprsunset --version
waybar --version
fuzzel --version
mako --version
uwsm --version
```

Replace manifest `unverified` values only with observed versions. If a
native validator fails, add a failing regression test, make the smallest
behavior-preserving correction in the owning file, rerun that validator, and
commit the correction separately. Do not change a binding, monitor, rule,
timeout, color, spacing value, font, or animation value to silence an unrelated
warning.

- [ ] **Step 3: Apply only after the Arch preview is accepted**

Run: `./bin/dotfiles install --apply --backup`

Expected: one recoverable backup set, selected Arch/shared links only, no service
or compositor action.

- [ ] **Step 4: Perform manual behavior checks without changing config**

Verify and record:

- `hyprctl configerrors` output is byte-empty;
- canonical candidates remain runtime-unverified until loaded provenance and
  freshness are established;
- all existing app, clipboard, group, media, mouse, tiling, workspace, resize,
  and lock bindings behave as before;
- Waybar modules/style/power menu render as before;
- wallpaper, idle lock/DPMS/suspend, lock screen, blue-light profiles, clipboard
  history, launcher, portal, and notification timeout behave as before;
- Zellij `Alt 1..0`, `Alt d/u`, and clipboard work;
- Kitty theme/font/pager/search and Fish auto-start workflow work.

If the user cannot provide an Arch session during execution, mark this task
`BLOCKED: real Arch/Hyprland runtime required`; do not reclassify static checks
as completion. That honest runtime handoff does not block pushing the completed
macOS and static-source work: skip the Arch apply/manual substeps, retain
`RUNTIME UNVERIFIED` in the audit, and continue with Steps 5–6.

- [ ] **Step 5: Run the final repository verification**

Run:

```bash
bash -n bin/dotfiles
bash tests/dotfiles-test.sh
./bin/dotfiles check --target arch
./bin/dotfiles diff
git diff --check
git status --short
git log --oneline --decorate -15
```

Expected: syntax/tests/check/diff pass, no whitespace errors, no unintended
files, and only deliberate commits.

- [ ] **Step 6: Obtain independent review and push**

Use `superpowers:requesting-code-review` against the full diff from `1e7a753`
through `HEAD`. Resolve every blocking finding with its own test and commit.
Then run the final verification again and push:

```bash
git push origin main
git status --short --branch
```

Expected: push succeeds, local `main` matches `origin/main`, and the worktree is
clean.

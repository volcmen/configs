# Cross-Platform Dotfiles Modernization Design

**Date:** 2026-08-30

**Status:** Approved in chat; written-spec review pending

**Targets:** macOS and Arch Linux with Hyprland

## Summary

Modernize this repository into one organized, single-source dotfiles system for
macOS and Arch Linux. Keep `home/` as the canonical, doti-compatible home
mirror. Add one declarative manifest and one repository-native command for
detecting the host, validating configuration, showing drift, and safely
installing symlinks.

The work must preserve the existing visual theme, keybindings, layouts,
animations, startup behavior, and terminal workflow. Modernization is limited
to verified compatibility, reliability, organization, and maintainability
improvements. It is not a redesign.

## Current State

The repository contains 49 tracked files under a doti-style `home/` mirror.
Shared terminal configuration and Arch/Hyprland configuration currently live in
the same source tree, but the repository has no platform manifest, native
installer, validation entry point, or documented ownership model.

Important current facts:

- Hyprland is already configured through a modular Lua entry point and required
  Lua modules. This structure is intentional and follows current upstream
  guidance; it must not be flattened.
- The tracked and live Fish, Git, and Starship files agree after the Starship
  timeout fix.
- Four tracked Kitty/Zellij files differ from their live macOS counterparts.
  Those differences must be reconciled explicitly, never overwritten blindly.
- `home/.config/fontconfig/conf.d/99-readability.conf.backup` is a stale-looking
  backup candidate, but it may be removed only after equivalence is proved.
- The Yazi recycle-bin plugin is a large vendored third-party component and
  needs explicit version/update ownership.
- Linux-only files are naturally absent from the current macOS home directory.

## Goals

1. Maintain one canonical source for every managed artifact.
2. Support macOS and Arch Linux without duplicated platform overlay trees.
3. Keep direct doti compatibility while making doti optional.
4. Provide safe, preview-first installation with conflict protection.
5. Validate configurations at the strongest level available on the current
   host and state weaker validation honestly.
6. Make upgrades deliberate and observable without installing or upgrading
   packages automatically.
7. Preserve all existing user-visible behavior unless the user separately
   approves a behavior change.

## Non-Goals

- Installing or upgrading Homebrew, Pacman, AUR, or application packages.
- Enabling, restarting, or reloading systemd, UWSM, Hyprland, or other services.
- Changing the login shell or session manager.
- Redesigning colors, spacing, fonts, keybindings, layouts, or animations.
- Generating application configuration from templates.
- Maintaining separate macOS and Linux copies of shared configuration.
- Claiming that macOS static checks prove Arch/Hyprland runtime correctness.
- Managing credentials, tokens, machine secrets, or Git credential stores.

## Core Invariant: One Canonical Source Tree

“Single source” means one canonical source tree per application, not one
physical file per application. Applications such as Hyprland, Fish, Kitty,
Waybar, Yazi, and mpv have meaningful native subfiles. Those files remain
modular when modularity improves ownership or is required by the application.

There will be no `macos/`, `linux/`, `common/`, or generated overlay copies.
Platform differences are represented in only two ways:

1. The manifest decides whether a canonical artifact applies to a platform.
2. A shared application may use a small native runtime condition inside its
   canonical config when the application actually needs different behavior.

Linux-only application files remain canonical under `home/.config`; the
installer simply does not select them on macOS.

## Repository Layout

```text
configs/
├── README.md
├── dotfiles.manifest
├── bin/
│   └── dotfiles
├── home/
│   └── .config/
│       └── ... canonical application files ...
├── tests/
│   ├── dotfiles-test.sh
│   └── fixtures/
└── docs/
    └── superpowers/
        ├── specs/
        └── plans/
```

`home/` stays compatible with doti. Neither `bin/dotfiles` nor doti generates
application configs. Both deploy the same canonical files.

## Manifest

### Format choice

`dotfiles.manifest` is a deliberately small, line-oriented data format instead
of TOML. A full TOML parser is not guaranteed on a fresh macOS or Arch system,
and a partial home-grown TOML parser would be misleading and unsafe.

The v1 grammar is pipe-delimited UTF-8 text:

```text
# app|platforms|kind|path|validator|required|tested_version
fish|macos,arch|file|.config/fish/config.fish|fish|yes|4.8
starship|macos,arch|file|.config/starship.toml|starship|yes|1.26
hyprland|arch|file|.config/hypr/hyprland.lua|hyprland-lua|yes|0.56
waybar|arch|file|.config/waybar/config.jsonc|jsonc|yes|0.15
```

### Field contract

| Field | Contract |
| --- | --- |
| `app` | Stable lowercase application/group identifier. |
| `platforms` | Comma-separated allowlist containing `macos`, `arch`, or both. |
| `kind` | `file` in schema v1. Other values fail closed. |
| `path` | Relative path used under both repository `home/` and target home. |
| `validator` | Fixed validator ID from an allowlist; never a shell command. |
| `required` | `yes` or `no`; controls whether a missing canonical artifact is fatal. |
| `tested_version` | Last upstream/runtime version against which behavior was reviewed. |

The parser rejects unknown fields or values, blank required fields, absolute
paths, `..`, duplicate target paths, pipes or newlines in values, and paths
that escape either root. Comments begin with `#`; blank lines are ignored.

The manifest records a reviewed version baseline, not an online “latest
version.” Checks report installed and reviewed versions but never query package
managers or mutate packages.

## Host and Target Model

The system keeps three concepts separate:

- **Physical host:** detected from the running operating system.
- **Validation target:** the platform whose source files should be checked.
- **Installation eligibility:** artifacts that may be deployed to the physical
  host.

Physical-host detection is strict:

- `uname -s = Darwin` → `macos`
- `uname -s = Linux` and `/etc/os-release` has `ID=arch` → `arch`
- everything else → unsupported

Arch derivatives are not silently treated as Arch. A validation override may
inspect Arch sources elsewhere, but it cannot authorize installation.

`DOTFILES_TARGET=macos|arch` and `--target` apply to read-only validation. They
do not change the result of `detect` and cannot change install eligibility.

Cross-platform `diff` is allowed only against an explicit non-live staging home.
Without a staging home, `diff` uses the physical host. `install` always uses the
physical host and the real user home; test-only overrides require an explicit
test mode.

## Command-Line Contract

`bin/dotfiles` targets the Bash 3.2 feature set available on macOS and also runs
on Arch Bash. It has no Homebrew, Python, Node, Bun, jq, GNU coreutils, or doti
dependency.

### `dotfiles detect`

- Prints exactly `macos` or `arch` on success.
- Produces a clear error and nonzero status for unsupported hosts.
- Ignores validation-target overrides.
- Never mutates state.

### `dotfiles check [--target macos|arch]`

Runs ordered validation layers:

1. manifest grammar and duplicate ownership;
2. canonical source existence and path safety;
3. format/syntax validation through allowlisted validators;
4. native non-mutating application validation when the binary exists;
5. runtime/session validation only when it is safe and meaningful.

Each result uses one of these explicit levels:

- `PASS` — applicable native or complete validation passed;
- `STATIC PASS` — source syntax passed off-platform;
- `RUNTIME UNVERIFIED` — a real target session is still required;
- `DRIFT` — live state differs from the canonical source;
- `BLOCKED` — a conflict, unsafe path, missing required prerequisite, or parse
  failure prevents progress.

The summary returns nonzero for syntax failures and blocked required artifacts.
A missing native application binary produces `RUNTIME UNVERIFIED`; it is never
reported as a passed validator and does not by itself block source deployment.

### `dotfiles diff`

Read-only comparison classifies every selected artifact as:

- missing target;
- correct repository symlink;
- symlink to another source;
- regular-file content match;
- regular-file content difference;
- directory/type conflict;
- unreadable or unsafe path.

Text differences use the platform `diff` command. Binary or undecodable files
receive metadata and digest/status output rather than raw terminal content.

### `dotfiles install`

Plain `install` is always a dry-run plan. Mutation requires `install --apply`.

Installation rules:

1. Parse and validate the complete manifest before touching the home directory.
2. Select only artifacts eligible for the physical host.
3. Preflight every source, parent, target, conflict, and available validator.
4. Abort the whole operation if any unsafe or unapproved conflict exists.
5. Treat an already-correct symlink as an idempotent no-op.
6. Create parent directories only when every existing ancestor is a directory.
7. Create absolute symlinks to the actual checkout so the repository may be
   cloned at any location.
8. Never replace regular files or foreign symlinks without `--backup`.
9. Never move a directory/type conflict automatically, even with `--backup`.
10. Never run package, service, session, shell, or reload commands.

`install --apply --backup` moves approved regular-file and foreign-symlink
conflicts to:

```text
${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles/backups/<UTC timestamp>/
```

The relative home path is preserved and an operation report records every move
and link. The installer acquires a state-directory lock, records mutations, and
automatically removes newly created links and restores moved targets if an
unexpected later operation fails. Existing backup sets are never overwritten.

## Validator Architecture

Validator names map to functions embedded in `bin/dotfiles`; the manifest
cannot execute arbitrary commands. Validators receive a canonical source path
and return a structured status.

Initial validator groups:

- shell-native structural checks for all files;
- `fish` syntax validation;
- Git config parsing against the candidate file;
- Starship configuration/render checks;
- Kitty candidate configuration checks;
- KDL/Zellij validation where the installed binary exposes a safe check;
- TOML parsing through the application binary where possible;
- Lua syntax checking plus a separate Hyprland-runtime-unverified result;
- JSONC, XML, INI, and Fontconfig checks;
- Fuzzel’s native `--check-config` on Arch;
- live Hyprland configuration errors only on an actual Hyprland session.

No generic Lua parser can validate Hyprland API names, dispatcher signatures,
monitors, rules, or UWSM behavior. macOS therefore reports Arch Hyprland Lua as
static-only even when Lua syntax succeeds.

## Application Ownership and Platform Strategy

### Shared: macOS and Arch

- **Fish:** one `config.fish`; platform-specific paths are guarded by explicit
  existence/OS checks. Generated `fish_variables` and frozen migration files
  are not tracked. Theme and binding state must remain explicit.
- **Git:** keep the portable intersection in one file. Credential-store setup
  remains host-local and outside this repository.
- **Starship:** one config, dynamic OS display, bounded command timeout, and no
  platform-specific executable path.
- **Kitty:** one canonical config tree. Avoid macOS/Linux include overlays;
  prefer portable options and narrowly guarded native features.
- **Zellij:** one KDL config. Preserve every owned binding instead of relying on
  changing defaults for behavior that matters.
- **Yazi:** one config tree. Use Yazi’s native platform selectors for genuine
  key differences. Treat vendored plugin code as pinned third-party content.
- **mpv:** one config tree using portable auto-selection or conditional profiles
  only when existing behavior requires them.
- **Fontconfig:** one canonical tree; remove the tracked backup only after the
  active files validate and compare equivalent.

### Arch-only

- Chromium and Electron Wayland flags
- Hyprland Lua modules
- hyprpaper, hypridle, hyprlock, and hyprsunset
- UWSM environment/session configuration
- Waybar JSONC, CSS, and power-menu XML
- Fuzzel
- Mako
- `mimeapps.list`
- xdg-desktop-portal Hyprland configuration

The current Hyprland Lua module boundaries, keybindings, and startup behavior
are preserved. UWSM environment deployment is separate from enabling or
restarting user services.

## Modernization Policy

Every app change is classified before implementation:

- **Required:** verified removed/deprecated syntax, correctness bug, unsafe path,
  or failure on a target version.
- **Recommended:** reliability or clarity improvement with no intended behavior
  change.
- **Optional:** aesthetic, preference, or workflow change; excluded unless the
  user approves it separately.

Current high-priority reviews include:

- validating the existing Hyprland Lua API calls against the real Arch version;
- making Fish 4.3+ theme/binding ownership explicit if generated migration files
  exist on a target host;
- adding Fuzzel’s native config check;
- auditing any dependency on Mako’s deprecated implicit `default` mode;
- reconciling tracked/live Kitty and Zellij differences;
- documenting the Yazi plugin version and update process.

Formatting-only rewrites are not mixed with semantic corrections. Each app is
modernized and validated independently so regressions have a small boundary.

## Testing Strategy

The repository uses a dependency-free shell test harness under `tests/`.
Tests run against temporary repository and home fixtures and never touch the
real home directory.

Required automated coverage:

- Darwin and Arch detection plus unsupported hosts;
- override isolation from physical-host installation eligibility;
- valid and malformed manifest rows;
- duplicate, absolute, traversal, and escaping paths;
- platform selection;
- missing required/optional sources and unavailable native validators;
- correct, foreign, missing, matching, differing, and type-conflict targets;
- dry-run zero-mutation behavior;
- idempotent repeated installation;
- conflict refusal without backup;
- backup path preservation;
- rollback after an injected mid-transaction failure;
- concurrent-install lock refusal;
- output levels and exit-code contract.

Repository checks also run application-native validators available on macOS.
Arch-only source checks run statically on macOS, then must be repeated on the
actual Arch/Hyprland machine before those files are declared runtime-valid.

## Migration Sequence

1. Record hashes, symlink state, installed versions, live drift, and generated
   files before mutation.
2. Add the manifest, test harness, and read-only `detect`, `check`, and `diff`
   behavior.
3. Reconcile the four known Kitty/Zellij live differences with explicit review.
4. Add preview-first installation and transaction/rollback tests.
5. Adopt shared applications incrementally: Git, Starship, Fontconfig, Kitty,
   Fish, Zellij, Yazi, then mpv.
6. Validate Arch-only peripheral configs statically without installing them on
   macOS.
7. Run the installer and native checks on Arch, then inspect Hyprland runtime
   configuration errors and behavior.
8. Apply verified required/recommended modernizations one application at a time.
9. Remove only proven stale backups or obsolete vendor residue.
10. Update README usage, validation levels, recovery instructions, doti
    compatibility, and version-review workflow.
11. Run the complete verification matrix, obtain independent review, commit,
    and push the finalized repository.

## Error and Recovery Policy

- Errors name the application, canonical path, target path, validation layer,
  and safe next action.
- Unsupported hosts, malformed manifests, unsafe paths, directory conflicts,
  and failures from validators that actually ran stop installation. A missing
  native binary remains explicitly unverified but does not prevent deploying
  its canonical source.
- Read-only commands continue collecting independent findings when safe, then
  return a nonzero summary.
- Mutation failures trigger automatic rollback of that transaction.
- Backup reports provide enough information for manual recovery without relying
  on the repository command still working.
- Secrets and credential-store files are never read into output or adopted.

## Acceptance Criteria

The modernization is complete when:

1. `home/` remains the only application-config source and still works with doti.
2. No shared application has duplicate macOS/Linux config copies.
3. `bin/dotfiles detect`, `check`, `diff`, and preview/apply installation obey
   this contract on temporary fixtures.
4. A macOS run validates all available shared applications without warnings or
   unintended live drift.
5. Arch-only checks are labeled static on macOS and later pass on real Arch.
6. Hyprland starts with no new configuration errors and preserves bindings,
   layout, theme, rules, and startup behavior.
7. Existing live Kitty/Zellij differences are reconciled intentionally.
8. No package, service, compositor, or login-shell mutation occurs.
9. README documents installation, preview, backup, recovery, validation levels,
   doti compatibility, and the version-review process.
10. Tests and independent review pass before the final commit is pushed.

## Key Risks and Mitigations

| Risk | Mitigation |
| --- | --- |
| Platform override installs Arch files on macOS | Overrides are read-only; install always uses physical host. |
| Existing live config is overwritten | Full preflight, preview default, explicit backup, directory conflicts refused. |
| Static Lua check is mistaken for Hyprland validity | Separate `STATIC PASS` and `RUNTIME UNVERIFIED` statuses. |
| Parser becomes a hidden dependency or execution surface | Tiny fixed grammar and allowlisted validators only. |
| Application upgrade changes implicit defaults | Record tested versions and explicitly own behavior-sensitive bindings/options. |
| Repo move breaks absolute links | Re-run preview/install from the new checkout; correct links are recreated only after conflict review. |
| Partial install leaves inconsistent state | Lock, mutation journal, backup report, and automatic rollback. |
| “Cleanup” changes the user’s workflow | Required/recommended/optional classification and per-app validation boundaries. |

## References

- [Hyprland current configuration start guide](https://wiki.hypr.land/Configuring/Start/)
- [Fish 4.x release notes](https://fishshell.com/docs/4.4/relnotes.html)
- [Fuzzel manual](https://man.archlinux.org/man/fuzzel.1.en)
- [Mako configuration manual](https://man.archlinux.org/man/mako.5)

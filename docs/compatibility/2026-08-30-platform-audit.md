# Cross-platform compatibility audit — 2026-08-30

This audit separates observed versions from reviewed manifest baselines and
static source checks from runtime evidence. A reviewed version is not an online
latest-version claim and is not evidence that the same version is installed on
another host.

## Confidence language

- `PASS` means the named scope passed its applicable physical-host check. A
  `PASS hyprland live-session` line applies only to the running session and is
  never evidence that a canonical candidate was loaded or is fresh.
- `STATIC PASS` means source syntax or structure passed off-platform; it does
  not establish target runtime behavior.
- `RUNTIME UNVERIFIED` means a required native binary, application-safe check,
  or real target session was unavailable. It is not a pass.
- `SKIPPED` means a manifest-optional canonical source was truly absent. It is
  nonblocking but remains unverified; unsafe optional paths are still blocked.
- `BLOCKED` means an unsafe source, parse error, or validator failure prevents
  progress.

Current `check` output also emits one `VERSION` row per selected artifact. Its
reviewed value is the manifest baseline; its installed value comes from a
fixed, non-package-manager command allowlist on the physical target or is the
explicit fallback `unavailable`/`not-applicable`.

## Observed macOS baseline

The baseline inventory was observed on macOS on 2026-08-30. The Git and
Starship rows use the installed versions revalidated during the 2026-08-31
live-adoption gate. The source links are direct application or distribution
documentation used for the compatibility review; they do not assert that the
linked documentation's current release is the installed release.

| Observed application/version | Observation | Authoritative source |
| --- | --- | --- |
| Fish 4.8.1 | Installed version observed in the configured Fish environment. | [Fish 4.x release notes](https://fishshell.com/docs/4.4/relnotes.html) |
| Git 2.50.1 / 2.55.0 | The fixed installed-version allowlist reported Apple Git 2.50.1; `/opt/homebrew/bin/git --version` reported Homebrew Git 2.55.0. | — |
| Starship 1.25.1 / 1.26.0 | The manager's zsh-invoked fixed command probe reported `/usr/local/bin/starship` 1.25.1; adopted Fish resolves `/opt/homebrew/bin/starship` 1.26.0, matching the manifest review baseline. | — |
| Kitty 0.47.2 | Installed macOS application version. | [Kitty configuration reference](https://sw.kovidgoyal.net/kitty/conf/) |
| Zellij 0.45.1 | Installed version; its canonical KDL passed `setup --check`. | [Zellij configuration options](https://zellij.dev/documentation/options.html) |
| Yazi 26.8.15 | Installed version; native per-OS keymap selectors are canonical. | [Yazi keymap reference](https://yazi-rs.github.io/docs/configuration/keymap/) |
| mpv 0.41.0 | Installed version; this CLI has no safe native candidate-file validator. | — |
| Fontconfig 2.18.3 | Installed version; both active XML files passed `xmllint`. | — |

`Starship 1.26.0` is both the manifest-reviewed baseline and the installed
Homebrew binary selected by adopted Fish. The separate `/usr/local` binary used
by the manager's zsh probe is 1.25.1.

## Source and version matrix

Every Arch installed-version cell below is `unverified`: no real Arch host was
available for this audit. The manifest baseline records the version last used
for source review; it must not be read as the installed Arch version.

| Application or binary | Platforms | Manifest review baseline | macOS/static evidence | Installed Arch version |
| --- | --- | --- | --- | --- |
| Fish | macOS, Arch | 4.8.1 | `PASS` on macOS | `unverified` |
| Git | macOS, Arch | 2.55.0 | `PASS` on macOS | `unverified` |
| Starship | macOS, Arch | 1.26.0 | `PASS` on macOS | `unverified` |
| Kitty | macOS, Arch | 0.47.2 | scripts `PASS`; application config `RUNTIME UNVERIFIED` | `unverified` |
| Zellij | macOS, Arch | 0.45.1 | `PASS` on macOS | `unverified` |
| Yazi | macOS, Arch | 26.8.15 | plugin Lua `PASS`; TOML validator `RUNTIME UNVERIFIED` on this host | `unverified` |
| mpv | macOS, Arch | 0.41.0 | `RUNTIME UNVERIFIED` | `unverified` |
| Fontconfig | macOS, Arch | 2.18.3 | active XML `PASS` on macOS | `unverified` |
| Chromium | Arch | `unverified` | flags source `STATIC PASS` | `unverified` |
| Electron applications | Arch | `unverified` | shared flags source `STATIC PASS`; no single Electron binary was inventoried | `unverified` |
| Fuzzel | Arch | `unverified` | allowlisted native candidate check; `RUNTIME UNVERIFIED` because Fuzzel is absent on this macOS host | `unverified` |
| Hyprland (`hyprctl`) | Arch | 0.56.2 | Lua `STATIC PASS`; session `RUNTIME UNVERIFIED` | `unverified` |
| hypridle | Arch | 0.1.7 | native/runtime check `RUNTIME UNVERIFIED` | `unverified` |
| hyprlock | Arch | `unverified` | native/runtime check `RUNTIME UNVERIFIED` | `unverified` |
| hyprpaper | Arch | 0.8.4 | native/runtime check `RUNTIME UNVERIFIED` | `unverified` |
| hyprsunset | Arch | `unverified` | native/runtime check `RUNTIME UNVERIFIED` | `unverified` |
| Mako | Arch | 1.11.0 | native check `RUNTIME UNVERIFIED` | `unverified` |
| UWSM | Arch | `unverified` | shell source `STATIC PASS`; runtime `unverified` | `unverified` |
| Waybar | Arch | 0.15.0 | JSONC/XML `STATIC PASS`; CSS runtime `RUNTIME UNVERIFIED` | `unverified` |
| xdg-desktop-portal-hyprland | Arch | `unverified` | native/runtime check `RUNTIME UNVERIFIED` | `unverified` |

`mimeapps.list` is also checked as Arch source, but it is a data file rather
than a versioned binary and therefore has no installed-binary row.

## Modernization findings

The classification follows the design contract: required fixes address
verified correctness or compatibility problems, recommended work improves
reliability without intended behavior change, and optional preference changes
remain excluded.

| Class | Finding | Decision and evidence |
| --- | --- | --- |
| Required | Four tracked Kitty/Zellij files differed from the live macOS files. | Reconciled deliberately in `fdc7cd1`; exact paths and changes are recorded below. |
| Required | Shared clipboard commands were platform-specific. | Zellij now calls `dotfiles-copy`; Yazi uses its native Linux/macOS selectors. Automated tests cover both dispatch paths. |
| Required | Hyprland Lua-era animation/dispatcher syntax and UWSM logout needed the reviewed forms. | Animation selectors use `bezier` for the existing Bézier names and `spring` for the existing `easy` spring; DPMS/workspace commands use the Lua dispatchers; logout uses `uwsm stop`. The selector correction is grounded in the [Hyprland 0.56.2 Lua binding](https://github.com/hyprwm/Hyprland/blob/v0.56.2/src/config/lua/bindings/LuaBindingsConfigRules.cpp#L428-L453) and [0.56.2 example](https://github.com/hyprwm/Hyprland/blob/v0.56.2/example/hyprland.lua#L134-L150). No reload was run. See also the [Hyprland animation guide](https://wiki.hypr.land/configuring/core/animations/) and [start guide](https://wiki.hypr.land/Configuring/Start/). |
| Required | Fuzzel's native candidate validator was unreachable through the generic `ini` manifest row. | The manifest now selects the fixed, allowlisted `fuzzel` validator, which invokes exactly `fuzzel --check-config --config="$file"`. Missing Fuzzel returns status 125 and stays visibly nonblocking; any other nonzero result blocks check and install preflight before mutation. Stubbed argv and mutation-boundary tests pass; real Arch execution remains unverified. |
| Recommended | Optional Fish tools and the Homebrew path needed explicit availability guards. | Guards were added in `e651449` without changing successful initialization order. |
| Recommended | The inactive Fontconfig alternative obscured canonical ownership but contained materially distinct rendering values. | Its exact historical bytes are preserved as a non-deployable compatibility archive; disposition and evidence are recorded below. |
| Optional | Theme, fonts, spacing, layouts, animations, bindings, and startup workflow redesigns. | Excluded. Existing user-visible values and behavior-sensitive files were preserved. |
| Optional | Unobserved package upgrades or replacement of the vendored Yazi plugin. | Excluded. Review and test an explicit version before changing the manifest baseline or plugin. |

Official configuration references used for Arch handoff are the
[Fuzzel manual](https://man.archlinux.org/man/fuzzel.1.en) and
[Mako configuration manual](https://man.archlinux.org/man/mako.5). Fuzzel now
has an allowlisted native candidate-file check; its real result, along with
Mako's native check, remains `RUNTIME UNVERIFIED` until it runs on Arch.

## Exact live-drift reconciliation

Exactly these four tracked files differed from their live macOS counterparts
on 2026-08-30:

| File | Observed drift | Canonical resolution |
| --- | --- | --- |
| `home/.config/kitty/kitty.conf` | Live font size, pager, disabled shortcut, macOS options, decorations, and shell integration differed from the tracked file. | Adopted the observed live behavior, made the pager path `$HOME`-portable, corrected the comment, and removed the explicit terminal override. |
| `home/.config/kitty/kitty-kitten-search/search.py` | Missing final newline only. | Added the final newline; Python code was unchanged. |
| `home/.config/kitty/kitty-kitten-search/scroll_mark.py` | Missing final newline only. | Added the final newline; Python code was unchanged. |
| `home/.config/zellij/config.kdl` | Live direct tab and half-page bindings were absent from the tracked file; clipboard command was Linux-specific. | Preserved the observed bindings and routed clipboard input through `dotfiles-copy`. |

This was a source reconciliation, not a live install. No home-directory config
was applied by Tasks 8–11.

## Fontconfig preservation disposition

Before disposition, both active `99-readability.conf` and inactive
`99-readability.conf.backup` were valid XML. They were not byte-equivalent and
were materially different: the inactive alternative selects `lcddefault`,
while the active config selects `lcdlight` and adds autohint, size-specific,
and family-specific rules. The alternative therefore must not be described as
equivalent, duplicate, or disposable.

The exact 805 historical bytes are preserved at
`docs/compatibility/archive/fontconfig-99-readability-alternative.conf`
(SHA-256
`42155db924b65b7a1a5bd9dfdb8423c9debf1ca0031178281791d05a468f1b08`).
This reference archive is outside `home/`, absent from `dotfiles.manifest`, and
never deployed. The old `.backup` pathname remains absent from managed `home/`,
so the manifest deploys exactly one readability config. Native `xmllint`
validation passes for the two active Fontconfig files and the archive.
The historical blob ends with an intentional blank line; `.gitattributes`
disables only the `blank-at-eof` whitespace check for this archive so its exact
bytes and the repository's normal diff hygiene can both be retained.

The active files remain byte-for-byte unchanged: `fonts.conf` has SHA-256
`8e14b0ab0f1545a87919ad01fd85e14211c1ebb06cf390a01043bb17d593a105`,
and active `99-readability.conf` has SHA-256
`795241374a5e285546266f54baa8a6ddceda4529c2ee64a9463bbf1f2925a31f`.

## Behavior-preservation baseline

Task 10 recorded these SHA-256 values before the Hyprland syntax edits and
recomputed them afterward. Matching pre/post values prove that these ten
behavior-sensitive files were byte-for-byte unchanged; they do not prove
Hyprland runtime behavior.

| File | Pre-change SHA-256 | Post-change SHA-256 |
| --- | --- | --- |
| `home/.config/hypr/hyprland/bindings/apps.lua` | `41513a965353073a44e023f233e3b2f21daddab7186fc4db26b7c4c30d40d120` | `41513a965353073a44e023f233e3b2f21daddab7186fc4db26b7c4c30d40d120` |
| `home/.config/hypr/hyprland/bindings/clipboard.lua` | `c2c7d7555536a4d8c211c557197aeee8fe82e0157dc7053cf1e3a63d2380581a` | `c2c7d7555536a4d8c211c557197aeee8fe82e0157dc7053cf1e3a63d2380581a` |
| `home/.config/hypr/hyprland/bindings/groups.lua` | `464e0f2c8b5d9f6321de19d22aff51aa7b6907bb4205f0a724a98b37285cfa8f` | `464e0f2c8b5d9f6321de19d22aff51aa7b6907bb4205f0a724a98b37285cfa8f` |
| `home/.config/hypr/hyprland/bindings/media.lua` | `6d897a990f2b3b84987806898e43f26f79b0451b713a45b1bda65f97a8025454` | `6d897a990f2b3b84987806898e43f26f79b0451b713a45b1bda65f97a8025454` |
| `home/.config/hypr/hyprland/bindings/mouse.lua` | `de68d9533583b9c02ac6bd8abecf7f757f38c8155f417dc45788cd10eca7daf5` | `de68d9533583b9c02ac6bd8abecf7f757f38c8155f417dc45788cd10eca7daf5` |
| `home/.config/hypr/hyprland/bindings/tiling.lua` | `abeb9cc90405b1156c01a53c1f8d80173832daf00f9c350d232321e0d7cc942b` | `abeb9cc90405b1156c01a53c1f8d80173832daf00f9c350d232321e0d7cc942b` |
| `home/.config/hypr/hyprland/general.lua` | `69009fa215ff05141f4b22004ca08f3e134eecf9c94b0c8cfec7a2fb921df16e` | `69009fa215ff05141f4b22004ca08f3e134eecf9c94b0c8cfec7a2fb921df16e` |
| `home/.config/hypr/hyprland/input.lua` | `a901c3da6e0ce600adf3fbe543fcd5fe2ff87a9aab27d58e75723d39f3933c84` | `a901c3da6e0ce600adf3fbe543fcd5fe2ff87a9aab27d58e75723d39f3933c84` |
| `home/.config/hypr/hyprland/rules.lua` | `393b6e0fe71d0b660ff7852ddc5cfeeab75e92985522e718d825ccb2ec3dce31` | `393b6e0fe71d0b660ff7852ddc5cfeeab75e92985522e718d825ccb2ec3dce31` |
| `home/.config/hypr/hyprland/shared.lua` | `efaf26481d442ef1d9712b85d88b96d79cb107f90ba95320a1e6d426678a4efd` | `efaf26481d442ef1d9712b85d88b96d79cb107f90ba95320a1e6d426678a4efd` |

## Arch static evidence summary

The macOS Arch-target check returned success while honestly separating static
and runtime evidence. Lua, shell, JSONC, and XML checks produced `STATIC PASS`
where tools were available. The Fuzzel candidate check was selected but
returned `RUNTIME UNVERIFIED` because the binary is absent on this macOS host.
Hyprland session validation, Mako, hypridle, hyprlock, hyprpaper, hyprsunset,
and other native/session-sensitive checks likewise remain runtime-unverified.

On an active Arch session, `hyprctl configerrors` is captured once and reported
as a separate `hyprland live-session` result. A clean result does not establish
which canonical Lua candidate is loaded or whether it is fresh, so every
candidate remains `RUNTIME UNVERIFIED`; any diagnostic text or probe failure
globally blocks the check. The capture remains byte-safe for newline/NUL-only
diagnostics, sanitizes controls, is cached, and never triggers a reload.

This macOS result is only the static evidence feeding the operator gate below.
It must never be promoted to an Arch runtime pass or used to replace an
`unverified` installed version.

## Real Arch/Hyprland operator handoff

`BLOCKED: real Arch/Hyprland runtime required`. Retain `RUNTIME UNVERIFIED`
until an operator completes this gate in a real Hyprland session. First run the
read-only preview and native checks; do not reload Hyprland:

```bash
./bin/dotfiles detect
./bin/dotfiles check --target arch
./bin/dotfiles diff
./bin/dotfiles install
hyprctl configerrors
fuzzel --check-config --config="$PWD/home/.config/fuzzel/fuzzel.ini"
zellij --config "$PWD/home/.config/zellij/config.kdl" setup --check
```

The preview is accepted only when `detect` reports `arch`; `diff` and the dry-run
`install` contain only expected Arch/shared deployment decisions and no
macOS-only decisions; Fuzzel and Zellij both exit 0; and
`hyprctl configerrors` output is byte-empty. Any output, including documented
or pre-existing diagnostics, blocks acceptance. That result describes the
current live session only;
canonical candidates remain runtime-unverified until loaded provenance and
freshness are demonstrated. Every proposed drift, missing path, creation, or
backup must be understood and accepted before applying.

If a native validator fails, stop before apply. Add a failing regression test,
make the smallest behavior-preserving correction in the exact owning file,
rerun the validator, and commit that defect separately. Never change a binding,
monitor, rule, timeout, color, spacing value, font, or animation value merely to
silence an unrelated warning.

Capture the observed versions, without replacing any `unverified` matrix value
that was not observed:

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

Only after the preview is accepted, run
`./bin/dotfiles install --apply --backup`; confirm it creates one recoverable
backup set, creates only the selected Arch/shared links, and performs no service
or compositor action. Then confirm `hyprctl configerrors` is still byte-empty
and manually verify the existing app, clipboard, group, media, mouse, tiling,
workspace, resize, and lock bindings; Waybar modules, style, and power menu;
wallpaper, idle/DPMS/suspend, lock screen, blue-light, clipboard-history,
launcher, portal, and notification behavior; Zellij `Alt 1..0`, `Alt d/u`, and
clipboard; and Kitty theme/font/pager/search plus the Fish auto-start workflow.

## macOS read-only pre-adoption gate — 2026-08-31

This gate ran from the disposable
`cross-platform-dotfiles-modernization` worktree and was deliberately
read-only. `bash tests/dotfiles-test.sh` exited 0 (`81 passed; 0 failed`),
`dotfiles detect` exited 0 and reported `macos`, and
`dotfiles check --target macos` exited 0 with 12 `PASS` and five
`RUNTIME UNVERIFIED` results. The unverified validators are Kitty (two files),
mpv, and Yazi (two files).

The live-state read-only preview was intentionally not treated as adoption:
`dotfiles diff` exited 1 with six `MATCH`, three `DRIFT`, and eight `MISSING`
entries; `dotfiles install` exited 1 with eight `CREATE` and nine `CONFLICT`
entries. All 17 selected preview rows were macOS rows. The required
Linux-only-target filter (`hypr`, `waybar`, `fuzzel`, `mako`, `uwsm`,
`chromium-flags`, and `electron-flags`) returned zero rows (`rg` exit 1 for no
matches); the install side of that pipeline retained its expected conflict exit
1.

No `install --apply` command was run during this pre-adoption gate, and this
phase created no backup set. Applying from that checkout would have created
canonical absolute symlinks pointing into an ephemeral worktree, so the gate
deferred adoption until the reviewed branch was integrated into the persistent
checkout. The following live-adoption gate resolved that deferral.

## macOS live adoption — 2026-08-31

The integrated `main` branch was adopted from the persistent
`/Users/david.david/Personal/github/configs` checkout.
`./bin/dotfiles install --apply --backup` exited 0 and created the recoverable
backup set at
`$HOME/.local/state/dotfiles/backups/20260831T190445Z-69466/`. Its
`report.tsv` and `report-recovery.tsv` are hardlinks to the same 35-line report,
and the set contains nine backed-up files. The install lock was removed after
the transaction and the empty transactions container was pruned.

Post-apply `./bin/dotfiles diff` exited 0 with 17 `LINKED` rows. A dry-run
`./bin/dotfiles install` then exited 0 with 17 `NOOP` rows and the same five
honest `RUNTIME UNVERIFIED` validator rows: Kitty (two files), mpv, and Yazi
(two files). An explicit target audit confirmed that all 17 symlinks resolve to
`/Users/david.david/Personal/github/configs/home/<relative path>`; none points
into the disposable worktree.

The live native gate passed Fish, Apple Git configuration, Homebrew Git
configuration and version 2.55.0, Starship through `STARSHIP_CONFIG`, Zellij
0.45.1, Bash, and the active Fontconfig XML. The gate's unqualified zsh
`starship` validation used `/usr/local/bin/starship` 1.25.1. A follow-up
validation passed the same adopted config with both that binary and
`/opt/homebrew/bin/starship` 1.26.0; adopted Fish resolves the latter because
its config prepends `/opt/homebrew/bin`. The config contains
`command_timeout = 2000`, and the Fish-resolved 1.26.0 version matches the
manifest review baseline. `./bin/dotfiles check --target macos` reported Apple
Git 2.50.1 through the fixed installed-version allowlist, independently of the
passing `/opt/homebrew/bin/git` 2.55.0 native gate.

No package install or update, service reload, application reload, or live Arch
apply occurred. Opening a new Kitty window remains an operator action. Real
Arch/Hyprland behavior remains `RUNTIME UNVERIFIED` and must use the operator
handoff above.

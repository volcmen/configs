# Cross-platform compatibility audit — 2026-08-30

This audit separates observed versions from reviewed manifest baselines and
static source checks from runtime evidence. A reviewed version is not an online
latest-version claim and is not evidence that the same version is installed on
another host.

## Confidence language

- `PASS` means the applicable validator ran successfully on the physical host.
- `STATIC PASS` means source syntax or structure passed off-platform; it does
  not establish target runtime behavior.
- `RUNTIME UNVERIFIED` means a required native binary, application-safe check,
  or real target session was unavailable. It is not a pass.
- `BLOCKED` means an unsafe source, parse error, or validator failure prevents
  progress.

## Observed macOS baseline

The following versions were observed on macOS on 2026-08-30. The source links
are direct application or distribution documentation used for the compatibility
review; they do not assert that the linked documentation's current release is
the installed release.

| Observed application/version | Observation | Authoritative source |
| --- | --- | --- |
| Fish 4.8.1 | Installed version observed in the configured Fish environment. | [Fish 4.x release notes](https://fishshell.com/docs/4.4/relnotes.html) |
| Git 2.55.0 | Homebrew Git; Apple Git may differ outside configured Fish. | — |
| Starship 1.26.0 | Homebrew Starship; stale `/usr/local` Starship 1.25.1 remains shadowed. | — |
| Kitty 0.47.2 | Installed macOS application version. | [Kitty configuration reference](https://sw.kovidgoyal.net/kitty/conf/) |
| Zellij 0.45.1 | Installed version; its canonical KDL passed `setup --check`. | [Zellij configuration options](https://zellij.dev/documentation/options.html) |
| Yazi 26.8.15 | Installed version; native per-OS keymap selectors are canonical. | [Yazi keymap reference](https://yazi-rs.github.io/docs/configuration/keymap/) |
| mpv 0.41.0 | Installed version; this CLI has no safe native candidate-file validator. | — |
| Fontconfig 2.18.3 | Installed version; both active XML files passed `xmllint`. | — |

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
| Fuzzel | Arch | `unverified` | native check `RUNTIME UNVERIFIED` | `unverified` |
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
| Required | Hyprland Lua-era animation/dispatcher syntax and UWSM logout needed the reviewed forms. | Field names changed to `curve`; DPMS/workspace commands use the Lua dispatchers; logout uses `uwsm stop` in `e062d2e`. No reload was run. See the [Hyprland start guide](https://wiki.hypr.land/Configuring/Start/). |
| Recommended | Optional Fish tools and the Homebrew path needed explicit availability guards. | Guards were added in `e651449` without changing successful initialization order. |
| Recommended | The inactive Fontconfig alternative obscured canonical ownership. | Decision and exact evidence are recorded in the Fontconfig section below. |
| Optional | Theme, fonts, spacing, layouts, animations, bindings, and startup workflow redesigns. | Excluded. Existing user-visible values and behavior-sensitive files were preserved. |
| Optional | Unobserved package upgrades or replacement of the vendored Yazi plugin. | Excluded. Review and test an explicit version before changing the manifest baseline or plugin. |

Official configuration references used for Arch handoff are the
[Fuzzel manual](https://man.archlinux.org/man/fuzzel.1.en) and
[Mako configuration manual](https://man.archlinux.org/man/mako.5). Their native
checks remain `RUNTIME UNVERIFIED` until they run on Arch.

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

## Fontconfig decision

Before removal, both active `99-readability.conf` and inactive
`99-readability.conf.backup` were valid XML. They were not byte-equivalent and
the `.backup` contained alternative rendering values. Only files ending in
`.conf` were part of the managed Fontconfig tree, so the `.backup` alternative
was inactive. Task 9 removed that inactive alternative after validation while
leaving `fonts.conf` and active `99-readability.conf` unchanged. This decision
does not claim the removed file was equivalent to or a duplicate of the active
configuration.

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

## Arch runtime handoff

The macOS Arch-target check returned success while honestly separating static
and runtime evidence. Lua, shell, JSONC, and XML checks produced `STATIC PASS`
where tools were available. Hyprland session validation, Fuzzel, Mako,
hypridle, hyprlock, hyprpaper, hyprsunset, and other native/session-sensitive
checks remain `RUNTIME UNVERIFIED`.

On the real Arch host, record the installed versions in the matrix, run the
native checks, inspect `hyprctl configerrors`, and test the preserved behavior
before replacing any `unverified` value. Static macOS evidence must never be
promoted to an Arch runtime pass.

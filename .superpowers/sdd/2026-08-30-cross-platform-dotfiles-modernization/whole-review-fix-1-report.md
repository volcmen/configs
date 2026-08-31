# Whole-review fix 1 report

Base: `c02bac0`

## Outcome

Both blocking findings are fixed without applying configuration or reloading
Hyprland:

1. All 17 `hl.animation` calls again use `bezier` for the existing Bézier
   names and `spring` for the existing `easy` spring. Leaves, enabled flags,
   speeds, selector names, styles, order, comments, and the `easy` spring
   definition are unchanged.
2. `hyprctl configerrors` is treated as one cached, global live-session probe.
   Every canonical candidate remains `RUNTIME UNVERIFIED` without proven
   loaded provenance and freshness. A clean probe is reported once as a
   separate live-session `PASS`; diagnostic output or a probe error is reported
   once as a global live-session `BLOCKED` result.

The corrected selector contract is grounded in Hyprland 0.56.2's
[`hl.animation` binding](https://github.com/hyprwm/Hyprland/blob/v0.56.2/src/config/lua/bindings/LuaBindingsConfigRules.cpp#L428-L453),
the pinned [0.56.2 example](https://github.com/hyprwm/Hyprland/blob/v0.56.2/example/hyprland.lua#L134-L150),
and the [animation guide](https://wiki.hypr.land/configuring/core/animations/).

## RED

Before production edits, the focused command exited 1:

```text
bash tests/dotfiles-test.sh \
  test_hyprland_animations_preserve_values_and_curve_types \
  test_check_reports_clean_hyprland_session_separately_from_candidates \
  test_check_blocks_hyprland_runtime_error_text_with_success_status \
  test_check_blocks_newline_only_hyprland_runtime_output \
  test_check_blocks_nul_only_hyprland_runtime_output

0 passed; 5 failed
```

The animation failure printed the 17 invalid `curve` selector rows. The clean
active-Arch fixture failed because one cached live-session result was still
attributed to all three distinct candidates. Dirty, newline-only, and NUL-only
fixtures failed because their global diagnostic was still attributed to a
candidate path.

## GREEN

Focused verification after the fixes:

```text
ok - test_check_marks_arch_hyprland_static_only_on_macos
ok - test_check_reports_clean_hyprland_session_separately_from_candidates
ok - test_check_blocks_hyprland_runtime_error_text_with_success_status
ok - test_check_blocks_newline_only_hyprland_runtime_output
ok - test_check_blocks_nul_only_hyprland_runtime_output
ok - test_hyprland_animations_preserve_values_and_curve_types
6 passed; 0 failed
```

Full suite:

```text
bash tests/dotfiles-test.sh
81 passed; 0 failed
```

The clean active-Arch stub invoked exactly `hyprctl configerrors` once and
produced this confidence output for three distinct canonical candidates:

```text
PASS hyprland .config/hypr/one.lua: syntax validated
RUNTIME UNVERIFIED hyprland .config/hypr/one.lua: canonical candidate provenance and freshness are unverified
PASS hyprland .config/hypr/different.lua: syntax validated
RUNTIME UNVERIFIED hyprland .config/hypr/different.lua: canonical candidate provenance and freshness are unverified
PASS hyprland .config/hypr/three.lua: syntax validated
RUNTIME UNVERIFIED hyprland .config/hypr/three.lua: canonical candidate provenance and freshness are unverified
PASS hyprland live-session: hyprctl configerrors reported no diagnostics
```

A live diagnostic retains the candidate `RUNTIME UNVERIFIED` lines, replaces
the final line with the following global result, and makes `check` exit 1:

```text
BLOCKED hyprland live-session: Config error: invalid monitor rule
```

Newline-only and NUL-only live output both produce exactly:

```text
BLOCKED hyprland live-session: validator reported diagnostic output
```

## Full, native, and static checks

All of these exited 0:

```text
bash -n bin/dotfiles
bash -n tests/dotfiles-test.sh
find home/.config/hypr -name '*.lua' -print0 | xargs -0 -n1 luac -p
fish -n home/.config/fish/config.fish
xmllint --noout home/.config/fontconfig/fonts.conf home/.config/fontconfig/conf.d/99-readability.conf home/.config/waybar/power-menu.xml
STARSHIP_CONFIG="$PWD/home/.config/starship.toml" STARSHIP_LOG=error starship print-config >/dev/null
git config --file home/.config/git/config --list >/dev/null
zellij --config "$PWD/home/.config/zellij/config.kdl" setup --check
python3 -c 'import pathlib; [compile(p.read_bytes(), str(p), "exec") for p in map(pathlib.Path, ["home/.config/kitty/kitty-kitten-search/search.py", "home/.config/kitty/kitty-kitten-search/scroll_mark.py"])]'
./bin/dotfiles check --target arch
git diff --check
```

The real command ran on macOS, so its exact confidence totals were:

```text
STATIC PASS=33
RUNTIME UNVERIFIED=28
PASS=0
BLOCKED=0
```

The exact Hyprland subset was:

```text
STATIC PASS hyprland .config/hypr/hyprland.lua: syntax validated on macos
RUNTIME UNVERIFIED hyprland .config/hypr/hyprland.lua: requires an Arch Hyprland session
STATIC PASS hyprland .config/hypr/hyprland/execs.lua: syntax validated on macos
RUNTIME UNVERIFIED hyprland .config/hypr/hyprland/execs.lua: requires an Arch Hyprland session
STATIC PASS hyprland .config/hypr/hyprland/general.lua: syntax validated on macos
RUNTIME UNVERIFIED hyprland .config/hypr/hyprland/general.lua: requires an Arch Hyprland session
STATIC PASS hyprland .config/hypr/hyprland/input.lua: syntax validated on macos
RUNTIME UNVERIFIED hyprland .config/hypr/hyprland/input.lua: requires an Arch Hyprland session
STATIC PASS hyprland .config/hypr/hyprland/keybinds.lua: syntax validated on macos
RUNTIME UNVERIFIED hyprland .config/hypr/hyprland/keybinds.lua: requires an Arch Hyprland session
STATIC PASS hyprland .config/hypr/hyprland/looknfeel.lua: syntax validated on macos
RUNTIME UNVERIFIED hyprland .config/hypr/hyprland/looknfeel.lua: requires an Arch Hyprland session
STATIC PASS hyprland .config/hypr/hyprland/rules.lua: syntax validated on macos
RUNTIME UNVERIFIED hyprland .config/hypr/hyprland/rules.lua: requires an Arch Hyprland session
STATIC PASS hyprland .config/hypr/hyprland/shared.lua: syntax validated on macos
RUNTIME UNVERIFIED hyprland .config/hypr/hyprland/shared.lua: requires an Arch Hyprland session
STATIC PASS hyprland .config/hypr/hyprland/bindings/apps.lua: syntax validated on macos
RUNTIME UNVERIFIED hyprland .config/hypr/hyprland/bindings/apps.lua: requires an Arch Hyprland session
STATIC PASS hyprland .config/hypr/hyprland/bindings/clipboard.lua: syntax validated on macos
RUNTIME UNVERIFIED hyprland .config/hypr/hyprland/bindings/clipboard.lua: requires an Arch Hyprland session
STATIC PASS hyprland .config/hypr/hyprland/bindings/groups.lua: syntax validated on macos
RUNTIME UNVERIFIED hyprland .config/hypr/hyprland/bindings/groups.lua: requires an Arch Hyprland session
STATIC PASS hyprland .config/hypr/hyprland/bindings/media.lua: syntax validated on macos
RUNTIME UNVERIFIED hyprland .config/hypr/hyprland/bindings/media.lua: requires an Arch Hyprland session
STATIC PASS hyprland .config/hypr/hyprland/bindings/mouse.lua: syntax validated on macos
RUNTIME UNVERIFIED hyprland .config/hypr/hyprland/bindings/mouse.lua: requires an Arch Hyprland session
STATIC PASS hyprland .config/hypr/hyprland/bindings/tiling.lua: syntax validated on macos
RUNTIME UNVERIFIED hyprland .config/hypr/hyprland/bindings/tiling.lua: requires an Arch Hyprland session
```

No apply, install mutation, compositor reload, service action, or real Arch
runtime validation was performed.

## Protected hashes

All ten values still match the behavior-preservation baseline:

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

## Changed files

- `README.md`
- `bin/dotfiles`
- `docs/compatibility/2026-08-30-platform-audit.md`
- `docs/superpowers/plans/2026-08-30-cross-platform-dotfiles-modernization.md`
- `home/.config/hypr/hyprland/looknfeel.lua`
- `tests/dotfiles-test.sh`
- `.superpowers/sdd/2026-08-30-cross-platform-dotfiles-modernization/whole-review-fix-1-report.md`

## Concerns and remaining boundary

- Real Arch/Hyprland runtime validation is still outstanding.
- A clean live-session probe remains insufficient candidate evidence by
  design; candidate `RUNTIME UNVERIFIED` may only be upgraded when loaded
  provenance and freshness are proven.
- Current online wiki prose contains a generic `curve` schema example alongside
  `bezier`/`spring` examples. The pinned 0.56.2 implementation and pinned
  example are the authority used here.

## Review round 1/5

The follow-up review found that the operator gates still allowed documented
pre-existing `hyprctl configerrors`, although the implementation correctly
blocks on every nonempty byte sequence. The plan and audit now require
byte-empty output both before acceptance and after apply; “no new errors” is no
longer sufficient. Candidate files remain `RUNTIME UNVERIFIED`, and the probe
remains scoped to the global live session.

The Hyprland binding citation was also corrected from the earlier range to the
actual selector-parsing lines 428–453 in the audit and this report.

Verification evidence:

```text
bash tests/dotfiles-test.sh test_documentation_records_operations_and_compatibility_evidence
1 passed; 0 failed

bash tests/dotfiles-test.sh
81 passed; 0 failed

rg stale acceptance exceptions and source anchors
0 matches

git diff --check
exit 0
```

This round changed documentation only. It did not modify code or tests and did
not run apply, install mutation, or reload commands.

# Dotfiles

One canonical `home/` tree for macOS and Arch Linux with Hyprland. The
repository-native `./bin/dotfiles` command detects the host, validates selected
sources, previews drift, and installs absolute symlinks safely. It never
installs or updates packages and never reloads applications, services, or the
compositor.

## Requirements

- Git and Bash 3.2 or newer.
- macOS, or Arch Linux identified exactly as `ID=arch` in `/etc/os-release`.
- Standard platform utilities used by the safety checks. Application binaries
  such as Fish, Zellij, or Starship enable stronger native validation when they
  are installed; an unavailable native validator is reported as
  `RUNTIME UNVERIFIED`.

The manager does not depend on Homebrew, Python, Node, Bun, `jq`, GNU
coreutils, or doti. Individual configuration files still require their owning
applications when you use them.

## Quick start

Clone anywhere; `$HOME/.dotfiles` is the recommended example:

```bash
git clone https://github.com/volcmen/configs.git "$HOME/.dotfiles"
cd "$HOME/.dotfiles"
```

Run the repository-native workflow in order:

```bash
./bin/dotfiles detect
./bin/dotfiles check
./bin/dotfiles diff
./bin/dotfiles install
./bin/dotfiles install --apply --backup
```

The first four commands are read-only. Plain `install` only prints a plan.
Only an `install` command containing `--apply` can change `$HOME`; the final
command above explicitly applies the accepted plan and backs up eligible
conflicts.

## Detect and check

`detect` prints `macos` or `arch` for the physical host and rejects unsupported
systems. A target override cannot change physical-host installation
eligibility.

```bash
./bin/dotfiles detect
./bin/dotfiles check
./bin/dotfiles check --target arch
```

`check` validates the manifest, source safety, syntax, and available native
validators. For every selected artifact it first prints one stable version row:

```text
VERSION <app> <path> reviewed=<manifest-version> installed=<observed-version|unavailable|not-applicable>
```

The reviewed value comes directly from `dotfiles.manifest`. Installed versions
are observed only on the physical target through a fixed application/argument
allowlist; `check` never evaluates manifest text or queries Homebrew, Pacman, or
another package manager. `unavailable` means an allowlisted version command
was missing, failed, or returned no recognizable version. `not-applicable`
means the target is off-platform or the artifact has no allowlisted version
probe. Manifest v1 is LF-only: CRLF and every other ASCII control byte are
rejected before any result row is printed. Identity paths may not contain
whitespace, and reviewed versions are single safe tokens, so `VERSION`, plan,
and recovery TSV boundaries cannot be forged by manifest data.

Validation confidence labels are deliberately distinct:

- `PASS`: applicable validation ran on the physical host.
- `STATIC PASS`: off-platform syntax or structure passed.
- `RUNTIME UNVERIFIED`: a native binary, safe candidate-file check, or real
  session is still required.
- `SKIPPED`: a manifest-optional canonical source is truly absent, so that
  artifact remains unverified but does not block the command.
- `BLOCKED`: an unsafe source or actual validation failure must be resolved.

A missing `required=yes` source is blocked. `required=no` changes only the
handling of true absence: an existing unsafe optional source, including a
broken symlink, is still blocked.

`--target` and `DOTFILES_TARGET=macos|arch` affect read-only validation only.
They never authorize an install for another platform.

## Preview and install

Inspect live drift and the complete installation plan before applying it:

```bash
./bin/dotfiles diff
./bin/dotfiles install
```

`diff` classifies each selected path and may exit nonzero for ordinary drift;
it prints `SKIPPED` for a truly absent optional source. Plain `install` prints
`CREATE`, `NOOP`, `CONFLICT`, `BACKUP`, `SKIPPED`, or `BLOCKED` actions without
writing anything. It builds the complete plan and runs every selected safe
source's candidate-file validator before any home or state mutation. A
validator failure blocks preview and apply; status 125 is printed as
`RUNTIME UNVERIFIED` and remains nonblocking. Install never runs live-session
or runtime probes.

Apply only after reviewing the plan:

```bash
./bin/dotfiles install --apply --backup
```

`--backup` is valid only after `--apply`. With it, regular-file and foreign
symlink conflicts are moved into one backup set before absolute links to this
checkout are created. Directory/type conflicts remain blocked even with
`--backup`. `install --apply` without `--backup` can link missing targets but
refuses existing regular files and foreign links.

No install command runs a package manager, changes the login shell, enables a
service, or reloads Kitty, Zellij, Hyprland, Waybar, or any other process.

## Backups and recovery

Backup sets are created under:

```text
${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles/backups/<UTC timestamp>-<pid>/
```

Each set contains `files/`, preserving paths relative to `$HOME`, and a
tab-separated, append-only `report.tsv`. A `MOVE_INTENT` row is durable before
the live target moves. `MOVE_FINAL` rows then record identity-validated physical
backup locations; the last complete row for an intent is current. If a location
can no longer be revalidated, the next row records its identity as unavailable
instead of naming a stale path. `UNOWNED_DISPLACED` records an unexpected inode
that the system move selected but could not safely return to its source name.
`LINK` rows record the relative path, canonical source, and installed target. An
unexpected failure during the same transaction triggers automatic rollback; a
completed install is recovered manually from its backup set.

Before an apply mutates state, it pins the physical identity of the effective
home and every existing publication ancestor. It uses the physical host's
system `stat` and exact-target, no-clobber `mv` dialect, records the actual
publication location and identity, and requires a backup source to retain its
inspected inode and fingerprint through staging and publication. It verifies
every planned `CREATE`, `BACKUP`, and `NOOP` plus its source and backup outcome
before reporting success. The backup `report.tsv` inode and exact expected rows
are verified at the same terminal commit boundary, after every mutation-capable
cleanup boundary and immediately before the transaction becomes committed. If
containment or ownership proof is lost, apply exits nonzero and rollback uses
the recorded physical parent and artifact identity, preserves foreign
arrivals, and reports the last identity-validated recovery location rather
than deleting without proof.

The report is created without clobbering and retained by an open file handle for
the whole transaction. Each backup set permanently retains a separately pinned
`report-recovery.tsv` hardlink beside its public `report.tsv`: both names refer
to the same verified report inode and carry identical complete rows. This is
durable recovery evidence if the public name is unlinked or replaced; it is not
transaction scratch and is never removed during successful cleanup. On failure,
`REPORT_RECOVERY` identifies that link's last identity-validated physical
location. A still-valid pinned recovery name remains authoritative even if a
renamed public-report sibling has the same inode. Location updates append
records through the retained handle; they never reopen or truncate either
report pathname.
Hooks, primitive test seams, and non-writer filesystem children run with the
report descriptor closed, so neither a hook nor a surviving descendant can
modify or keep the handle alive. A failed or partial append leaves all earlier
complete recovery records intact and makes the transaction fail.

After each no-clobber move, the pre-call source, destination, and nested
destination identities are compared with all post-call candidates. The original
source identity is located first, which distinguishes a moved outer directory
from a no-op source that remains in place. A no-op is valid only when that
source remains and no candidate changed; a changed destination with a restored
source is ambiguous and left untouched. If the original identity is absent,
only a single newly changed candidate can be treated as unowned; multiple
plausible candidates are recorded as ambiguous and left untouched. Unexpected
regular files, symlinks, and directories are restored no-clobber when possible;
otherwise they remain unowned, retain an identity-validated recovery location,
and are never removed by rollback.

For manual recovery:

1. Stop using the affected application and inspect `report.tsv` or its permanent
   same-inode companion `report-recovery.tsv`.
2. For each `MOVE_INTENT`, use its last complete `MOVE_FINAL` row and verify that
   the current target is still the symlink
   recorded by its matching `LINK` row. If it changed after installation, stop
   instead of overwriting it.
3. Remove only that verified installed symlink, then move the corresponding
   file from `files/<relative-path>` back to the original target shown in the
   report.
4. Run `./bin/dotfiles diff` again to inspect the recovered state.

There is no automated restore subcommand. Keep the report with the backup so
recovery does not depend on this checkout remaining available.

## Using doti

[doti](https://github.com/volcmen/doti) remains an optional alternative. Point
it at this repository using doti's documented workflow: the same `home/`
directory is its home mirror, so no generated copy or platform overlay is
needed. Do not manage the same live target concurrently with doti and
`./bin/dotfiles`; preview with one owner and understand its backup behavior
before applying.

## Updating versions

`dotfiles.manifest` records the last version against which each source was
reviewed, not an online latest release. Package upgrades are always manual:

1. Upgrade with the host's normal package tooling outside this repository.
2. Record the exact installed version and review upstream application
   documentation.
3. Add a failing regression test for any required config change, make the
   smallest behavior-preserving edit, and run the native validator.
4. Update `tested_version` only after that evidence exists, then run
   `bash tests/dotfiles-test.sh` and `./bin/dotfiles check`.

Review the resulting `VERSION` rows as local evidence, not as an online latest
version check. `unavailable` and `not-applicable` must remain explicit until an
operator safely observes the corresponding installed binary. A manifest
`tested_version` is either the literal `unverified` or a semver-style token such
as `0.56.2` or `v1.2.3-rc.1+build.7`; spaces, shell punctuation, and path-like
values fail closed.

The vendored Yazi recycle-bin plugin follows the same deliberate review flow;
it is never fetched or updated automatically.

## Arch/Hyprland runtime verification

macOS can statically inspect Arch sources, but it cannot prove an Arch
Hyprland session. On the actual Arch machine, from this checkout, run the
read-only gate first:

```bash
./bin/dotfiles detect
./bin/dotfiles check --target arch
./bin/dotfiles diff
./bin/dotfiles install
hyprctl configerrors
fuzzel --check-config --config="$PWD/home/.config/fuzzel/fuzzel.ini"
zellij --config "$PWD/home/.config/zellij/config.kdl" setup --check
```

Record the installed Hyprland, hyprpaper, hypridle, hyprlock, hyprsunset,
Waybar, Fuzzel, Mako, and UWSM versions. Resolve only observed failures, rerun
the checks, and manually verify bindings, layout, theme, rules, startup,
idle/lock/DPMS, launcher, notifications, portal, terminal, and clipboard
behavior. Keep every unobserved item `RUNTIME UNVERIFIED`.

`hyprctl configerrors` checks the one running Hyprland session. The manager
reports that probe once as `hyprland live-session`; even a clean probe does not
prove that any canonical Lua candidate is loaded or fresh, so candidate files
remain `RUNTIME UNVERIFIED` until that provenance is established. Any live
diagnostic still blocks the overall check.

The tool never reloads Hyprland or services. Apply only after the read-only
results and runtime checks are accepted, using the explicit backup command from
the previous section.

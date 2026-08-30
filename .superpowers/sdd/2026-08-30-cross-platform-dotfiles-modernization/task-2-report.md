# Task 2 Report: Strict physical-host detection

## Implementation

- Added test-only seam access through `test_value`, gated exclusively by `DOTFILES_TESTING=1`.
- Added physical kernel detection via `uname -s`, with test override available only in test mode.
- Added `/etc/os-release` lookup, with an isolated test path available only in test mode.
- Added strict host detection:
  - `Darwin` produces `macos`.
  - `Linux` produces `arch` only when the exact `ID` is `arch`.
  - Unsupported kernels, unreadable/missing IDs, and non-Arch Linux IDs exit `69`.
- Wired the `detect` command to `detect_host`; it does not consult `DOTFILES_TARGET`.

## Files

- `bin/dotfiles`
- `tests/dotfiles-test.sh`

## RED evidence

Command:

```text
bash tests/dotfiles-test.sh
```

Output:

```text
ok - test_help
ok - test_unknown_command_fails
FAIL: status 69 != 0; output: dotfiles: detect is not implemented
not ok - test_detects_macos_and_ignores_target
FAIL: status 69 != 0; output: dotfiles: detect is not implemented
not ok - test_detects_exact_arch
FAIL: missing <unsupported host>; output: dotfiles: detect is not implemented
not ok - test_rejects_arch_derivative_and_other_linux
2 passed; 3 failed
```

## GREEN evidence

Command:

```text
bash -n bin/dotfiles && bash tests/dotfiles-test.sh
```

Output:

```text
ok - test_help
ok - test_unknown_command_fails
ok - test_detects_macos_and_ignores_target
ok - test_detects_exact_arch
ok - test_rejects_arch_derivative_and_other_linux
5 passed; 0 failed
```

## Final tests

The final pre-commit verification is the same syntax check and full task suite:

```text
bash -n bin/dotfiles && bash tests/dotfiles-test.sh
```

Result: exit `0`, `5 passed; 0 failed`.

## Self-review

- Detection is based on physical kernel and OS identity only.
- Target overrides are not read by `detect_host`.
- Test environment variables are ignored unless `DOTFILES_TESTING=1`.
- Linux derivative detection is strict and does not use `ID_LIKE`.
- `git diff --check` passed.

## Concerns

No known concerns within Task 2 scope.

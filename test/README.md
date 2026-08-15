# test

- **繁體中文：[README.zh-TW.md](README.zh-TW.md)**

The regression suite for `csv2`. One script, numbered to match the plan.

```zsh
./test_csv2.zsh                      # builds release/csv2 first if it is missing
CSV2=/path/to/csv2 ./test_csv2.zsh   # test a specific binary, e.g. the Linux one
```

Output goes to the terminal and to `test_csv2.log` beside the script. The exit
status is non-zero if any case fails; SKIPs do not fail the run.

## Numbering is the contract

Every case is `T<n>`, and `T<n>` is the same case in
[`../plan/plan.md`](../plan/plan.md)'s test list. A failure therefore names the
paragraph that explains *why* the behaviour is what it is, instead of leaving
you to find it.

That mapping is the reason the plan's test list was renumbered: it previously
held two spliced sequences (1–18, then a second 6–25), so "test 12" named two
different cases and any citation of a number was already ambiguous.

## SKIP is a reported state, not an omission

A case the tool cannot yet satisfy is printed as `SKIP` **with the reason**:

```
SKIP  T41 behaviour identical with no index (the .index sidecar is not implemented)
```

It is never quietly dropped. A suite that hides what it did not run reports a
coverage it does not have — which is the same failure mode as a script that
exits zero after corrupting a file.

Current state: **74 PASS, 0 FAIL, 1 SKIP** on macOS (arm64, Swift 6.4).

The one skip is T47, which needs the Linux cross-compile (phase 6). It cannot
be turned into a pass on this machine: the whole point of the case is that the
Linux build produces byte-identical output, and there is no Linux build yet.

T9, T12 and T13 used to be skips for a more uncomfortable reason — the code
took the streaming path, but "it is written as a ring buffer" is not evidence
that RSS stays bounded. They are now measured: csv2 reports peak RSS and bytes
read on a `metrics:` line under `-debug`, and the cases assert against those
numbers. T13 in particular shows `-mid 1,2` reading 64 KiB of a 3.3 MB file,
which is the property that separates it from `-tail`.

The plan asks T9 for "an input larger than memory". A regression suite cannot
build one, and does not have to: the property that matters is that memory does
not GROW with the input, and two inputs an order of magnitude apart show that
directly in seconds.

## Environment knobs the suite relies on

| Variable | Used for |
|---|---|
| `CSV2_INDEX_MIN_BYTES` | T41/T46 — otherwise the index cases would need a 16 MiB fixture |
| `CSV2_PARALLEL_MIN_BYTES` | T42 — set high to force the single-threaded run that the parallel one is compared against |
| `CSV2_PARALLEL_CHUNK_BYTES` | T42 — turned down so a small file yields many chunks. A run that produces ONE chunk exercises no boundary and would pass on an implementation with no chunking logic at all |
| `CSV2_PRETTY_MAX_BYTES` | T19c — to reach the refusal without building a table that would actually exhaust memory |

These exist in the tool for exactly this reason, and it is written in the
source next to each of them: a threshold that cannot be lowered is a threshold
that can only be tested by producing the data it was meant to protect against.

## Fixtures

`fixtures/TARGET_PACKAGES.csv` is committed. It is a copy of the real file that
was corrupted by `${line%,*}` on 2026-08-15 — a genuine failure case, which is
what makes T1 (byte-identical round-trip) the most valuable case in the suite.
It is a copy rather than a path into the parent project because the plan
requires the suite to run on both macOS and the Linux guest, and a test that
reaches outside its own repository runs on exactly one machine.

Everything else is **generated inside the script**, and deliberately so. When
the point of a fixture is a specific byte sequence — a lone `\r`, a UTF-8 BOM, a
stray `0xE9`, a file with no trailing newline — committing it invites an editor,
a `.gitattributes` rule or a well-meaning formatter to normalise it away. The
test would then keep passing while testing nothing. Generating it with `printf`
in the script puts the byte sequence in the source, where it is visible and
cannot drift.

## Style

Follows the swift_tar test scripts (`$HOME/proj/multissh/swift_tar/test_*.sh`):
pass/fail counters, `ok`/`bad` helpers, the log written beside the script, a
temp directory created in the same folder and removed by a trap on exit.

The rule carried over from `sos/linux_test/test_git_submodule.zsh` is **test
behaviour, not file existence**. Checking that a file was produced proves
nothing about whether it is correct; several cases here assert byte-identity
against a reference instead.

No case may assume a host-specific path. The suite has to run unchanged on the
aarch64 Linux guest, where `$HOME`, the Homebrew prefix and the multissh key
directory are all different or absent.

## Adding a case

1. Add it to the test list in `../plan/plan.md` first, with its number and the
   reason it exists. A case with no stated reason gets deleted by whoever is
   tidying up in six months.
2. Implement it here under the same number, in the same phase section.
3. Tick the box in the plan **only once it passes**. A ticked box on an
   untested item is exactly the "looks like it succeeded" failure this project
   keeps running into.

# csv2

A CSV parser and editor for the command line, written in Swift, targeting the
aarch64 Linux guest of the [LinuxCS](https://github.com/raliclo/LinuxCS) project
and the macOS host it is built from.

繁體中文說明見 [README.zh-TW.md](./README.zh-TW.md)。

## Status

**Planned, not implemented.** This repository currently contains its design and
nothing else. No source, no build, no binary. See [plan/plan.md](./plan/plan.md)
for the full design and the questions still open.

It is **not** shipped in the LinuxCS guest rootfs for now — the scripts that
need it run on the macOS host. It is still tested on **both** macOS and aarch64
Linux, with byte-identical output required from each: Foundation on Linux is a
separate implementation, so passing on macOS says nothing about Linux.

Nothing below describes working software. It describes what is intended.

## Why this exists

Not because the world lacks a CSV tool — because this project has already been
bitten by naive comma splitting, twice in one day.

`TARGET_PACKAGES.csv` has a `status_notes` column holding quoted prose with
commas in it. A script that cut fields with `${line%,*}` rewrote the middle of
those notes. It exited zero and printed a list of what it had changed; the "old"
values in that list were half-sentences. The file was restored from git.

The same day, `artifacts.csv` took a commit string into `built_utc`, a timestamp
column. Nothing raised an error.

Neither failure was caused by CSV being hard. They happened because no tool was
at hand, so everyone reached for `cut -d,` and `${line%,*}`. The purpose of csv2
is to make handling CSV correctly *easier* than splitting on commas.

So the first requirement is not speed and not feature count:

> RFC 4180 quoting, embedded commas, embedded newlines, CRLF and BOM must all be
> handled correctly, and anything else must fail loudly rather than silently
> emit a half-correct file.

Output always uses `\n` as the record separator, on every platform, with no
detection of the host OS — otherwise the requirement that macOS and Linux
produce byte-identical output could not hold. Input accepts LF and CRLF mixed in
one file, decided per record rather than per file. Bytes inside quoted fields
are never touched, so "LF only" describes the record separator and not every
byte in the file.

## Two formats, declared by suffix

| Suffix | Header rows |
|---|---|
| `.csv` | 1 — standard CSV |
| `.csv2` | 2 — English titles, then Traditional Chinese titles |

The format is **declared by the suffix, never detected**. Detection guesses, and
a wrong guess turns the first data record into a header — silently.

The two-row form exists because this project's data files are bilingual, and
carrying the Chinese column titles in the file beats keeping them in a separate
document that drifts.

## Planned interface

```
csv2 -r               read
csv2 -contains S      records containing S, with their addresses
csv2 -A N -B N -C N   context around matches, as in grep
csv2 -head N          first N records          (records, not lines)
csv2 -tail N          last N records
csv2 -mid a,b         records a through b, inclusive
csv2 -t               include the header rows (off by default)
csv2 -rownum          prepend a record-number column
csv2 -md              Markdown table output
csv2 --json           JSON Lines output
csv2 -i / -o          input / output file
csv2 -si / -so        read stdin / write stdout, without buffering the whole file

csv2 -insert N ROW      insert as record N
csv2 -append ROW        append at the end
csv2 -delete a[,b]      delete record a, or records a through b
csv2 -delete -cell r:c  clear one cell (the field count never changes)
csv2 -update r:c VAL    update one cell

csv2 -hash COLS       mask columns with SHA-256, one way
csv2 -encrypt COLS    encrypt columns (ChaCha20-Poly1305)
csv2 -decrypt COLS    decrypt columns
csv2 -keyfile PATH    key file; defaults to multissh's private key

csv2 -debug           diagnostics to stderr
csv2 -log FILE        append a timestamped operation record
```

`N` counts **records, not lines** throughout. A record with a quoted newline in
it spans several lines, and counting lines yields half a record.

Addresses are `record:field`, 1-based — the same notation `-contains` prints, so
finding and editing compose:

```sh
csv2 -contains "old value" -i a.csv2     # -> 12:6 status_notes …
csv2 -update 12:6 "new value" -i a.csv2 -o b.csv2
```

## Design decisions worth knowing before reading the code

Each of these is argued in full in [plan/plan.md](./plan/plan.md).

- **Headers are opt-in.** Output carries data rows only unless `-t` is given,
  because most output is piped onward. But writing headerless output to a
  `.csv`/`.csv2` file is refused: such a file lies about its own format.
- **`-update`, not `-set`.** `-insert` / `-update` / `-delete` is SQL's
  vocabulary and reads as one set.
- **Deleting a cell means clearing it.** Actually removing the field would leave
  that record one column short and shift everything after it left — the exact
  corruption this tool exists to prevent, and it raises no error.
- **No `-key` flag.** A secret on the command line is visible in `ps` and stays
  in shell history. `-keyfile` only.
- **Nothing is printed on the normal path.** A CLI that talks cannot go in a
  pipeline. The default log threshold is WARN.

## Licence

MIT — see [LICENSE](./LICENSE).

Note for anyone reusing the design: the plan calls for column encryption built
on swift_tar's `crypto.swift`. If that code is ever vendored in rather than
merely referenced, its own licence travels with it and this file is not the
whole story.

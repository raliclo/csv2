# csv2

A CSV parser and editor for the command line, written in Swift, targeting the
aarch64 Linux guest of the [LinuxCS](https://github.com/raliclo/LinuxCS) project
and the macOS host it is built from.

繁體中文說明見 [README.zh-TW.md](./README.zh-TW.md)。

## Status

**Phases 1–4 are implemented and pass their tests. Phases 5–7 are not.**

```sh
./compile_csv2.sh       # build release/csv2
./test/test_csv2.zsh    # 60 PASS, 0 FAIL, 8 SKIP on macOS (arm64, Swift 6.4)
```

| Works | Does not yet |
|---|---|
| RFC 4180 parsing, quotes, embedded commas and newlines, CRLF, BOM | `.csv.index` / `.csv2.index` sidecars |
| `-r`, `-contains`, `-A`/`-B`/`-C`, `-head`/`-tail`/`-mid`, `-rownum` | parallel scanning |
| two-row `.csv2` headers, `--json`, `-md` | `--pretty` alignment (the flag is accepted, it does not align) |
| `-insert`/`-append`/`-delete`/`-update`, `-delete -cell` | the Linux cross-compile and the in-guest run |
| `-hash`, `-encrypt`, `-decrypt`, `-keyfile`, `-debug`, `-log` | |
| the `-append` O(1) fast path | |

Progress is tracked as checkboxes at the end of [plan/plan.md](./plan/plan.md),
and a box is only ticked once the matching case in
[test/test_csv2.zsh](./test/test_csv2.zsh) passes. Cases the tool cannot yet
satisfy are reported as SKIP with the reason rather than quietly left out.

It is **not** shipped in the LinuxCS guest rootfs for now — the scripts that
need it run on the macOS host. It is still meant to be tested on **both** macOS
and aarch64 Linux, with byte-identical output required from each: Foundation on
Linux is a separate implementation, so passing on macOS says nothing about
Linux. That second half has not happened yet; it is phase 6, and T47 in the
suite is the case that will assert it.

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

## Comparisons

[`compare/vs-sqlite.csv2`](./compare/vs-sqlite.csv2) and
[`compare/vs-postgresql.csv2`](./compare/vs-postgresql.csv2) hold the comparison
dimension by dimension. They are written in the format they describe — two
header rows, English then Traditional Chinese — so they double as the first real
`.csv2` fixtures.

Each row carries a `basis` column saying whether the claim was **measured** here,
taken from **documented** behaviour, **reasoned** from the shape of the work, or
is **UNMEASURED** and must not be relied on. That column matters more than the
verdicts: the storage rows are measured, and the full-scan rows are not, because
no Swift RFC 4180 parser exists yet to measure.

The measured storage result is not one-sided. Against SQLite, CSV is smaller for
text (1.31x, or 1.75x once an index exists) and **larger** for integers
(SQLite came in at 0.75x), because SQLite stores varints where CSV stores
decimal digits.

## When to stop using this

> Above about 1 GiB with write traffic, or when you need lookups by key, use
> SQLite instead.

Every edit rewrites the whole file, so changing one cell in a 1 GiB file writes
1 GiB where PostgreSQL would write about 10 KB. `-append` is the exception and
takes an O(1) path. Lookups are by position, not by key, so finding the row
where `pkg_name = busybox` is a full scan.

SQLite is the real neighbour here, not PostgreSQL — one file, no daemon, no
schema migration — and it has B-trees, page-level updates and transactions.
csv2 keeps exactly one advantage over it: **the file stays plain text that a
human can read and git can diff**. For this project that advantage is the whole
point, since both CSV accidents were recovered from git.

## Licence

MIT — see [LICENSE](./LICENSE).

Note for anyone reusing the design: the plan calls for column encryption built
on swift_tar's `crypto.swift`. If that code is ever vendored in rather than
merely referenced, its own licence travels with it and this file is not the
whole story.

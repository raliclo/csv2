# csv2

A CSV parser and editor for the command line, written in Swift, targeting the
aarch64 Linux guest of the [LinuxCS](https://github.com/raliclo/LinuxCS) project
and the macOS host it is built from.

繁體中文說明見 [README.zh-TW.md](./README.zh-TW.md)。

## Status

**Phases 1–6 are implemented and pass their tests. Phase 7 (shipping) is a deliberate deferral.**

```zsh
./compile_csv2.zsh       # build release/csv2
./test/test_csv2.zsh    # 74 PASS, 0 FAIL, 1 SKIP on macOS (arm64, Swift 6.4)
```

| Works | Does not yet |
|---|---|
| RFC 4180 parsing, quotes, embedded commas and newlines, CRLF, BOM | shipping in the rootfs, `install.zsh` (phase 7) |
| `-r`, `-contains`, `-A`/`-B`/`-C`, `-head`/`-tail`/`-mid`, `-rownum` | |
| two-row `.csv2` headers, `--json`, `-md`, `--pretty` (UAX #11 widths) | |
| `-insert`/`-append`/`-delete`/`-update`, `-delete -cell` | |
| `-hash`, `-encrypt`, `-decrypt`, `-keyfile`, `-debug`, `-log` | |
| the `-append` O(1) fast path | |
| `.csv.index` / `.csv2.index` sidecars, `--verify-index` | |
| parallel search, byte-identical to the single-threaded run | |
| builds and runs on aarch64 Linux, byte-identical to macOS | |

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

## Interface

```
SELECTING / 選取
  -r                    read
  -contains S           report every CELL containing S, as record:field
  --filter              with -contains, emit the matching records instead
  --include-headers     search the header rows too (reported as record 0a / 0b)
  --normalize           compare in NFC; what is stored is never normalised
  -A N  -B N  -C N      context in RECORDS, as in grep; blocks separated by --
  -head N               first N records          (records, not lines)
  -tail N               last N records
  -mid a,b              records a through b, inclusive; `a,` and `,b` are open
  -t                    include the header rows (off by default)
  -rownum               prepend a record-number column
  --physical            also print the physical line the record starts on
  --a1                  also print spreadsheet A1 notation

INPUT / OUTPUT
  -i FILE  -o FILE      file paths; -o writes a temp file and renames
  -si  -so              stdin / stdout, without buffering the whole file
  --headers 1|2         required with -si: stdin has no extension
  --in-place            edit -i in place, via temp file + rename

OUTPUT SHAPE / 輸出形狀
  -md [--pretty]        Markdown table; needs -t. --pretty aligns by DISPLAY
                        width and therefore gives up streaming
  --json                JSON Lines; --json-ascii escapes non-ASCII
  --en  --zh            which header row names the columns

EDITING / 編輯
  -insert N ROW         insert as record N; ROW is ONE line of CSV text
  -append ROW           append at the end (O(1) when writing in place)
  -delete a[,b]         delete record a, or records a through b
  -delete -cell r:c     clear one cell (the field count never changes)
  -update r:c VAL       update one cell
  --truncate-partial    drop a trailing incomplete record instead of failing

PROTECTION / 保護
  -hash COLS            mask columns with SHA-256, one way
  -encrypt COLS         encrypt columns (ChaCha20-Poly1305, fresh nonce)
  -decrypt COLS         decrypt; COLS may be `all` to take every marked column
  -keyfile PATH         key file; defaults to multissh's private key
  --yes                 accept the default key without a prompt

INDEX / 索引
  --no-index            never read or write a .index sidecar
  --verify-index        O(n) full check; the O(1) check on the normal path is
                        deliberately a heuristic, not a proof

DIAGNOSTICS / 診斷
  -debug                diagnostics to stderr, including a metrics: line
  -log FILE             append a timestamped operation record
  --version  --help
```

Both spellings of every flag are accepted: `-contains` and `--contains` are the
same. An **unknown** flag is always an error — multissh has already been bitten
by an unknown option being swallowed as a hostname.

There is deliberately no `-key`. A secret passed on the command line is visible
in `ps` to every process on the machine and stays in shell history.

`N` counts **records, not lines** throughout. A record with a quoted newline in
it spans several lines, and counting lines yields half a record.

Addresses are `record:field`, 1-based — the same notation `-contains` prints, so
finding and editing compose:

```sh
csv2 -contains "old value" -i a.csv2     # -> 12:6 status_notes …
csv2 -update 12:6 "new value" -i a.csv2 -o b.csv2
```

### Environment variables

Each exists so its logic can be **tested** without producing the data it was
meant to protect against, not merely so it can be tuned. A threshold that
cannot be lowered can only be exercised by building a 16 MiB fixture.

| Variable | Default | Effect |
|---|---|---|
| `CSV2_INDEX_MIN_BYTES` | 16 MiB | below this, no index is read or written |
| `CSV2_PARALLEL_MIN_BYTES` | 16 MiB | set above the file size to force the single-threaded path |
| `CSV2_PARALLEL_CHUNK_BYTES` | 4 MiB | smaller values make a small file yield many chunks, so chunk boundaries are actually exercised |
| `CSV2_PRETTY_MAX_BYTES` | 16 MiB | `-md --pretty` refuses above this rather than being OOM-killed |
| `CSV2_MAX_BUFFER_RECORDS` | 1,000,000 | upper bound on `-tail N` and `-B N` |

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
- **The index is always an optimisation and never a precondition.** With no
  index, behaviour is identical. Stale, truncated, corrupt, wrong version — all
  are discarded in favour of a scan, none is an error. An index that quickly
  gives you the wrong data is far worse than no index.
- **Parallel output must be byte-identical to single-threaded.** That is the
  acceptance condition, not an aspiration: this project's failures are mostly
  silent, and parallelising is especially good at producing results that are
  correct most of the time.
- **`--pretty` aligns by display width, which is a fourth number.** `套件名稱`
  is 12 bytes, 4 code points, 4 grapheme clusters and **8 columns**. Swift's
  `String.count` gives clusters, so aligning with it is wrong for Han — which
  was already true before emoji, since a `.csv2` file's second header row is
  Traditional Chinese.

## Comparisons

[`compare/vs-sqlite.csv2`](./compare/vs-sqlite.csv2) and
[`compare/vs-postgresql.csv2`](./compare/vs-postgresql.csv2) hold the comparison
dimension by dimension. They are written in the format they describe — two
header rows, English then Traditional Chinese — so they double as the first real
`.csv2` fixtures.

Each row carries a `basis` column saying whether the claim was **measured** here,
taken from **documented** behaviour, **reasoned** from the shape of the work, or
is **UNMEASURED** and must not be relied on. That column matters more than the
verdicts: the storage rows are measured, the full-scan rows are not.

When those tables were written the reason was that no Swift RFC 4180 parser
existed to measure. One exists now, so the rows are measurable and simply have
not been measured — a weaker excuse, and the tables still say UNMEASURED
because that is what they are.

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

`src/Crypto.swift` is **copied** from
`multissh/swift_tar/crypto.swift`, not referenced: swift_tar lives outside this
repository, and a build that reached across to it would work on this machine and
nowhere else — while the plan requires csv2 to build on the Linux guest too.

That copy is the same author's own code (`raliclo/multissh`), so nothing
third-party travels with it. Worth stating precisely, because multissh itself
carries **no LICENSE file**: relicensing it here under MIT is the copyright
holder's own choice, not something inherited. Anyone reusing this design with a
different provenance for those primitives has a licence question that this file
does not answer.

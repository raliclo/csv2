# csv2

A CSV parser and editor for the command line, written in Swift, targeting the
aarch64 Linux guest of the [LinuxCS](https://github.com/raliclo/LinuxCS) project
and the macOS host it is built from.

繁體中文說明見 [README.zh-TW.md](./README.zh-TW.md)。

## Status

**Phases 1–6 are implemented and pass their tests. Phase 7 (shipping) is a deliberate deferral.**

```zsh
./compile_csv2.zsh       # build release/csv2
./test/test_csv2.zsh    # 100 PASS, 0 FAIL, 1 SKIP on macOS (arm64, Swift 6.4)
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
need it run on the macOS host. It is tested on **both** macOS and aarch64
Linux, with byte-identical output required from each: Foundation on Linux is a
separate implementation, so passing on macOS says nothing about Linux. That is
case T47, driven from the parent project by
`test_submodules/run_csv2_test.zsh`, which builds csv2 in the guest and
compares twelve invocations sha256 by sha256.

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

A `.csv2` file is otherwise an ordinary CSV — the second row is simply a second
header, with no marker and no separator:

```csv
pkg,ver,note
套件,版本,備註
zlib,1.3.2,first record
zstd,1.5.6,second record
```

That file holds **two** records, not three. `csv2 --json` says so on its first
line, which is the quickest way to check csv2 read the format you meant:

```console
$ csv2 -r --json -i example.csv2 | head -1
{"meta":{"format":"csv2","headers":2,"fields":3}}
```

Both header rows must have the same field count as the data. A `.csv2` cell may
not contain a raw newline — one record is always one line — so newlines inside
values are written `\n`, carriage returns `\r` and backslashes `\\`.

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
  -hash COLS            mask columns, one way. Deterministic, so equal values
                        stay equal — and see the warning below
  -encrypt COLS         encrypt columns (ChaCha20-Poly1305, fresh nonce)
  -decrypt COLS         decrypt; COLS may be `all` to take every marked column
  -keyfile PATH         key file; defaults to multissh's private key.
                        With -hash it selects HMAC over plain SHA-256
  --yes                 accept the default key without a prompt

COLS is a comma-separated list of column names, 1-based column numbers, or a
mix: `-hash license`, `-hash 7`, `-hash 6,license`.

INDEX / 索引
  --no-index            never read or write a .index sidecar
  --build-index         build the sidecar now. Otherwise one only appears as a
                        SIDE EFFECT: a write builds one, and -tail builds one
                        because it must read the whole file anyway -- so -mid
                        alone would never produce one
  --verify-index        O(n) full check; the O(1) check on the normal path is
                        deliberately a heuristic, not a proof

DIAGNOSTICS / 診斷
  -debug                diagnostics to stderr, including a metrics: line
  -debug=trace          one level lower: every record's selection decision
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

### What each mode actually emits

Four different shapes come out of this tool, and picking the wrong one is the
easiest mistake to make: `-contains` prints a **report**, not CSV.

```console
$ csv2 -contains busybox -i TARGET_PACKAGES.csv
1:1	pkg_name	busybox
1:4	source	fork raliclo/busybox branch develop; upstream git.busybox.net
1:6	status_notes	CORRECTED 2026-08-10 after reading the generated…
6:6	status_notes	Added 2026-08-09. Fills the busybox zstd gap.…
13:6	status_notes	Required because compile.zsh is zsh-only (${0:A:h}…
```

Five lines, because five **cells** match — the long values are cut short here
with `…` for the page, not by csv2.

Three fields separated by a **TAB**: the address, the column name, the value.
One line per matching **cell**, so two matching columns in one record print two
lines, while the same string twice inside one cell prints one. In a script,
`cut -f1`, `cut -f2`, `cut -f3`.

**Values are escaped**, using the same backslash convention `.csv2` uses plus
`\t`: a literal tab becomes `\t`, a newline `\n`, a carriage return `\r`, a
backslash `\\`. Without that a cell containing a tab or a newline would break
the format the report promises — and quoted prose containing both is exactly
the data this tool was written for.

Matching is **case-sensitive** and there is no flag to change that.
`--normalize` affects Unicode normalisation only, not case.

There is **no column projection**: nothing selects "just the license column".
To get one value, use `--json` and read the field you want, or `-contains` and
take `cut -f3`.

```console
$ csv2 -contains busybox --filter -i TARGET_PACKAGES.csv
busybox,fce9d7f35ea3 (submodule),896 KiB,fork raliclo/busybox branch develop,…
```

`--filter` switches to the matching **records**, as CSV. Add `-t` to get the
header rows too — and see the refusals below for when `-t` is not optional.

`-A`, `-B` and `-C` **imply `--filter`**: a context record has no matching cell,
so there is nothing for a cell report to say about it. Blocks that are not
adjacent are separated by `--`, as in grep.

```console
$ csv2 -contains busybox --json -i TARGET_PACKAGES.csv
{"meta":{"format":"csv","headers":1,"fields":7}}
{"record":1,"field":1,"header_en":"pkg_name","value":"busybox","line":2}
{"record":1,"field":4,"header_en":"source","value":"fork raliclo/busybox …"}
{"meta":{"records":21,"matched":3}}
```

JSON Lines. The **first** line is metadata describing the format csv2 believes
it is reading, so a caller can assert `headers` is what it expected instead of
accepting a wrong guess. The **last** line carries the counts: they cannot be
in the first line without reading the whole input before emitting anything,
which is the streaming guarantee.

Read those two counts precisely. `records` is how many data records were
**read**, not how many the file holds — `-mid 5,5` on a 21-record file reports
5, because it stopped there. `matched` counts matching **records**, while the
lines between the two meta lines are one per matching **cell**, so the two
numbers differ whenever a record matches in more than one column.

A selection rather than a search emits a different object, one per record:

```console
$ csv2 -mid 5,5 --json -i TARGET_PACKAGES.csv
{"meta":{"format":"csv","headers":1,"fields":7}}
{"record":5,"line":6,"fields":{"pkg_name":"zlib (libzlib)","version":"1.3.2…",…}}
{"meta":{"records":5,"matched":0}}
```

`fields` is keyed by column name, which is the way to pull one column out
without counting.

`-md` emits a Markdown table and is one-way — csv2 cannot read it back.

### Exit status

`0` on success, non-zero on any error, and there is no third case: csv2 does
not partially succeed. A run that fails writes nothing to `-o`, because output
goes to a temp file that is renamed only after everything else worked.

`--build-index` and `--verify-index` each print one line to **stdout** — they
are explicit administrative actions, not the normal path, but if you pipe them
anywhere that line is in your stream.

Errors go to stderr as exactly **two** lines, English then Chinese, and name the
record and field. With `-log FILE` the same failure is also appended there with
a timestamp; without it nothing else is printed. On the normal path csv2 prints
nothing at all — it has to work inside a pipeline.

An error in the **arguments** is thrown before `-log` has been read, so it
reaches stderr but not the log file: the path to log to came from the same
arguments that failed to parse.

### What it refuses, and why

Refusals are the point of the tool, so they are listed rather than discovered.
Each of these exits non-zero with a message saying why:

| Combination | Why it is refused |
|---|---|
| `-head 3 -o out.csv2` (no `-t`) | data rows without a header written to a path whose suffix promises one; the next read would eat the first records as the header |
| `-md` without `-t` | a Markdown table has no shape without a header row, and silently adding one would make "no header by default" grow an invisible exception |
| `-md -o out.csv2` | the suffix declares CSV, the content would be Markdown |
| `-si` without `--headers 1` or `2` | stdin has no suffix, so the format is not declared; a default here would be a guess |
| `-head` with `-tail` | no single reading of both is obviously right |
| `-mid 7,3` | `a > b`; not swapped for you, because a range written backwards usually means the logic is backwards too |
| `-i x -o x` without `--in-place` | opening the output truncates it before the input has been read |
| `-delete 12:6` | that is a cell address; add `-cell`, or give a record number |
| `-insert -cell` | inserting a cell mid-record shifts every later field one column along |
| `-update 99:3` on a 21-record file | out of range is an error, never "grow the file to fit" |
| `-append 'a,b,c'` on a 7-column file | the field count must match the header; csv2 will not pad or truncate to fit |
| `-encrypt` with no `-keyfile` and no tty | a prompt that cannot be shown is never a yes |
| an edit with no `-o`, `-so` or `--in-place` | `-insert`/`-append`/`-delete`/`-update` need an explicit destination; there is no implied in-place |
| `-o /dev/stdout` | output is written to a temp file beside the target and renamed, which needs a regular file. Use `-so` |
| unknown flag | never swallowed as something else |

### Masking a column: read this before using `-hash`

`-hash` is **deterministic** — that is the whole reason to choose it over
`-encrypt`. Equal values produce equal digests, so you can still tell which
rows had the same original value. `-encrypt` uses a fresh nonce per cell, so
identical plaintexts give different ciphertexts and that ability is gone.

Determinism has a price, and it is not small:

> **`-hash` without a key is plain, unsalted SHA-256 of the value.** For a
> column with few possible values — `license`, `status`, `category`, a country
> code — anyone holding the hashed file can hash a word list and read the
> column straight back.

That is not hypothetical. A blind review of this tool recovered 3 of the 21
licences in the sample file from the hashed output alone, with no access to the
original and nothing but a list of SPDX identifiers.

**Pass `-keyfile` and it becomes HMAC-SHA256.** Still deterministic, so equal
values still compare equal, but the digests now depend on a secret and the word
list is useless without it:

```console
$ csv2 -hash license -i TARGET_PACKAGES.csv -o masked.csv -t
$ head -1 masked.csv | cut -d, -f7
license:hash                       # unkeyed — dictionary applies

$ csv2 -hash license -keyfile k.bin -i TARGET_PACKAGES.csv -o masked.csv -t
$ head -1 masked.csv | cut -d, -f7
license:hmac:289b9391              # keyed — fingerprint of the key used
```

Choose the unkeyed form only when the value space is genuinely large — a long
free-text field, an opaque identifier — or when you do not actually need the
values hidden from someone holding the file.

### Protected columns are marked in the file

`-hash`, `-encrypt` and `-decrypt` rewrite the **header** so the file records
what was done to which column:

| Marker | Meaning |
|---|---|
| `license:hash` | unkeyed SHA-256 |
| `license:hmac:<fp>` | HMAC-SHA256, `<fp>` identifying the key |
| `license:enc:<fp>:<salt>` | encrypted; `-decrypt all` finds these |

Addressing still uses the plain name: `-update 3:license` works after masking.
Re-masking an already-marked column is refused rather than layered.

`--json` keys stay clean, so the same marking appears in the metadata line
instead:

```console
$ csv2 -head 1 -t --json -i masked.csv
{"meta":{"format":"csv","headers":1,"fields":7,"protected":{"license":"hmac"}}}
```

The key is absent entirely when nothing is protected.

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

# csv2

`csv2` is a command-line CSV parser and editor written in Swift. It handles
RFC 4180 CSV, a two-header `.csv2` format, Markdown tables, JSON Lines output,
streaming input/output, indexed reads, parallel searches, and protected
columns.

Traditional Chinese documentation: [README.zh-TW.md](README.zh-TW.md).

## Status

The parser, editor, Markdown reader/writer, index, parallel search, encryption,
logging, and cross-platform builds are implemented and covered by the test
suite.
The public Swift module surface is available and has been verified on macOS,
aarch64 Linux, WSL, and Windows through the standalone module/client check.

## Build and install

Requirements: Swift 6 with warnings treated as errors. The build uses plain
Swift source files, Foundation, and Dispatch; it does not use SwiftPM or
SwiftNIO.

```zsh
./compile_csv2.zsh
./test/test_csv2.zsh
./install.zsh
```

The build detects macOS, Linux, and Windows. It writes `release/csv2` on
POSIX systems and `release/csv2.exe` on Windows. `install.zsh` supports
`--dry-run`, `--prefix DIR` (installs into `DIR/bin`), `--dir DIR` (installs
into `DIR` exactly), `--no-rc`, and `--uninstall`.

On macOS, install into `/usr/local/bin` rather than Homebrew's directory if a
script run over ssh needs to find it: a clean non-login shell has
`/usr/local/bin` on its PATH and does not have `/opt/homebrew/bin`, which
`path_helper` adds from `/etc/zprofile` for login shells only. install.zsh
says which of the two you got.

## Formats

The input suffix declares the format:

| Suffix | Headers | Rules |
|---|---:|---|
| `.csv` | 1 | RFC 4180; quoted commas and newlines are supported |
| `.csv2` | 2 | English and Traditional Chinese headers; one record per line; `\\n` and `\\r` escapes |
| `.md` | recovered | A Markdown table; use `--md-table N` for a selected table |
| other or none | 0 | One column per line; bytes are preserved verbatim |

**A suffix-less file has no structure to contradict, so nothing in it is
suspect.** A `#`, a JSON object, an XML declaration, a Markdown table's rows
and its `|---|` separator all come back as their own bytes -- which is what
makes a document containing a table editable line by line. A `.csv` or `.csv2`
holding a `|---|` row IS refused, because there the suffix claims otherwise
and a one-column file that looks like Markdown is `-md` output under the wrong
name.

**A blank line is a record there too**, so `-insert N ''` and `-append ''` put
a real empty line in -- prose is mostly blank lines, and a document you cannot
insert one into is not editable. A `.csv` or `.csv2` still refuses `''`,
because there the suffix has said how many fields a record has and an empty
string is not one of them.

Output record separators are always LF. CR and other bytes inside quoted CSV
fields remain data. UTF-8 BOMs are removed; UTF-16 input is refused with a
conversion instruction.

Header rows are omitted from selection output unless `-t` is supplied. Writing
headerless rows to a `.csv` or `.csv2` path is refused because the suffix would
then misrepresent the file. csv2 does not silently convert between one-header
and two-header formats.

## Reading and selecting

```sh
csv2 -r -i data.csv
csv2 -head 10 -t -i data.csv2
csv2 -tail 5 -i data.csv
csv2 -mid 20,30 -i data.csv
csv2 -contains MIT -i data.csv
csv2 -contains MIT --filter -t -o matches.csv -i data.csv
```

For the repository fixture, JSON metadata reports how far the record numbering
got and how many cells matched:

```text
$ csv2 -contains busybox --json -i test/fixtures/TARGET_PACKAGES.csv
{"meta":{"records":21,"matched":3}}
```

Available reading options:

```text
-r                 read records (the default)
-contains S        report every matching cell as record:field
--filter           emit matching records instead of a locating report
--include-headers  include header rows in searches
--normalize       compare search text in NFC; stored bytes are unchanged
-A N -B N -C N     record context around matches
-head N -tail N    first or last N records; N must be at least 1
-mid a,b           inclusive record range; either end may be omitted
-t                 include header rows in output
-rownum            prepend a record-number column
--physical         include the source line in addresses; not with --json
--a1               include spreadsheet A1 notation in addresses
-get r:c           print one cell value
-count             print how many data records the file has
```

`-count` prints one line: the number of data records. It is O(1) when a usable
`.index` sidecar is beside the file and O(n) otherwise, and it writes no
sidecar either way. A file with only a header row counts 0, which is not an
error. There is deliberately no `total` in `--json`'s meta: that number is only
known when an index is, so the field would come and go, and a caller not
finding it could not tell an empty file from a run without an index.

**`-mid a,b` with `a` past the last record is an error**, and the message names
the total. `b` past the last record is not: a window that starts inside the
file and asks for more than is there has an unambiguous answer, which is what
is there. The asymmetry exists because empty output cannot be told apart from
"these rows are genuinely empty" -- the same reason `-get` past the end has
always been an error.

Record numbers count data records, not physical lines. Header addresses are
`0` for `.csv`, and `0a`/`0b` for `.csv2`. `-contains` searches every column;
use `--search-cell R:C`, `--search-row R`, or `--search-column C` to restrict
the search to one cell, record, or column. These scope options are mutually
exclusive and require `-contains`. Column names cannot contain `:` because
that character is reserved by the `r:c` address syntax. The `:hash`, `:hmac:`,
and `:enc:` suffixes are reserved csv2 protection markers, not user-defined
column names.

## Output formats and streams

```sh
csv2 -r --json -i data.csv2
csv2 -r --json --json-ascii -i data.csv2
csv2 -r -t -md --pretty -i data.csv2
csv2 -r -si --headers 1 -so < data.csv
```

`--json` emits JSON Lines. The first and last lines are metadata; record lines
contain record data. The first metadata line carries `header`, the column names in the file's own
order, and for a `.csv2` also `header_zh`, the second header row in the same
positions -- so a consumer can use either header row and knows the column
ORDER, which the keys of a `fields` object cannot give it. `header` is present
whenever the file HAS a header row, so a `.lines` file — which has none — carries
no `header` key at all, and a script that reads column order from it must expect
that rather than an empty list. To get the order WITHOUT the file's records, take
the first line alone: `csv2 -head 1 --json -i f.csv | head -1`. There is no
header-only verb. With no header row the `fields` object is keyed by position
as decimal strings — `{"1":"one"}` — so a script written against column NAMES
gets numbers there, not an error.

The meta line's `fields` is the number of fields per record: 3 for a
three-column CSV, and 0 for a `.lines` file, where the count is not fixed.

`--json-ascii` escapes non-ASCII characters. `-md` and `--json` are mutually
exclusive and say so; there is no single run that emits both.

`-md` emits Markdown and requires `-t`. `--md-style` selects the layout, and the
three names are about PADDING only — none of them changes a value:

| `--md-style` | What it does |
|---|---|
| `preserve` (default) | Keeps each untouched row's original spacing. The rows you edited are re-emitted compactly, so it means "preserve the rows you did not touch", not "preserve the source layout" |
| `compact` | `\|zstd\|1.5.6\|BSD\|` — no padding anywhere |
| `pretty` | Re-aligns every column to a common width across the whole table |

`preserve` therefore gives the smallest diff when editing a document in place,
which is what it is the default for. `--pretty` (a different flag) holds the
selected table in memory and is bounded by `CSV2_PRETTY_MAX_BYTES`.

When a table is selected out of a document with `--md-table N`, the `line` on
each `--json` record is the line in the DOCUMENT — the same number your editor
shows — and `--physical`'s `@L` is that same number. A record on document line
27 reports 27, however far down the file the table begins.

Between 2026-09-06 and 09-07 this said the opposite: the number was relative to
the table, and this page told you to add the table's offset yourself. That
advice did not work — the `|---|` separator is a line in your document and not
a line in the translated table, so the offset was +25 for data rows and +24 for
the header, and the obvious implementation was off by one. The number is now
the document's and there is nothing to add.

`--physical` cannot be combined with `--json`; it adds to the address in the
locating report, which `--json` does not produce. Use `--json`'s own `line`.

Use `--en` or `--zh` to choose the header language in human-readable output.
`--version`/`-V` prints the build version; `--help`/`-h` prints the complete
option list.

`-si` reads stdin and `-so` writes stdout. Neither streams the whole input into
memory. When stdin is used, `--headers` is required, because stdin has no
extension to declare a format with.

**`--headers 0` reads the input line by line** — one field per line, bytes
verbatim. That is the format a file with no `.csv`/`.csv2` suffix already has,
and until now it could only be had by *having no suffix*, so neither stdin nor
a prose `.md` could ask for it. It is also the one value a declaring suffix
does not override: `--headers 1|2` against a `.csv2` is refused because the
suffix has already answered how many header rows there are, while `0` declines
that question rather than answering it differently. A `.md` read this way is
prose, and can be edited and written back as prose — for documents that merely
CONTAIN a table rather than being one.

## Errors

Errors are written to stderr as an English line followed by a Traditional
Chinese line. stdout remains empty, so failures can be handled safely in a
pipeline. All errors exit non-zero.

```text
csv2: vs-sqlite.csv2 declares 2 header row(s) by its suffix, but --headers says 1. The suffix declares the format; --headers is for input with no suffix to declare it. Drop --headers to read the file as it is. Renaming it instead makes the suffix agree with --headers, which is NOT the same thing: a header row then becomes data record 1, at rc=0, and nothing afterwards can tell it was one
csv2：vs-sqlite.csv2 的副檔名宣告了 2 列標頭，但 --headers 說 1 列。副檔名宣告格式，--headers 是給「沒有副檔名可宣告」的輸入用的。請拿掉 --headers，照這個檔案原本的樣子讀它。改檔名是讓副檔名去遷就 --headers，那不是同一件事：一列標頭會因此變成第 1 筆資料，rc=0，而事後沒有任何東西看得出它曾經是標頭
```

**A `#` line is data, not a comment.** CSV has no comment syntax, and a
column named `#id` is legal, so skipping such a line would mean guessing which
lines are data. A file with `# ...` at the top is refused by naming the `#`
rather than by counting fields, because the count is two steps from the cause.
To read such a file as lines without touching it, pipe it in:
`csv2 -si --headers 0 < FILE`. Reading it under a name with no `.csv`/`.csv2`
suffix does the same, and removing the line makes it a CSV. Note that
`--headers 0` on a file that HAS one of those suffixes means a headerless CSV,
not lines: the suffix has already declared comma separation. A node reading the
earlier message, which named only the rename, concluded the file could not be
read at all.

## Editing

```sh
csv2 -update 12:3 'new value' -i data.csv --in-place
csv2 -update-where 'pending' 'done' -i data.csv --in-place
csv2 -update 12:3 --value-file value.bin -i data.csv --in-place
csv2 -insert 4 'a,b,c' -i data.csv --in-place
csv2 -append 'a,b,c' -i data.csv --in-place
csv2 -delete 4 -i data.csv --in-place
csv2 -delete -cell 4:3 -i data.csv --in-place
csv2 -delete -col 3 -i data.csv --in-place
csv2 -add-column 3 'note,備註' 'todo' -i data.csv2 --in-place
```

Supported edit verbs are `-insert`, `-append`, `-delete`, `-update`, and
`-add-column`, plus content-anchored `-update-where`. All indexes refer to the original input and are applied in one
pass. `-delete -cell` clears a field without changing the field count.
`-delete -col` removes a column from every record and every header row.
`-add-column` takes both header titles for `.csv2`; omitting the Traditional
Chinese title leaves that header cell empty and emits a warning.

`--in-place` writes through a private temporary file and rename, except for
`-append`, which uses an append-only fast path. `-append` validates the input
before writing and writes only the appended bytes, while still reading the
existing file to validate its final record. Concurrent appends are serialized
by the operating system for complete writes, but general concurrent edits are
not supported.

`-append --in-place` does not use a temporary file and does not rename the
result. It opens the existing file for append and writes directly to it. If the
process is interrupted after the write begins, the file may contain a partial
record; the all-or-nothing preservation guarantee for ordinary in-place edits
does not apply to this append-only path.

`--truncate-partial` discards a trailing incomplete record during a rewrite.
It is refused with `-append`, which cannot remove existing bytes.

`-update-where OLD VALUE` requires exactly one data cell to equal `OLD` in
full. Zero matches, multiple matches, or overlapping repeated updates are
refused before output is written. It is a whole-cell update, not substring
replacement.

`--value-file PATH` and `--value-stdin` supply the `-update` value as exact
bytes, including trailing newlines and whitespace. They require exactly one
`-update` and cannot be combined with a literal value or `-si`.

`--dry-run` currently previews `-update` and `-update-where`, printing each
changed cell as `old -> new`, and writes no DATA file. It is not silent on disk
if you also passed `-log`: the preview is appended there, including the new
value, followed by a line reading `dry run: N change(s), wrote nothing`. That
line is true of the data file and false of the file it is written in. Until
2026-09-07 this page said "writes nothing" without qualification.

Other edit verbs are refused rather than returning empty output that could be
mistaken for “no changes”. `--backup` with `--in-place` saves the original
beside the input as `INPUT.bak` and refuses to overwrite an existing backup.

**An edit cannot take `--json` at all**, so an edit's refusal is never a JSON
error object: adding `--json` to an edit replaces whatever would have been
reported with `conflicting-options`, which is a refusal about the flags rather
than about the edit. JSON error objects — one object on stderr with a stable
`code`, `message`, and `message_zh`, exit status 1 — are for READS. Until
2026-09-07 this paragraph promised them here, and the table below repeated the
promise.

An edit whose destination is Markdown MUST pass BOTH `-md` and `-t`, and
neither is optional — `-t` is required for the same reason it is when reading,
because a Markdown table has no shape without its header row. The examples in
this section are CSV edits and show neither.
Editing a `.md` file without it is refused, naming the suffix, and the file is
left alone. With `--md-table N --in-place`, only the selected table is replaced;
surrounding prose is carried across and all output line endings are LF.
`--dry-run` works here as it does everywhere: it prints each changed cell and
writes nothing. Until 2026-09-06 that last sentence was false — `--dry-run` with
`-md` performed the write, and reported success with no output on either stream
— which is why it is now stated rather than left to be assumed.

## Protection and audit logging

```sh
csv2 -hash email -i data.csv -o masked.csv -t
csv2 -encrypt secret -keyfile key.bin -i data.csv -o encrypted.csv -t
csv2 -decrypt secret -keyfile key.bin -i encrypted.csv -o clear.csv -t
csv2 -log audit.log -update 1:2 value -i data.csv -o result.csv
```

`-hash` without a key is the plain, **unsalted** SHA-256 of the value. It is
one-way and preserves equality comparisons, but unsalted means anyone can hash
their guesses and compare: for a column of email addresses or postcodes that
recovers the values. **That is the reason to supply a key**, not a refinement of
it.

`-keyfile PATH` reads the key from a file — at least 16 bytes, and
`head -c 32 /dev/urandom > key.bin` is a fine way to make one. `--yes` is a
DIFFERENT thing, not a spelling of the same one: it uses an ambient key at
`~/.multissh/generated/mldsa44-ed25519.key.raw`, created by `mssh-keygen`. Output
keyed that way is reproducible only on a machine holding that file, so prefer
`-keyfile` for anything you need to reproduce or back up. If both are given,
`-keyfile` wins.

`-encrypt` uses ChaCha20-Poly1305 with a fresh nonce, so encrypting the same
input twice gives different bytes; both decrypt.

**`-t` is not needed for `-hash` or `-encrypt`** and changes nothing there — the
examples above carry it, and did so alone until 2026-09-07 while a reader could
reasonably conclude it was required. These verbs always write the header row,
because that is where the protection marker lives. `-md` editing genuinely does
require `-t`; these do not.

Protected columns are marked in the header: `name:hash`, `name:hmac:KEYID` for a
keyed hash, and `name:enc:KEYID:SALT` for a ciphertext.

The fourth field is a per-file **salt**, not a nonce. Until 2026-09-07 this page
called it NONCE, which describes one nonce covering a whole column under
ChaCha20-Poly1305 — catastrophic reuse, and a design csv2 does not have. The
real AEAD nonces are per cell, inside each ciphertext; that is why the same
plaintext encrypts to different bytes in two rows of one column.

The two `KEYID`s are not the same kind of thing:

| Marker | `KEYID` |
|---|---|
| `name:hmac:KEYID` | Stable for a given key. The same key gives the same value on every file and every run |
| `name:enc:KEYID:SALT` | A fingerprint over the key AND that file's salt, so it differs on every encryption even with one unchanged key |

So an `:enc:` KEYID identifies the key only WITHIN one file. Do not group files
by it to find which key opens them — that finds nothing, and every file appears
to need a different key. A wrong key is reported by decryption, which says both
fingerprints and names the salt.

**What an encrypted column still leaks.** Ciphertext length is the plaintext's
plus 28 bytes with no padding, so value lengths are visible and an empty cell is
distinguishable. The column's own name, every other column, the record count and
the row order are all in the clear. What does NOT leak is equality: two records
holding the same value encrypt to different bytes, which is the concrete
advantage over `-hash`.

`-encrypt`, `-decrypt` and `-hash` accept `--in-place`, and `--backup` applies to
them. Until 2026-09-07 `--backup` was silently ignored there — exit 0, nothing on
either stream, the plaintext overwritten and no `.bak` — on the one path where
losing the original cannot be undone. Encrypting a column that is already
encrypted is refused, and so is decrypting a column that was never encrypted or
was hashed rather than encrypted; hashing is one-way, so there is nothing to
return.

Edits that would put a raw value into a protected column are refused — and that
covers more verbs than "edit" suggests:

| Verb on a protected column | |
|---|---|
| `-update`, `-update-where`, `-delete -cell` | refused |
| `-append`, `-insert` | refused — a whole record carries a raw value into that column |
| `-delete -col` | allowed — removing the column writes no raw value |

Under `--json`, a protected file's meta `header` carries the marker as stored
(`email:hmac:6e9c89ad`) while each record's `fields` is keyed by the BASE name
(`email`), which is also the name you address with. The two deliberately differ;
a script joining them by name has to strip the marker at the first `:`. The meta
line also gains a `protected` object naming each protected column and its kind.

`-hash` and `-encrypt` mark BOTH header rows of a `.csv2`, so a file with
English and Chinese headers gets `license:hmac:KEYID` and `授權:hmac:KEYID`.

Secrets are accepted from key files, not command-line arguments. `-debug` writes
diagnostics to stderr; `-log` appends timestamped operation records — plain text,
one line each, append-only, English only, and the file is created if absent:

```text
2026-09-07T15:37:42.384+08:00 INFO  csv2 -log a.log -update 1:license <value> -i d.csv --in-place
2026-09-07T15:37:42.388+08:00 INFO  update 1:license: "MIT" -> "Zlib"
2026-09-07T15:37:42.398+08:00 INFO  wrote 2 records, 2 fields, atomic rename OK
```

The first line is the invocation with the VALUE redacted; `--value-file` and
`--value-stdin` are recorded as themselves, so the record says where the value
came from. Until 2026-09-07 both were replaced by `<value>`, which made a
`--value-stdin` run indistinguishable from a literal one.

**The log holds cleartext cell data, and it is created 0644.** That is the point
of it — the second line above is what makes the record useful — but it means
`-update`, `-update-where`, `-delete` and `-delete -cell` write values into it,
`-delete N` writes a whole record, and a `-contains` search records its needle.
Protecting a column does not protect the log beside it: keep it where you would
keep the data, not where you would keep a build artifact. What the log never
holds is a key — `-keyfile` is recorded as the path, and the key's fingerprint
appears where a key would identify itself.

There is no `-key` option: secrets on a command line are visible to other
processes and may remain in shell history. Use `-keyfile` instead.

## Indexes and performance

The optional sidecar is named by appending `.index` to the complete data-file
name, for example `data.csv.index`. It is an optimisation, never a source of
truth or a precondition:

```sh
csv2 --build-index -i data.csv
csv2 --verify-index -i data.csv
csv2 -contains needle --no-index -i data.csv
```

Missing, stale, corrupt, or unsupported indexes are **silently** discarded in
favour of a scan. The run exits 0, the answer is correct, and nothing is printed
on either stream — so an index you built for speed can be lost to one changed
mtime and you will not be told. Reads stay right and get much slower. `-debug`
is the only window onto this and prints `index hit` or the reason it did not:

```text
$ csv2 -mid 500,500 -debug -i data.csv
index hit
metrics: read_bytes=65536 file_bytes=2808905 peak_rss_bytes=9404416
```

`read_bytes` against `file_bytes` is the evidence that a window was seeked to
rather than scanned for; a discarded index shows the whole file read.

**Some verbs create a sidecar without being asked.** Above
`CSV2_INDEX_MIN_BYTES`, `-tail` and any `-update … --in-place` write one beside
the data, silently — `-r`, `-count`, `-head`, `-mid`, `-get` and `-contains` do
not. Use `--no-index` to prevent it. Until 2026-09-07 this page mentioned
non-creation for `-count` alone, which invited reading that as the general rule.

**Editing maintains the index rather than invalidating it**, so a file under
active editing keeps its sidecar useful. The exception is two concurrent
`-append --in-place` runs, where the second warns that it could not update it.

`--verify-index` checks the sidecar's own integrity — its checksum, header and
shape — and exits non-zero when it is absent or invalid. It does **not** compare
the index against the data, which is what its own failure text says and what
this page said the opposite of until 2026-09-07 by calling it "a full
validation". An unusable sidecar is left on disk unchanged; `--build-index`
replaces it.

`--build-index` ignores `CSV2_INDEX_MIN_BYTES` — an explicit request beats the
heuristic — and combining it with `--no-index` is refused as a contradiction.
`--no-index` disables both reading and writing the sidecar; the writing half
matters only for the two verbs above.

`-contains` can use parallel search when the format and thresholds permit it;
output is byte-identical to the single-threaded path.

Environment variables used for controlled testing and tuning:

| Variable | Default | Purpose |
|---|---:|---|
| `CSV2_INDEX_MIN_BYTES` | 16 MiB | minimum file size for AUTOMATIC sidecar creation; `--build-index` ignores it |
| `CSV2_PARALLEL_MIN_BYTES` | 16 MiB | minimum size for parallel search |
| `CSV2_PARALLEL_CHUNK_BYTES` | 4 MiB | search chunk size |
| `CSV2_PRETTY_MAX_BYTES` | 16 MiB | maximum material held by `--pretty` |
| `CSV2_MD_MAX_BYTES` | 16 MiB | maximum Markdown input |
| `CSV2_MAX_BUFFER_RECORDS` | 1,000,000 | limit for `-tail` and context buffers |

## Testing and measurements

```zsh
./test/test_csv2.zsh
../test_submodules/run_csv2_test.zsh
./verifications/measure.zsh
```

The local suite reports pass/fail/skip counts and exits non-zero on failure.
The parent-project runner builds csv2 in the aarch64 Linux guest, compares
host and guest output, runs the guest suite, and records measurements.

### Measured read/write time

These are recorded wall-clock durations for the benchmark corpus, shown in
microseconds (µs). They are not a fixed per-record guarantee; process startup,
storage, corpus size, and host conditions are included. The macOS and Windows
runs used 200,000 records (25.4 MiB); the Linux guest run used 20,000 records
(2.48 MiB), so compare only like-for-like rows.

| Measurement | macOS arm64<br>2026-08-17 | Windows x86_64<br>2026-08-27 | Linux aarch64 guest<br>2026-08-30 |
|---|---:|---:|---:|
| Full read, single-threaded | 556,000 µs | 2,512,000 µs | 93,000 µs |
| Full read, parallel | 203,000 µs | 839,000 µs | 101,000 µs |
| Small durable edit | 19,200 µs | 81,500 µs | 10,600 µs |
| Full-file rewrite | 655,000 µs | 2,444,000 µs | 192,000 µs |

The source measurements are kept in `verifications/measure_output*.txt` and
are produced by `verifications/measure.zsh` using best-of-N timings.

### Parallel-search throughput and RSS

The parallel-search measurement uses the same 10,000,000 data records in a
1,307,777,815-byte `.csv` file and a 1,307,777,833-byte `.csv2` file. Every
record matches `needle`; the values below are one run per format and cap on
macOS arm64, with 10 workers and 4 MiB chunks.

| Format | `CSV2_PARALLEL_MAX_BYTES` | Elapsed | Throughput | Peak RSS |
|---|---:|---:|---:|---:|
| `.csv` | default 1 GiB | 34.886 s | 35.8 MiB/s | 9.28 MiB |
| `.csv2` | default 1 GiB | 39.609 s | 31.5 MiB/s | 51.84 MiB |
| `.csv` | 8 MiB | 34.354 s | 36.3 MiB/s | 9.30 MiB |
| `.csv2` | 8 MiB | 32.376 s | 38.5 MiB/s | 51.69 MiB |

This is a measurement, not a performance guarantee; compare only runs with
the same binary, record count, host, and search conditions. The raw output is
[`verifications/measure_parallel_rss_output.txt`](verifications/measure_parallel_rss_output.txt).

## When to stop using this

Every row here was measured on 2026-09-06, not carried forward from an earlier
list. Three entries that used to be on it are gone because the feature landed —
the third was "counting without reading the file", which `-count` has answered
since phase 8 while this table went on sending readers to a whole-file `--json`
pass. It survived a re-measurement dated 2026-09-01 that this sentence claimed
covered every row, which is the argument for re-running the rows rather than
re-reading them.

| Not offered | What to do instead |
|---|---|
| column projection (`-cols`) | `--json` and `jq`, or `-get` per cell |
| case-insensitive matching | nothing does — `-contains mit` finds no `MIT`. Use `--json` and one pass of your own |
| a search that ignores which column it is in | `-contains` matches a substring in EVERY column, so `-contains MIT` also finds `transMITter` — see the last example below. Use `--search-column license` to scope it, or `--search-row`/`--search-cell`. Until 2026-09-07 this row said scoping was not offered at all, and warned that counting would be "silently wrong", 260 lines below the section documenting the flag that fixes it |
| skipping `#` comment lines | nothing does, and deliberately: a `#` is data and `#id` is a legal column name, so skipping one would mean guessing which lines are data. The refusal names the `#` |
| a header-only read | `csv2 -head 1 --json -i f.csv \| head -1` — the meta line carries `header`; no verb returns the names alone |
| converting between `.csv` and `.csv2` | refused on purpose; write the records out and read them back in |
| safe concurrent writers | serialise them yourself; two writers silently lose one edit. Two concurrent `-append --in-place` runs are the exception: both records land whole, and the one finishing SECOND warns it could not update the index |

One thing this table used to say and no longer does: **editing a Markdown
table** is supported, and it is in the examples below.

It also used to say that **telling refusals apart programmatically** is done
with the `--json` error object. That is true for reads and false for edits,
which cannot take `--json` at all — so an edit's refusal is available only as
text on stderr. That row was removed rather than corrected, because it named a
capability the reader most wants exactly where it does not exist.

## Examples

Self-contained: every command here runs against a file the first block makes,
and every output is what this version actually prints.

```console
$ printf 'pkg,version,license\n套件,版本,授權\nzlib,1.3.1,MIT\nzstd,1.5.6,BSD\n' > pkgs.csv2
```

Read the records. The two header rows are not records, so they are not printed:

```console
$ csv2 -r -i pkgs.csv2
zlib,1.3.1,MIT
zstd,1.5.6,BSD

$ csv2 -r -t -i pkgs.csv2
pkg,version,license
套件,版本,授權
zlib,1.3.1,MIT
zstd,1.5.6,BSD
```

One cell, by name, with nothing around it:

```console
$ csv2 -get 1:license -i pkgs.csv2
MIT
```

**The locating report is three TAB-separated fields: address, column name,
value.** It is not CSV, and that is on purpose — a value containing a comma
would break a CSV report:

```console
$ csv2 -contains MIT -i pkgs.csv2
1:3	license	MIT
```

**`--json` emits TWO metadata lines, and neither is a record.** The first says
what csv2 believes it is reading; the last carries the counts. A parser that
treats every line as a record meets the first one immediately:

```console
$ csv2 -r --json -i pkgs.csv2
{"meta":{"format":"csv2","headers":2,"fields":3,"header":["pkg","version","license"],"header_zh":["套件","版本","授權"]}}
{"record":1,"line":3,"fields":{"pkg":"zlib","version":"1.3.1","license":"MIT"}}
{"record":2,"line":4,"fields":{"pkg":"zstd","version":"1.5.6","license":"BSD"}}
{"meta":{"records":2,"matched":0}}
```

A Markdown table. Both header rows travel in one cell separated by `<br>`, and
`--pretty` aligns by DISPLAY width, so the CJK titles count two columns each:

```console
$ csv2 -r -t -md --pretty -i pkgs.csv2
| pkg<br>套件 | version<br>版本 | license<br>授權 |
|-------------|-----------------|-----------------|
| zlib        | 1.3.1           | MIT             |
| zstd        | 1.5.6           | BSD             |
```

**See an edit before making it.** `--dry-run` prints the change and writes
nothing:

```console
$ csv2 -update 1:version '1.3.2' --dry-run -i pkgs.csv2 --in-place
update 1:version: "1.3.1" -> "1.3.2"

$ csv2 -update 1:version '1.3.2' --backup -i pkgs.csv2 --in-place
$ csv2 -r -i pkgs.csv2
zlib,1.3.2,MIT
zstd,1.5.6,BSD
$ ls pkgs.csv2*
pkgs.csv2	pkgs.csv2.bak
```

**An edit anchored on content refuses when the match is not unique**, and names
every address it found rather than picking one:

```console
$ printf 'k,v\n甲,乙\na,x\nb,x\n' > dup.csv2
$ csv2 -update-where x Z -i dup.csv2 --in-place
csv2: -update-where "x": more than one data cell matches (1:2, 2:2); refusing an ambiguous update
csv2：-update-where「x」：有多個資料儲存格符合（1:2, 2:2）；拒絕這個有歧義的更新
```

**Refusals are readable by a program under `--json`** — one line on stderr,
with a stable `code`. The exit status stays 1:

```console
$ csv2 --json -i nosuch.csv
{"error":{"code":"not-found","message":"cannot open input file: nosuch.csv","message_zh":"無法開啟輸入檔：nosuch.csv"}}
```

**And the trap worth seeing once:** `-contains` is a substring search across
every column, so it finds the word inside another value too:

```console
$ printf 'pkg,license\n套件,授權\nzlib,MIT\ntransMITter,BSD\n' > lic.csv2
$ csv2 -contains MIT -i lic.csv2
1:2	license	MIT
2:1	pkg	transMITter
```

## License

MIT. See [LICENSE](LICENSE).

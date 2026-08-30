# csv2

`csv2` is a command-line CSV parser and editor written in Swift. It handles
RFC 4180 CSV, a two-header `.csv2` format, Markdown tables, JSON Lines output,
streaming input/output, indexed reads, parallel searches, and protected
columns.

Traditional Chinese documentation: [README.zh-TW.md](README.zh-TW.md).

## Status

The parser, editor, Markdown reader/writer, index, parallel search, encryption,
logging, and cross-platform builds are implemented and covered by the test
suite. Packaging csv2 into the LinuxCS guest root filesystem is not included.
The public Swift module surface is available; module verification on macOS and
aarch64 Linux remains pending.

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
`--dry-run`, `--prefix DIR`, `--no-rc`, and `--uninstall`.

## Formats

The input suffix declares the format:

| Suffix | Headers | Rules |
|---|---:|---|
| `.csv` | 1 | RFC 4180; quoted commas and newlines are supported |
| `.csv2` | 2 | English and Traditional Chinese headers; one record per line; `\\n` and `\\r` escapes |
| `.md` | recovered | A Markdown table; use `--md-table N` for a selected table |
| other or none | 0 | One column per line; bytes are preserved verbatim |

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

For the repository fixture, JSON metadata reports the number of data records
and matches:

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
-head N -tail N    first or last N records
-mid a,b           inclusive record range; either end may be omitted
-t                 include header rows in output
-rownum            prepend a record-number column
--physical         include the physical starting line in addresses
--a1               include spreadsheet A1 notation in addresses
-get r:c           print one cell value
```

Record numbers count data records, not physical lines. Header addresses are
`0` for `.csv`, and `0a`/`0b` for `.csv2`. `-contains` searches every column;
there is no column-restriction option.

## Output formats and streams

```sh
csv2 -r --json -i data.csv2
csv2 -r --json --json-ascii -i data.csv2
csv2 -r -t -md --pretty -i data.csv2
csv2 -r -si --headers 1 -so < data.csv
```

`--json` emits JSON Lines. The first and last lines are metadata; record lines
contain record data. `--json-ascii` escapes non-ASCII characters. `-md` emits
Markdown and requires `-t`; `--md-style preserve|compact|pretty` selects its
layout. `--pretty` holds the selected table in memory and is bounded by
`CSV2_PRETTY_MAX_BYTES`.

Use `--en` or `--zh` to choose the header language in human-readable output.
`--version`/`-V` prints the build version; `--help`/`-h` prints the complete
option list.

`-si` reads stdin and `-so` writes stdout. Neither streams the whole input into
memory. When stdin is used, `--headers 1` or `--headers 2` is required.

## Errors

Errors are written to stderr as an English line followed by a Traditional
Chinese line. stdout remains empty, so failures can be handled safely in a
pipeline. All errors exit non-zero.

```text
csv2: vs-sqlite.csv2 declares 2 header row(s) by its suffix, but --headers says 1. The suffix declares the format; --headers is for input with no suffix to declare it. Drop --headers to read the file as it is. Renaming it instead makes the suffix agree with --headers, which is NOT the same thing: a header row then becomes data record 1, at rc=0, and nothing afterwards can tell it was one
csv2：vs-sqlite.csv2 的副檔名宣告了 2 列標頭，但 --headers 說 1 列。副檔名宣告格式，--headers 是給「沒有副檔名可宣告」的輸入用的。請拿掉 --headers，照這個檔案原本的樣子讀它。改檔名是讓副檔名去遷就 --headers，那不是同一件事：一列標頭會因此變成第 1 筆資料，rc=0，而事後沒有任何東西看得出它曾經是標頭
```

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

`--truncate-partial` discards a trailing incomplete record during a rewrite.
It is refused with `-append`, which cannot remove existing bytes.

`-update-where OLD VALUE` requires exactly one data cell to equal `OLD` in
full. Zero matches, multiple matches, or overlapping repeated updates are
refused before output is written. It is a whole-cell update, not substring
replacement.

`--value-file PATH` and `--value-stdin` supply the `-update` value as exact
bytes, including trailing newlines and whitespace. They require exactly one
`-update` and cannot be combined with a literal value or `-si`.

`--dry-run` prints each changed cell as `old -> new` and writes nothing.
`--backup` with `--in-place` saves the original beside the input as `INPUT.bak`
and refuses to overwrite an existing backup. Under `--json`, refusals are one
JSON error object on stderr with a stable `code`, `message`, and `message_zh`;
the exit status remains 1.

An edit may use `-md` when the destination is Markdown. With
`--md-table N --in-place`, only the selected table is replaced; surrounding
prose is carried across and all output line endings are LF.

## Protection and audit logging

```sh
csv2 -hash email -i data.csv -o masked.csv -t
csv2 -encrypt secret -keyfile key.bin -i data.csv -o encrypted.csv -t
csv2 -decrypt secret -keyfile key.bin -i encrypted.csv -o clear.csv -t
csv2 -log audit.log -update 1:2 value -i data.csv -o result.csv
```

`-hash` uses SHA-256 without a key, or keyed hashing with `-keyfile`/`--yes`.
Hashing is one-way but preserves equality comparisons. `-encrypt` uses
ChaCha20-Poly1305 with a fresh nonce. Protected columns are marked in the
header; raw edits to a protected column are refused. Secrets are accepted from
key files, not command-line arguments. `-debug` writes diagnostics to stderr;
`-log` appends timestamped operation records.

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

Missing, stale, corrupt, or unsupported indexes are discarded in favour of a
scan. `--verify-index` performs a full validation and exits non-zero when the
sidecar is absent or invalid. `--no-index` disables both reading and writing
the sidecar. `-contains` can use parallel search when the format and thresholds
permit it; output is byte-identical to the single-threaded path.

Environment variables used for controlled testing and tuning:

| Variable | Default | Purpose |
|---|---:|---|
| `CSV2_INDEX_MIN_BYTES` | 16 MiB | minimum file size for sidecar creation |
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

## License

MIT. See [LICENSE](LICENSE).

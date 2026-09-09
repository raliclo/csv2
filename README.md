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

## Install a release

Three archives are published per version, one per platform that can both build
and verify its own — each was packed on the machine that built the binary, and
the packaging script ends by extracting the archive, running the extracted
binary and having it read a CSV.

```sh
curl -LO https://github.com/raliclo/csv2/releases/download/v0.1.0/csv2-0.1.0-macos-arm64.tar.zst
curl -LO https://github.com/raliclo/csv2/releases/download/v0.1.0/csv2-0.1.0-macos-arm64.tar.zst.sha256
sha256sum -c csv2-0.1.0-macos-arm64.tar.zst.sha256
zstd -d csv2-0.1.0-macos-arm64.tar.zst -c | tar -x
./csv2-0.1.0-macos-arm64/csv2 --version
```

Substitute `linux-x86_64` or `windows-x86_64` for the other two. **aarch64 Linux
is tested and its archive is not published yet** — it simply has not been built
on that machine.

Until 2026-09-09 this paragraph gave a reason: that the image testing it has no
zstd. That was false; it has `/usr/bin/zstd`. The file I read was Buildroot's own
upstream example defconfig rather than the configuration this project feeds to
Buildroot, which sets `BR2_PACKAGE_ZSTD=y` and says above it why. Every step of
the reasoning after that was sound and inherited a false premise, which is a
reminder worth more than the paragraph it replaced: ask the machine, not the file
that describes it.

With Homebrew — this repository is its own tap, so there is no second one:

```sh
brew tap raliclo/csv2 https://github.com/raliclo/csv2
brew trust raliclo/csv2
brew install raliclo/csv2/csv2
```

**The `brew trust` line is not optional.** Homebrew 6 refuses to load a formula
from an untrusted third-party tap, and the refusal arrives at `brew install`,
not at `brew tap`.

With Scoop:

```powershell
scoop install https://raw.githubusercontent.com/raliclo/csv2/develop/scoop/csv2.json
```

## Build and install from source

Requirements: Swift 6 with warnings treated as errors. The build uses plain
Swift source files, Foundation, and Dispatch; it does not use SwiftPM or
SwiftNIO.

```zsh
./compile_csv2.zsh
./test/test_csv2.zsh
./install.zsh
```

The build detects macOS, Linux, and Windows. It writes `release/csv2` on
POSIX systems and `release/csv2.exe` on Windows. `install.zsh` takes:

| Flag | |
|---|---|
| `--dry-run` | says what it would do and writes nothing |
| `--prefix DIR` | installs into `DIR/bin`, creating it if absent |
| `--dir DIR` | installs into `DIR` exactly, creating it if absent |
| `--no-rc` | writes no startup file — so `csv2` will NOT run by name afterwards |
| `--uninstall` | removes the binary and the block it wrote |

They compose: `--uninstall` on its own looks only in the default location and
exits 0 having removed nothing, so pair it with the same `--prefix`/`--dir` you
installed with.

**The default is Homebrew's `bin`** — the directory the paragraph above tells you
to avoid for ssh-reachable scripts. `--dry-run` prints it. Installing elsewhere
leaves any earlier binary on disk and replaces the startup block, so the old one
stays and stops being found.

**It writes `~/.zshenv`**, creating it if absent, and `--uninstall` removes its
own marked block but not that file. Exit 0 does not mean `csv2` runs by name:
under `--no-rc` it explicitly does not, which is why the installer probes and
prints what it found.

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
| `.csv2` | 2 | English and Traditional Chinese headers; RFC 4180 quoting as for `.csv` -- quoted commas and doubled quotes both work -- EXCEPT that a record is one line, so a newline inside a field is written as the escape rather than quoted, as is a carriage return |
| `.md` | recovered | A Markdown table; use `--md-table N` for a selected table |
| other (`.txt`, `.log`, …) or none | 0 | One column per line; bytes are preserved verbatim. `--json` calls this `"format":"lines"` |

Suffix matching is case-insensitive (`DATA.CSV` is a `.csv`), and when a name
has several suffixes the LAST one decides — so `data.csv.bak`, which is what
`--backup` writes, reads as line mode rather than as a CSV. The `-o` path's
suffix declares a format too, and is checked against the input's header count.
`--headers 0` on a `.csv2` leaves `"format":"csv2"` beside `"headers":0`.

**A suffix-less file has no structure to contradict, so nothing in it is
suspect.** A `#`, a JSON object, an XML declaration, a Markdown table's rows
and its `|---|` separator all come back as their own bytes -- which is what
makes a document containing a table editable line by line. A `.csv` or `.csv2`
holding a separator row **that is the line's only field** IS refused, because
there the suffix claims otherwise and a one-column file that looks like Markdown
is `-md` output under the wrong name. `|---|,2` in a two-column file is data at
exit 0 — the same one-field predicate as the `#` rule below, and the refusal
says so: "is a Markdown separator row **and has one field**".

**A blank line is a record there too**, so `-insert N ''` and `-append ''` put
a real empty line in -- prose is mostly blank lines, and a document you cannot
insert one into is not editable. A `.csv` or `.csv2` still refuses `''`,
because there the suffix has said how many fields a record has and an empty
string is not one of them.

Output record separators are always LF, and **CRLF input is normalised to LF**
on the way in — a file written on Windows reads correctly and comes back out
with LF endings, which is a change to the bytes rather than only to what is
added. `-debug` announces it (`input contained CRLF line endings; normalised to
LF`); nothing is printed on the normal path. CR and other bytes inside quoted
CSV fields remain data. UTF-8 BOMs are removed; UTF-16 input is refused with a
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

`-contains --json` emits one object per matching CELL, between the two metadata
lines. This is the whole output for a three-record file, not an excerpt — until
2026-09-07 this block showed the last line alone under a `$` prompt, with no
ellipsis, which is the likeliest thing on this page to have produced a broken
parser:

```text
$ csv2 -contains busybox --json -i test/fixtures/TARGET_PACKAGES.csv
{"meta":{"format":"csv","headers":1,"fields":7,"header":["pkg_name",…]}}
{"record":1,"field":1,"header_en":"pkg_name","value":"busybox","line":2}
…four more hit lines, values abridged here…
{"meta":{"records":21,"matched":3}}
```

The `…` are this page's, not the program's: five cells match, in three records.
Until 2026-09-07 this block showed the final line ALONE under a `$` prompt with
no ellipsis, which is the likeliest thing on this page to have produced a broken
parser.

**That record shape is not the one `-r --json` uses.** A cell hit carries
`record`, `field`, `header_en` (and `header_zh` for a `.csv2`), `value` and
`line`, and has **no `fields` object at all** — so a script written against
`.fields` gets `undefined` on every line. Under `-A`/`-B`/`-C` the shape changes
again, back to whole records with a `fields` object plus `"match": true|false`,
which is the only way to tell a hit from its context programmatically.

The trailing `records` is how far the record numbering got, and `matched` counts
matching RECORDS — five cells in three records report `matched:3`, so it is not a
count of the hit lines above it.

Available reading options:

```text
-r                 read records (the default)
-contains S        report matching cells: record:field TAB column TAB value
--filter           emit matching records instead of a locating report
--include-headers  include header rows in searches
--normalize       compare BOTH sides in NFC; can remove matches, see below
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

`-count` prints one line: the number of data records. It counts them without
checking that each has the file's field width, so it can answer confidently for
a file `-r` refuses — a ragged record at 15000 of 20000 gives `20000` at exit 0.
It does check quote termination, so a file torn mid-quote is refused. It is O(1) when a usable
`.index` sidecar is beside the file and O(n) otherwise, and it writes no
sidecar either way. A file with only a header row counts 0, which is not an
error. There is deliberately no `total` in `--json`'s meta: that number is only
known when an index is, so the field would come and go, and a caller not
finding it could not tell an empty file from a run without an index.

**`-o` must name a regular file.** `-o /dev/null` is refused, and the refusal
says why: `-o` writes a temp file beside the destination and renames it, which a
device node cannot be. To discard output, redirect `-so` instead.

**`-count` takes no companions and refuses them by name.** A companion here is
anything that would change WHAT is produced — a verb, an output shape, a
destination, a search. Flags that only change how the same count is arrived at
or reported — `--no-index`, `--headers`, `-debug` — are not companions and still
work. It is a whole-file
count and does nothing else, so combining it with a verb, an output shape or a
destination is refused: the refusal lists exactly the flags that were typed.
Until 2026-09-08 those flags were accepted and DISCARDED at exit 0 —
`csv2 -count -update 1:1 X -i f.csv --in-place` printed a number and left the
file byte-identical, and `-contains ZZZ -count` returned the file's total, so
"how many records mention this" got a plausible answer to a different question.
`--no-index`, `--headers` and `-debug` are not companions in this sense and
still work.

**`-mid a,b` with `a` past the last record is an error**, and the message names
the total. `b` past the last record is not: a window that starts inside the
file and asks for more than is there has an unambiguous answer, which is what
is there. The asymmetry exists because empty output cannot be told apart from
"these rows are genuinely empty" -- the same reason `-get` past the end has
always been an error.

Record numbers count data records, not physical lines.

**A header address is something csv2 PRINTS, never something you write.** The
locating report shows `0` for a `.csv` header and `0a`/`0b` for a `.csv2`'s two
rows — and no verb accepts one. `-get 0:1`, `--search-cell 0a:1` and
`--search-row 0` are all refused. To search header rows, use
`--include-headers`. Until 2026-09-07 this sentence gave the two spellings with
no such warning, sitting between `-get r:c` and `--search-cell R:C`, which are
both things that take addresses.

`-contains` searches every column;
use `--search-cell R:C`, `--search-row R`, or `--search-column C` to restrict
the search to one cell, record, or column. These scope options are mutually
exclusive with EACH OTHER and require `-contains`; each of them pairs with
`--filter`, `-A`/`-B`/`-C`, `-rownum` and `--json` — but those four are not all
compatible with EACH other: `-rownum --json` is refused, and so is `-rownum` on
a locating report. On a `.csv2` a column name
must come from the ENGLISH header row.

`--filter`, `-A`/`-B`/`-C` and `--normalize` also require `-contains`, and say
so when they are given without it. **A search that matches nothing still exits
0**, so `if csv2 -contains X …; then` is true on every file — which is not how
`grep` behaves.

The locating report is `record:field`, TAB, column name, TAB, value. In the
value a TAB is written `\t`, a newline `\n` and a backslash `\\`, so one line
always describes one cell and the separator can never appear inside one.
`--a1` adds the spreadsheet cell to the address: `2:2 [B3]`. Its ROW is the
header rows plus the record number — not the physical line — so a value holding a
quoted newline shifts the two apart. It requires `-contains` and is refused with
`--filter`, `-md` and `--json`. A1 is printed, never accepted: `-get C3` is
refused like a header address.

`-rownum` prepends a record-number column to RECORDS. On a locating report it
is INERT — accepted and ignored — because the report's address already carries
the record number and `-rownum` is output-side only: it must never shift what an
address means. Under `--json` it is refused instead, because there it would not
merely be inert: `--json` names fields rather than numbering them, so the column
would have nowhere to go.

The report's column-name field follows `--en`/`--zh` and defaults to English,
including for a hit whose value came from a `.csv2`'s Chinese header row.

`-A`/`-B`/`-C` do not add to that report — they REPLACE it with whole records,
and put a `--` line between groups that are not adjacent. Groups that overlap
merge into one and get no separator.

`--normalize` normalises BOTH the needle and the stored text to NFC before
comparing, and it can make a match DISAPPEAR: in a file holding `Jos` followed
by a combining acute, `-contains Jos` matches the raw bytes and does not match
after NFC, because composing the accent replaces the `s` with `ś`. It never
changes what is stored. Column names cannot contain `:` because
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

The meta line's `fields` is the width of the HEADER: 3 for a three-column CSV,
and **0 whenever there is no header row** — a `.lines` file, or any file read
with `--headers 0`. `0` does not mean the width is unfixed: a `.csv` read with
`--headers 0` still pins it to record 1 and still refuses a ragged file. Use it
to size rows only when it is non-zero. Until 2026-09-07 this said 0 meant "not
fixed", which is false on exactly the run that reports it.

`--json-ascii` escapes non-ASCII characters, **and that is a framing guarantee,
not a cosmetic one.** Plain `--json` emits U+0085, U+2028 and U+2029 as their
own bytes. That is legal JSON and legal JSON Lines — the record separator is
`\n`, and `jq` or `while IFS= read -r` are unaffected — but a consumer that
splits on Unicode line boundaries, which is what Python's `str.splitlines()`
does, sees a record break in the middle of a string and gets unparseable
fragments. `--json-ascii` escapes all three and costs nothing.

`-md` and `--json` are mutually exclusive and say so; there is no single run
that emits both.

**`meta.format` is `csv`, `csv2` or `lines`, and a Markdown table reports
`csv`.** A `.md` input is translated to CSV before any reader sees it, so a
consumer cannot tell a Markdown table from a CSV by this field; use the path if
you need to know.

**`meta.records` is how far the record numbering got, which equals the file's
total for every verb except `-head` and `-mid a,b`**, where the reader stops
early. It is not a record count, and there is deliberately no `total` — see
`-count`.

**A zero-record read is two metadata lines and nothing between them.** A
header-only `.csv`, or an empty file read as `.lines`, produces exactly that. A
consumer that slices "lines 2 to n-1" — which the framing above invites —
selects the closing metadata line on such a file and fails on it. Select
structurally instead: a record line is the one WITHOUT a `meta` key.

**`-t` is accepted and has no effect under `--json`**: the header is already in
the meta line, so there is nothing for it to add. It is inert rather than
refused, unlike `-rownum`, which would have to invent a key.

**Under `--filter`, `--json` emits the record shape** — `record`, `line`,
`fields` — the same as `-r`, with no field naming which cell matched. The
locating report is where that lives.

**`--include-headers` adds a sixth key and two zeroes.** A hit in a header row
emits `record: 0`, an extra `header_row` of `"0"` (or `"0a"`/`"0b"` for a
`.csv2`), and does NOT increment `matched`, which counts data records. So a
script gated on `matched > 0` reports "no match" while a hit line is sitting in
the stream, and `.record` fed back to `-get` is refused, because no verb accepts
a header address.

**A consumer that stops early gets exit 141, not 1 — once the output is large
enough to block.** `csv2 -r --json -i big.csv | head -1` leaves csv2 killed by
SIGPIPE with stderr empty, distinguishable from a failure, which is 1 with an
error object. On a file small enough that everything fits in the pipe buffer,
csv2 finishes before `head` closes and the status is 0. So handle 0 and 141 as
"the consumer stopped early" and 1 as failure; do not treat 141 as guaranteed.
Until 2026-09-08 this said it unconditionally, which is false on a three-record
fixture — the size of file anyone verifies a claim on.

**Under `--json` a truncated run IS structurally detectable**, unlike the CSV
output described under Errors. A fault found part-way through leaves the record
lines already written on stdout and **no closing metadata line**. Requiring that
line is the cheapest completeness check a consumer can make, and it holds
whether or not any record lines got out: on a small file the fault is found
before the buffer flushes, so stdout is empty — which also has no closing
metadata line, and is caught by the same check.

`-md` emits Markdown and requires `-t`. `--md-style` selects the layout, and the
three names are about PADDING only — none of them changes a value:

| `--md-style` | What it does |
|---|---|
| `preserve` (default) | Keeps each untouched row's original spacing. **On CSV input there is no original spacing to keep, so this behaves exactly as `compact`** — if you are rendering a CSV into a document for a person to read, ask for `pretty`. The rows you edited are re-emitted compactly, so it means "preserve the rows you did not touch", not "preserve the source layout" |
| `compact` | `\|zstd\|1.5.6\|BSD\|` — no padding anywhere |
| `pretty` | Re-aligns every column to a common width across the whole table |

`preserve` therefore gives the smallest diff when editing a document in place,
which is what it is the default for. On a CSV input, where no original spacing
exists to keep, it behaves as `compact`.

**`--pretty` is `--md-style pretty`** — one setting with two spellings, giving
byte-identical output and sharing one bound. Until 2026-09-07 this page called
it "a different flag", which was the one sentence a reader would rely on when
choosing between them. Giving both with different values is refused rather than
resolved, because the result used to depend on which came last. Both need `-md`
and are refused without it.

Alignment is by DISPLAY width, per column: each column is as wide as the widest
of its header and its cells, with one space either side. Width is measured on
the ESCAPED text, in grapheme clusters — a CJK character counts 2, a combining
mark 0, and a ZWJ emoji sequence counts as one cluster, which is right on a
terminal that renders the sequence and two columns narrow on one that does not.
For a `.csv2` the header measured is the literal `<br>`-joined string.

Holding a whole table to align it is what `CSV2_PRETTY_MAX_BYTES` bounds. Over
it, the run exits 1 with an empty stdout and a message naming both ways out.
That cap counts the DATA CELLS' escaped bytes; `CSV2_MD_MAX_BYTES` counts the
input file's raw bytes. Both read "16 MiB" in the table below and they are not
measuring the same thing.

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

`-si` reads stdin and `-so` writes stdout. Neither LOADS the whole input into
memory — until 2026-09-07 that sentence said "streams … into memory", which is a
contradiction in terms, since streaming is what you do instead of loading. When
stdin is used, `--headers` is required, because stdin has no extension to
declare a format with.

For a read, `-so` is the default and passing it changes nothing. For an EDIT
through a pipe it becomes one of two destinations, and one of them is required —
`-o FILE` or `-so`, with `--in-place` unavailable because there is no named file
to write back to:

```sh
csv2 -update 1:1 'X' -si --headers 1 -so < data.csv
```

`-count` and `--in-place` refuse stdin outright and say so, naming `-i FILE`.

Reading from a pipe is always single-threaded, so `-contains` never takes the
parallel path there whatever the thresholds allow, and `-debug` reports
`file_bytes=0` — which makes the `read_bytes` against `file_bytes` comparison
described under Indexes meaningless on a pipe. That comparison was written here
on 2026-09-07 without the condition that made it true.

**`--headers 0` reads the input line by line** — one field per line, bytes
verbatim. That is the format a file with no `.csv`/`.csv2` suffix already has,
and until now it could only be had by *having no suffix*, so neither stdin nor
a prose `.md` could ask for it. What a declaring suffix refuses is DISAGREEMENT: `--headers 1`
on a `.csv2` and `--headers 2` on a `.csv` are both errors, while a `--headers`
that agrees with the suffix is accepted and does nothing.

**`--headers 0` is accepted on every suffix**, and what it then means depends on
the suffix, which is the part worth reading twice:

| Input | `--headers 0` gives |
|---|---|
| no suffix, or `.txt`, `.log`, … | one field per line, bytes verbatim — line mode |
| `.md` | the same: prose, editable and writable back as prose |
| `.csv`, `.csv2` | headerless CSV — **still split on commas**, with the field count pinned by record 1 |
| stdin | line mode; `--headers` is required there because there is no suffix |

So on a `.csv` it removes the header row and nothing else. A ragged file read
that way is still refused, naming record 1 rather than a header that does not
exist.

Two sentences here were false until 2026-09-07, four lines apart and
contradicting each other: that `0` is refused whatever the suffix says, and that
it is the one value a suffix cannot override. A correction on that date fixed
the `--headers 1|2` claim in this same paragraph and left both standing. A `.md` read this way is
prose, and can be edited and written back as prose — for documents that merely
CONTAIN a table rather than being one.

## Errors

Errors are written to stderr as an English line followed by a Traditional
Chinese line — always exactly two, or exactly one JSON object under `--json`.
Every failure exits 1.

**stdout is NOT empty when a fault is found part-way through a file, and you
have to check the exit status.** csv2 streams, and a tool that streams cannot
also promise nothing reached stdout before it stopped: a 537 KB file with a bad
record at 20001 wrote 19,126 good records and then failed, and that truncated
output reads back as a perfectly valid CSV of 19,125 records with no marker of
any kind. `csv2 -r -i data.csv > out.csv` without testing `$?` is how you get a
silently shortened file.

Until 2026-09-07 this section said stdout remains empty "so failures can be
handled safely in a pipeline", which contradicted the streaming guarantee four
sections away. The promise was the false one.

**csv2 stops at the FIRST fault.** A file with two bad records reports the
first and says nothing about the second, so cleaning a colleague's file is one
round trip per fault. There is no mode that lists them all: reporting a second
fault would mean deciding what the first one meant, and a wrong guess there is
how a repair tool corrupts a file. Expect to iterate.

Errors found BEFORE reading starts — an unusable flag combination, a missing
file, a suffix conflict — do leave stdout empty, and they are most of them.

Under `--json` a refusal is one object on stderr with `code`, `message` and
`message_zh`. **The set of codes is not closed — give your consumer a default
branch.** These are the ones observed:

| `code` | Raised by |
|---|---|
| `not-found` | the input, output or key file could not be opened |
| `unknown-flag` | a flag this version does not recognise |
| `ambiguous-match` | two columns share a name, so an address cannot be resolved |
| `invalid-input` | a value or address the file cannot satisfy, and some flag conflicts |
| `conflicting-options` | other flag conflicts |

Until 2026-09-08 this said "there are three codes", listing the first, fourth
and fifth, one sentence before promising that `code` values are stable across
versions — which is what makes a closed list load-bearing. A three-way switch
with `default: unknown` falls through on any file with duplicate column names.
The count was wrong rather than the codes; each individual entry has held.

The removed sentence is described here rather than quoted: reproducing a
withdrawn promise verbatim leaves it on the page for anyone skimming, and the
case that pins its removal then catches itself on the quotation — which is how
the first version of T295a failed. The Chinese page kept that promise one round
longer than this one, which is PR.

The split between `invalid-input` and `conflicting-options` follows where the
check happens rather than a rule you can predict — `--physical --json` reports
`invalid-input` while `-md --json` reports `conflicting-options`, and both are
flag conflicts. Branch on the exit status, or treat those two codes as one
class.

`-get` refuses `--json` as well, and that refusal REPLACES the error you were
about to get, so an out-of-range record under `-get --json` is reported as the
flag conflict rather than as the range.

**A failed edit leaves the input byte-identical.** `--in-place` writes a private
temporary file and renames it, so there is no state in which the input is half
written; `-append --in-place` is the documented exception, appending directly.
That guarantee was previously only inferable from the exception.

```text
csv2: vs-sqlite.csv2 declares 2 header row(s) by its suffix, but --headers says 1. The suffix declares the format; --headers is for input with no suffix to declare it. Drop --headers to read the file as it is. Renaming it instead makes the suffix agree with --headers, which is NOT the same thing: a header row then becomes data record 1, at rc=0, and nothing afterwards can tell it was one
csv2：vs-sqlite.csv2 的副檔名宣告了 2 列標頭，但 --headers 說 1 列。副檔名宣告格式，--headers 是給「沒有副檔名可宣告」的輸入用的。請拿掉 --headers，照這個檔案原本的樣子讀它。改檔名是讓副檔名去遷就 --headers，那不是同一件事：一列標頭會因此變成第 1 筆資料，rc=0，而事後沒有任何東西看得出它曾經是標頭
```

**A `#` line is data, not a comment.** CSV has no comment syntax, and a
column named `#id` is legal, so skipping such a line would mean guessing which
lines are data. **The trigger is the field count, and the `#` only chooses the
message.** A line holding exactly ONE field, anywhere in the file, is refused by
naming the `#` rather than by counting fields, because for that line the count
is two steps from the cause; a `#` in the MIDDLE gets that message too, naming
the record and the line. A `#` line with the file's own field count is DATA:
`#comment,x` in a two-column file is record content at exit 0, and `#x,y,z` in a
two-column file is an ordinary field-count error that never mentions the `#`. A
header starting with `#` is a legal column name — which is what makes `#id`
legal, two sentences above.

Two earlier versions of this paragraph were wrong in opposite directions. It
said "at the top" until 2026-09-08, inviting the reader to assume a mid-file `#`
was fine; the correction said it "fires wherever the line is", which claims more
than the program keeps. The test written with that correction passed because its
fixture happened to be a one-field line — a case that agreed with the code and
not with the sentence it was there to defend.
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
`-add-column`, plus content-anchored `-update-where`. Several may be given in
one invocation. All RECORD NUMBERS refer to the original input and every edit is
applied in one pass — so `-insert 2 'NEW' -delete 4` deletes the record that was
4th before the insert, not the one that is 4th after it. (This sentence said
"all indexes" until 2026-09-07, in a page where "index" otherwise means the
`.index` sidecar.)

**`-delete a,b` deletes an inclusive RANGE**, the same reading as `-mid a,b`. To
remove records that are not adjacent, repeat the flag:

```sh
csv2 -delete 2,4 -i data.csv --in-place        # deletes 2, 3 AND 4
csv2 -delete 2 -delete 4 -i data.csv --in-place # deletes 2 and 4, keeping 3
```

Both forms exit 0 and print nothing, so the wrong one costs a record with no
sign that anything unintended happened. Until 2026-09-07 only `-delete 4`
appeared here, which left a reader with two records to remove choosing blind.

`-insert N` makes the new record number N; the record previously at N and
everything after it shift down. It cannot address one past the end — use
`-append` for that.

`-delete -cell` clears a field without changing the field count.
`-delete -col` removes a column from every record and every header row.
`-add-column N NAME VALUE` makes the new column number N — the column
previously at N and everything after it shift right — and writes VALUE into that
cell of every existing record. On a `.csv` NAME is one title; on a `.csv2` it is
both, comma-separated, and omitting the Traditional Chinese half leaves that
header cell empty and emits a warning. NAME is always split on commas, so a
title that contains one cannot be expressed.

**N may be one past the last column, and that appends.** On a two-column file
`-add-column 3` is valid and puts the new column at the end; `-add-column 4` is
refused, and the refusal states the rule — "this file has 2 columns, so the
highest position is 3, which appends". This is the opposite of `-insert`, which
refuses one-past-the-end and sends you to `-append`, so the inference from the
neighbouring verb is exactly wrong.

**Two `-insert`s at the same N resolve in the order they were given**, so
`-insert 1 A -insert 1 B` puts A first and B second. Nothing is dropped and
nothing is refused; a script assembling a command line from parts gets a defined
answer rather than a surprise.

`-delete -col` may be repeated to remove several columns in one run.

**A column may be addressed by NAME anywhere a number is accepted** — `-update
1:license`, `-delete -cell 1:license`, `-delete -col license`. Names and numbers
both refer to the column as it is in the INPUT, so an address stays correct
alongside `-delete -col` or `-add-column` in the same run. Until 2026-09-07 it
did not: an address was resolved against the header AFTER the structural edit
and applied to a record before it, which wrote to a neighbouring column at exit
0 with nothing on either stream.

`--in-place` writes through a private temporary file and rename, except for
`-append`, which uses an append-only fast path. `-append` validates the input
before writing and writes only the appended bytes, while still reading the
existing file to validate it — the WHOLE file, not just its final record: appending to a file with a fault at record 5000 of 8000 is refused, naming 5000. Concurrent appends are serialized
by the operating system for complete writes, but general concurrent edits are
not supported.

`-append --in-place` does not use a temporary file and does not rename the
result. It opens the existing file for append and writes directly to it. If the
process is interrupted after the write begins, the file may contain a partial
record; the all-or-nothing preservation guarantee for ordinary in-place edits
does not apply to this append-only path.

`--truncate-partial` discards a trailing incomplete record — which means one
specific thing: the file ends INSIDE an unclosed quote. A file whose last line
merely has too few fields is a different fault and is refused, not truncated. It
works on a plain read as well as a rewrite, which is what you want when holding
a torn file, and is refused with `-append`, which cannot remove existing bytes.
When it discards, it says so on stderr AT EXIT 0:

```text
csv2: --truncate-partial discarded 12 bytes: an unterminated record beginning at byte 4
```

**stderr is not always empty on a successful run.** Warnings are one line,
English only, and do not change the exit status; `-add-column` without its
Traditional Chinese title emits one too. That is the whole list.

`-update-where OLD VALUE` requires exactly one data cell to equal `OLD` in
full. Zero matches, multiple matches, or overlapping repeated updates are
refused before output is written. It is a whole-cell update, not substring
replacement.

`--value-file PATH` and `--value-stdin` supply the `-update` value as exact
bytes, including trailing newlines and whitespace.

**They exist because a command-line argument cannot carry every byte.** An
argument is a NUL-terminated string, so a value containing a NUL is cut there
before csv2 ever sees it — silently, at exit 0 — and a literal that is not valid
UTF-8 is refused outright. Neither limit applies to these two flags, and that is
the whole reason to reach for them:

```sh
printf 'before\0after' > value.bin
csv2 -update 1:3 --value-file value.bin -i data.csv --in-place
printf 'from a pipe' | csv2 -update 1:3 --value-stdin -i data.csv --in-place
```

Under either flag, `-update` takes the ADDRESS only — the value slot is gone.
They require exactly one `-update` (`-update-where` does not count), cannot be
repeated, are mutually exclusive with each other, and cannot be combined with a
literal value or with `-si`. `--value-file -` is not stdin; it is a file named
`-`. An empty regular file is accepted and blanks the cell at exit 0; a
directory, a device such as `/dev/null`, and a missing path are each refused
with the path and the reason named.

`--in-place` works with `--value-stdin` — the "refuses stdin" rule elsewhere on
this page is about `-si`, the INPUT, not about where a value comes from.

**Reading the bytes back.** `-get r:c` writes the stored bytes and exactly one
LF terminator, so a round-trip check is `cmp <(csv2 -get 1:3 -i f.csv) <(cat
value.bin; printf '\n')`. The locating report cannot print bytes that are not
UTF-8 and renders such a cell as `<non-UTF-8: 58 ff 59>`, and `--json` refuses
the file entirely with `invalid-input` rather than substituting U+FFFD. So a
column holding arbitrary bytes is readable with `-get` and not with `--json`.

`--dry-run` currently previews `-update` and `-update-where`, printing each
changed cell as `old -> new`, and writes no DATA file. It is not silent on disk
if you also passed `-log`: the preview is appended there, including the new
value, followed by a line reading `dry run: N change(s), wrote nothing`. That
line is true of the data file and false of the file it is written in. Until
2026-09-07 this page said "writes nothing" without qualification.

Other edit verbs are refused rather than returning empty output that could be
mistaken for “no changes”. `--backup` with `--in-place` saves the original
beside the input as `INPUT.bak` and refuses to overwrite an existing backup — so
it works once per path, and a second backed-up edit needs the `.bak` moved
aside first. A FAILED edit removes the backup it had just taken, since the
input is unchanged and a leftover `.bak` would block every later use; before
2026-09-08 one failure burned that single use permanently.

**An edit cannot take `--json` at all**, so you cannot get an edit's OWN error
as a JSON object: adding `--json` to an edit replaces whatever would have been
reported with `conflicting-options`, a refusal about the flags rather than about
the edit. What you do get is still one parseable object on stderr with `code`,
`message` and `message_zh`, exit status 1 — `csv2 -update 1:license X --json -i
f.csv --in-place` emits exactly that. So a consumer can parse every refusal this
tool produces; what it cannot do is learn from JSON why the EDIT would have
failed, because the run never reached the edit.

Until 2026-09-07 this paragraph promised the edit's own error here. The 09-07
correction over-shot: it said an edit's refusal is "never a JSON error object"
and the table below said it is "available only as text on stderr", which told a
script author not to parse at all and cost them a working code path.

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

**What an encrypted column still leaks.** Ciphertext is the plaintext's length
plus 28 bytes with no padding, and it is stored **base64**, so a cell holds
`4 * ceil((len + 28) / 3)` characters. Length is therefore visible in steps of
three: plaintexts of 0, 1 and 2 bytes all store as 40 characters, so an empty
cell is NOT distinguishable from a one- or two-byte one, and 3 and 4 bytes both
store as 44. Until 2026-09-08 this paragraph said an empty cell WAS
distinguishable — it erred conservatively, claiming more leakage than exists,
but a reader padding values to hide an empty cell was acting on a false
statement and a reader sizing a column could not compute the stored width at
all, because base64 appeared nowhere on this page.

The column's own name, every other column, the record count and the row order
are all in the clear. What does NOT leak is equality: two records
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
$ csv2 -mid 500,500 -debug -i data.csv 2>&1 >/dev/null
csv2: 2026-09-08T01:17:16.211+08:00 DEBUG index hit: record 500 via grid point 257 at byte 6297
csv2: 2026-09-08T01:17:16.212+08:00 DEBUG metrics: read_bytes=65536 file_bytes=76898 peak_rss_bytes=9404416
```

Every `-debug` line is prefixed, timestamped and levelled, and goes to stderr.
Until 2026-09-08 this block showed the messages bare, which was a transcript
that never happened — the same fault as the `-contains --json` example corrected
on 2026-09-07, and it survived because the case pinning it matched a substring.

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

`-contains` can use parallel search, and **only** `-contains` — a plain read is
never parallel, whatever the file's size. Output is byte-identical to the
single-threaded path. Until 2026-09-08 the two rows above were labelled "Full
read", which invited a reader to expect that speedup from `-r`; they measure a
search that scans the whole file.

Everything below has to hold for the parallel path to run, and `-debug` names
the first one that does not:

| Requirement | Note |
|---|---|
| the verb is `-contains` | and not `--filter`, `-A`/`-B`/`-C`, or a `--search-*` scope — each of those forces one thread |
| a named file, not stdin | the file has to be seekable |
| `.csv` or `.csv2` | a suffix-less file and a `.md` are excluded; forcing them was a crash until 2026-09-08 |
| a `.csv` needs an `.index` | one record per line has to be PROVEN, and only a built index proves it — so `--no-index` also turns parallelism off on a `.csv` |
| at least `CSV2_PARALLEL_MIN_BYTES` | inclusive at the boundary |
| more than one core | |

```text
$ csv2 -contains x -debug -i data.csv 2>&1 >/dev/null | grep single-threaded
csv2: 2026-09-08T02:00:12.643+08:00 DEBUG single-threaded: .csv with no index proving one record per line; build one with --build-index
```

`CSV2_PARALLEL_MAX_BYTES` bounds how much is held in flight at once; it is in
the table below.

Environment variables used for controlled testing and tuning:

| Variable | Default | Purpose |
|---|---:|---|
| `CSV2_INDEX_MIN_BYTES` | 16 MiB | minimum file size for AUTOMATIC sidecar creation; `--build-index` ignores it |
| `CSV2_PARALLEL_MIN_BYTES` | 16 MiB | minimum size for parallel search |
| `CSV2_PARALLEL_CHUNK_BYTES` | 4 MiB | search chunk size |
| `CSV2_PARALLEL_MAX_BYTES` | 1 GiB | how much of the file the parallel search holds in flight at once |
| `CSV2_PRETTY_MAX_BYTES` | 16 MiB | the DATA CELLS' escaped bytes that `--pretty` may hold |
| `CSV2_MD_MAX_BYTES` | 16 MiB | the Markdown input FILE's raw bytes |
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

All four columns were measured on 2026-09-08 with the same binary. Each figure
is one `measure.zsh` run, which is itself best-of-N per row, and each column is
the file named beside it — `measure_output.txt`,
`measure_output_macos_ssd.txt`, `measure_output_windows.txt`,
`measure_output_linux.txt`. The two macOS columns were interleaved rather than
run back to back.

| Measurement | macOS arm64<br>sparse image | macOS arm64<br>local SSD | Windows x86_64 | Linux aarch64 guest |
|---|---:|---:|---:|---:|
| Whole-file search, single-threaded | 551,000 µs | 546,000 µs | 1,806,000 µs | 62,000 µs |
| Whole-file search, parallel | 213,000 µs | 201,000 µs | 774,000 µs | 71,000 µs |
| Small durable edit | 37,300 µs | 7,800 µs | 66,300 µs | 9,000 µs |
| Full-file rewrite | 1,232,000 µs | 601,000 µs | 1,887,000 µs | 150,000 µs |

**The two macOS columns are the same machine, the same binary and the same
minute.** Only the filesystem holding the corpus differs. The two read rows do
not notice it — 1% — and the two write rows differ by 4.8× and 2.0×. Until
2026-09-08 this table had one macOS column and never said where the corpus was,
which made a storage effect look like a property of csv2.

**The write rows move between runs; the read rows do not.** Across six
interleaved runs the sparse image gave 35,800–44,100 µs for the small edit and
1,201,000–1,322,000 µs for the rewrite, the SSD 5,800–7,800 µs and
601,000–619,000 µs. Both read rows stayed inside 2%. A single write figure from
either medium is worth about as much as its range says it is.

**The guest's parallel row is SLOWER than its single-threaded row, and that is
the real result.** On a 2.48 MiB corpus the boundary-finding pass and the worker
handoff cost more than four workers save: the harness reports `speedup 0.88x on
4 workers`. It is a genuine parallel run — the harness now refuses to report a
row that did not take the path the row is named after — and it is the honest
answer to "should I parallelise a small file".

The source measurements are kept in `verifications/measure_output*.txt` and
are produced by `verifications/measure.zsh` using best-of-N timings.
`RECORDS=20000 ./verifications/measure.zsh` measures a smaller corpus, which is
how a like-for-like comparison against the guest column is made; the script
takes no positional argument and ignores one silently. It also sets
`CSV2_PARALLEL_MIN_BYTES` itself on each row, to force the path that row is
about, so exporting that variable before running it has no effect.

**Where the corpus lives changes these numbers more than anything else on this
page.** The harness builds it inside its own directory, so a checkout on a
sparse image measures that sparse image.

### Parallel-search throughput and RSS

The parallel-search measurement uses the same 10,000,000 data records in a
1,307,777,815-byte `.csv` file and a 1,307,777,833-byte `.csv2` file. Every
record matches `needle`. Measured 2026-09-08 on macOS arm64 (sparse image), 10
workers, 4 MiB chunks, best of three interleaved rounds; elapsed and peak RSS
are taken from the same run.

**A `.csv` needs an `.index` to be searched in parallel at all**, so the `.csv`
rows below have one. The last row is the same file without it, and it is there
because it is both the most useful tuning fact here and the evidence for what
this table used to be.

| Format | Index | `CSV2_PARALLEL_MAX_BYTES` | Elapsed | Throughput | Peak RSS |
|---|---|---:|---:|---:|---:|
| `.csv` | yes | default 1 GiB | 9.636 s | 129.4 MiB/s | 52.05 MiB |
| `.csv2` | not needed | default 1 GiB | 36.980 s | 33.7 MiB/s | 52.19 MiB |
| `.csv` | yes | 8 MiB | 34.259 s | 36.4 MiB/s | 51.56 MiB |
| `.csv2` | not needed | 8 MiB | 38.166 s | 32.7 MiB/s | 49.03 MiB |
| `.csv` | **none — single-threaded** | — | 31.150 s | 40.0 MiB/s | **9.44 MiB** |

**Until 2026-09-08 the two `.csv` rows of this table were that last row.** The
harness never built the index, and setting `CSV2_PARALLEL_MIN_BYTES=1` did not
help because the obstacle was never the size threshold. The published figures
were 34.886 s at 9.28 MiB — which is, to within noise, the single-threaded row
above. A table headed "parallel" was reporting the scan path's time and the scan
path's memory for half its rows, and the `CSV2_PARALLEL_MAX_BYTES` column, whose
whole purpose is to show what that knob costs, was measured where the knob
cannot do anything: there are no chunks in flight on the single-threaded path.
Anyone who sized a container from 9.28 MiB was sizing it for a scan.

Two things the corrected table says that the old one could not:

- **Build the index.** 31.150 s to 9.636 s on the same file, same search.
- **The cap costs time here and saves no memory.** 9.636 s to 34.259 s, and peak
  RSS barely moves. With every record matching, the peak is dominated by the
  output side rather than by chunks in flight, so capping the chunks throttles
  the search without touching what is actually large. On a corpus where few
  records match, the same knob is what keeps memory bounded — which is why this
  is a measurement of one workload and not a rule.

This is a measurement, not a performance guarantee; compare only runs with
the same binary, record count, host, storage and search conditions. It is
produced by `verifications/measure_parallel_rss.zsh` — a separate script from
the one above, and NOT covered by the `measure_output*.txt` glob — and the raw
output is
[`verifications/measure_parallel_rss_output.txt`](verifications/measure_parallel_rss_output.txt).

Throughput here is dominated by OUTPUT, not by input bytes: every record matches
and every match is a line written. That is why this table's MiB/s and the
`parallel` row of the previous section disagree by a factor of three on the same
host and binary — they are measuring different bottlenecks, and neither is
"the speed of csv2".

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
| column projection (`-cols`) | `csv2 -r --json -i f.csv \| jq -r 'select(.record) \| .fields.license'`. The `select(.record)` is not optional: without it the two meta lines arrive as `null`s in your column. Or `-get` per cell, with `csv2 -count -i f.csv` for the loop's upper bound. Both go through `--json`, which REFUSES a file holding non-UTF-8 bytes that `-get` reads fine |
| an exact whole-cell search | `-contains` is a SUBSTRING match, so `-contains MIT --search-column license` also finds `MIT-0` and `NON-MIT` — scoping the column does not make the match exact. `-update-where` IS exact ("no data cell equals"), so both semantics exist and only one of them searches. For an exact count: `csv2 -r --json -i f.csv \| jq -r 'select(.record) \| select(.fields.license == "MIT") \| .record' \| wc -l` |
| case-insensitive matching | nothing does — `-contains mit` finds no `MIT`, **and prints nothing at exit 0**, which is indistinguishable from "no such data". Fold the case yourself: `csv2 -r --json -i f.csv \| jq -r 'select(.record) as $r \| $r.fields\|to_entries[] \| select(.value\|ascii_downcase\|contains("mit")) \| "\\($r.record)\\t\\(.key)\\t\\(.value)"'` |
| a search that ignores which column it is in | `-contains` matches a substring in EVERY column, so `-contains MIT` also finds `transMITter` — see the last example below. Use `--search-column license` to scope it, or `--search-row`/`--search-cell`. Until 2026-09-07 this row said scoping was not offered at all, and warned that counting would be "silently wrong", 260 lines below the section documenting the flag that fixes it |
| skipping `#` comment lines | nothing does, and deliberately: a `#` is data and `#id` is a legal column name, so skipping one would mean guessing which lines are data. The refusal names the `#` on any ONE-FIELD line, wherever it is — but the trigger is the field count, so `#comment,x` in a two-column file is data at exit 0. Read the file under a suffix-less name to get every line verbatim |
| a header-only read | `csv2 -head 1 --json -i f.csv \| head -1 \| jq -r '.meta.header[]'` — the meta line carries `header`; no verb returns the names alone. On a `.lines` input there is no `header` key at all |
| converting between `.csv` and `.csv2` | refused on purpose. To do it by hand, `.csv` → `.csv2`: `csv2 -r -t -i p.csv -o work` (the `-t` is required — without it the header row is dropped silently), then `csv2 -insert 2 '套件,版本,授權' -i work --in-place`, then **rename it**: `mv work out.csv2`. The rename is the step that converts; reading the suffix-less path back gives you `.lines`, which is what it already was. Reverse: `csv2 -r -t -i p.csv2 -o work`, `csv2 -delete 2 -i work --in-place`, `mv work out.csv`. csv2 will not invent a header row it was not given |
| safe concurrent writers, EXCEPT append against append | serialise them yourself; two writers silently lose one edit — the file stays VALID, and the surviving version is whichever run renamed its temp file last, so the loss is a missing edit rather than damage you would notice. Two concurrent `-append --in-place` runs are the exception: both records land whole, and the one finishing SECOND warns it could not update the index |

One thing this table used to say and no longer does: **editing a Markdown
table** is supported, and it is in the examples below.

It also used to say that **telling refusals apart programmatically** is done
with the `--json` error object, and that row was removed on 2026-09-07 on the
grounds that an edit's refusal is "available only as text on stderr". That
reason was wrong: an edit given `--json` emits one parseable object with
`conflicting-options`. Every refusal this tool produces is machine-readable.
What an edit cannot give you is the edit's OWN error as JSON, because `--json`
is refused before the edit runs — a narrower and much less alarming fact than
the row's removal implied.

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

# csv2

A CSV parser and editor for the command line, written in Swift, targeting the
aarch64 Linux guest of the [LinuxCS](https://github.com/raliclo/LinuxCS) project
and the macOS host it is built from.

繁體中文說明見 [README.zh-TW.md](./README.zh-TW.md)。

## Status

**Phases 1–6 are implemented and pass their tests. Phase 7 (shipping) is a deliberate deferral.**

```zsh
./compile_csv2.zsh       # build release/csv2
./test/test_csv2.zsh    # 0 FAIL. The one SKIP is T47, which compares two
                        # platforms and so runs from the parent project.
```

| Works | Does not yet |
|---|---|
| RFC 4180 parsing, quotes, embedded commas and newlines, CRLF, BOM | shipping in the rootfs (phase 7) |
| `-r`, `-contains`, `-A`/`-B`/`-C`, `-head`/`-tail`/`-mid`, `-rownum` | |
| two-row `.csv2` headers, `--json`, `-md`, `--pretty` (display widths) | |
| `-insert`/`-append`/`-delete`/`-update`, `-delete -cell`, `-delete -col` | |
| `-hash`, `-encrypt`, `-decrypt`, `-keyfile`, `-debug`, `-log` | |
| the `-append` O(1) fast path | |
| `.csv.index` / `.csv2.index` sidecars, `--verify-index` | |
| parallel search, byte-identical to the single-threaded run | |
| builds and runs on aarch64 Linux, byte-identical to macOS | |
| builds and passes on x86_64 Linux (WSL2) and on Windows (MSVC) | |

`install.zsh` puts the binary where each platform's shell actually looks:
`$(brew --prefix)/bin` where Homebrew is present, `~/.local/bin` as the
user-level fallback, and on Windows `%LOCALAPPDATA%\csv2\csv2.exe` — the path
scoop's shim already names, so the shell resolves to the new build without this
script writing into scoop's own directory. **Check which csv2 you got by
comparing the file, not the version**: two builds both say `csv2 0.1.0`, so
`csv2 --version` cannot tell them apart.

Progress is tracked as checkboxes at the end of [plan/plan.md](./plan/plan.md),
and a box is only ticked once the matching case in
[test/test_csv2.zsh](./test/test_csv2.zsh) passes. Cases the tool cannot yet
satisfy are reported as SKIP with the reason rather than quietly left out.

**Designed but not built: `csv2view`, a native SwiftUI viewer.** Nothing below
describes it, because none of it exists yet — the design lives in
[plan/plan.md](./plan/plan.md) and names the three things csv2 has to gain
first: a `-count` verb, an error instead of empty output when `-mid`'s START
record is past the end, and line numbers in the index so a file with a quoted
newline can still be seeked into. A measured 5.6 ms per 40-record window on a
19.5 MB file is why the viewer will call this binary rather than embed a copy
of its parser. **Do not write a script against any of that; it is a plan, not
an interface.**

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

**`--headers 1|2` is required for `-si`**, where stdin has no suffix to declare
the format. With `-i` it is accepted only when it **agrees** with the suffix;
disagreeing is refused:

```console
$ csv2 -r --headers 1 -i vs-sqlite.csv2
csv2: vs-sqlite.csv2 declares 2 header row(s) by its suffix, but --headers says 1. The suffix declares the format; --headers is for input with no suffix to declare it. Rename the file or drop --headers.
csv2：vs-sqlite.csv2 的副檔名宣告了 2 列標頭，但 --headers 說 1 列。副檔名宣告格式，--headers 是給「沒有副檔名可宣告」的輸入用的。請改檔名，或拿掉 --headers。
$ echo $?
1
```

The suffix is the declaration; `--headers` exists only for input that has no
suffix to declare anything. Why it is checked rather than trusted is in
[todo/known-defects.md](todo/known-defects.md).

For the same reason csv2 will not convert between the two formats: writing a
one-header-row input to a `.csv2` path is refused rather than silently losing a
record to the missing second header row (T56d).

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
  -get r:c              print ONE cell's value, raw -- the read that matches
                        -update r:c VAL. This is the verb to build scripts on:
                        what composes is the ADDRESS, and this is how a value
                        crosses from a report to an edit
  -contains S           report every CELL containing S, as record:field
  --filter              with -contains, emit the matching records instead
  --include-headers     search the header rows too (reported as record 0a / 0b)
  --normalize           compare in NFC; what is stored is never normalised
  -A N  -B N  -C N      context in RECORDS, as in grep; blocks separated by --
  -head N               first N records          (records, not lines)
  -tail N               last N records
  -mid a,b              records a through b, inclusive; `a,` and `,b` are open
  -t                    include the header rows (off by default). It applies
                        to SELECTIONS only -- an edit rewrites the whole file
                        and always writes the headers, with or without -t
  -rownum               prepend a record-number column. It does NOT renumber
                        anything: see "Two numberings" below
  --physical            also print the physical line the record starts on, as
                        `record:field@Lline`; with --a1 the two combine into
                        `13:6@L14 [F14]`.
                        Adds to the LOCATING REPORT, so it needs -contains
                        without --filter/-md/--json
  --a1                  also print spreadsheet A1 notation. Same restriction
                        as --physical, and it counts the header rows: data
                        record 1 is A2 in a .csv and A3 in a .csv2

INPUT / OUTPUT
  -i FILE  -o FILE      file paths; -o writes a temp file and renames
  -si  -so              stdin / stdout, without buffering the whole file
  --headers 1|2         required with -si: stdin has no extension. With -i it
                        is accepted only when it AGREES with the suffix, and
                        disagreeing is refused -- the suffix declares the
                        format. See the warning above; never combine it with
                        an edit verb
  --in-place            edit -i in place, via temp file + rename

OUTPUT SHAPE / 輸出形狀
  -md [--pretty]        Markdown table; needs -t. On a .csv2 the two header
                        rows are joined with <br> into one Markdown header
                        cell -- `pkg<br>套件` -- because Markdown has one
                        header row and the data has two; --en or --zh gives
                        one clean row instead.
                        --pretty aligns by DISPLAY width and therefore gives
                        up streaming. That width is grapheme clusters with
                        emoji presentation applied, NOT a per-code-point UAX
                        #11 lookup: the latter gets a ZWJ family, a skin-tone
                        modifier and a variation-selector emoji wrong.
                        `-debug` prints the computed column widths, so you can
                        check the alignment instead of counting it by eye
  --json                JSON Lines; --json-ascii escapes non-ASCII, including
                        characters above U+FFFF, which JSON has no single
                        \uXXXX form for and which become UTF-16 surrogate
                        pairs -- U+1F680 is written \ud83d\ude80
  --en  --zh            which header row names the columns

EDITING / 編輯
  -insert N ROW         insert as record N; ROW is ONE line of CSV text.
                        REPEATABLE, and every N refers to the INPUT: three
                        -insert flags in one run all count against the file as
                        it arrived, not as it grows. See below -- the same three
                        numbers give a different file if you run them one at a
                        time
  -append ROW           append at the end (O(1) when writing in place)
  -delete a[,b]         delete record a, or records a through b
  -delete -cell r:c     clear one cell (the field count never changes)
  -delete -col N|NAME   remove that column from every record AND from both
                        header rows -- the one deletion that keeps alignment
  -update r:c VAL       update one cell
  --truncate-partial    when READING, drop a record left unfinished at EOF by
                        an unclosed quote, instead of failing. A trailing
                        record with too few fields is a hard error either way:
                        it is complete as written and simply wrong. Refused
                        with -append, which can only add bytes

PROTECTION / 保護
  -hash COLS            mask columns, one way. Deterministic, so equal values
                        stay equal — and see the warning below
  -encrypt COLS         encrypt columns (ChaCha20-Poly1305, fresh nonce)
                        The header is ALWAYS written, with or without -t and
                        including under a selection: the key fingerprint and
                        salt live in it, the salt is new on every run, and
                        ciphertext without them can never be decrypted by
                        anyone.
  -decrypt COLS         decrypt; COLS may be `all` to take every marked column.
                        A column that is not marked encrypted is REFUSED by
                        name -- plaintext is never fed to the cipher, so you
                        get "not marked as encrypted" rather than an
                        authentication failure. `all` refuses too when nothing
                        in the file is marked. A HASHED column is not
                        encrypted and cannot be decrypted by anything:
                        hashing is one-way
  -keyfile PATH         key file; defaults to multissh's private key.
                        With -hash it selects HMAC over plain SHA-256
  --yes                 accept the default key without a prompt

COLS is a comma-separated list of column names, 1-based column numbers, or a
mix: `-hash license`, `-hash 7`, `-hash 6,license`.

INDEX / 索引
  --no-index            never read or write a .index sidecar. The sidecar is
                        the whole filename plus ".index": packages.csv ->
                        packages.csv.index, pkgs.csv2 -> pkgs.csv2.index
  --build-index         build the sidecar now. Otherwise one only appears as a
                        SIDE EFFECT: a write builds one, and -tail builds one
                        because it must read the whole file anyway -- so -mid
                        alone would never produce one
  --verify-index        O(n) full check of all three of the index's claims --
                        the grid offsets, the record count, and whether any
                        record spans lines. The O(1) check on the normal path
                        is deliberately a heuristic, not a proof

DIAGNOSTICS / 診斷
  -debug                diagnostics to stderr, including a metrics: line on
                        every path. Measure with it rather than guessing:
                        23 MB of peak RSS on a 615 MB file in parallel, 9.5 MB
                        single-threaded over the same file. Until 2026-08-20
                        the parallel figure was 608 MB -- one byte resident per
                        byte of input. See the parallelism section
  -debug=trace          one level lower: every record's selection decision,
                        including the ones NOT emitted and why, and the point
                        at which the read stops -- so a record with no line is
                        a record that was never reached, and says so
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
with `…[+N more chars]`, and **csv2 is what cuts them**: the report is one line
per hit, so a 400-byte cell would otherwise carry the format away with it. The
cut is marked, never silent. It means the third column is a PREVIEW — `-get`
returns the whole value, and `--json` carries it in full.

Three fields separated by a **TAB**: the address, the column name, the value.
One line per matching **cell**, so two matching columns in one record print two
lines, while the same string twice inside one cell prints one. In a script,
`cut -f1`, `cut -f2`, `cut -f3`.

**Values are escaped**, using the same backslash convention `.csv2` uses plus
`\t`: a literal tab becomes `\t`, a newline `\n`, a carriage return `\r`, a
backslash `\\`. Without that a cell containing a tab or a newline would break
the format the report promises — and quoted prose containing both is exactly
the data this tool was written for.

**So the third column is for reading, not for feeding back.** It is a display
form: escaped so the report stays one line per hit. `-update` takes a *logical*
value and escapes it for you, so handing it the escaped text writes the
backslashes themselves — `X⏎Y\Z` becomes the seven characters `X\nY\\Z`, at
rc=0, and nothing says so. **What composes is the ADDRESS.** To carry a value
across, read it with `-get`, which returns the stored bytes:

```sh
addr=$(csv2 -contains "old" -i f.csv2 | head -1 | cut -f1)   # 12:6
val=$(csv2 -get "$addr" -i f.csv2)                           # the value itself
csv2 -update "$addr" "$val" -i f.csv2 --in-place             # round-trips
```

Asserted by T96.

Matching is **case-sensitive** and there is no flag to change that. **The way
to fold case is `--json` and one pass of your own**, not a sweep of spellings:
enumerating `mbedtls`/`mbedTLS`/`MbedTLS`/… is 2^n runs, which is 128 at seven
letters and a million at twenty.

```sh
csv2 -r --json -i f.csv2 | python3 -c '
import json,sys
for line in sys.stdin:
    o=json.loads(line)
    if "fields" not in o: continue
    for k,v in o["fields"].items():
        if "mbedtls" in v.lower(): print(o["record"], k, v)'
```

One scan, every spelling, and the record numbers come back addressable.

**`--normalize` applies to the search string too**, not only to the cells — so
a needle typed in NFC finds a cell stored in NFD. Storage is still never
normalised; only the comparison is.
`--normalize` affects Unicode normalisation only, not case.

**`--normalize` governs cell VALUES, not column names.** A column name is
matched by canonical equivalence always: an NFC `café` typed on the command line
finds a header stored as NFD, with or without the flag, because to everyone
reading it that is the same name. A value is matched byte for byte unless you
ask otherwise, because a value is data and changing what counts as equal would
change what is in the file.

One consequence is worth stating plainly: **a name that matches more than one
column is refused, not resolved by position.** CSV does not forbid duplicate
column names and spreadsheets produce them, so `-update 1:note X` on a file with
two columns called `note` is an error naming both positions — address it by
number. Two columns differing only in Unicode form collide the same way, and
those do not look identical in a hex dump. Asserted by T75.

### `--zh` on a file with one header row

`--zh` falls back to the only header row there is, and says nothing. That is
deliberate, and it is the one silent substitution in this tool, so here is the
reasoning rather than just the behaviour.

`--zh` is a **display preference**, not a selector over data. Refusing would
break any script that walks a mix of `.csv` and `.csv2` files for a purely
cosmetic reason, forcing it to branch on format to ask for a nicety. And the
fallback cannot be mistaken for success: you asked for Chinese column names and
the output visibly contains English ones — different, not plausible-but-wrong.

**If what you actually want is to assert the file is bilingual, `--zh` is the
wrong instrument and `--json` is the right one:**

```console
$ csv2 -head 1 -t --json -i pkgs.csv | head -1
{"meta":{"format":"csv","headers":1,"fields":2}}
$ csv2 -head 1 -t --json -i pkgs.csv2 | head -1
{"meta":{"format":"csv2","headers":2,"fields":2}}
```

That first line exists precisely so a caller can assert what it is reading
instead of accepting a wrong guess. Asserted by T78.

**But be exact about which parts of it are observed.** `fields` and `records`
are counted from the file. `format` and `headers` are the *declaration* — they
restate what the name said, because that is what "declared by the suffix,
never detected" means. So `headers:2` on a `.csv2` is not evidence that a
second header row exists; it is evidence that csv2 treated the second line as
one.

**That matters for a file you did not produce.** Rename a one-header `.csv` to
`.csv2` and csv2 reads its first data record as header row `0b` — at rc=0, one
record short, and no check can catch it, because a row of titles and a row of
data are not distinguishable by shape. Nothing in the format can rescue this;
only looking can:

```console
$ csv2 -head 1 -t -i handed-to-me.csv2       # both header rows, then record 1
pkg,ver,note
zlib,1.3.2,first                             <- data, not titles: a .csv wearing the wrong name
zstd,1.5.7,second

$ csv2 -head 1 -t -i vs-sqlite.csv2          # what a real one looks like
dimension,csv2,sqlite,advantage,basis,note
比較項目,csv2,SQLite,優勢方,依據,說明
"storage, text at scale",…
```

Writing such a file is refused (csv2 will not convert between the two
formats); reading one cannot be, and that asymmetry is deliberate — csv2
believes the name because inventing a detector would mean guessing, which is
the thing the suffix rule exists to prevent. Asserted by T97.

### A BOM is stripped, and never reaches a column name

A file that opens with a UTF-8 BOM — anything exported by Excel, typically —
has it removed on read and not written back. What matters more than either is
where it does **not** end up: the first column's name is `pkg_name`, never
`\ufeffpkg_name`.

That distinction is the whole point. A BOM absorbed into the first header would
make `-update 1:pkg_name` fail to resolve a column that is visibly right there,
and a name-based address is the thing this tool asks you to build scripts on.
Asserted by T7.

There is **no column projection**: nothing selects "just the license column".
For one value at an address you already have, use `-get`:

```console
$ csv2 -get 12:6 -i pkgs.csv
fork raliclo/busybox, branch develop
```

It prints that cell and nothing else — no quoting, no delimiter, no header, no
address — so `$(csv2 -get …)` is the value. Deliberately not CSV: a one-cell CSV
row would need quoting whenever the value contained a comma, and the caller
would be back to decoding. The address is the same one `-update` takes, which is
what lets search, read and write compose:

```console
$ csv2 -contains "old value" -i pkgs.csv    # -> 12:6
$ csv2 -get 12:6 -i pkgs.csv                # read what is there now
$ csv2 -update 12:6 "new value" -i pkgs.csv --in-place
```

An address out of range is an **error**, not empty output — empty output is what
an existing empty cell looks like, and the two have to be distinguishable.
Header cells are not addressable: the locating report calls them `0a`/`0b`, but
no verb can act on one, `-update` included.

**`-get` always ends with exactly one newline, and that is a terminator, not
data.** A value that itself ends in a newline therefore comes back with two, and
nothing marks which is which — `$(csv2 -get …)` then eats both, because command
substitution strips every trailing newline, not one:

```console
$ csv2 -get 1:2 -i pkgs.csv | od -c | tail -2      # cell is "value ends here\n"
0000000   v   a   l   u   e       e   n   d   s       h   e   r   e  \n
0000020  \n

$ csv2 -mid 1,1 --json -i pkgs.csv                 # the same cell, unambiguous
{"record":1,"line":2,"fields":{"a":"x","b":"value ends here\n"}}
```

Newlines *inside* a value are fine — they come back as themselves. It is only a
**trailing** newline that cannot be distinguished from the terminator. When that
distinction matters, `--json` is the shape that carries it. Asserted by T71.

`-get` returns the **logical value**, not the bytes on disk. A `.csv2` file
stores an embedded newline as the two characters `\n`; `-get` gives you the
newline, the same as it would from a `.csv` file holding a real one. The two
formats differ in how they store a value, not in what the value is.

For many values at once, use `--json` and read the fields by name, or take the
third column of the locating report:

```console
$ csv2 -contains busybox -i pkgs.csv | cut -f1      # addresses, whole
$ csv2 -contains busybox -i pkgs.csv | cut -f3      # values, PREVIEWS -- see above
```

### `--a1` counts the header rows

`--a1` prints the cell as a spreadsheet would address it, which means the row
number depends on how many header rows the format has — one for `.csv`, two for
`.csv2`. The same data record is therefore a different spreadsheet row in each:

```console
$ csv2 -contains zlib --a1 -i pkgs.csv       # 1 header row
1:1 [A2]	pkg	zlib
$ csv2 -contains zlib --a1 -i pkgs.csv2      # 2 header rows
1:1 [A3]	pkg	zlib
```

Both are data record 1. `A2` and `A3` are what you would click on. The column
letter comes from the field number the same way: field 3 is `C`.

**Past column Z the letters carry the way a spreadsheet's do**, which is not
the way a plain base-26 counter would: there is no digit for zero, so field 27
is `AA` and not `BA`, field 52 is `AZ`, field 53 is `BA`, and field 702 is `ZZ`
followed by `AAA`. Asserted at each of those boundaries by T103 — the
implementation was right from the start, but nothing held it there and nothing
said so, which left anyone addressing a wide sheet to guess.

`--a1` and `--physical` add to the **locating report**, so they need
`-contains` and are refused with `-r`, `--filter`, `-md` and `--json` — those do
not emit an address for anything to be added to.

### What `-log` writes, and what it does not

`-log FILE` appends a timestamped record of the operation. **Several csv2
processes may share one log file**: the append happens in the kernel, so a
concurrent writer cannot land on another's offset and overwrite it. That is
worth stating because it was not always true — the file was opened for writing
and seeked to the end once, which is the same thing with one process and not
with two. Eight processes logging 25 operations each left 98 entries of 200,
none of them malformed and every run exiting 0. Asserted by T104, which runs on
Windows too — and failed there when this was first written, leaving 110 of 120
entries. The Windows path now uses `FILE_APPEND_DATA`, the OS-level atomic
append, rather than the C runtime's seek-then-write. No platform has a window.

It is an audit trail,
so it records what changed — which means it has to be explicit about what it
will not record:

| | In the log |
|---|---|
| the invocation | yes, but values are replaced: `-update 1:6 <value>`, `-insert 3 <row>` |
| key **bytes** | never |
| the keyfile **path**, and the key fingerprint | yes — never the key itself. But see below: the two markers' fingerprints do not mean the same thing |
| old and new values in an **ordinary** column | in full, never truncated; that is the point of an audit trail |
| old and new values in a **protected** column | `<redacted>` |

**One entry is one line, and every line is escaped to keep it that way.** A
newline, tab, CR or backslash is written as `\n`, `\t`, `\r` or `\\`. Without
that, text containing a newline started a new line whose entire content that
text chose — a forged entry, with a timestamp of its choosing, in the audit
trail, at rc=0. Truncating did not prevent that; it only shortened the forged
line.

**"Every line" was not always true, and the gap is worth knowing about**, since
it says what the guarantee now rests on. The escaping was applied to logged
*values* and to nothing else. Two other routes reached the log unescaped: the
invocation record, written on **every** run — so `-contains` alone forged an
entry, with no write access to the data at all — and any error message quoting
input back, such as the name in `no column named "…"`. Escaping now happens
once, where a log line is built, which is the only point that also covers
messages nobody has written yet. Asserted by T102, including that it happens
exactly once: two fixes each correct on its own escaped the invocation twice
and turned a newline into a literal `\\n` that no longer round-trips.

**The grammar, so a script can read it.** One entry is one line:
`TIMESTAMP LEVEL MESSAGE`, single-space separated, the level padded to five
characters. In an `update` entry the old and new values are each wrapped in
`"`, and a `"` inside a value is **doubled**, exactly as `.csv2` and RFC 4180
do it — so `INNOCENT" -> "ALSO INNOCENT` is written
`"INNOCENT"" -> ""ALSO INNOCENT"` and a reader who knows the format needs
nothing new. Without that doubling a value could rewrite which half of the
entry was old and which was new, inside an otherwise legitimate line, and no
regex could recover the truth. Asserted by T106. Unescape the line first
(`\n`, `\t`, `\r`, `\\`), then read the quoted fields.

**"In full" has no upper bound, and above 1 MiB it says so.** A value larger
than that is still written whole, with a `WARN` naming its size: a cap would
be an audit trail that drops data, which is the thing this line exists to
avoid, but a log that quietly grows by a megabyte should say so at the time.
Only the *old* value can reach that size — a new one cannot be passed, because
`ARG_MAX` refuses the command line first.

**A `:hmac:` fingerprint identifies the key. A `:enc:` one identifies the key
*and this file's salt*, so it is different on every run.** Both are the first
four bytes of SHA-256 over the DERIVED key, and that is where they part: `-hash`
derives with a fixed salt, so the same keyfile always yields the same number;
`-encrypt` draws a fresh 16-byte salt per run and stores it in the marker, so
the derived key — and the fingerprint — is per file.

```console
$ for i in 1 2 3; do csv2 -encrypt secret -keyfile k.bin -i s.csv -o e$i.csv -t; done
secret:enc:d88cdbf1:…      # one keyfile,
secret:enc:e16b394a:…      # three runs,
secret:enc:869e54ce:…      # three fingerprints

$ for i in 1 2 3; do csv2 -hash secret -keyfile k.bin -i s.csv -o h$i.csv -t; done
secret:hmac:9acc9081       # the same number every time; a different keyfile changes it
```

**So do not carry a `:enc:` fingerprint between files.** Comparing it *within*
one file is exactly right, and is what the refusal does — csv2 re-derives with
that file's stored salt and checks. Writing one down as "my key's fingerprint"
and comparing it against a second file will mismatch for the *same* key, and
read as if the key had changed.

A column counts as protected when **the file's own header says so** — a header
reading `secret:hmac:d6c8da42` or `secret:enc:…` marks it — not merely when the
current run is the one encrypting or hashing it. So editing a cell in an
already-protected column redacts, even though that run performs no transform of
its own:

In practice you will not see a redacted update, because the edit does not get
that far — an edit aimed at a column the file declares transformed is refused
outright:

```console
$ csv2 -update 1:secret "new value" -i pkgs.csv -o out.csv -log app.log
csv2: -update 1:secret targets a column this file declares transformed; a raw
value written there would sit in a hashed column looking like a hash, and
nothing can detect it …
$ echo $?
1
$ grep update app.log
INFO  csv2 -update 1:secret <value> -i pkgs.csv -o out.csv -log app.log
```

The refusal is the stronger guard: it stops the write instead of hiding it, and
it is what the refusals table below describes. **Redaction remains as a
backstop** — if any future path ever logs a value from a protected column it
will be `<redacted>` — but no documented route reaches it today. An earlier
version of this section showed the redacted form as an ordinary session; it was
still here after the refusal was added, which is how a reader ends up trying a
command that cannot work. Asserted by T40 and T73.

**The log is a file on disk with normal permissions.** Redaction keeps secrets
out of it; it is not a reason to put the log somewhere careless.

### Two numberings, and where they disagree

`-rownum` prepends a column. Everything else keeps the numbering it had:

```console
$ csv2 -contains busybox -i pkgs.csv
1:1	pkg_name	busybox
$ csv2 -contains busybox -rownum -i pkgs.csv
1:1	pkg_name	busybox

$ csv2 -r -t -rownum -i pkgs.csv
rownum,pkg_name,version,source,license
1,busybox,1.37.0,"fork raliclo/busybox, branch develop",GPL-2.0
```

The address `1:1` still means `pkg_name`, in both runs. But in the printed row,
`pkg_name` is now the **second** physical column. **The address numbering and
the physical column position differ by one whenever `-rownum` is on**, and
nothing in the output says so.

Addresses are stable on purpose: an address you found earlier, or wrote down
from a bug report, has to keep meaning the same cell no matter which display
flags a later run uses. `-update 1:1` edits `pkg_name` whether or not `-rownum`
was passed to the run that found it.

What this costs you is the other direction. **Anything that reads the output by
column position — another program, a spreadsheet import, `cut` — sees `rownum`
at position 1 and everything shifted one right.** So do not mix the two: use
addresses with addresses, positions with positions.

The rownum column is also **never searched**: `-contains 4` will not match a
record merely for being the fourth. Its value is generated by the display, not
data from your file, and matching on it would let the output of a run change
what that run finds. Asserted by T15.

By default the header rows are **invisible to search**, even though their cells
are text like any other. `--include-headers` includes them, addressed `0a` for
the first header row and `0b` for the second — never plain `0`, so that a hit in
the English title row and one in the Chinese title row are distinguishable:

```console
$ csv2 -contains note --include-headers -i pkgs.csv2
0a:3	note	note
$ csv2 -contains 備註 --include-headers -i pkgs.csv2
0b:3	note	備註
$ csv2 -contains 備註 --include-headers --zh -i pkgs.csv2
0b:3	備註	備註
```

The middle field is the column's name **in the language you asked for**, not the
name from whichever header row matched. That is why the second line says `note`
while the value beside it is Chinese: the row that matched was `0b`, but the
report was not asked for Chinese names. `--zh` changes the name and nothing
else. Asserted by T66.

**That `cut -f3` has no `-d`, and the omission is the whole point.** It is
cutting on TAB, because the locating report is TAB-separated with its values
escaped. Do not reach for `cut` against `--filter` or `-mid` output: that is
CSV, a value may contain a comma, and `cut -d, -f3` will hand you a fragment
of one — silently, at exit 0. On this project's own fixture it returns 104
bytes of a 515-byte cell. That failure is why csv2 exists; getting it from
csv2's own output would be a poor joke. Asserted by T65.

```console
$ csv2 -contains busybox --filter -i TARGET_PACKAGES.csv
busybox,fce9d7f35ea3 (submodule),896 KiB,fork raliclo/busybox branch develop,…
```

`--filter` switches to the matching **records**, as CSV. Add `-t` to get the
header rows too — and see the refusals below for when `-t` is not optional.

`-A`, `-B` and `-C` **imply `--filter`**: a context record has no matching cell,
so there is nothing for a cell report to say about it. Blocks that are not
adjacent are separated by `--`, as in grep.

**"As in grep" is about the `--` separator, not about grep's `-`/`:` line
markers.** grep marks a context line differently from a matched one; the CSV
output cannot, because a marker in a CSV row would be a field, and a row with an
extra field is a broken record. So with `-A`/`-B`/`-C` the CSV output is a
mixture of matches and context that nothing distinguishes — and `-contains`
exists precisely to give you the `record:field` address, so if you need the
address, run it once without context to get the addresses and once with context
to read around them.

`--json` has no such constraint and does mark them, but only when context is on
— without it, every emitted record matched and the key would be a constant:

```console
$ csv2 -contains zstd -C 1 --json -i pkgs.csv
{"meta":{"format":"csv","headers":1,"fields":2}}
{"record":2,"line":3,"match":false,"fields":{"pkg":"zlib","ver":"2"}}
{"record":3,"line":4,"match":true,"fields":{"pkg":"zstd","ver":"3"}}
{"record":4,"line":5,"match":false,"fields":{"pkg":"ncurses","ver":"4"}}
{"meta":{"records":4,"matched":1}}
```

The trailing `matched` is a count, not an index: it tells you how many records
matched, not which of the objects above it they were. That is what `match` is
for. Asserted by T63.

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
without counting — and for the same reason, a record whose header has **two
columns with one name cannot be emitted this way**: a JSON object cannot hold
two values under one key, and every parser in use keeps the last and discards
the first. csv2 refuses rather than emitting a line that loses data once it is
parsed. Read it without `--json`, or use `-contains --json`, whose report shape
gives each hit its own line and is unaffected. Asserted by T75.

`-md` emits a Markdown table and is one-way — csv2 cannot read it back. Writing
it to a `.csv`/`.csv2` path with `-o` is refused, and if you route around that
with `-so` and a shell redirect, reading it back is refused too: a one-column
file whose record is a Markdown separator row is `-md` output, not CSV, and the
message says so instead of complaining about field counts. Asserted by T74.

### In a pipeline

`-si` and `-so` compose with every verb; there is nothing special about a
pipeline except that stdin has no suffix, so `--headers` has to say what the
format is:

```console
$ cat packages.csv | csv2 -si --headers 1 -contains busybox --filter -so
busybox,1.37.0,"fork raliclo/busybox, branch develop",GPL-2.0
```

**It streams, but stdout is buffered in 64 KiB blocks — not by line.** "Without
buffering the whole file" is a statement about memory, and it is true: on a
stream that keeps coming, the first output appears immediately and memory stays
flat. But under 64 KiB of output nothing appears until the run ends, so piping
csv2 into something you are watching live will look like it has hung when in
fact it has nothing to flush yet. If you need each record as it is produced,
you need a tool that line-buffers; csv2 is built for throughput in a pipeline,
not for interactive tailing. Measured, not assumed: 8 000 records out and the
first bytes arrive in 0.01 s while input runs for 3 s; 2 000 records out and
nothing arrives until close. Asserted by T61.

### Exit status

`0` on success, non-zero on any error, and there is no third case: csv2 does
not partially succeed. A run that fails writes nothing to `-o`, because output
goes to a temp file that is renamed only after everything else worked.

**The same holds for `--in-place`, where it matters more:** a failed in-place
edit leaves the original **byte-for-byte unchanged**, and leaves no temp file
beside it. This is the one guarantee with no fallback — with `-o` you still have
the input if the output is wrong, and with `--in-place` the input *is* the
output. Asserted by T28c.

`--build-index` and `--verify-index` each print one line to **stdout** — they
are explicit administrative actions, not the normal path, but if you pipe them
anywhere that line is in your stream.

Errors go to stderr as exactly **two** lines, English then Chinese — escaped
by the same rule as the log, which is what makes the count reliable: a message
quoting an input value that contained a newline used to print four, and a script
reading the pair took the injected line for part of the error. Asserted by T102.
With `-log FILE` the same failure is also appended there with a timestamp;
without it nothing else is printed. On the normal path csv2 prints nothing at all — it has
to work inside a pipeline.

**How much of a location an error carries depends on how much there is.** Do not
write a script that expects to find `record N, field M` in every message:

| The fault is | The message names | Example |
|---|---|---|
| at one cell | `record N (line L), field M` | `record 1 (line 3), field 2: undefined escape sequence \q; .csv2 defines only \n, \r and \\` |
| at one record, but no single field | `record N` | `record 1 (line 2) has 2 fields but the header has 3` |
| in the arguments | neither — it is thrown before any record is read | `unknown flag --nope` |
| in the file as a whole | neither — there is no record to name | `cannot open input file: /nope.csv` |

Only a fault located at one cell names both. The rest name the record, or
nothing, because there is nothing else true to name. Asserted by T60.

**The record number in an error is a real address.** `record 1 (line 3), field
2` names the same cell `csv2 -get 1:2` names: it counts data records, so it
agrees with everything else here, and the line is there because that is what a
text editor wants. A fault inside a header row says `header row 0a` or `0b`
instead, because a header row has no record number to give. Asserted by T93.

**Whether you can act on it depends on what the error was.** The example above
is a PARSE error, and a file csv2 cannot parse is one no verb will touch —
`-get 1:2` on it returns that same error, not the cell. That is correct: the
alternative is acting on a file whose shape is unknown. Fix the cell the address
names, then address it. For errors that are not parse failures — an out-of-range
`-update`, a refused flag combination — the file is readable and the address is
immediately usable.

An error in the **arguments** is thrown before `-log` has been read, so it
reaches stderr but not the log file: the path to log to came from the same
arguments that failed to parse.

### What it refuses, and why

Refusals are the point of the tool, so they are listed rather than discovered.
Each of these exits non-zero with a message saying why:

| Combination | Why it is refused |
|---|---|
| `-head 3 -o out.csv2` (no `-t`) | data rows without a header written to a path whose suffix promises one; the next read would eat the first records as the header. **This applies to selections, not to edits** — see below |
| `-md` without `-t` | a Markdown table has no shape without a header row, and silently adding one would make "no header by default" grow an invisible exception |
| `-md -o out.csv2` | the suffix declares CSV, the content would be Markdown |
| `-si` without `--headers 1` or `2` | stdin has no suffix, so the format is not declared; a default here would be a guess |
| `-head` with `-tail` | no single reading of both is obviously right |
| `-mid 7,3` | `a > b`; not swapped for you, because a range written backwards usually means the logic is backwards too |
| `-i x -o x` without `--in-place` | opening the output truncates it before the input has been read |
| `-delete 12:6` | that is a cell address; add `-cell`, or give a record number |
| `-delete -cell -col 3` | they are opposites: `-cell` blanks a field and keeps the column, `-col` removes the column |
| `-delete -col` removing every column | a file with no columns is not a CSV file |
| `-delete -col X` with `-update`/`-delete -cell`/`-encrypt`/`-hash` on X | the edit would have no effect and would still be reported as done |
| `-delete -col` with `-insert`/`-append` | the literal row would have to match either the old shape or the new one, and there is no way to tell which was meant |
| `--a1` or `--physical` without a locating report | they add a part to the report's address, and `-r`/`--filter`/`-md`/`--json` do not emit one; there would be nothing to add to |
| `-insert -cell` | inserting a cell mid-record shifts every later field one column along |
| `-update 99:3` on a 21-record file | out of range is an error, never "grow the file to fit" |
| `-append 'a,b,c'` on a 7-column file | the field count must match the header; csv2 will not pad or truncate to fit |
| `-encrypt` with no `-keyfile` and no tty | a prompt that cannot be shown is never a yes |
| an edit with no `-o`, `-so` or `--in-place` | `-insert`/`-append`/`-delete`/`-update` need an explicit destination; there is no implied in-place |
| `-o /dev/stdout` | output is written to a temp file beside the target and renamed, which needs a regular file. Use `-so` |
| `-update`/`-delete -cell` on a column the file marks `:enc:`, `:hmac:` or `:hash` | a raw value written there cannot be read back, and for an encrypted column `-decrypt` stops at that cell — so records the edit never touched are lost with it |
| `-insert`/`-append` into a file that has such a column | every field of the literal row is raw, including that one, and no value you could supply would be right: the transform needs the key, and the header carries only its fingerprint |
| `-append` onto a file whose last record is incomplete | a short final record, or one left open by an unclosed quote. Checked for `-o` and for `--in-place` alike — the fast path used to skip it and produce a file csv2 then refused to read |
| `-append` with `--truncate-partial` | appending adds bytes and cannot remove the incomplete record, so the file would keep it *and* gain a complete record after it. Write a clean copy first: `csv2 -r -t --truncate-partial -i f.csv -o clean.csv` |
| a value, row or search string that is not valid UTF-8 | Swift decodes `argv` with replacement, so the bytes are already gone; storing what arrives would put U+FFFD where a byte was, silently. Put the value in a file — bytes survive there, which is what the round-trip guarantee is about. **Paths are not checked**: on Linux they may legitimately hold any bytes, and csv2 hands a path to the filesystem rather than storing it as data. **POSIX only**: a Windows command line arrives as UTF-16, so whatever happened to an invalid byte happened before the process started and there is nothing left for csv2 to inspect |
| unknown flag | never swallowed as something else |

### Every edit index refers to the input, and that is visible with `-insert`

`-insert`, `-delete`, `-update` and `-delete -cell` can each be given more than
once in a run, and **every index counts against the file as it arrived**. The
edits are collected and applied in one pass, so an earlier insert never shifts
a later one's target.

That is the only semantics that makes a batch predictable, and it is also why
the same three numbers mean two different things depending on how you group
them:

```console
$ csv2 -insert 2 A -insert 4 B -insert 5 C -i f.csv --in-place   # one run
r1  A  r2  r3  B  r4  C  r5

$ csv2 -insert 2 A -i f.csv --in-place                            # three runs
$ csv2 -insert 4 B -i f.csv --in-place
$ csv2 -insert 5 C -i f.csv --in-place
r1  A  r2  B  C  r3  r4  r5
```

Both exit 0. Neither is wrong — each run's indices are correct against the file
that run was given — but only the first is a batch. **Decide which you mean; do
not discover it.** If you want rows to land at FINAL positions 2, 4 and 6, the
input-relative numbers are 2, 3 and 4.

Two consequences worth stating because they are easy to trip over:

- **Range is checked against the input too.** `-insert 6` on a five-record file
  is refused in a batch, and legal as the third of three separate runs, because
  by then the file really does have six places to put it.
- **Two inserts at the same N keep the order you wrote them**, and `-insert`
  composes with `-append` in one run.

Asserted by T27.

### `-t` gates selections, never edits

A selection produces a **fragment**, so whether the header goes with it is a
question, and `-t` answers it. An edit produces a **file**, so it is not a
question: the headers always go out, with or without `-t`, and to a `.csv2`
destination both of them do.

```console
$ csv2 -head 1 -i pkgs.csv2 -o sel.csv2
csv2: sel.csv2 declares a format with a header, so writing data rows there needs -t; without it the next read would take the first record(s) as the header
csv2：sel.csv2 的副檔名宣告了帶標頭的格式，因此在此寫入資料列必須給 -t；否則下次讀取會把最前面的紀錄當成標頭
$ echo $?
1

$ csv2 -update 1:note X -i pkgs.csv2 -o edited.csv2   # no -t, and no refusal
$ head -2 edited.csv2
pkg,ver,note
套件,版本,備註
```

The asymmetry is the point. Refusing the edit would leave you no way to edit a
`.csv2` at all without remembering a flag whose absence can only ever produce a
broken file; accepting the selection would produce exactly that broken file.
Asserted by T59.

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
| `CSV2_PARALLEL_MAX_BYTES` | 1 GiB | ceiling on what the in-flight chunks may hold. It governs the **output** fragments — one batch of them is kept so they can be written in chunk order, which is what makes parallel output byte-identical to single-threaded. The read side needs no ceiling: a worker reads its chunk 64 KiB at a time and never holds more. Lowering this holds fewer chunks in flight and the rest queue; `-debug` says so, with the numbers. **It is not a cap on the process's memory** — under an 8 MiB setting, peak RSS was still 58 MB, because the fixed working set is not part of what it governs |
| `CSV2_PARALLEL_CHUNK_BYTES` | 4 MiB | smaller values make a small file yield many chunks, so chunk boundaries are actually exercised |
| `CSV2_PRETTY_MAX_BYTES` | 16 MiB | `-md --pretty` refuses above this rather than being OOM-killed |
| `CSV2_MAX_BUFFER_RECORDS` | 1,000,000 | upper bound on `-tail N` and `-B N`. Asking for more is **refused, not truncated** — a short answer that looks like a whole one is the failure this tool exists to avoid. The message names the request, the limit and the variable |

**Parallelism applies to `-contains` and to nothing else**, and only when every
one of these holds. Setting the two knobs above does not by itself make a run
parallel:

| Requirement | Why |
|---|---|
| a search, without `--filter` or `-md` | those emit records, and chunks would emit them out of order |
| no `-A`/`-B`/`-C`, no `-head`/`-tail`/`-mid` | context and position are relative to a stream a chunk does not see |
| no transform, no edit | those write, and writers do not chunk |
| `-i FILE`, not stdin | chunking needs to seek |
| more than one core | |
| at least `CSV2_PARALLEL_MIN_BYTES` | |
| **one record per line** | `.csv2` guarantees it. A `.csv` qualifies only with an index that scanned the file and recorded there are no embedded newlines — build one with `--build-index` |

That last row is the one that surprises. A `.csv` containing an embedded
newline can never take the parallel path, which is also the case a
boundary-straddling test most wants to construct.

**`-debug` says which path ran, always**, including when it is the ordinary one
and why:

```console
$ csv2 -contains xyz -i pkgs.csv2 -debug     # 2>&1
DEBUG parallel: 9 chunks, 10 workers, chunk 512 bytes
$ csv2 -contains xyz -i pkgs.csv -debug
DEBUG single-threaded: .csv with no index proving one record per line; build one with --build-index
$ csv2 -r -i pkgs.csv2 -debug
DEBUG single-threaded: not a search; parallelism applies to -contains only
```

Reporting only the interesting case would make silence ambiguous, and that
ambiguity bites exactly here: comparing a "parallel" run against a
single-threaded one proves nothing if both quietly took the same path — and
identical output is precisely what that looks like. Asserted by T72.

**And when a `.csv` takes the parallel path, the sidecar it believed is named**:

```console
$ csv2 -contains xyz -i pkgs.csv -debug
DEBUG parallel: trusting index pkgs.csv.index, which declares no_embedded_newlines;
      if the file changed since that was built while keeping the same size and mtime,
      record numbers will be wrong -- csv2 --verify-index -i pkgs.csv is the O(n) proof
DEBUG parallel: 6 chunks, 10 workers, chunk 4194304 bytes
```

Until 2026-08-20 this line did not exist, and the asymmetry ran the wrong way.
The one path that *trusts* an index said nothing at all, while the paths that
decline one do explain themselves. By the O(1) stamp's own limits — described
below — a trusted index can be stale, so that was the only branch capable of
being silently wrong, and it was the only one leaving no trace. An operator
reading `-debug` could see why a sidecar had been rejected, never that one had
been believed, nor which file it was. Asserted by T101, which also pins the
line's other property: it is emitted once per run, not once per eligibility
check. Note where the record numbers go wrong when this does happen — not at
the record that spans lines, whose own number survives, but from the first
chunk boundary after it, because what a stale `no_embedded_newlines` corrupts
is each later chunk's starting record number.


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
  gives you the wrong data is far worse than no index. That covers the index's
  own contents too: the header carries a checksum over the whole index, offsets
  included, so a damaged one is discarded rather than followed, and the next
  operation that reads the whole file writes a good one back. Asserted by T68.
  **What the checksum is not:** it catches corruption — a flipped bit, a short
  write, a partially overwritten file — and is not a signature. Anyone who can
  rewrite the offsets can rewrite eight more bytes. It also cannot help when the
  *data* file changes without changing size, mtime or its first and last bytes;
  that is what the O(1) check has always been, a heuristic. For a proof, run
  `--verify-index`, which is O(n) because it has to be. **What it proves is
  that the index's three claims are accurate — not what those claims say.** On
  a file where every other record spans lines it prints `index OK` just the
  same, because the index correctly records that. It is not a way to ask "does
  this file have embedded newlines"; the search's `-debug` line answers that
  one, explicitly. **What it proves** is
  all three of the index's claims: the grid offsets, the record count, and
  whether any record spans lines. The third was added on 2026-08-19, and it is
  the one that mattered — it is the claim the parallel path consumes when it
  treats a line as a record, it was the only claim nothing re-derived, and the
  edit that breaks it leaves the other two intact, so checking those two alone
  returned `index OK` on an index that then produced the wrong record number.
  Asserted by T79. The sidecar for
  `packages.csv` is `packages.csv.index` — the whole filename plus `.index`, so
  `foo.csv` and `foo.csv2` never collide. That is the line to put in
  `.gitignore`: it is derived from the data file and is never the source of
  truth, so it should not be committed and need not be backed up.
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

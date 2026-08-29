# csv2

A CSV parser and editor for the command line, written in Swift, targeting the
aarch64 Linux guest of the [LinuxCS](https://github.com/raliclo/LinuxCS) project
and the macOS host it is built from.

繁體中文說明見 [README.zh-TW.md](./README.zh-TW.md)。

## Status

**Phases 1–6 and 8–10 are implemented and pass their tests. Phase 7 (shipping) is a deliberate deferral.** One item in phase 9 is still open: repeating the Swift 6 module verification on macOS and aarch64 Linux, which has so far only been done natively on Windows.

All build entry points require a Swift 6 toolchain and explicitly select Swift
6 language mode; an installed Swift 6 compiler silently defaulting to Swift 5
mode is not considered a Swift 6 build.

```zsh
./compile_csv2.zsh      # auto-detect the host; release/csv2 or release/csv2.exe
./test/test_csv2.zsh    # 0 FAIL. On macOS the one SKIP is T47, which
                        # compares two platforms and so runs from the parent
                        # project. Other platforms skip more, each with its
                        # reason printed; the suite checks the count itself.
```

| Works | Does not yet |
|---|---|
| RFC 4180 parsing, quotes, embedded commas and newlines, CRLF, BOM | shipping in the rootfs (phase 7) |
| `-r`, `-contains`, `-A`/`-B`/`-C`, `-head`/`-tail`/`-mid`, `-rownum` | |
| two-row `.csv2` headers, `--json`, `-md`, `--pretty` (display widths) | |
| `-insert`/`-append`/`-delete`/`-update`, `-delete -cell`, `-delete -col`, `-add-column` | |
| `-hash`, `-encrypt`, `-decrypt`, `-keyfile`, `-debug`, `-log` | |
| the `-append` fast path — O(1) in bytes written, O(n) in bytes read | |
| `.csv.index` / `.csv2.index` sidecars, `--verify-index` | |
| parallel search, byte-identical to the single-threaded run | |
| builds and runs on aarch64 Linux, byte-identical to macOS | |
| builds and passes on x86_64 Linux (WSL2) and on Windows (MSVC) | |

**And what it does not do at all**, because a table of eleven wins and one
deployment item reads as a tool with one outstanding thing. Each of these is
described somewhere below; this is the list a reader should see first:

| Not offered | What to do instead |
|---|---|
| column projection (`-cols`) | `--json` and `jq`, or `-get` per cell |
| case-insensitive matching | `--json` and one pass of your own — see the note under `-contains` |
| counting without reading (`-count`) | `records` on the trailing `--json` meta line — and see the note below the table, because the obvious way to get it reads the whole file |
| converting between `.csv` and `.csv2` | refused on purpose; write the records out and read them back in |
| editing a Markdown table | supported since 2026-08-26 — render with `-md`, edit, read the `.md` back. See the note below the table |
| safe concurrent writers | serialise them yourself; two writers silently lose one edit. Two concurrent `-append --in-place` runs are the exception: both records land whole, and the one that finishes SECOND warns that it could not update the index |
| telling refusals apart programmatically | nothing but exit 1 and English prose, in every one of them |
| scoping a search to ONE column | nothing does. `-contains` is a substring search across every column, so counting with it is silently wrong the moment the word appears anywhere else — see below |

**A new column on a `.csv2` needs both titles, and csv2 will not invent the
second one.** That is the same rule that refuses to write a one-header `.csv`
into a `.csv2`:

> going to two rows would mean **inventing a row of titles**

A program that refuses to invent a Chinese title there, and invents one here,
would be contradicting itself inside the same binary. So `-add-column` takes
both, the way a header row carries them -- one CSV record, comma-separated:

```console
$ csv2 -add-column 2 'note,備註' 'todo' -i pkgs.csv2 --in-place
```

Give only the English title on a `.csv2` and it **warns** on stderr and leaves
row 2 empty. It is a warning rather than a refusal because the file that comes
back is still correct csv2, and because the person adding a column is often not
the person who can translate its name. The empty cell says so and can be filled
later; an English title copied into the Chinese row would be a translation
csv2 invented, and a wrong one is harder to find afterwards than a blank.

**A search cannot be scoped to a column, and that makes the obvious counting
idiom wrong.** `-contains` matches a substring in ANY column:

```console
$ cat lic.csv
pkg,license,source
libA,MIT,upstream
transMITter,BSD,relicensed from MIT in 2019

$ csv2 -contains MIT -i lic.csv
1:2  license  MIT
2:1  pkg      transMITter                    ← not a licence
2:3  source   relicensed from MIT in 2019    ← not a licence either
$ csv2 -contains MIT --json -i lic.csv | tail -1
{"meta":{"records":2,"matched":2}}           ← the answer is 1
```

Nothing narrows it. Use `--json` and one pass of your own, keyed on the column
you mean — the same answer the table above gives for column projection and for
case-insensitive matching, and for the same reason. Round 77 reached for the
csv2-only route, got six commands and a silently wrong number.

**A `.csv2` costs more to READ than the same data as `.csv`.** Measured on
450,000 identical records, best of 5, byte-identical output:

| | `.csv` | `.csv2` |
|---|---|---|
| `-r` | 422 ms | 767 ms |
| `-r --json` | 1335 ms | 1719 ms |

The gap is roughly flat (~350 ms), so it is per-value work and not output
volume — and neither fixture contained a single backslash, so it is the cost of
LOOKING for escapes, not of undoing them. Set against the documented saving:
`.csv2` guarantees one record per line, so `-contains` parallelises without an
index and wins ~200 ms on the same data. On a read-heavy workload `.csv` plus a
sidecar is the faster pair; `.csv2` earns its keep on searches, on two header
rows, and on values that would otherwise need quoting. Round 77 measured this;
in a document that quotes milliseconds in fifteen places, saying nothing read
as "no difference".

**A file whose suffix is not `.csv` or `.csv2` is one column, as of
2026-08-26.** That includes no suffix at all, and it includes `.txt`, `.list`,
`.log` — anything the tool does not recognise is a list of lines. This
paragraph said "no suffix" until round 78 measured the rule, and the difference
is a hazard worth stating: **a genuine CSV named `data.txt` reads as one column
at exit 0**, because nothing about the name says otherwise. `--headers 1` is
how you tell it, and it still works exactly as it did.** A list of paths, a
`find` dump, a column of package names — a table that happens to have one
column — is now readable without renaming it:

```console
$ find . -type f > files
$ csv2 -contains '.swift' -i files
$ csv2 -append 'src/new.swift' -i files --in-place
```

The shape is **one column, ZERO header rows, and the line's bytes verbatim**.
Each third of that was measured before it was chosen:

- **Zero header rows**, because the documented way through before this —
  `--headers 1` — ate the first line of every such file as a title. It vanished
  from the output, at exit 0.
- **A comma does not split**, because a path may contain one, and a `find` dump
  with a comma in it became a two-column table that then failed on the first
  line without one.
- **Nothing is unescaped**, and a quote is data. A line holding a literal `\n`
  keeps it; `"a,b"` keeps its quotes. `.csv2` escaping would have changed what
  such a line means on the way in, so "a one-column `.csv2`" describes the
  SHAPE correctly and the ESCAPING wrongly.

A column can only be addressed by NUMBER here, and there is only ever column 1;
`-get 1:name` is refused, naming why. `--headers` still overrides, because a
file called `data` that really is a CSV was readable that way before this and
had to stay readable — a new default must not take a working use away.

**Markdown goes both ways as of 2026-08-26.** `-md` renders a table; a `.md`
input reads one back, and a `.csv2` rendered and read back is byte-identical to
what it started as — including a value holding a `|`, an embedded newline, a
literal `<br>`, and leading or trailing spaces.

```console
$ csv2 -r -t -md -i pkgs.csv2 > table.md      # edit table.md by hand
$ csv2 -update 1:2 'fixed' -i table.md -o pkgs.csv2 -t
```

Four things are worth knowing before relying on it:

- **How many header rows is recovered, not asked for.** `-md` joins a `.csv2`'s
  two titles with an unescaped `<br>`, so the header cells say which format the
  table came from. `--headers` is therefore refused on a `.md`: a value given
  there could disagree with the table, and one of them would have to be
  ignored.
- **The file must BE a table**, or you must say which table. Prose around it is
  refused, naming the line; so is a file holding two tables, naming the line
  the second starts on. `--md-table N` takes the Nth table out of a document.
  csv2 does not pick one for you — before this refusal existed, a second
  table's header and its `|---|` separator were read as DATA, at exit 0.
- **Alignment is lost.** `|:---|---:|` is presentation, not data, and it does
  not survive the round trip. Nothing else does not.
- **It is read whole, not streamed.** A `.md` is translated into `.csv2` in
  memory and handed to the ordinary reader, so that a Markdown table obeys
  every rule that reader already enforces instead of growing a second parser
  that would drift from it. The bound is `CSV2_MD_MAX_BYTES` (16 MiB), refused
  above it with the size and the way through.

**Counting: the obvious route is the expensive one.** `records` on the trailing
meta line is the answer, but `csv2 -r --json` reaches it by reading every byte.
`csv2 -tail 1 --json` reaches the same number **and, when a sidecar exists,
seeks straight to the end**: measured on a 200,000-record file, 960 bytes read
against 2,777,795, same answer. Extract it with

```sh
n=$(csv2 -tail 1 --json -i f.csv | tail -1 | sed -n 's/.*"records":\([0-9]*\).*/\1/p')
```

The sidecar is the whole trick and it is not automatic: without one, `-tail`
reads the file to find its end, and below `CSV2_INDEX_MIN_BYTES` it does not
leave one behind either — the 2.7 MB file above read all 2,777,795 bytes twice
in a row until `--build-index` was run on it. So this is cheap on a file you
have indexed on purpose, or on one big enough that something already did.
Round 75 found the cheap form by deriving it from two separate sections; the
table used to point only at the expensive one.


`install.zsh` puts the binary where each platform's shell actually looks:
`$(brew --prefix)/bin` where Homebrew is present, `~/.local/bin` as the
user-level fallback, and on Windows `%LOCALAPPDATA%\csv2\csv2.exe` — the path
scoop's shim already names, so the shell resolves to the new build without this
script writing into scoop's own directory. **Check which csv2 you got by
comparing the file, not the version**: two builds both say `csv2 0.1.0`, so
`csv2 --version` cannot tell them apart.

After copying, it asks a shell started from an empty environment whether
`csv2` now resolves to the file it just placed — not whether the directory
appears in `$PATH`, which is a different question with a different answer. On
Windows the install directory is not on PATH at all and `csv2` resolves
perfectly well through a scoop shim; a directory can equally be on PATH while
an earlier one supplies a different build.

Only when no shell can run it by name does `install.zsh` write a PATH line, and
it writes it to the file the **account's** login shell reads, which is not
necessarily the shell running the installer. For zsh that is `~/.zshenv` rather
than `~/.zshrc`, because a script reached over ssh is not interactive and reads
only the former; for bash it is `~/.bashrc` plus a login file that sources it.
The block is delimited by `# >>> csv2 install.zsh >>>` markers, installing
twice does not add a second one, and `--uninstall` takes every one of them back
out. `--no-rc` skips this entirely and prints the line for you to add yourself.

It ends by saying which kinds of shell can reach the binary — every shell
including scripts over ssh, login shells only, or interactive terminals only.
Those are different properties and only some of them are usually the one you
need.

Its options, which were undocumented until round 75 needed one of them and
could not find it:

| | |
|---|---|
| `--dry-run` | say what would happen, write nothing |
| `--prefix DIR` | install into DIR instead of the chosen location. This is how you install somewhere private — a throwaway directory, a container image, a machine where `$(brew --prefix)/bin` already holds a csv2 you do not want replaced |
| `--no-rc` | never touch a shell rc file; print the PATH line for you to add |
| `--uninstall` | remove the binary and every block this script wrote |

Without `--prefix` the destination is chosen for you, and on a Homebrew machine
that is `$(brew --prefix)/bin` — which will overwrite a csv2 already there. That
is what installing means and it is the intended behaviour, but a reader trying
the tool out wants `--prefix` and the document did not offer it.

Progress is tracked as checkboxes at the end of [plan/plan.md](./plan/plan.md),
and a box is only ticked once the matching case in
[test/test_csv2.zsh](./test/test_csv2.zsh) passes. Cases the tool cannot yet
satisfy are reported as SKIP with the reason rather than quietly left out.

**Designed but not built: `csv2view`, a native SwiftUI viewer.** Nothing below
describes it, because none of it exists yet — the design lives in
[plan/plan.md](./plan/plan.md) and named two things csv2 had to gain first: a
`-count` verb, and line numbers in the index so a file with a quoted newline
can still be seeked into. **The second arrived on 2026-08-21** — index v4
stores the line beside each grid point, and a `.csv` with a record spanning
lines now seeks exactly as a `.csv2` does (T157). (A third item, "an error instead of empty
output when `-mid`'s START record is past the end", was on this list until
2026-08-20 and is now a WARN naming both numbers — see `-mid` above.) A measured 5.6 ms per 40-record window on a
19.5 MB file is why the viewer will call this binary rather than embed a copy
of its parser. **That number needs a sidecar, and `-mid` never builds one** —
run `--build-index` first, or measure 277 ms and conclude the figure is
fiction, which is what a reader following this document exactly will do. The
file behind it is 450,000 records of about 40 bytes each; the shape matters,
because the same size in wide prose records is a different measurement. **Do not write a script against any of that; it is a plan, not
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

**A field csv2 reads and does not change is written back exactly as it arrived,
quotes and all.** A field it *does* change is re-serialised, and then csv2's
own rule applies: quote when the value contains a comma, a quote, CR or LF, or
when it begins or ends with a space or tab. The whitespace case is not required
by RFC 4180 and is there because that whitespace is data of the kind that
vanishes silently — spreadsheets and several parsers strip it from an unquoted
field. So `-update` on a cell holding `"   "` writes `"   "` back, and a value
you supply ending in a space is quoted when it lands — through `-update`, and
through `-insert` and `-append` too, which write a row you typed rather than
one they read. Until 2026-08-25 those two kept the row's literal bytes, so
`-append 'r2, leading'` wrote ` leading` unquoted while `-update 1:2 ' leading'`
quoted the identical value: csv2 read both back correctly and the spreadsheets
this rule exists for did not.

**One thing this rule does NOT do is defend a spreadsheet from a formula.** A
value beginning `=`, `+`, `-` or `@` is a formula to Excel, LibreOffice and
Sheets, and csv2 stores it as the text it is: `=1+1` lands unquoted, exactly as
typed, because mangling a value to please a downstream reader is the one thing
this tool will not do. If your output is opened by a spreadsheet and its values
come from somewhere you do not control, that is yours to handle.

What follows from that: after an edit, an untouched field is byte-identical,
and an edited one carries csv2's quoting rather than whatever the previous
writer chose. A file that quoted every field will not stay that way in the
cells you edited. Asserted by T133.

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
csv2: vs-sqlite.csv2 declares 2 header row(s) by its suffix, but --headers says 1. The suffix declares the format; --headers is for input with no suffix to declare it. Drop --headers to read the file as it is. Renaming it instead makes the suffix agree with --headers, which is NOT the same thing: a header row then becomes data record 1, at rc=0, and nothing afterwards can tell it was one
csv2：vs-sqlite.csv2 的副檔名宣告了 2 列標頭，但 --headers 說 1 列。副檔名宣告格式，--headers 是給「沒有副檔名可宣告」的輸入用的。請拿掉 --headers，照這個檔案原本的樣子讀它。改檔名是讓副檔名去遷就 --headers，那不是同一件事：一列標頭會因此變成第 1 筆資料，rc=0，而事後沒有任何東西看得出它曾經是標頭
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

**A tab needs no escape and is stored raw.** Only the three above are escaped,
because only those three would otherwise end the line or end an escape; a tab
is an ordinary byte inside a `.csv2` cell and comes back exactly as it went in.
(The locating report `-contains` prints does escape a tab, as `\t` — that is a
report keeping one hit on one line, not the file format. Round 76 had to
establish the file's behaviour by experiment, because this paragraph listed
three escapes and said nothing about the character next to them on the
keyboard.)

## Interface

```
SELECTING / 選取
  -r                    read. This is what happens with no verb at all, so
                        `csv2 -i f.csv` and `csv2 -r -i f.csv` are the same
                        command
  Where `r:c` splits, when a column NAME contains a colon: at the FIRST colon.
  `-get 1:a:b` on a file with a column called `a:b` returns that column. A
  colon is overloaded here -- it separates `r:c`, and it separates a protection
  marker (`license:hash`, `license:hmac:<fp>`, `license:enc:…`) -- and only the
  second meaning was written down until round 77 asked. "Split at the last
  colon" is equally defensible and would silently address a different cell, so
  the rule is stated rather than left to be discovered.

  -get r:c              print ONE cell's value, raw -- the read that matches
                        -update r:c VAL. This is the verb to build scripts on:
                        what composes is the ADDRESS, and this is how a value
                        crosses from a report to an edit
  -contains S           report every CELL containing S, as record:field
  --filter              with -contains, emit the matching records instead
  --include-headers     search the header rows too (reported as record 0a / 0b)
  --normalize           compare in NFC; what is stored is never normalised
  -A N  -B N  -C N      context in RECORDS, as in grep; blocks separated by --.
                        Giving any of them switches the output to records, at
                        any value including 0 -- the shape follows the flag,
                        not the number. Repeats: the last one wins, and -C sets
                        both sides, so `-C 1 -A 3` and `-A 3 -C 1` differ
  -head N               first N records          (records, not lines)
  -tail N               last N records
  -mid a,b              records a through b, inclusive; `a,` and `,b` are
                        open, and `,` alone is both ends open, which is every
                        record -- the same as `-r`. A range that overruns the end is CLAMPED, not
                        refused, and a start past the end gives empty output
                        at rc=0 -- but it says so: a single WARN line on
                        stderr naming the start you asked for and the last
                        record there is. The WARN goes to stderr whatever
                        output shape was asked for, including -md, which has
                        no meta line to put it in -- it is one line per RUN,
                        not one per shape. It also fires on a file with a
                        header and no records at all, where every window is
                        past the end; until 2026-08-21 that was the one case
                        it missed. `records` on the trailing --json meta line
                        answers the same question for a caller that would
                        rather parse than read stderr -- but only by
                        comparing it against the START you asked for: a window
                        that missed and one that hit and was clamped both
                        report the file's own record count with `matched:0`,
                        and on an empty file it reads `0` either way. The WARN
                        is the one that says which happened. -head and -tail clamp the same way,
                        silently, because clamping an END is what was asked
                        for
  -t                    include the header rows (off by default). It applies
                        to SELECTIONS only -- an edit rewrites the whole file
                        and always writes the headers, with or without -t
  -rownum               prepend a record-number column. It does not change any
                        ADDRESS -- `1:1` still means the first field of the
                        first record on a read; see "Two numberings" below.
                        (This says nothing about what an EDIT does: a -delete
                        renumbers the records after it, and always has. Round
                        75 read this line while asking that question and took
                        it for an answer.) With -o or -so
                        the column is written, header and all, so every
                        address in that FILE is one greater than in the input
                        -- `-get 1:1` on it returns the row number, not the
                        first field. The address-stability rule below is about
                        display flags on a read; this writes a file. Refused
                        with -get and with --json, each of which would ignore it
  --physical            also print the physical line the record starts on, as
                        `record:field@Lline`; with --a1 the two combine into
                        `13:6@L14 [F14]`. The two numbers are the same
                        there only because no record in that file spans lines:
                        with an embedded newline they part company, as in
                        `2:2@L4 [B3]` -- physical line 4, spreadsheet row 3.
                        Both are correct; they answer different questions.
                        Adds to the LOCATING REPORT, so it needs -contains
                        without --filter/-md/--json
  --a1                  also print spreadsheet A1 notation. Same restriction
                        as --physical, and it counts the header rows: data
                        record 1 is A2 in a .csv and A3 in a .csv2

INPUT / OUTPUT
  -i FILE  -o FILE      file paths; -o writes a temp file and renames
  -si  -so              stdin / stdout, without buffering the whole file
  --headers 1|2         required with -si: stdin has no extension, and
                        required with -i when the path does not end in .csv or
                        .csv2 -- and the suffix is matched WITHOUT regard to
                        case, so `DATA.CSV` is read as a `.csv` and needs no
                        --headers. Until 2026-08-25 that check was
                        case-sensitive on the reading side and case-insensitive
                        on the writing side, and the split produced both a
                        message that was false (`-o x.CSV2` refused for
                        "declaring a format with a header" while `-i x.CSV2`
                        was refused for declaring nothing) and a silent record
                        loss: the never-convert guard reads the reading-side
                        test, so writing a one-header input to `.CSV2`
                        succeeded, and on a case-insensitive filesystem that
                        file IS the `.csv2` you read back with a record eaten
                        as its second header row. Case-insensitive matching is
                        still the NAME declaring the format; it is not
                        detection. With -i it
                        is accepted only when it AGREES with the suffix, and
                        disagreeing is refused -- the suffix declares the
                        format. See the warning above. This entry used to end
                        "never combine it with an edit verb", which forbade
                        what its own first line requires: editing a stream
                        needs -si, and -si needs --headers. The disagreeing
                        case is already a refusal; there was nothing else the
                        sentence was guarding
  --in-place            edit -i in place, via temp file + rename -- EXCEPT for
                        -append, which writes O(1) bytes onto the end of the
                        file itself and keeps the inode. So an append is not
                        atomic for a reader, and a crash mid-append can leave a
                        partial record where every other edit would have left
                        the original untouched. `-r -t --truncate-partial`
                        writes a clean copy of such a file. An EDIT:
                        a run with no edit verb is refused, so a SELECTION
                        cannot be written back over its own input. Until
                        2026-08-21 `-head 1 -t -i f.csv --in-place` succeeded
                        and left one record of twenty-two, at rc=0, with
                        nothing on either stream and only the invocation in
                        the log. To crop a file, write the selection to a new
                        file with -o

OUTPUT SHAPE / 輸出形狀
  -md [--pretty]        Markdown table; needs -t. On a .csv2 the two header
                        rows are joined with <br> into one Markdown header
                        cell -- `pkg<br>套件` -- because Markdown has one
                        header row and the data has two; --en or --zh gives
                        one clean row instead.
                        **There is no 200-character cut here.** That belongs
                        to the locating report, which is a preview; -md renders
                        the data, so a 400,000-character cell is a
                        400,000-character line. If the width matters, slice
                        with -mid first.
                        In DATA cells `|` becomes `\|`, `\` becomes `\\`
                        and an embedded newline becomes <br>. **Control
                        characters are escaped the way the locating report
                        escapes them** -- a TAB as `\t`, everything else below
                        0x20 and DEL as `\xNN` -- because -md is read by a
                        person and a control character is not text on a
                        terminal. It passed them through until 2026-08-22, and
                        a licence cell holding `GPL-3.0` followed by seven
                        backspaces and `MIT` then RENDERED as `MIT` while -get
                        returned the real bytes. Note this before writing a
                        checker:
                        splitting a rendered row on `|` counts the escaped
                        ones too and reports an alignment fault that is not
                        there. -md IS reversible as of 2026-08-26: read the
                        table back from a path ending .md. This entry said the
                        opposite until round 78 -- "a cell holding the text
                        <br> and a cell holding a real newline emit the same
                        bytes" was true, and stopped being true when the
                        literal <br> started being escaped. It also told the
                        reader not to do the thing the feature exists for.
                        --pretty pads with spaces, and those pads are escaped
                        on the way out (\x20) so a value's own edge spaces
                        survive; an empty cell and a cell of spaces are still
                        distinguishable, in the file and in --json.
                        --pretty aligns by DISPLAY width and therefore gives
                        up streaming. That width is grapheme clusters with
                        emoji presentation applied, NOT a per-code-point UAX
                        #11 lookup: the latter gets a ZWJ family, a skin-tone
                        modifier and a variation-selector emoji wrong.
                        `-debug` prints the computed column widths, so you can
                        check the alignment instead of counting it by eye
  --md-style S          how `-md` writes the table out: `preserve` (the
                        DEFAULT), `compact`, or `pretty`.
                        `preserve` writes a row back as the exact line it
                        arrived on, so a row nobody edited is byte-identical
                        and the diff is the cells that changed. It needs a
                        `.md` INPUT to copy a layout from; from a `.csv`/
                        `.csv2` there is nothing to preserve and it renders as
                        `compact`.
                        `compact` is `|a|b|` -- the default until 2026-08-29,
                        still reachable by name.
                        `pretty` is `--pretty`, and the two are the same flag
                        spelled twice.
                        The default changed because rendering a padded table
                        back rewrote EVERY row: on a four-row table a one-cell
                        edit arrived as a six-line diff, which buries the real
                        change in a review and makes `git blame` on every
                        untouched row point at an edit that did not touch it.
                        `--pretty` is not the smaller option -- it widens the
                        `|---|` separator to the column widths, so it rewrites
                        the whole table on FIRST contact even when nothing was
                        edited, and it re-flows every row whenever any value's
                        width changes
  --md-table N          read the Nth Markdown table out of a `.md` document,
                        counting from 1. Without it a `.md` input must BE a
                        table and nothing else -- prose around it is refused,
                        naming the line, and so is a file holding two tables.
                        Nothing here picks one for you. Refused on any input
                        that is not a `.md`
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
  -append ROW           append at the end. WITH --in-place, and only there,
                        the new record ends the way the file already does --
                        CRLF into a CRLF file, LF into an LF one, decided from
                        the file's last TERMINATOR and not from its last two
                        bytes, which are the end of a VALUE when the file was
                        cut off mid-record. With -o there is no append: the
                        whole file is rewritten through the normal path, which
                        emits LF, so a CRLF file comes out as LF like it does
                        after any other edit. This entry promised the CRLF
                        behaviour unconditionally until 2026-08-25; a blind
                        round measured -o and got LF.
                        append at the end. O(1) in BYTES WRITTEN, not in time:
                        the whole file is read first, because a file whose last
                        record is incomplete cannot be safely appended to and
                        there is no cheap way to know. Measured linear --
                        0.07 s at 1.9 MB, 0.24 s at 8.2 MB, 0.92 s at 34.6 MB
                        on records of about 77 bytes; the curve is linear in
                        BYTES, so the same sizes in wider records take longer.
                        Until 2026-08-20 the check ran only when the file did
                        not end in a newline, which let an append onto a record
                        left open by an unclosed quote through at rc=0 and
                        produced a file csv2 then refused to read
  -delete a[,b]         delete record a, or records a through b
  -delete -cell r:c     clear one cell (the field count never changes)
  -delete -col N|NAME   remove that column from every record AND from both
                        header rows -- the one deletion that keeps alignment.
                        ONE column, not a list: `-delete -col a,b` names a
                        column called `a,b`, which is also how a name
                        containing a comma is reached at all. A NUMBER is
                        resolved against the file as it is now, so running
                        `-delete -col 1` twice removes two different columns --
                        the second run's `1` is what used to be `2`
  -add-column N NAME [VAL]
                        insert a column at position N, numbered from 1 the way
                        every other address here is. N may be one past the last
                        column, which appends; beyond that is refused, because
                        clamping `-add-column 9` on a two-column file to the
                        end and exiting 0 would hand back a file in which the
                        9 silently meant nothing. NAME carries both titles the
                        way a header row does -- one CSV record, so
                        `'note,備註'` is two fields and a title containing a
                        comma can be quoted like anything else. On a `.csv2`
                        given only the English title, row 2 is left EMPTY and
                        a warning goes to stderr. VAL fills every data row;
                        omitted, they are empty. Cannot be combined with
                        `-delete -col` in one run: both number columns against
                        the file as it ARRIVES, so the same number names two
                        different columns depending on which is applied first,
                        and both readings are defensible. Run them separately.
                        To set one cell afterwards, compose with `-update r:c`.
                        Repeatable: every N counts against the file as it
                        ARRIVED, the way `-insert`'s does, so
                        `-add-column 2 A -add-column 3 B` on a two-column file
                        puts B AFTER the old column 2, not before it
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
                        With -hash it selects HMAC over plain SHA-256.
                        ANY file of at least 16 bytes; its bytes are key
                        MATERIAL, run through a KDF, so there is no format to
                        get right. Make one with
                        `head -c 32 /dev/urandom > key.bin`.
                        Creating protection from fewer than 16 bytes is
                        REFUSED -- a one-byte keyfile used to be accepted
                        silently, and the column came back in 98 tries.
                        Reading a file already made with a short key is not
                        refused: losing data for a security reason is the
                        worse trade
  --yes                 accept the default key without a prompt
  --version  -V         print the version and exit
  --help  -h            print the flag list and exit
  REPEATS               giving a flag that takes a VALUE twice is REFUSED --
                        -i, -o, -head, -tail, -mid, -contains, -get, -hash,
                        -keyfile, -log, --headers and the rest of them -- with
                        -A/-B/-C the documented exception, where the last one
                        wins. A repeat is refused rather than taken once
                        because the second value may have been meant to change
                        something: the same reason `-hash note -hash ver` is
                        refused rather than leaving `note` in plaintext at
                        rc=0. `--en` with `--zh` is refused too: they are two
                        answers to one question.
                        A repeated BOOLEAN is accepted and does nothing --
                        `-r --json --json` is `-r --json`. It carries no second
                        value to lose, so the reason above has nothing to bite
                        on. This entry said "every flag" until 2026-08-22,
                        which is a promise the program does not keep for the
                        sixteen boolean flags
  --                    the NEXT argument is data, not a flag: write a value
                        that begins with a dash as
                        `-update 1:2 -- --in-place -i f.csv -o g.csv`.
                        The destination is part of the example because typed
                        without one it refuses -- an edit needs somewhere to
                        go -- and this file has printed runnable-looking
                        fragments that were not before.
                        It is not "everything after this is data" -- flags that
                        follow are still flags, which is what lets `-i` and
                        `-o` come after the value in the same command
  a value that looks    only a KNOWN flag name is refused in a data position:
  like a flag           `-5 degrees`, `--nope` and `-` are written as data,
                        while `-r` is refused and told about `--`. So a script
                        breaks on the day its data equals a flag name, not
                        before -- and the refusal names the way through

COLS is a comma-separated list of column names, 1-based column numbers, or a
mix: `-hash license`, `-hash 7`, `-hash 6,license`. Four refusals go with it,
all of them cases where guessing would be worse than stopping:

- **An empty list is refused.** `-hash ""` used to exit 0 having protected
  nothing at all; "no columns" and "a variable that came out empty" cannot be
  told apart, and one of them leaves the file unprotected while every check
  reports success.
- **A token that is both a column number and a column name is refused.** On a
  file whose columns are called `2` and `1`, `-hash 2` cannot be resolved
  without guessing which the caller meant. Rename, or use a number that is not
  also a name.
- **A comma inside a name has no escape**, because the list separates on
  commas. Reach such a column by its NUMBER, or with `-delete -col`, which
  takes exactly one name and therefore takes the comma with it.
- **A name that matches more than one column is refused**, naming both
  positions rather than picking one — the duplicate-header rule further down,
  which applies here too. This paragraph said "three" until 2026-08-21 while
  the fourth was implemented, tested and documented elsewhere.

Asserted by T140 and T144.

INDEX / 索引
  --no-index            never read or write a .index sidecar. The sidecar is
                        the whole filename plus ".index": packages.csv ->
                        packages.csv.index, pkgs.csv2 -> pkgs.csv2.index
  --build-index         build the sidecar now, at any file size. Otherwise one
                        only appears as a SIDE EFFECT, and only at or above
                        CSV2_INDEX_MIN_BYTES: a REWRITING edit builds one,
                        -tail builds one because it must read the whole file
                        anyway, and `-append --in-place` builds one for the
                        same reason -- it reads the file to the end to prove
                        the last record is complete. So -mid alone never
                        produces one, and nothing produces one for a small
                        file unless you ask. An existing index is EXTENDED by
                        an append rather than rebuilt.
                        Until 2026-08-21 the append was the exception, on the
                        grounds that its fast path never read to the end; that
                        had not been true since the unclosed-quote check was
                        added, and the cost of the entry above is a grid point
                        per 256 records on a scan that was happening anyway.
                        The build-index cost is the SCAN: 505 ms on 17.7 MB /
                        450,000 records. What it BUYS is the difference between
                        an indexed window and an unindexed one -- about 4 ms
                        against 179 ms measured here -- so it pays for itself
                        in about three windows, not the 130 this entry said
                        until 2026-08-22. That number divided the cost by the
                        cheap operation instead of by the saving, in a
                        paragraph whose point is that the index is expensive
  --verify-index        O(n) full check of all four of the index's claims --
                        the grid offsets, the line each grid point names, the
                        record count, and whether any record spans lines.
                        The line was added to the format on 2026-08-20 and to
                        this proof on 2026-08-21; in between, an index with a
                        wrong line passed. It is not free: 451 ms on 17.7 MB /
                        450,000 records, more than the 204 ms search it is
                        protecting. The O(1) check on the normal path
                        is deliberately a heuristic, not a proof.
                        Exit 0 when the index is there and accurate, 1 when
                        there is none or it cannot be used. It runs the O(n)
                        comparison only when the cheap stamp already agrees:
                        an index the stamp rejects is reported unusable
                        WITHOUT being compared against the data, and says so.
                        That exit 1 is about this command, which was asked to
                        prove the sidecar; on every other path an unusable
                        sidecar is discarded for a scan and is not an error.
                        There are TWO exit 1s and they mean opposite things
                        about whether the data was read: the unusable case
                        prints nothing on stdout, while an index the stamp
                        accepted and the data contradicts prints one
                        `index MISMATCH:` line per failed claim on stdout --
                        thousands of them on a large shifted index -- before
                        the two-line refusal on stderr. Empty stdout means the
                        sidecar was never compared

DIAGNOSTICS / 診斷
  -debug                diagnostics to stderr, including a metrics: line on
                        every path -- reads, writes, and both index commands.
                        A refusal prints none, because that line belongs to a
                        run that did work. It was missing from the writes and
                        from --build-index/--verify-index until 2026-08-22,
                        which is five paths of ten, and the missing half was
                        the one whose cost a caller most wants to see. That line is
                        `read_bytes=N file_bytes=N peak_rss_bytes=N`:
                        read_bytes is what was actually pulled off the disk
                        and file_bytes is the input's size. Reads are 64 KiB at
                        a time and the last one is short, so on a 17.5 MB file
                        of 450,000 records:
                          -r                          17550004  (the file)
                          -mid 2,3 --no-index            65536  (stopped early)
                          -mid 200000,200000 --no-index 7864320 (scanned there)
                          -mid 200000,200000           65536    (index seek)
                          -tail 1                        8112   (seek near EOF)
                        **read_bytes < file_bytes means the run did not have
                        to touch the whole file**, and that is the claim this
                        line supports. Anything more precise has been wrong
                        three times: this entry said whole buffers ALWAYS until
                        2026-08-21, NEVER on a seek until 2026-08-22, and then
                        that a seek and an early stop are indistinguishable --
                        which the third and fourth rows above disprove. Each
                        version was a rule generalised from whichever examples
                        were at hand; the numbers are the measurement, and the
                        sentence under them now claims only what they show.
                        Measure with it rather than guessing:
                        23 MB of peak RSS on a 615 MB file in parallel, 9.5 MB
                        single-threaded over the same file. Until 2026-08-20
                        the parallel figure was 608 MB -- one byte resident per
                        byte of input. The parallel figure GROWS with the file
                        and the single-threaded one does not: 17 MB at 192 MB,
                        23 MB at 615 MB, 57 MB at 2.1 GB, against 9.4 MB
                        single-threaded at every size. Quote it with the size
                        it was taken at or it means nothing. See the
                        parallelism section
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

**The cut bounds the VALUE, not the line.** 200 characters of the value are
kept and `N` counts the characters dropped — both before escaping. Escaping
happens afterwards, so a value made of control characters still produces a long
line: 200 raw characters can become 800 written ones. `\xNN` is written with
the hex in upper case. If you are measuring a length from this column, add
`preview` and `N` in RAW characters and do not measure the bytes on the line.

**"Character" here means a GRAPHEME CLUSTER** — the same unit `--pretty`
measures with, and the reason a family emoji counts as one. Five of them past
the cut report `[+5 more chars]`, not 35 (Unicode scalars) or 55 (UTF-16
units), and the cut never lands inside a cluster.

Three fields separated by a **TAB**: the address, the column name, the value.
One line per matching **cell**, so two matching columns in one record print two
lines, while the same string twice inside one cell prints one. In a script,
`cut -f1`, `cut -f2`, `cut -f3`.

**Values are escaped**, using the same backslash convention `.csv2` uses plus
`\t`: a literal tab becomes `\t`, a newline `\n`, a carriage return `\r`, a
backslash `\\`. **Every other control character becomes `\xNN`**, because this
report is printed to a terminal and a control character is not text there: a
cell holding `ESC [ 3 1 m` used to recolour the output from inside the third
column, and an ESC can also erase the line it is being printed on — the line
carrying the address. Asserted by T149. Without that a cell containing a tab or a newline would break
the format the report promises — and quoted prose containing both is exactly
the data this tool was written for.

**So the third column is for reading, not for feeding back.** It is a display
form: escaped so the report stays one line per hit. `-update` takes a *logical*
value and escapes it for you, so handing it the escaped text writes the
backslashes themselves — `X⏎Y\Z` becomes the seven characters `X\nY\\Z`, at
rc=0, and nothing says so. **What composes is the ADDRESS.** To carry a value
across, read it with `-get`, which returns the stored bytes:

```sh
set -o pipefail                                              # or the refusal vanishes
addr=$(csv2 -contains -- "old" -i f.csv2 | head -1 | cut -f1)   # 12:6
val=$(csv2 -get "$addr" -i f.csv2)                           # the value itself
csv2 -update "$addr" -- "$val" -i f.csv2 --in-place          # round-trips
```

**Two things in that first line are load-bearing.** The `| head -1` makes the
pipeline's exit status `head`'s, so a csv2 that REFUSED exits 0 as far as the
script is concerned and `addr` is empty — indistinguishable from "not found",
which most maintenance scripts treat as "nothing to do" and skip. `pipefail`
(or capturing the output before slicing it) is what keeps the refusal. And the
search string sits in a DATA position like any other: `-contains --in-place`
is refused as a flag in a data slot, so a script whose data can equal a flag
name needs the `--` on the search too, not just on the value. Both were missing
from this recipe until 2026-08-22, and a round following it verbatim reported
"no cell contains --in-place" about a file whose record 3 contains exactly
that.

Asserted by T96 — **for the tool. The shell in the middle is the part that
loses data**: `$( )` strips every trailing newline, so a value ending in one
comes back one byte shorter and is written back that way, at rc=0, with nothing
to see. csv2 handed over the right bytes and got different ones back. When a
value may end in whitespace, carry it through a file instead, or pin the end:

```sh
val=$(csv2 -get "$addr" -i f.csv2; printf x)   # x guards the value's own tail
val=${val%x}                                   # drop the guard
val=${val%$'\n'}                               # drop the newline -get itself adds
```

All three lines are needed and the third is the one that is easy to miss: this
recipe was published here on 2026-08-21 without it, and writing the result back
grew a value ending in a newline by one more each time, at rc=0. `-get`
terminates its output with a newline like every other command; `printf x`
protects the value's trailing newline and `-get`'s along with it.

**And there is a second thing in the middle, which the three lines above do
not fix: the command line itself.** A shell variable can hold a NUL byte;
`execve` cannot pass one. The argument stops at the first NUL, so a value with
one in the middle arrives at csv2 already cut short, and csv2 writes exactly
what it was handed:

```console
$ printf 'pkg,note\nzlib,before\x00after\n' > nul.csv
$ val=$(csv2 -get 1:2 -i nul.csv; printf x); val=${val%x}; val=${val%$'\n'}
$ csv2 -update 1:2 "$val" -i nul.csv --in-place; echo $?
0
$ csv2 -get 1:2 -i nul.csv | od -t x1 | head -1
0000000 62 65 66 6f 72 65 0a               # "before" -- six bytes gone, rc=0
```

**csv2 cannot see this.** The truncation happens before the process starts,
and a shorter value is indistinguishable from a deliberate edit. It is the
same boundary the refusals table already guards for a value that is not valid
UTF-8 — and the same remedy: **carry the value through a file, where bytes
survive.** The refusal exists for the case that mangles one character and
there is nothing to refuse in the case that drops the rest of the value.
`-log` records what was actually written (`"before\x00after" -> "before"`),
which is the only place the loss is visible.

**The report's own values are for reading, and this is a third reason:** `-get`
is the only shape that hands you the stored bytes, and even it is at the mercy
of what you pour them into.

**An address is only as current as the file it came from, and there are two
ways it can be wrong without anything saying so.**

The first is a stale sidecar. If a `.index` file sits beside the data and the
data has since changed in a way the O(1) stamp cannot see — same size, same
mtime, same first and last bytes — the search trusts it and can report a record
number that is off. The three commands then all exit 0 and the edit lands on a
neighbouring record. Two ways to make that impossible, and they are priced
differently:

```sh
csv2 --verify-index -i f.csv2          # O(n): prove the sidecar first, exit 1 if not
csv2 -contains "old" --no-index -i f.csv2   # or do not use one at all
```

On 17.7 MB / 450,000 records: proving the sidecar costs 451 ms and the search
that follows 204 ms, so 655 ms; not using the index costs 528 ms. **For a
single search, proving it first is the more expensive of the two.** It wins
from about the second search onward, because the proof is paid once. Both were
called "cheap" here until 2026-08-21, which is doing work the numbers do not
support.

**The second is simpler and neither of those touches it: somebody edits the
file between your two commands.** The address was true when `-contains` printed
it and describes a different record by the time `-update` runs. csv2 has no way
to see that — each command opens the file fresh, which is what makes it safe to
run at all — so if a file can change under you, either serialise the writers or
carry the VALUE rather than the address:

```sh
csv2 -update "$addr" "$new" -i f.csv2 --in-place    # trusts the address
csv2 -contains "$old" -i f.csv2                     # or re-find, and accept a race you can see
```

`--no-index` is the flag for "refuse to trust a sidecar"; it is listed under
the index flags and named here because this recipe is where it matters.

**A write repairs the sidecar, which erases the evidence — on a file large
enough to have one built.** If a stale index sends an edit to the wrong record,
the edit rewrites the file and builds a correct sidecar as it goes, so
`--verify-index` afterwards says `index OK` at exit 0, about the file you have
just damaged. Below `CSV2_INDEX_MIN_BYTES` the write does not build one, so the
stale sidecar is left where it is and `--verify-index` still exits 1 — the
evidence survives on small files and not on large ones. Either way: verify
BEFORE the edit, not after.

**`-contains`, `-mid` and `-tail` read the sidecar; `-get` and the edit verbs
scan.** So a stale index can make either half of the recipe wrong, and which
one depends on how you found the address: the search's record number can be
off, and a `-mid` window can start on the wrong record, while the `-get` or
`-update` you hand the address to works perfectly on whatever record that
address now names. Each command is behaving correctly and the pair disagrees.

*(This paragraph said "only `-contains`" until 2026-08-21. It was written from
a blind round's report and never measured; the next round measured it and found
`-mid` taking an index hit. The lesson is the one this file keeps recording:
a sentence about behaviour, taken from a report and not run, is a guess.)* See
**The index sidecar** below for what the stamp can and cannot notice.

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

**And it can take a hit away, not only add one.** Because the fold applies to
the cell as well, a match that existed only in the stored bytes stops existing:

```console
$ csv2 -contains cafe -i acc.csv          # no --normalize
1:2  word  cafe
3:2  word  café                            ← the NFD cell; its bytes literally
                                             start c-a-f-e, then U+0301
$ csv2 -contains cafe --normalize -i acc.csv
1:2  word  cafe                            ← that hit is gone
```

Both answers are right for the question each was asked, and the second is the
one you almost always want — an ASCII `cafe` is not the word `café`. But the
paragraph above describes only the widening, and round 76 pointed out what
follows from that: a script that adds `--normalize` defensively, expecting it
to find strictly more, can silently find less. Decide which comparison you
want; do not add the flag as insurance.

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

**The other direction is the same rename and the same damage**, and this
document described only one of them until 2026-08-21. A `.csv2` handed to you
as `.csv` loses nothing and gains a record: its row of Chinese titles becomes
data record 1, searchable and addressable, at rc=0. `--json`'s meta line
cannot tell you — it reports `{"format":"csv","headers":1}`, which is true of
the NAME and says nothing about the content. Looking is again the only check:

```console
$ csv2 -mid 1,1 -t -i handed-to-me.csv       # is record 1 a row of titles?
pkg,ver,note
套件,版本,備註                                <- titles sitting in the data
```

### A UTF-8 BOM is stripped; a UTF-16 one is refused

A file that opens with a **UTF-8** BOM — anything exported by Excel, typically —
has it removed on read and not written back. **Exactly one is removed**: a
second BOM is a zero-width no-break space in the first column's name, which is
data, so it stays in the output. It is stripped from the name used for
ADDRESSING, though, which is why `-get 1:a` still works on such a file while
the header written out still carries it.

**A UTF-16 BOM is a different file and gets a different answer: refused, with
the conversion named.** `FF FE` and `FE FF` cannot begin a UTF-8 file, so this
is not a guess. csv2 reads bytes and does not convert encodings; left to
itself it would read a UTF-16 file byte-transparently — correct for a tool that
promises bytes round-trip, and useless to the person holding it, because every
second byte is NUL, the column names carry them, and the whole thing parses at
rc=0 into records that mean nothing.

**The guard is the BOM and only the BOM.** A UTF-16 file saved without one may
parse at rc=0 into records that mean nothing, and csv2 has nothing to detect it
by that would not also misfire on legitimate data. It may equally fail with a
message about field counts — the NUL bytes make the columns come out uneven —
which is an accident, not a check: do not read that error as csv2 having
noticed the encoding. If you are handed UTF-16, convert it; do not rely
on being told.

**A blank line anywhere is refused — in a file with two or more columns**,
including the one a file ending in two newlines has: `record 2 (line 3) is a blank line, and a blank line is not a
record with 2 empty fields; remove it`. Every other CSV reader has an opinion
here and they differ — skip it, return one empty field, return N empty fields —
and each of those quietly changes what record 3 is.

**In a ONE-column file there is nothing to refuse:** a blank line and a record
holding one empty field are the same bytes, so it is read as a record. Write
`""` on that line if you want the file to say which it means — it reads
identically and cannot be mistaken for anything else.

**A `.csv2` must end with a newline; a `.csv` need not.** One record per line is
what `.csv2` means, so a file that stops mid-line has a torn last record and is
refused, naming `--truncate-partial` as the way to discard it. A `.csv` with no
final newline is ordinary — plenty of tools write one — and is read as it
stands.

**A bare CR inside an UNQUOTED field is data, and this is where csv2 differs
from most parsers.** `1,x<CR>y` is one record with the value `x<CR>y`; Python's
`csv` module reads it as two rows. Neither is wrong — RFC 4180 defines the
record separator as CRLF and says nothing about a lone CR mid-field — but a
script that compares counts across the two will see the difference. Inside
QUOTES a CR is data everywhere. The promise holds for however many CRs a
record carries — until 2026-08-21 a third one tipped a count and the same
record was refused — and it holds for a record but not for a column NAME: a
bare CR in the header row is how a CR-terminated file looks, and it is refused
(see above). Quote the field and the CR is a name again.

**NUL and the other control bytes are accepted verbatim** in file content:
they are data, they round-trip, and the locating report escapes them for
display. **In file content** is the whole of that promise: a NUL cannot reach
csv2 through an argument at all, because the command line stops at the first
one — see the compose recipe above.

**A zero-byte file is refused too**, with `expected 1 header row(s), found 0` —
a file with no header does not declare its own shape, and guessing one is how a
data row becomes a header. So is a file that is nothing but a UTF-16
byte-order mark, which is what an editor writes for an empty document saved as
UTF-16: two bytes, semantically the same empty file, and until 2026-08-21 it
was accepted as a one-column CSV whose column name was those two bytes (T162).

```console
$ csv2 -r -i export.csv
csv2: this file begins with a UTF-16LE byte-order mark; csv2 reads bytes and
does not convert encodings, so it would parse as records that mean nothing.
Convert it first with: iconv -f UTF-16LE -t UTF-8 file > converted.csv -- the
new name has to keep a .csv or .csv2 suffix, because the suffix is what
declares the format
```

**A gzip file gets the same treatment.** `1f 8b` cannot begin a UTF-8 CSV any
more than `ff fe` can, and one named `.csv` was read at rc=0 as a single record
of binary until 2026-08-25 — `-contains` searched it and reported finding
nothing, which is the answer this tool exists not to give. The refusal names
`gunzip -c`.

**CR line endings get the same treatment** — the pre-OS X Mac convention, which
CSV does not support. **There are two checks, because there are two shapes.**
The first is a bare CR in the HEADER row, and it is
exact rather than approximate: a file whose lines end in CR has no LF to end
its first line, so everything it contains lands in the first record, and the
column names are where the evidence always is.

The check has been wrong twice, in opposite directions, and both are worth
knowing because they say what the rule is not:

- It first asked whether there was *no* LF at all, and one trailing LF
  silenced it: the file read as **zero records at rc=0**.
- It then asked whether bare CRs **outnumbered** LFs, which is a count and not
  a fact about line endings. `a,b⏎1,x␍␍␍y⏎` — one record, LF-terminated — was
  refused with a message stating it "uses CR line endings", and the `tr '\r'
  '\n'` that message prescribes turned that record into a file csv2 will not
  read. In the other direction, `col␍"L⏎L⏎L⏎L"␍zz␍` — a genuine CR-terminated
  file — has three CRs and three LFs, so the count never fired: it was read at
  rc=0 as three records under a column named `col␍"L`, the quoted field torn
  down its own newlines, nothing on stderr.

The second is **the file's last byte being a bare CR**, which is what a
CR-terminated BODY under a normally-terminated header looks like — what
`(echo a; cat old_mac_body) > f.csv` produces. The header check cannot see that
file, and until 2026-08-25 it read as ONE record at rc=0 with `records:1` on
the meta line: every count in it wrong by the number of lines in it, and the
documented presence test reporting the wrong number confidently.

A bare CR inside a RECORD is still data, still round-trips, and is still left
alone — a file ending with a newline is never refused, whatever its records
contain. If a CR really is the last byte of your last value, end the file with
a newline and it is read as data. A CR that really belongs to a column NAME has to be quoted — one pair of
quotes, and the intent is explicit. Asserted by T115 and T180. What matters more than either is
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
$ csv2 -get 1:2 -i pkgs.csv | od -c            # cell is "value ends here\n"
0000000   v   a   l   u   e       e   n   d   s       h   e   r   e  \n
0000020  \n
0000021

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
| old and new values in an **ordinary** column | in full, never truncated; that is the point of an audit trail. This covers `-update` and `-delete -cell` alike — blanking a cell records what was in it |
| old and new values in a **protected** column | `<redacted>`, including inside a deleted record |
| a deleted **record** | its contents, column by column: `delete record 2: "a"="4", "b"="5", "c"="6"`. The largest thing this tool destroys, so the entry says what was in it. **The column names are quoted too** — a name can contain a comma or an `=` — and this example showed them bare until 2026-08-22, which is enough to mis-split the line in a parser written from it |
| a deleted **column** | the column name, not its values — one entry for the run rather than one per record, because the values are the whole column |
| `-hash` and `-encrypt` | which columns, and which key. Unkeyed hashing says so in as many words: `hashing columns notes with NO key (unsalted SHA-256)` |
| a sidecar this run wrote | `wrote index /path/to/f.csv.index: N records, stride 256, M entries` — the only log line carrying an absolute path, and the only one about a file other than the input |
| the outcome of the run | `wrote N records, M fields, atomic rename OK` — the line that says the write completed, and the one to look for when asking whether an edit landed. **`M` is the row WIDTH, not the number of fields written**: a 3-record 3-column file says `3 records, 3 fields`, and a 22×7 one says `22 records, 7 fields` |

**One entry is one line, and every line is escaped to keep it that way.** A
newline, tab, CR or backslash is written as `\n`, `\t`, `\r` or `\\`, and
**every other control character becomes `\xNN`, hex in upper case** — the same
convention the locating report uses, described in one place and not the other
until 2026-08-21. A value carrying an ESC arrives as `\x1B`. Without
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
regex could recover the truth. Asserted by T106. Unescape the line first —
`\n`, `\t`, `\r`, `\\` **and `\xNN`** — then read the quoted fields. A reader
written to the shorter list, which is what this paragraph gave until
2026-08-21, rebuilds a value carrying an ESC as six literal characters and
reports a mismatch that is not there.

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

Those loops print **nothing** — csv2 prints nothing on the normal path — so the
markers have to be read out of the files afterwards:

```console
$ for i in 1 2 3; do csv2 -encrypt secret -keyfile k.bin -i s.csv -o e$i.csv -t; done
$ for i in 1 2 3; do csv2 -contains ':enc:' --include-headers -i e$i.csv | cut -f3; done
secret:enc:d88cdbf1:…      # one keyfile,
secret:enc:e16b394a:…      # three runs,
secret:enc:869e54ce:…      # three fingerprints

$ for i in 1 2 3; do csv2 -hash secret -keyfile k.bin -i s.csv -o h$i.csv -t; done
$ for i in 1 2 3; do csv2 -contains ':hmac:' --include-headers -i h$i.csv | cut -f3; done
secret:hmac:9acc9081       # the same number every time; a different keyfile changes it
```

An earlier version of this section showed those markers as the output of the
loops themselves. They are file *headers*; a reader who ran the loop verbatim
got a blank screen and no way to tell whether anything had happened. It is the
same mistake this document owns up to in the `-log` section, made twice more
here, and it survived until a reader ran the loop instead of reading it.

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

**What the log does not record, and a second reader cannot recover:**

| Not in the trail | Why it matters |
|---|---|
| the working directory, and the `-i` path as an absolute one | two runs of `csv2 -update 1:2 X -i f.csv --in-place` from different directories, into one shared log, are the same three lines. The `-log` path IS absolute; the input path is quoted as typed |
| a process id, or any ordering key | two concurrent writers each log `wrote N records … rename OK`, and one of the two edits is not in the file. The lines cannot be paired with their `update` lines |
| the destination of a write | `wrote N records` names no file, and `-o` onto an OCCUPIED path destroys what was there while the trail reads exactly as it does for a new file |
| that an index was TRUSTED | the one branch that can be silently wrong (see the sidecar section) says so under `-debug`, on stderr, and nowhere else |
| what a search found | a `-contains` run logs its invocation only, so the address a later `-update` consumed has no provenance |
| that every line ending in the file was rewritten | on a CRLF input the trail reads `update 1:note: "alpha" -> "ALPHA"` — one cell — while `diff` reports every line changed, because an edit rewrites each record separator to LF. This is the one that makes the trail UNDERSTATE the change rather than merely omit context, and a second reader reconciling the trail against a diff cannot do it. See the CRLF note further down: a checksum or a `diff` across an edit of a CRLF file is measuring the terminators |
| who | nothing in the trail says which account ran it. Defensible for a single-host tool, and still the first question anyone asks of an audit trail |

None of these is a defect on its own; together they are the reason the trail
answers "what did this run do" and not "what happened to this file". The last
two were added on 2026-08-26; round 76 pointed out that a table presenting
itself as the list of what a second reader cannot recover had better be
complete, and that the CRLF one is worse than the five above it.

### Two numberings, and where they disagree

`-rownum` prepends a column. Everything else keeps the numbering it had:

```console
$ csv2 -contains busybox -i pkgs.csv
1:1	pkg_name	busybox
1:3	source	fork raliclo/busybox, branch develop
$ csv2 -contains busybox -rownum -i pkgs.csv
1:1	pkg_name	busybox
1:3	source	fork raliclo/busybox, branch develop

$ csv2 -r -t -rownum -i pkgs.csv
rownum,pkg_name,version,source,license
1,busybox,1.37.0,"fork raliclo/busybox, branch develop",GPL-2.0
```

(Two hits, because the `source` field on that row contains the word too — this
block showed one until 2026-08-21, on a fixture whose own printed content says
otherwise.)

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
are text like any other. `--include-headers` includes them. On a `.csv2`, which has two
header rows, they are addressed `0a` for the first and `0b` for the second, so
that a hit in the English title row and one in the Chinese title row are
distinguishable. On a `.csv` there is one header row and it is plain `0` — a
script matching `^0[ab]:` will miss every header hit in a `.csv`:

```console
$ csv2 -contains note --include-headers -i pkgs.csv2
0a:3	note	note
$ csv2 -contains 備註 --include-headers -i pkgs.csv2
0b:3	note	備註
$ csv2 -contains 備註 --include-headers --zh -i pkgs.csv2
0b:3	備註	備註
```

```console
$ csv2 -contains name --include-headers -i pkgs.csv     # one header row
0:1	name	name
```

In `--json` the same distinction is a `header_row` key — `"0a"`, `"0b"` or
`"0"` — present only on a header hit. Until 2026-08-21 both rows came out as
`"record":0` and the only discriminator left was the physical line, in the
output shape meant for programs, under the very sentence that gives
distinguishability as the reason the two labels exist.

**A header hit does not count as a match.** `matched` on the trailing `--json`
meta line counts matching RECORDS, and a header row is not a record — so a run
that prints `0a:3 note note` reports `"matched":0`. That is consistent with
every other place csv2 draws the line, and it means the documented presence
test (`read matched from the meta line`) answers "nothing found" for a hit it
just printed. Count the hit lines instead when `--include-headers` is in play.

Two further consequences of a header row not being a record: `-A`/`-B`/`-C`
context never enters the header rows, and `--filter --include-headers` emits a
matching header row **as a record** — with `-t` the header then appears twice
in the output, once as the header and once as data. csv2 reads that back
correctly, and it is still worth knowing before piping it anywhere.

None of these is addressable by a verb, in any spelling: `-get`, `-update` and
`-delete -cell` all refuse `0:`, `0a:` and `0b:` with the same sentence, which
says why rather than complaining about the shape of an address csv2 printed
itself. Asserted by T132 and T186.

The middle field is the column's name **in the language you asked for**, not the
name from whichever header row matched. That is why the second line says `note`
while the value beside it is Chinese: the row that matched was `0b`, but the
report was not asked for Chinese names. `--zh` changes the name and nothing
else. Asserted by T66.

**That `cut -f3` has no `-d`, and the omission is the whole point.** It is
cutting on TAB, because the locating report is TAB-separated with its values
escaped. Do not reach for `cut` against `--filter` or `-mid` output: that is
CSV, a value may contain a comma, and `cut -d, -f3` will hand you a fragment
of one — silently, at exit 0. On this project's own fixture
(`test/fixtures/TARGET_PACKAGES.csv`), `cut -d, -f3` on the first data line
returns 7 bytes where `-get 1:6` returns a 513-byte cell. That failure is why
csv2 exists; getting it from csv2's own output would be a poor joke. The
numbers here were "104 bytes of a 515-byte cell" until 2026-08-21, with no
fixture named — unreproducible, in the paragraph about not trusting a
plausible-looking fragment. Asserted by T65.

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
$ csv2 -contains busybox --json -i test/fixtures/TARGET_PACKAGES.csv
{"meta":{"format":"csv","headers":1,"fields":7}}
{"record":1,"field":1,"header_en":"pkg_name","value":"busybox","line":2}
{"record":1,"field":4,"header_en":"source","value":"fork raliclo/busybox …"}
{"meta":{"records":21,"matched":3}}
```

The path is spelled out because the counts depend on it. The parent project
keeps its own working copy of that file and it has moved on — 22 records at the
time of writing — so a reader who runs this against that copy gets a different
number and has no way to know which of the two the example meant. Asserted by
T113: the count in this block is checked against the fixture on every run.

JSON Lines. The **first** line is metadata describing the format csv2 believes
it is reading, so a caller can assert `headers` is what it expected instead of
accepting a wrong guess. The **last** line carries the counts: they cannot be
in the first line without reading the whole input before emitting anything,
which is the streaming guarantee.

**In the LOCATING REPORT on a `.csv2`, each object carries a sixth key,
`header_zh`**, holding the second header row's name for that column — the
example above is a `.csv`, which has five. `--en` and `--zh` change the middle
field of the plain locating report and change nothing here: both names are
carried, because a consumer that wanted one of them can pick, and one that
wanted the other cannot invent it.

**In a SELECTION** — `-r`, `-head`, `-tail`, `-mid` — a record object keys
`fields` by the first header row, and a JSON object cannot hold two values
under one key. The second row therefore travels on the **meta line**, as an
array in column order:

```console
$ csv2 -r --json -i example.csv2 | head -1
{"meta":{"format":"csv2","headers":2,"fields":3,"header_zh":["套件","版本","備註"]}}
```

An array rather than an object because the second row is positional: it may
legitimately repeat a name, which an object cannot hold. It is on the meta line
rather than in every record because the names do not vary by record, and
repeating three strings 450,000 times is the kind of output this tool refuses
elsewhere.

Until 2026-08-26 this paragraph said "`--json` always carries both names" and
that was true only of the locating report. On a `.csv2` there was no way to
obtain the second header row through `--json` at all — a consumer that wanted
the Chinese titles had to parse the raw header row, which is the thing this
tool exists to stop people doing. Round 77 measured it; the meta key is the fix,
not a smaller promise.

**A value that is not valid UTF-8 is refused, not substituted.** JSON is
defined over text, so those bytes cannot be carried: the decoder would put
U+FFFD where they are and the line would still be valid JSON — data loss that
looks exactly like success, in the shape this document recommends when the
value is what matters. `-get` and the CSV shapes hand back the bytes and the
locating report names them as `<non-UTF-8: 63 61 66 e9>`. **`-md` substitutes
U+FFFD and says nothing**, and that is deliberate: it is a rendering, not a
round trip, and `--pretty` even pads the column to the substituted width. Do
not read a value back out of `-md` — T136 says the same thing about `<br>`.
Asserted by T158 and T164.

**The last line is absent when the stream is cut short** — a reader that left
(exit 141), or a `-so` edit that failed after emitting records. There is no
in-band marker for that: if the counts matter, check that the last line you
received is a `meta` object rather than assuming it is.

Read those two counts precisely. `records` is the highest data record number
**reached**, not how many the file holds and not how many were parsed —
`-mid 5,5` on a 21-record file reports 5, because it stopped there. On a path
that uses the index the difference matters: `-tail 1` on a 600,000-record file
reports `records:600000` after seeking, reading a few kilobytes and parsing one
record. It is the position it got to, which is what makes it the answer to
"did my window exist" and not an answer to "how much work was done". `matched` counts matching **records**, while the
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

`-md` emits a Markdown table, and since 2026-08-26 csv2 reads one back — from a
path ending `.md`, which is what declares it. Writing a table to a `.csv`/`.csv2`
path with `-o` is still refused, because those suffixes declare CSV and the
bytes would not be; if you route around that with `-so` and a shell redirect,
reading the result back as CSV is refused too: a one-column file whose record is
a Markdown separator row is `-md` output, not CSV, and the message says so —
and now also says to rename it `.md`. Asserted by T74.

### In a pipeline

`-si` and `-so` compose with every verb, and `--headers` has to say what the
format is, because stdin has no suffix to declare it:

```console
$ cat packages.csv | csv2 -si --headers 1 -contains busybox --filter -so
busybox,1.37.0,"fork raliclo/busybox, branch develop",GPL-2.0
```

**Four things ARE different in a pipeline**, and the sentence above used to
claim otherwise ("there is nothing special about a pipeline except that stdin
has no suffix"), which round 76 measured and disagreed with:

| | |
|---|---|
| no parallel search | chunking needs to seek, so `-contains` on a stream is single-threaded whatever the size. The same bytes as a file with an index say `parallel: 8 chunks, 10 workers`; piped in they say `single-threaded: stdin` |
| no index, read or written | a sidecar sitting beside the file the bytes came from is not consulted — a stream has no path and cannot seek |
| `--build-index` is refused | it needs `-i FILE`; there is nothing to build a sidecar beside |
| output is buffered by block, not by line | the paragraph below |

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

`0` on success, non-zero on any error. **With `-o` and `--in-place`, csv2 does
not partially succeed**: the output is a temp file that is renamed only when
everything worked, so a failed run leaves the destination untouched.

**`-so` is the exception, and it is not a small one.** A stream cannot be taken
back. An edit whose address turns out to be past the end is only discovered
when the end is reached, and by then the records before it have already gone to
stdout: measured, a failing `-update` on a 19.5 MB file wrote 198,349 valid
records and then exited 1, where the same command on a 12 KB file wrote none,
because everything still fitted in the buffer. So a `-so` run that exits
non-zero may have produced output, and how much depends on the size of the
file. If that matters, write to `-o` and move the file yourself.

**There is one exit status that is neither, and a pipeline meets it constantly:
141.** When the downstream consumer of `-so` goes away first — `| head -1`, a
reader that stops early — csv2 dies of `SIGPIPE` and exits `128 + 13 = 141`. It
prints nothing, leaves nothing behind, and does not drain the input first: on a
400 MB stream, `| head -1` returns in 0.04 s where `| wc -c` takes 9.7 s. That
is correct Unix behaviour and not a csv2 error, so **a caller that treats every
non-zero status as "csv2 failed" will misreport a perfectly ordinary
`| head`.** Check for 141 explicitly if your script cares — but note that 141
is a property of the OUTPUT SIZE, not of the command: the same pipeline gives 0
on a small file, because everything fit in the 64 KiB buffer and was written
before the reader left, and 141 on a large one.

**141 means only that, and a write that fails for any other reason is an
error.** A full disk under `-so` used to produce 141 as well, with nothing on
stderr and a half-written file on disk — indistinguishable from the benign case
above, in the one status this section tells you to disregard. A write that
fails because the destination is full, the descriptor is closed, or the device
errors now exits `1` and names the destination in the usual two lines. Asserted
by T131; the disk-full reproduction is in `todo/known-defects.md` (DV).

**Every refusal exits `1`, and there is nothing else to tell them apart by.**
Measured across 28 distinct refusals: exit status `1` every time, exactly two
stderr lines every time, nothing on stdout, no error code, no category token,
no stable grammar. **The two-line count is the count WITHOUT `-debug`.** A
refusal detected after the arguments are parsed comes after whatever `-debug`
has already printed, so `csv2 -update 99:1 X -i f.csv -so -debug` puts three
lines on stderr and more with a longer run. The `metrics:` line is the only one
a refusal never prints, because it belongs to a run that did work. If a script
counts those two lines, do not hand it `-debug`. A script that must
react differently to different refusals has to match on English prose, and
there is no supported way around that today. This is stated rather than
implied because a reader who assumes otherwise writes the matching anyway and
finds out later.

**A signal gives `128 + signo`, not `1`.** A `SIGTERM` from a job scheduler is
143, `SIGINT` is 130, `SIGKILL` is 137 — measured across eight signals. Those
are not csv2 refusals and mean nothing about the file, which is intact in every
one of them. A script that treats "not 0, not 141" as "csv2 rejected my input"
will misreport a scheduler timeout exactly the way this section warns it would
misreport a `head`.

**A search that matches nothing exits `0`.** `-contains` reports what it found;
finding nothing is not an error. So `if csv2 -contains X -i f.csv` is not a
test for presence — it succeeds either way. To ask the question, read `matched`
from the trailing `--json` meta line:

```sh
set -o pipefail
n=$(csv2 -contains -- "$needle" --json -i f.csv | tail -1 |
    sed -n 's/.*"matched":\([0-9]*\).*/\1/p')
[ "${n:-0}" -gt 0 ] || { echo "not found" >&2; exit 1; }
```

`tail -1` because the meta line is last; `pipefail` because without it a
refusal exits 0 through the pipeline and `n` is empty, which reads as "not
found". A header hit does not count here — see `--include-headers`. This
recipe was prescribed in two places and shown in none until 2026-08-22, in a
document that spells out a whole Python block for case-folding.

A run that fails writes nothing to `-o`, because output goes to a temp file
that is renamed only after everything else worked.

**Two processes editing one file: the last one to finish wins, silently.**
Both exit 0, both write an audit entry saying they succeeded, and one of the
two edits is not in the file. Measured 3 times out of 3 on a 2,000-record file
with two concurrent `-update --in-place` runs. csv2 takes no lock, and nothing
in it will tell you this happened — the `-log` entries are each true of their
own process and the trail as a whole is then wrong about the file. **If two
writers can reach the same file, serialise them yourself.**

**Two processes APPENDING to one file is the one case that is not "one edit
lost".** `-append --in-place` does not rewrite the file, so there is no temp
file and no rename: it writes its bytes onto the end. That write goes through
a descriptor opened `O_APPEND`, where the kernel makes finding the end and
writing there one operation — so two concurrent appends both land, whole, and
neither can overwrite the other. The run that finishes SECOND notices (the file grew by more than it wrote)
and says so with a `WARN` -- the first one has already looked and seen its own
write and nothing else, which is why exactly one warning appears and not two.
The index beside the file cannot be updated by either of them: the offsets each computed are no
longer where the records are. The sidecar is left alone and the next read
discards it as stale.

Until 2026-08-22 that write was a seek to the computed end followed by a plain
write, which is not the same thing at all. Two appends racing then wrote at the
same offset and the shorter landed on top of the longer, leaving a fragment of
the overwritten row behind: sometimes a bare newline, so csv2's own blank-line
rule refused a file csv2 had just written; sometimes a WELL-FORMED record that
nobody appended, which read back at rc=0 with nothing anywhere reporting it.
The `-log` file had been moved off that construction for exactly this reason,
one source file away.

**A reader never sees a half-written file — when the writer is csv2 and the
edit is not an append.** Output goes to a temp file and is renamed into place,
and rename is atomic, so a concurrent reader gets either the whole old file or
the whole new one and never a mixture, even while a writer is part-way through.
That is a promise you can build on, not an implementation detail: it is why the
temp-file-and-rename is there. An append writes onto the end of the file
itself, so a reader can see a record arriving; the bytes are never interleaved
with another writer's, but they are not atomic for a READER the way a rename
is.

**An edit rewrites every record separator, including the ones it did not
touch.** Output uses `\n` on every platform, so editing one cell of a CRLF
file returns an LF file — the fields are byte-identical and the file is not.
Every verification idiom that works on the whole file (a checksum, a `diff`,
"the records I did not name are unchanged") is wrong on a CRLF input; compare
VALUES instead, with `--json` or `-get`. `-append --in-place` is the exception
that proves it: it writes onto the end and matches whatever line ending is
already there, because it is not rewriting the rest.

**What it costs is disk: peak usage is twice the file.** The temp file grows
to the size of the finished output while the original is still there, so
rewriting one cell of a 1 GiB file needs 1 GiB free, not the few bytes the
edit changes. The write-amplification figure further down counts the bytes
WRITTEN; this is the space that has to exist at the same time, and ENOSPC
part-way through leaves the original intact and reports the failure — which is
the promise working, not failing.

**The promise belongs to the writer, not to csv2's reader**, and this document
sends you to other writers — `iconv`, `tr`, a shell redirect. Measured against
an ordinary `cat > file` racing a read, 30 trials produced 12 silent
truncations and 18 loud errors, and no whole file at all. **The split between
the two is not a property of csv2**: it is where the reader's EOF happens to
land relative to a record boundary, so a later round measured 5 and 25 on its
own fixture. "No whole file at all" is the part that reproduces. csv2 cannot detect
the silent case: a file cut at a record boundary is a shorter file, not a
malformed one, and **nothing csv2 prints can tell you a read was complete** —
`records` reports what it reached, which is the number that would be wrong.
If a file is being rewritten by something that is not csv2, rename into place
yourself rather than writing over it.

**The same holds for `--in-place`, where it matters more — with one exception,
`-append`, stated at the end of this paragraph:** a failed in-place edit leaves
the original **byte-for-byte unchanged**, and leaves no temp file
beside it — including when the run is killed by `SIGINT`, `SIGTERM` or `SIGHUP`
part-way through, and the same for every other catchable signal that ends a run
— `SIGQUIT`, `SIGXFSZ`, `SIGALRM`, `SIGUSR1`, `SIGUSR2` and the rest. **"The rest" is literal**: the handler is installed for every catchable terminating signal, not for a list someone maintains, so a signal not named here behaves like the ones that are. That list started at
three, and a blind round found a hidden multi-megabyte file left by each of the
others; `SIGXFSZ` is what an `ulimit -f` or a filesystem quota produces, which
is not exotic (T131e, T131f). `SIGKILL` and a power cut cannot be caught and
will leave one;
it is named `.<file>.csv2tmp.<pid>` and is safe to delete.

**`-append --in-place` is the exception, because it has no temp file to fall
back to.** It writes onto the end of the file itself and keeps the inode, so
there is no rename to make the change atomic: a run killed mid-append can leave
a partial record where every other edit would have left the original untouched.
Everything else above still holds for it — the handler is installed, the index
is not corrupted — but "byte-for-byte unchanged" is not among the guarantees.
`-r -t --truncate-partial` writes a clean copy of a file with a torn tail.

Round 77 read the two passages together, found they could not both be literally
true, and could not settle it by experiment: the largest record `-append`
accepts is bounded by `ARG_MAX` and lands in a single write, so a partial append
could not be manufactured at any size the flag takes. Being hard to reproduce is
not the same as being impossible — a filesystem is free to split a write — which
is why the exception is stated rather than left to the reader to derive from two
sections that contradict each other.
 A consequence worth
knowing: rename recreates the destination, so **deleting the file while an edit
is running brings it back** — the `rm` lands on the old inode and the rename
puts the new one where the name was. This is the one guarantee with no fallback — with `-o` you still have
the input if the output is wrong, and with `--in-place` the input *is* the
output. Asserted by T28c.

**Several addresses, one run.** `-update` is repeatable, and every address in
one run resolves against the file as it arrived, so N edits either all land or
none do. A loop that runs csv2 once per address is not that: the fourth call
failing leaves the first three written, at exit 1, with no way to tell from the
file which had happened. The same is true of `-insert`, and is why its numbers
are documented as resolving against the input.

```sh
csv2 -update 3:6 A -update 12:6 B -update 40:6 C -i f.csv --in-place   # atomic
```

**Before an edit you cannot undo, `-so` is a dry run.** It writes what the edit
would produce to stdout, touches nothing, and refuses out-of-range addresses
exactly as the real run would — so `csv2 -update 12:6 X -i f.csv -so | head`
answers "what will this do" before `--in-place` answers "what did it do".

**That sentence is about the input, and `-o` says nothing about the
destination: an existing file there is overwritten, silently, at rc=0.** There
is no flag to guard against it — `>` behaves the same way and csv2 does not
try to be different — so the guard is yours: write to a new name, or check
first. A blind round lost a file to this while treating `-o` as the safe
alternative to `--in-place`, which is exactly how the sentence above reads if
you stop at "safe".

**Temp-file-and-rename has a cost, and it lands on symlinks and permissions.**
A rename replaces a *name*, so writing to a symlink's own path would swap the
link for a regular file and leave the target untouched — while the shell's `>`
writes through it. Both `-o` and `--in-place` therefore resolve the destination
first: the link keeps pointing where it did, and the file it points at is the
one written. The original file's permission bits are carried onto the temp file
before the rename, so an edit does not change who can read it — and the temp
file is created 0600 to begin with, so it is not readable by anyone else while
it is being written either. It was 0644 for the duration until 2026-08-21, and
on a large file that is a window measured in seconds. Asserted by T129, T130
and T161.

**When `-o` names a path that does not yet exist there is no original**, so
nothing is carried over and the file keeps the temp file's mode: **0600**, not
your umask. `csv2 -r -t -i pkgs.csv -o new.csv` under `umask 022` produces
`-rw-------`, while writing over an existing 0644 file produces `-rw-r--r--`.
Safe by default, and worth knowing before a pipeline hands that file to
another user.

**In a diagnostic, an INPUT path appears as you typed it and an OUTPUT path
appears resolved.** `cannot open input file: ./nope.csv` keeps the `./`; an
`-o` refusal prints the absolute path once the destination has been resolved,
and under `--in-place` the resolved one — `/private/tmp/x` comes back as
`/tmp/x` on macOS — because `--in-place` resolves the destination and not the
source. A refusal that quotes your `-i` argument therefore shows what you typed
even when the run is `--in-place`. **The exception is a destination that cannot
be resolved because it is not there**: `-o nodir/out.csv` prints
`the directory nodir does not exist`, as typed, since there is nothing to
resolve against. It matters because matching the English prose is the only way
to tell refusals apart. The paragraph here said the opposite of both halves
until 2026-08-21 and had no exception until 2026-08-22; each version was
written from the examples in front of it.

Three things it does not preserve, all deliberate: a **hard link** is broken,
because rename cannot do otherwise; **extended attributes** are lost, because
the temp file is a new file and nothing copies them across; and a **read-only
file** in a writable directory is still replaced, because rename asks
permission of the DIRECTORY and never looks at the file. Restoring the mode stops an edit from
widening who can read a file, which is the half that hands data to someone
else; refusing to write a read-only file would be csv2 having an opinion about
your directory permissions, which is not its business.

`--build-index` and `--verify-index` print to **stdout** — they are explicit
administrative actions, not the normal path, but if you pipe them anywhere
those lines are in your stream. `--build-index` prints one line.
`--verify-index` prints one on success and **one per claim that failed** on a
mismatch, which can be more than one line per grid point -- a point whose byte
offset AND line are both wrong prints two. In practice one edit often moves
both by the same amount and only the offset is reported: splitting one record
into two shifts every later record number by one AND every later line by one,
so the line each grid point names still matches and only the byte claim fires.
Two claims for one point is what a corrupted SIDECAR produces, not what a
changed FILE usually does: a large index that has
shifted can print thousands. Neither can be combined with a verb — the flag
replaces the operation, and asking for both is refused rather than silently
dropping the verb (T160).

Errors go to stderr as exactly **two** lines, English then Chinese — escaped
by the same whole-line rule as the log, which is what makes the count
reliable, **and that rule covers every control character**: a newline, tab or
CR as `\n`, `\t`, `\r`, everything else below 0x20 and DEL as `\xNN`. Until
2026-08-21 it covered the newline and the CR alone, so `no column named
"<ESC>[2K…"` put a live erase-line sequence on the line carrying the
diagnosis — the hazard this document gives as the reason for escaping the
locating report, one screen away. The count held throughout; the rule did not.

**A backslash is NOT escaped by that rule, on purpose**, because a message
that teaches `\n` has to read as `\n` — `undefined escape sequence \q` is a
sentence, not a value. Values interpolated INTO a message are escaped where
they are interpolated, backslash and all, so `no column named "…"` tells a
column literally named `na\nme` from one containing a newline. A message
quoting a PATH keeps its BACKSLASHES -- a Windows path is full of them and
doubling them would misname the file -- and everything else in it is escaped
like any other line, so a filename containing a newline arrives as `no\nsuch.csv`
and one containing an ESC as `x\x1B[2Ky.csv`. That is what keeps a refusal two
lines and a log entry one. It also means the path in a message is not always
the string you would pass back to `open`: this sentence said paths were "left
alone" until 2026-08-22, generalised from the backslash it was written for. A message
quoting an input value that contained a newline used to print four, and a script
reading the pair took the injected line for part of the error. Asserted by T102.
With `-log FILE` the same failure is also appended there with a timestamp;
without it nothing else is printed. On the normal path csv2 prints nothing at all — it has
to work inside a pipeline.

**One thing does print without `-debug`, and it is deliberate**: a `WARN`
line. **It is a list, not a policy** — these six and no others: a `-mid`
window that begins past the end of the file, a value over 1 MiB going into the
log in full, `--truncate-partial` naming the bytes it discarded, an index
sidecar that could not be written, **a `-log` file that could not be
written**, and **another process appending to the same file during an
`-append --in-place`**. The last was missing from this list until 2026-08-21, and it is the
one it could least afford to miss: the caller asked for an audit trail, the run
exits 0, no log file exists, and one line of English on stderr is the whole
notice. It used to be introduced as a principle
("a run that succeeded while doing something the caller almost certainly did
not intend") followed by the list, and a reader cannot tell from that which of
the two they are being promised — the principle covered a case the list did
not, and that case destroyed data. WARN is the default threshold. Unlike an
error it is **one line and English only**, which is what every diagnostic in
this tool is; the two-line bilingual shape belongs to the message that ends a
run. Exit status stays 0, because the run did what it was told.

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
Each of these exits non-zero with a message saying why. **The right-hand column
is the reason, not the message**: the text csv2 prints is often shorter and
names the argument it saw, so match on exit status and read the message, rather
than matching the message against this table.

**This table is the interesting refusals, not all of them.** It exists for the
combinations a caller would otherwise have to discover; it does not list the
ordinary argument errors (`-get: expected r:c, got "x"`, `--headers takes 1 or
2`, an unreadable `-i`, an `-o` whose directory does not exist or cannot be
written), nor the ones described in prose elsewhere — repeated flags,
`--headers` disagreeing with the suffix, a file with no suffix, re-masking a
marked column in either direction, `0:`/`0a:`/`0b:` addressing, the four COLS
refusals, `--verify-index` or `--build-index` given a verb, and the
environment-variable limits. A round read this table as a closed contract in
August 2026 and found nine refusals it does not mention; the fix was to say so
here rather than to grow the table into something nobody reads.

| Combination | Why it is refused |
|---|---|
| `-head 3 -o out.csv2` (no `-t`), reading a `.csv2` | data rows without a header written to a path whose suffix promises one; the next read would eat the first records as the header. **This applies to selections, not to edits** — see below. Reading a `.csv` and writing `.csv2` hits a different refusal first, whatever flags you add: csv2 does not convert between the formats |
| `-md` without `-t` | a Markdown table has no shape without a header row, and silently adding one would make "no header by default" grow an invisible exception |
| `-md -o out.csv2` | the suffix declares CSV, the content would be Markdown. Reaching this needs a `.csv2` INPUT: from a `.csv` the format-conversion refusal on the first row fires first, whatever flags you add |
| `-si` without `--headers 1` or `2` | stdin has no suffix, so the format is not declared; a default here would be a guess |
| `-head` with `-tail` | no single reading of both is obviously right |
| `-mid 7,3` | `a > b`; not swapped for you, because a range written backwards usually means the logic is backwards too |
| `-i x -o x` without `--in-place`, however the two are spelled — and however many NAMES the file has | that IS an in-place edit, and `--in-place` also keeps a symlink pointing where it did and leaves the permissions alone. Spelling covers `./x`, `../d/x`, an absolute path and a symlink; a hard link is not a spelling, so the file's (device, inode) is compared as well. **POSIX only**: the Windows CRT reports inode 0 for every file, where that comparison would say every file is every other one |
| `-delete 12:6` | that is a cell address; add `-cell`, or give a record number |
| `-delete -cell -col 3` | they are opposites: `-cell` blanks a field and keeps the column, `-col` removes the column |
| `-delete -col` removing every column | a file with no columns is not a CSV file |
| `-delete -col X` with `-update`/`-delete -cell`/`-encrypt`/`-hash` on X | the edit would have no effect and would still be reported as done |
| `-delete -col` with `-insert`/`-append` | the literal row would have to match either the old shape or the new one, and there is no way to tell which was meant |
| `-delete -col` with `-add-column` | both number columns against the file as it arrives, so the same number means two different columns depending on which is applied first |
| `-add-column N` with N past one-after-the-last column | clamping it to the end would exit 0 having silently ignored the number |
| `-add-column 0` | columns are numbered from 1 here; 0 is the header |
| `-add-column` on a file with no suffix | that file is one column, bytes verbatim, so a comma in it is DATA — a second column would be read back as part of the first |
| `--a1` or `--physical` without a locating report | they add a part to the report's address, and `-r`/`--filter`/`-md`/`--json` do not emit one; there would be nothing to add to |
| `-insert -cell` | inserting a cell mid-record shifts every later field one column along |
| `-update 99:3` on a 21-record file | out of range is an error, never "grow the file to fit" |
| `-append 'a,b,c'` on a 7-column file | the field count must match the header; csv2 will not pad or truncate to fit |
| `-encrypt` with no `-keyfile` and no tty | a prompt that cannot be shown is never a yes |
| an edit with no `-o`, `-so` or `--in-place` | `-insert`/`-append`/`-delete`/`-update` need an explicit destination; there is no implied in-place |
| `-o /dev/stdout` | output is written to a temp file beside the target and renamed, which needs a regular file. Use `-so` |
| `-update`/`-delete -cell` on a column the file marks `:enc:`, `:hmac:` or `:hash` | a raw value written there cannot be read back, and for an encrypted column `-decrypt` stops at that cell — so records the edit never touched are lost with it |
| `-insert`/`-append` into a file that has such a column | every field of the literal row is raw, including that one, and no value you could supply would be right: the transform needs the key, and the header carries only its fingerprint |
| `-o` naming the `-keyfile`, or the `-log` file; `-log` naming the input; `-keyfile` being the input of an `--in-place` run | the same-file comparison that guards `-i` against `-o`, asked of the other files a run touches. Each of these exited 0 with both streams empty and destroyed something: the only key that decrypts what was just written, the audit trail of the run writing it, or the input itself -- csv2 appends the invocation line into the file it is reading, which then fails its own field-count check for ever |
| a SELECTION with `--in-place` | `-head`, `-tail`, `-mid`, `-contains` and a bare `-r` all select; `--in-place` is where an EDIT goes. Writing a selection back over its own input discards every record it did not name, and until 2026-08-21 it did exactly that at rc=0 with nothing said and nothing logged. Crop with `-o NEW.csv` |
| `-insert N ROW` whose field count differs from the header | the same check `-append` gets, and it names the count both ways: `-insert 2 has 2 fields but the header has 4`. It was missing from this table until 2026-08-21, and a table that presents itself as complete is read as one |
| `-append` onto a file whose last record is incomplete | a short final record, or one left open by an unclosed quote. Checked for `-o` and for `--in-place` alike — the fast path used to skip it and produce a file csv2 then refused to read |
| `-append` with `--truncate-partial` | appending adds bytes and cannot remove the incomplete record, so the file would keep it *and* gain a complete record after it. Write a clean copy first: `csv2 -r -t --truncate-partial -i f.csv -o clean.csv` |
| a value, row or search string that is not valid UTF-8 | Swift decodes `argv` with replacement, so the bytes are already gone; storing what arrives would put U+FFFD where a byte was, silently. Put the value in a file — bytes survive there, which is what the round-trip guarantee is about. **Paths are not checked**: on Linux they may legitimately hold any bytes, and csv2 hands a path to the filesystem rather than storing it as data. **Nor is a COLS list** — `-hash`, `-encrypt`, `-decrypt` and `-delete -col` take a column NAME, and an invalid byte there fails to match a column and is reported as `no column named "caf<U+FFFD>"`, which refuses the run without storing anything. **POSIX only**: a Windows command line arrives as UTF-16, so whatever happened to an invalid byte happened before the process started and there is nothing left for csv2 to inspect |
| unknown flag | never swallowed as something else |

### Every edit index refers to the input, and that is visible with `-insert`

**They may also be mixed with one another in a single run** — `-insert 3 X
-delete 2` is one atomic edit, not two — and the rule below governs all of them
together, not each verb separately. Round 75 read "can each be given more than
once" as granting repetition of one verb and ran the mixture as a bet; it works,
and the sentence did not say so.

**A `-delete` renumbers the records after it.** Afterwards the file is numbered
1..N with no gap, so an address taken before the edit may name a different
record after it. The `-insert` example below shows this in its output and the
document nowhere states it; round 75 had to infer it, and the `-rownum` entry —
which says it "does not renumber anything" about ADDRESSES on a read — is what a
reader meets while asking.

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

- **Range is checked against the input too, and the legal range is `1..N`.**
  `-insert` puts a row *before* record N, so on a five-record file the last
  legal position is 5 and `-insert 6` is refused — in a batch and on its own.
  **`-insert` cannot address the end of a file; that is what `-append` is
  for.** An earlier version of this bullet said `-insert 6` becomes legal as
  the third of three separate runs "because by then the file really does have
  six places to put it". The prediction holds — by then the file has seven
  records, so 6 is interior — but the reasoning does not: a five-record file
  has five insert positions, not six.
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
csv2: /home/you/work/sel.csv2 declares a format with a header, so writing data rows there needs -t; without it the next read would take the first record(s) as the header
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
values still compare equal, but the digests now depend on the key — and the
word list is useless to anyone who does not have it:

```console
$ csv2 -hash license -i TARGET_PACKAGES.csv -o masked.csv -t
$ csv2 -contains ':hash' --include-headers -i masked.csv | cut -f3
license:hash                       # unkeyed — dictionary applies

$ csv2 -hash license -keyfile k.bin -i TARGET_PACKAGES.csv -o masked.csv -t
$ csv2 -contains ':hmac:' --include-headers -i masked.csv | cut -f3
license:hmac:289b9391              # keyed — fingerprint of the key used
```

**`--yes` also selects a key, and therefore also selects the algorithm.** It
means "use the default key without asking", which for `-hash` is the difference
between `:hash` and `:hmac:<fingerprint>`:

```console
$ csv2 -hash license -i pkgs.csv -o m.csv -t          # license:hash
$ csv2 -hash license --yes -i pkgs.csv -o m.csv -t    # license:hmac:9c65c01a
```

So adding `--yes` to make a script non-interactive changes the algorithm at
rc=0, and removing it changes it back.

**It does not, however, make the column secret from anyone else on the
machine.** The default key is a FILE on this host, and `--yes` is a documented
one-word way to ask csv2 to use it — so a local reader builds the same table
you did:

```console
$ printf 'w,license\n1,Zlib\n2,MIT\n3,GPL-2.0\n' > words.csv
$ csv2 -hash license --yes -i words.csv -o rainbow.csv -t
$ csv2 -contains ':hmac:' --include-headers -i rainbow.csv | cut -f3
license:hmac:9c65c01a               # the same fingerprint your file carries
```

Joining on the digest recovers every value the word list contains — measured at
6 of 6 on a licence column, one MORE than the unkeyed form recovered, because
the keyed digests collide less. The marker even announces which key was used,
and this document publishes that fingerprint. **`--yes` is for "do not prompt
me", not for "keep this from the people who can run csv2 here".** Against a
local reader, use `-keyfile` with a key they cannot read; against nobody in
particular, the unkeyed form is honest about what it is. **The file records which happened**
— that is what the marker is for — but two files hashed differently never
compare equal, so a join across them silently matches nothing. Decide once, per
column, and read the marker rather than the command line. Asserted by T142.

Choose the unkeyed form only when the value space is genuinely large — a long
free-text field, an opaque identifier — or when you do not actually need the
values hidden from someone holding the file.

### `-hash`, `-encrypt` and `-decrypt` are EDITS

They rewrite every record, so they behave like the edit verbs and not like the
selection verbs, and this was written nowhere until 2026-08-21 — which is how a
selection combined with one of them wrote itself back over its own input.

- **They may not be combined with a selection under `--in-place`.** `-head 1
  -hash col -i f.csv --in-place` is refused for the same reason `-head 1 -t
  --in-place` is: the records the selection did not name would be discarded.
  `-r -hash col --in-place` is fine — it rewrites every record and drops none.
- **With no destination they write CSV to stdout.** They are the exception to
  "an edit with no `-o`, `-so` or `--in-place` is refused"; that rule names
  `-insert`, `-append`, `-delete` and `-update`, and means exactly those four.
- **They always write the header**, with or without `-t`, because the marker
  lives there and a masked file without its marker cannot be read back
  correctly. On a `.csv2` both header rows are marked.
- **They log the outcome line** — `wrote N records, M fields, atomic rename
  OK` — like every other write. Until 2026-08-21 they did not, so the one line
  this document tells an auditor to look for was missing from exactly the
  writes that cannot be undone.

### Protected columns are marked in the file

`-hash`, `-encrypt` and `-decrypt` rewrite the **header** so the file records
what was done to which column:

A column name ending `:hash`, `:hmac:<fp>` or `:enc:<fp>:<salt>` is therefore
**reserved**: a plain column called `secret:hash` is treated as protected, and
csv2 will refuse to edit it — fail-safe, and the message will be describing a
file it has misread. Name the column something else.

| Marker | Meaning |
|---|---|
| `license:hash` | unkeyed SHA-256 |
| `license:hmac:<fp>` | HMAC-SHA256, `<fp>` identifying the key |
| `license:enc:<fp>:<salt>` | encrypted; `-decrypt all` finds these |

**Both header rows of a `.csv2` must carry the same marker, and a file whose
rows disagree is refused** — by every verb, before anything else, naming the
column and what each row says. Every check for a protected column reads the
header, and until 2026-08-25 they all read row 0a: a file whose 0b said
`:enc:` and whose 0a did not walked past all of them, so `-update` wrote
plaintext into an encrypted column and `-hash` overwrote the `:enc:` marker
together with its salt, at rc=0, on a file whose Chinese header row still said
`:enc:`. Reading both rows and taking the union would have fixed the misses and
left the file incoherent; refusing is what this tool does when two sources
disagree.

Addressing still uses the plain name: `-update 3:license` works after masking.
Re-masking an already-marked column is refused rather than layered, **in both
directions**. Until 2026-08-20 each verb looked only for its own marker:
`-hash` on an `:enc:` column was accepted and it is the worst thing this tool
can do — it hashes the CIPHERTEXT one way and overwrites the `:enc:` marker
together with its salt, at rc=0, printing nothing, and the correct key
afterwards gets `no encrypted columns found`. The rule was general and the
implementation was two special cases that each recognised only themselves.
Asserted by T124.

`--json` keys stay clean, so the same marking appears in the metadata line
instead:

```console
$ csv2 -head 1 -t --json -i masked.csv
{"meta":{"format":"csv","headers":1,"fields":7,"protected":{"license":"hmac"}}}
```

The key is absent entirely when nothing is protected.

## The index sidecar

Everything about the `.index` file in one place, because the paragraph that
warns you about it used to point here and there was nothing here to point at.

**What it is.** `packages.csv` gets `packages.csv.index` — the whole filename
plus `.index`, so `foo.csv` and `foo.csv2` never collide. It holds a byte
offset and a physical line for every 256th record, the record count, a
`no_embedded_newlines` flag, a stamp of the data file, and a checksum over
itself. It is derived, never the source of truth: put the name in
`.gitignore`.

**When one appears.** `--build-index` builds one at any size. Otherwise only as
a side effect, and only at or above `CSV2_INDEX_MIN_BYTES` (16 MiB): a
rewriting edit builds one, `-tail` builds one because it must read to the end
anyway, and `-append --in-place` builds one because it reads to the end too —
it has to prove the file's last record is complete before adding bytes after
it. `-mid`, `-contains`, `-r` and `-get` never build one. An append EXTENDS an
index that already exists rather than rebuilding it, which is the only place
in the tool where an index is edited instead of derived.

**Who reads it.** `-contains` (to split the file into chunks), `-mid` and
`-tail` (to seek). `-get` and the edit verbs scan and ignore it. `--no-index`
turns all of that off.

**What it is checked against, and what that cannot catch.** Before use: the
data file's size, mtime **to the nanosecond**, and a hash of its first and last
64 bytes, plus the index's own checksum. That is O(1) and it is a heuristic —
a change that keeps all of those identical is not detected, and one exists:
overwrite a record with the same number of bytes, restore the mtime exactly.
`--verify-index` is the O(n) answer and compares the index's four claims
against the data; it exits 0 when they hold, 1 when they do not or there is no
index, and prints one line per failing claim.

**The two ways an address from it can be wrong.** A stale sidecar that the
stamp still accepts (above), and the file simply changing between your two
commands, which no sidecar is involved in and no flag prevents. Verify before
an edit, not after: a rewriting edit repairs the sidecar as it goes, so
`--verify-index` afterwards reports on the file you have already changed.

**Why it is never required.** Every operation gives the same answer without it.
Stale, truncated, corrupt or a version behind — all discarded in favour of a
scan, none an error, because an index that quickly gives you the wrong data is
worse than no index at all.

### Environment variables

Each exists so its logic can be **tested** without producing the data it was
meant to protect against, not merely so it can be tuned. A threshold that
cannot be lowered can only be exercised by building a 16 MiB fixture.

| Variable | Default | Effect |
|---|---|---|
| `CSV2_INDEX_MIN_BYTES` | 16 MiB | gates WRITING only, and only the side-effect kind: below this, a rewriting edit and `-tail` do not leave a sidecar behind. READING is not gated at all — a sidecar that exists is consulted at any file size, which is what makes `--build-index` on a small file useful. `--build-index` is an explicit request and writes one at any size. The single sentence that used to be here read "no index is read or written as a SIDE EFFECT", which parses two ways and is false under one of them; a blind round measured a 33 KB file consulting its sidecar on 2026-08-25 |
| `CSV2_PARALLEL_MIN_BYTES` | 16 MiB | set above the file size to force the single-threaded path |
| `CSV2_PARALLEL_MAX_BYTES` | 1 GiB | ceiling on what the in-flight chunks may hold. It governs the **output** fragments — one batch of them is kept so they can be written in chunk order, which is what makes parallel output byte-identical to single-threaded. The read side needs no ceiling: a worker reads its chunk 64 KiB at a time and never holds more. Lowering this holds fewer chunks in flight and the rest queue; `-debug` says so, with the numbers. **It is not a cap on the process's memory, and it is not the lever that moves it.** Measured on a 192 MB file: 17.07 MB peak RSS at the default, 17.22 MB under an 8 MiB setting, 17.10 MB under 64 MiB — the differences are noise, while single-threaded over the same file is 9.39 MB. What moves peak RSS is the FILE SIZE (17 MB at 192 MB, 23 MB at 615 MB, 57 MB at 2.1 GB), not this ceiling. The row used to say "under an 8 MiB setting, peak RSS was still 58 MB", which is true and was taken at a size the row did not name; read beside the 23 MB headline it says lowering the ceiling RAISES memory by 35 MB, which is not what happens. Round 77 put the two side by side and could not reconcile them |
| `CSV2_PARALLEL_CHUNK_BYTES` | 4 MiB | smaller values make a small file yield many chunks, so chunk boundaries are actually exercised |
| `CSV2_PRETTY_MAX_BYTES` | 16 MiB | `-md --pretty` refuses above this rather than being OOM-killed. **It measures the material being aligned, not the input file** — `--pretty` has to hold the whole table to compute column widths. So a slice of an arbitrarily large file is always fine: `-mid 150000,150004 -t -md --pretty` on a 23 MB file aligns 237 bytes of material and succeeds, while `-r` over the same file refuses. **The limit is not a cap on the process's memory**: aligning 15 MB of material took 81 MB of peak RSS, about 5x, because the table is held as records before it is rendered. Until 2026-08-21 this entry said the slice "holds 9 MB", which is what `csv2 -tail 1` costs too — the process's floor, attached to the one concept this row exists to teach |
| `CSV2_MAX_BUFFER_RECORDS` | 1,000,000 | upper bound on `-tail N` and `-B N`. Asking for more is **refused, not truncated** — a short answer that looks like a whole one is the failure this tool exists to avoid. The message names the request, the limit and the variable -- and it quotes the flag that was TYPED, so `-C 6`, which sets the before side too, is reported as `-C 6` and not as `-B 6`. Until 2026-08-21 the `-B` message named two of the three and `-C` was reported as `-B` |

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
| **one record per line** | `.csv2` guarantees it. A `.csv` qualifies only with an index that scanned the file and recorded there are no embedded newlines — build one with `--build-index`. This is the PARALLEL path's requirement, and it is not the seek's: since index v4 a `-mid` or `-tail` seek works on any indexed file, because each grid point carries its line |

That last row is the one that surprises. A `.csv` containing an embedded
newline can never take the parallel path, which is also the case a
boundary-straddling test most wants to construct.

**`-debug` says which path ran, always**, including when it is the ordinary one
and why:

Every diagnostic line really begins `csv2: <ISO-8601 timestamp> LEVEL `, and
the examples in this document **elide that prefix** so the message itself fits
on one line. A REFUSAL is not one of them: the two-line error that ends a run
prints `csv2: <message>` with no timestamp and no level, on both lines, and the
examples of those are shown as they really are. One shown in full, once, so a script can be written against the
real shape:

```console
$ csv2 -r -i pkgs.csv -debug     # 2>&1, all of it
csv2: 2026-08-20T19:32:39.922+08:00 INFO  csv2 -r -i pkgs.csv -debug
csv2: 2026-08-20T19:32:39.922+08:00 DEBUG single-threaded: not a search; parallelism applies to -contains only
csv2: 2026-08-20T19:32:39.922+08:00 DEBUG format=csv fields=4 records=2
csv2: 2026-08-20T19:32:39.923+08:00 DEBUG metrics: read_bytes=103 file_bytes=103 peak_rss_bytes=8962048
```

**The first line is the INVOCATION record, at `INFO`.** It is the same line
`-log` writes, and `-debug` lowers the threshold far enough for it to reach
stderr as well — so a script that reads "the first line" of a `-debug` run gets
the command, not the diagnosis. This block showed one line of the four until
2026-08-21, in the paragraph offering it as the real shape.

With the prefix elided from here on:

```console
$ CSV2_PARALLEL_MIN_BYTES=1000 CSV2_PARALLEL_CHUNK_BYTES=512 \
      csv2 -contains xyz -i big.csv2 -debug      # 2>&1, on a 2,980-byte file
DEBUG parallel: 6 chunks, 10 workers, chunk 512 bytes
DEBUG parallel: 199 records, 0 matched
$ csv2 -contains xyz -i pkgs.csv -debug
DEBUG single-threaded: .csv with no index proving one record per line; build one with --build-index
$ csv2 -r -i pkgs.csv2 -debug
DEBUG single-threaded: not a search; parallelism applies to -contains only
```

**The two environment variables in the first line are not decoration.** Without
them that command prints `single-threaded: file is 2980 bytes, under
CSV2_PARALLEL_MIN_BYTES (16777216)` — the opposite of what the example is
showing — because a fixture small enough to print here is far below the 16 MiB
threshold. An example that gives the opposite answer when run verbatim is worse
than no example — and until 2026-08-21 **this** was that example: it named
`pkgs.csv2`, the 44-byte fixture above, which is under the 1000-byte floor the
same line sets, so the printed `parallel:` line could not happen. Nine chunks
of 512 bytes also needs about 4.6 kB. The file here is 199 records of
`row<N>,value<N>` and it does what is printed.

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

**If you cannot accept that risk on a given run, `--no-index` is the answer**,
and it is worth naming here rather than leaving it as a mechanism described
elsewhere. It means "never read or write a sidecar", so the search reads the
file and counts for itself: slower, and right by construction. **How much
slower is not only the scan**: on a `.csv` it also gives up the parallel
search, because a `.csv` needs an index to prove one record per line. Measured
on 17.7 MB / 450,000 records, `-contains` goes from 204 ms to 528 ms — 2.6x,
and `-debug` says which of the two reasons applied. On the file above, the
trusted stale index reports `40000:2` for a record whose true address is
`39999:2`; `--no-index` reports `39999:2`. `--verify-index` answers
the same question the other way — it proves the sidecar before you rely on it,
once, instead of on every run.

A blind-test subject reading this section concluded there was "no flag that
says refuse to trust an index unless it was proven". There is; it was simply
never presented as the answer to the question they were asking.


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
  operation that WRITES the file, or that has to read it to the end anyway —
  `-tail`, a rewriting edit — puts a good one back, **provided the file is at
  or above `CSV2_INDEX_MIN_BYTES`**: below it nothing builds a sidecar, so a
  damaged one simply stays there, discarded on every read. `-append
  --in-place` replaces one too, for the same reason `-tail` does: it reads to
  the end to prove the last record is complete. An index that is already
  VALID is extended rather than rebuilt; a damaged one is discarded and a
  fresh one written in its place. A plain `-contains` or `-r` reads
  every byte and writes nothing, because building an index is not free and a
  read was not asked to pay for one; the `--build-index` entry says the same
  thing from the other side. Asserted by T68.

  This holds for the case the stamp CANNOT see too, but it did not until
  2026-08-25. When the stamp accepts a sidecar whose offsets have drifted, the
  seek lands somewhere that is not a record boundary — one byte early is enough
  — and `-mid` then refused a file with no blank line in it, blaming a record
  number and a line number both computed from the index that was wrong. Before
  a seek is used, csv2 now parses one record at that byte and requires it to
  have as many fields as the header; if it does not, the index is dropped and
  the file is scanned. A mis-seek costs a scan, which is the whole bargain. It
  can still be fooled — an offset landing at a plausible boundary parses fine,
  and that is the known hole this heuristic does not close — but being fooled
  can only ever cost a scan and never an answer. T204.
  **What the checksum is not:** it catches corruption — a flipped bit, a short
  write, a partially overwritten file — and is not a signature. Anyone who can
  rewrite the offsets can rewrite eight more bytes. It also cannot help when the
  *data* file changes without changing size, mtime or its first and last bytes;
  that is what the O(1) check has always been, a heuristic. **It is harder to
  arrange by hand than it sounds, and two blind rounds concluded from that
  that the check is stronger than this paragraph says. It is not.** The mtime
  compared includes NANOSECONDS, so a `touch -r` that carries only whole
  seconds moves it; the replacement has to be byte-for-byte the same length;
  and the wrong record number comes from the chunked search, so the file has to
  be big enough for that path to run. Get all three right and the indexed
  answer is off by one where a scan is correct — reproduced, and pinned by T143
  so that it stays reproducible for as long as this paragraph claims it. For a proof, run
  `--verify-index`, which is O(n) because it has to be. **What it proves is
  that the index's four claims are accurate — not what those claims say.** On
  a file where every other record spans lines it prints `index OK` just the
  same, because the index correctly records that. It is not a way to ask "does
  this file have embedded newlines"; the search's `-debug` line answers that
  one, explicitly. **What it proves** is
  all four of the index's claims: the grid offsets, the line each grid point
  names, the record count, and whether any record spans lines. The line was
  added on 2026-08-21 and this passage said "three" until 2026-08-22 — the
  drift this document is otherwise about. The spans-lines claim was added on
  2026-08-19, and it is the one that mattered — it is the claim the parallel path consumes when it
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
1 GiB where PostgreSQL would write about 10 KB. `-append` is the exception: it writes
only that row's bytes. It still reads the whole file first (see its flag entry),
so what it saves is the write, not the time. Lookups are by position, not by key, so finding the row
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

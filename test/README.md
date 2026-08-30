# csv2 regression tests

The test suite covers parsing, selection, output formats, editing, protection,
indexes, parallel search, diagnostics, and platform-specific behaviour.

```zsh
./test_csv2.zsh
CSV2=/path/to/csv2 ./test_csv2.zsh
```

The script builds `release/csv2` when no binary is supplied. Results are written
to the terminal and to `test_csv2.log`. The exit status is non-zero when any
case fails; skipped cases include their reason.

Cases are numbered `T<n>` and grouped by feature. The parent-project runner
executes the suite in the aarch64 Linux guest and performs host/guest
byte-identity checks that cannot run inside one platform.

Most fixtures are generated so exact bytes such as BOMs, CR characters,
invalid UTF-8, missing final newlines, and embedded commas cannot be normalised
by an editor. The committed `fixtures/TARGET_PACKAGES.csv` covers realistic
quoted-field cases.

Environment variables lower size thresholds so large-file behaviour can be
tested with small fixtures:

| Variable | Used for |
|---|---|
| `CSV2_INDEX_MIN_BYTES` | index creation and append tests |
| `CSV2_PARALLEL_MIN_BYTES` | parallel/single-thread comparison |
| `CSV2_PARALLEL_CHUNK_BYTES` | multiple search chunks |
| `CSV2_PRETTY_MAX_BYTES` | bounded Markdown rendering |
| `CSV2_MD_MAX_BYTES` | bounded Markdown input |
| `CSV2_MAX_BUFFER_RECORDS` | bounded tail/context buffers |

New cases should be added to `../plan/plan.md`, implemented under the matching
number, and marked complete only after they pass on the supported platforms.

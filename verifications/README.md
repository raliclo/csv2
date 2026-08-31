# csv2 verification measurements

The verification scripts measure parser and writer throughput, durable-write
latency, and the effect of parallel and index thresholds. They do not replace
the correctness suite in [`../test/test_csv2.zsh`](../test/test_csv2.zsh).

```zsh
./measure.zsh
./benchmark.zsh
RECORDS=20000 ./measure.zsh
CSV2=/path/to/csv2 ./measure.zsh
```

`measure.zsh` writes `measure_output.txt`. The parent-project runner executes
the same measurement inside the aarch64 Linux guest and captures
`measure_output_linux.txt`. Native Windows verification writes
`measure_output_windows.txt`.

The corpus is generated row by row. `RECORDS` controls its size more reliably
than an approximate megabyte setting. Measurements are best-of-N readings and
should only be compared when the record count, binary, and host conditions are
the same.

The parser measurement uses quoted fields containing commas and searches for a
non-matching value, so the result represents parsing rather than output
encoding. It also measures identical data rows in `.csv` and `.csv2` form and
reports the `.csv2`/`.csv` ratio. Parallel efficiency is below linear speedup
because boundary finding remains single-threaded.

Latest comparison (2026-08-31, macOS arm64, 200,000 records, best of five,
single-threaded and no index): `.csv` took 0.556 s and `.csv2` took 0.563 s,
for a `.csv2`/`.csv` ratio of 1.01x after the no-backslash fast path was added.
The complete run is in
[`measure_output.txt`](measure_output.txt).

For a comparable parallel-search throughput and RSS measurement, run
`./measure_parallel_rss.zsh`. It uses matching `.csv` and `.csv2` corpora with
at least 10,000,000 records and approximately 1 GiB each, with every record
matching. It runs both formats under the default and 8 MiB
`CSV2_PARALLEL_MAX_BYTES` settings; results are written to
`measure_parallel_rss_output.txt`.

Latest result (2026-08-30, macOS arm64, `csv2 0.1.0`, 10,000,000 records,
10 workers, 4 MiB chunks, every record matching): `.csv` ran at 35.8/36.3 MiB/s
with 9.28/9.30 MiB peak RSS, while `.csv2` ran at 31.5/38.5 MiB/s with
51.84/51.69 MiB peak RSS, for the default/8 MiB maximum respectively. The
`.csv` corpus was 1,307,777,815 bytes and the `.csv2` corpus was 1,307,777,833
bytes.

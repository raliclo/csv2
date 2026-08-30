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
encoding. Parallel efficiency is below linear speedup because boundary finding
remains single-threaded.

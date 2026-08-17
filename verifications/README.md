# verifications

- **繁體中文：[README.zh-TW.md](README.zh-TW.md)**

Measurements, not tests. Nothing here passes or fails; it prints numbers and
writes them beside itself so a later run can be compared with an earlier one.
The pass/fail suite is [`../test/test_csv2.zsh`](../test/test_csv2.zsh).

```zsh
./measure.zsh                    # results land in measure_output.txt
RECORDS=20000 ./measure.zsh      # smaller corpus, for a slow machine
CSV2=/path/to/csv2 ./measure.zsh
```

| File | Where it came from |
|---|---|
| `measure_output.txt` | the host — run this script directly |
| `measure_output_linux.txt` | the aarch64 guest — written by `sos/test_submodules/run_csv2_test.zsh`, which runs this same script inside the VM and captures the output back |

`RECORDS`, not a size in MB: the corpus is built row by row, so the record count
is what is actually controlled. A size knob could only be an estimate, and would
then disagree with the byte count the script prints.

## Why this exists

`plan/plan.md` has a section headed "寫程式之前應該先量的" — three numbers it
says to measure **before** writing any code, ending with: *this project has a
record of getting a boot-time conclusion wrong and having to correct a round of
documentation afterwards.*

They were measured after phases 1–6 were complete. This directory is that debt
being paid, and the result is worth stating plainly:

| | plan assumed | measured | |
|---|---|---|---|
| full RFC 4180 parse | 2900 MiB/s (`memchr`), "an order of magnitude slower" expected | **45 MiB/s** | **64× slower**, not 10× |
| parallel parse | not predicted | **124 MiB/s, 2.76×** on 10 workers | nowhere near linear |
| whole-file rewrite | 39 MiB/s | **38 MiB/s** | accurate |
| 1 GiB single-cell edit | 26 s | **26.9 s** | accurate |
| smallest durable edit | not measured | **0.019 s** | — |

The write-side predictions were right. The read side was out by 64×, and the
plan's own caveat — that the real parser would be "an order of magnitude"
slower — was correct in direction and six times short in size.

## The thresholds got more defensible, for a different reason

The 16 MiB index and parallel thresholds were chosen against 2900 MiB/s. At that
rate a 16 MiB scan costs 0.0055 s, and maintaining a sidecar to avoid it is hard
to justify. At the measured 45 MiB/s it costs 0.355 s, and the threshold makes
sense.

**The answer was right and the reasoning was hollow.** That is exactly what the
plan's warning was about: a correct conclusion drawn from a wrong number stops
being correct the moment the situation shifts. It now has a measurement under it.

## The guest numbers, and why two of them invert

`sos/test_submodules/run_csv2_test.zsh` runs this same script inside the aarch64
guest and captures the output to `measure_output_linux.txt`. Compared with a
macOS run at the same record count:

| | macOS (20k) | guest (20k) | |
|---|---|---|---|
| full parse | 41 MiB/s | **37 MiB/s** | only 10% slower |
| whole-file rewrite | 28 MiB/s | **33 MiB/s** | guest is faster |
| smallest durable edit | 0.0192 s | **0.0045 s** | guest is 4x faster |
| parallel (forced on) | 2.7x | **0.94x** — slower than single-threaded | |

Parsing is only 10% slower because the guest runs under `-accel hvf`: aarch64 on
Apple Silicon is hardware virtualisation, not instruction emulation.

**The two write numbers do not mean what they look like.** The guest appears
faster because it is doing less. QEMU's `-drive` has no `cache=`, so it defaults
to `writeback`, and the guest's flush arrives on the host as `fsync(2)` — which
on macOS does *not* force the drive to empty its own volatile cache. That needs
`F_FULLFSYNC`, which is what csv2 calls directly on Darwin. So 0.0192 s and
0.0045 s measure different events: data reaching the platter, versus data
leaving the guest. **The guest's durability figure is bounded by the host's QEMU
settings, not by anything about Linux.**

**Parallel is a net loss in the guest (0.94x)** — and that is the threshold
working. The 2.6 MB corpus is far below 16 MiB; the measurement forces
parallelism on with `CSV2_PARALLEL_MIN_BYTES=1000`. At the default threshold it
would never engage, so what the threshold excludes here is a parallelisation
that would have made the run slower. That is the second measurement supporting
the threshold, this time from the side where it says no.

## Reading these numbers honestly

- They are **best-of-N**, not averages: the fastest run is the one least
  polluted by other load. Compare like with like.
- **Only compare runs with the same `RECORDS`.** At 20 000 records the whole
  corpus is 2.6 MB, and process startup plus the flush — both fixed costs — are
  a large share of the total, so the MiB/s figure understates the steady rate.
  The same binary measured 28 MiB/s at 20 000 records and 39 MiB/s at 200 000.
  The script prints this warning itself below 100 000.
- The corpus is built with quoted fields containing commas, because a parser
  measured on `a,b,c` is measured on the case it does not have to work for.
- Parse throughput is measured with `-contains` on a needle that cannot match,
  so the number is the parser and not the writer. Timing `-r` would measure
  parse + encode + write and report a figure for something nobody does.
- The worker count in the parallel line comes from csv2's own `-debug`, not from
  `getconf _NPROCESSORS_ONLN`. busybox has no `getconf`, so in the guest that
  call fails and the fallback would quietly report one core — turning a
  measurement into a guess that happens to look like a number.
- Parallel efficiency is well under 100% by construction: the pass that finds
  record boundaries is single-threaded. The figure is printed so that "parallel"
  is not read as "P times faster".

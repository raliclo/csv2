# verifications

- **繁體中文：[README.zh-TW.md](README.zh-TW.md)**

Measurements, not tests. Nothing here passes or fails; it prints numbers and
writes them beside itself so a later run can be compared with an earlier one.
The pass/fail suite is [`../test/test_csv2.zsh`](../test/test_csv2.zsh).

```zsh
./measure.zsh              # results land in measure_output.txt
CSV2=/path/to/csv2 ./measure.zsh
```

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

## Reading these numbers honestly

- They are **best-of-N**, not averages: the fastest run is the one least
  polluted by other load. Compare like with like.
- The corpus is built with quoted fields containing commas, because a parser
  measured on `a,b,c` is measured on the case it does not have to work for.
- Parse throughput is measured with `-contains` on a needle that cannot match,
  so the number is the parser and not the writer. Timing `-r` would measure
  parse + encode + write and report a figure for something nobody does.
- **Not yet measured: the guest's disk throughput under QEMU.** That is the
  third item on the plan's list and it needs `measure.zsh` run inside the guest,
  where today's T47 flow builds csv2 into a per-run image clone that is deleted
  afterwards — a measurement has to leave its numbers behind to be worth taking.

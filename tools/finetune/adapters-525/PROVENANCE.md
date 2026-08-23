# Cumulative iteration 525 — the best validation loss

This directory holds the `adapter_config.json` for the checkpoint the evaluation
calls `@525`, and the record of which file that was. The weights themselves
(`adapters.safetensors`, 14 MB) are **not tracked** — they are a build product of
`tools/finetune/train.sh`. In the run described below they were a copy of
`tools/finetune/adapters/0000200_adapters.safetensors`.

The name is misleading and the mapping matters, so it is written down rather than
inferred. `mlx_lm` restarts its iteration counter at 1 on every resume, and names
checkpoints from the *local* count — so a supervised run that was interrupted
twice wrote three overlapping sets of filenames, each overwriting the last:

| attempt | local iters | cumulative | files written | mtime |
| --- | --- | --- | --- | --- |
| 1 | 1–325 | 1–325 | 25 … 325 | 23:27–23:30 |
| 2 | 1–200 | 326–525 | 25 … 200 (overwrote) | 23:35–23:38 |
| 3 | 1–75 | 526–600 | 25 … 75 (overwrote) | 23:41–23:42 |

So the surviving files are: 25–75 from attempt 3 (cumulative 550–600), 100–200
from attempt 2 (cumulative 425–525), and 225–325 from attempt 1 (unchanged).
`0000200_` was written at 23:38:39, inside attempt 2's window, and is therefore
cumulative **525** — confirmed by mtime, not by assuming.

Validation loss by cumulative iteration: 1:1.575 · 100:0.781 · 200:0.368 ·
300:0.808 · 326:0.512 · 425:0.518 · **525:0.338** · 526:0.439 · 600:0.497.

The final adapter is 525→600 further trained, at a *worse* validation loss, which
is why this checkpoint is worth measuring separately.

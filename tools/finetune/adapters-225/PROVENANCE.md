# Cumulative iteration 225 — a little over one epoch

This directory holds the `adapter_config.json` for the checkpoint the evaluation
calls `@225`, and the record of which file that was. The weights themselves
(`adapters.safetensors`, 14 MB) are **not tracked** — they are a build product of
`tools/finetune/train.sh`. In the run described below they were a copy of
`tools/finetune/adapters/0000225_adapters.safetensors`.

## Why this checkpoint exists as an arm

The published comparison measured the base model and two *late* checkpoints,
cumulative 525 and 600. Both are past two and a half epochs — 600 iterations at
an effective batch of four over 875 training examples — and both were clearly
worse than base on maths correctness. That result could not distinguish two
explanations:

- the fine-tune damages correctness, or
- the fine-tune damages correctness *when trained this long*.

875 examples at an effective batch of four is one epoch every ~219 iterations, so
cumulative 225 is the first checkpoint past one full pass over the data, and it
survives on disk. Adding it costs one arm and answers the question.

## Which file that is, and how it is known

The name is misleading and the mapping matters, so it is written down rather than
inferred. `mlx_lm` restarts its iteration counter at 1 on every resume and names
checkpoints from the *local* count, so a supervised run interrupted twice wrote
three overlapping sets of filenames, each overwriting the last:

| attempt | local iters | cumulative | files written | mtime |
| --- | --- | --- | --- | --- |
| 1 | 1–325 | 1–325 | 25 … 325 | 14:27:04–14:30:46 |
| 2 | 1–200 | 326–525 | 25 … 200 (overwrote) | 14:35:32–14:38:39 |
| 3 | 1–75 | 526–600 | 25 … 75 (overwrote) | 14:41:22–14:42:54 |

`0000225_adapters.safetensors` has an mtime of 14:27:04, inside attempt 1's
window, and attempt 1's files above 200 were never overwritten. It is therefore
cumulative **225** — confirmed by mtime, not by assuming.

The same table has a consequence worth stating: **there is no surviving
checkpoint below cumulative 225.** Attempt 1's files at 25–200 were overwritten
twice, so the earliest recoverable point in this run is one epoch in. A sub-epoch
arm would need a retrain, which is free but is not this.

Validation loss by cumulative iteration: 1:1.575 · 100:0.781 · **200:0.368** ·
300:0.808 · 326:0.512 · 425:0.518 · 525:0.338 · 526:0.439 · 600:0.497. Note that
225 sits between the 200 and 300 evaluations, on a curve computed over two
validation batches — which the three-arm comparison already showed predicts
nothing that matters.

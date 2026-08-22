## Schema compliance, per surface

Fraction of responses that decoded with nothing done to them -- no fence
removed, no prose trimmed, no LaTeX escape repaired, no renormalisation.

| backend | steps | lesson | formulas |
|---|---|---|---|
| `local/qwen3-4b+lora@525` | 88% (38/43) | 98% (42/43) | 50% (21/42) |
| `local/qwen3-4b+lora@600` | 93% (39/42) | 95% (41/43) | 56% (24/43) |
| `local/qwen3-4b-base` | 86% (36/42) | 88% (38/43) | 60% (26/43) |

## What had to be done, when it was not clean

| backend | surface | fenced | prose sliced | escapes repaired | renormalised | failed to parse |
|---|---|---|---|---|---|---|
| `local/qwen3-4b+lora@525` | steps | 0 | 0 | 3 | 0 | 0 |
| `local/qwen3-4b+lora@525` | lesson | 0 | 0 | 1 | 0 | 0 |
| `local/qwen3-4b+lora@525` | formulas | 0 | 0 | 21 | 0 | 1 |
| `local/qwen3-4b+lora@600` | steps | 0 | 0 | 2 | 0 | 1 |
| `local/qwen3-4b+lora@600` | lesson | 0 | 0 | 1 | 0 | 0 |
| `local/qwen3-4b+lora@600` | formulas | 0 | 0 | 19 | 0 | 0 |
| `local/qwen3-4b-base` | steps | 0 | 0 | 5 | 0 | 1 |
| `local/qwen3-4b-base` | lesson | 0 | 1 | 3 | 0 | 0 |
| `local/qwen3-4b-base` | formulas | 0 | 0 | 17 | 0 | 0 |

## Maths correctness (final answer, symbolic equivalence)

`undecidable` means the grader could not parse one side and the case
needs a human, not that the answer was wrong.

| backend | correct | wrong | undecidable |
|---|---|---|---|
| `local/qwen3-4b+lora@525` | 58% (25/43) | 8 | 10 |
| `local/qwen3-4b+lora@600` | 55% (23/42) | 9 | 10 |
| `local/qwen3-4b-base` | 74% (31/42) | 7 | 4 |

## Completeness: how much came back

Median items per response -- steps in a solution, formulas listed,
sections in a lesson. Schema compliance is blind to this: a one-step
solution that decodes cleanly scores a perfect 100%, so a fine-tune that
learns to answer tersely would look like an improvement.

| backend | steps | lesson sections | formulas | thin (<=1 step) |
|---|---|---|---|---|
| `local/qwen3-4b+lora@525` | 3 | 3 | 6 | 18/43 |
| `local/qwen3-4b+lora@600` | 3 | 3 | 6 | 17/42 |
| `local/qwen3-4b-base` | 3 | 3 | 6 | 8/42 |

## LaTeX that renders

Rendered with KaTeX 0.16.21 -- the version the app loads -- and
`throwOnError: true`. The app itself renders with `throwOnError: false`,
so in production these failures are silent.

| backend | strings checked | render | fail |
|---|---|---|---|
| `local/qwen3-4b+lora@525` | 491 | 97% (476) | 15 |
| `local/qwen3-4b+lora@600` | 492 | 97% (478) | 14 |
| `local/qwen3-4b-base` | 501 | 97% (487) | 14 |

## Latency and cost

Requests were issued one at a time, so these are per-request latencies
rather than what a user sees when four surfaces are fetched at once.
Time to first token is **not** measured: the app does not stream, so
there is no first token to time.

| backend | median s | p90 s | in tok | out tok | est. USD |
|---|---|---|---|---|---|
| `local/qwen3-4b+lora@525` | 7.76 | 13.15 | 32209 | 52009 | n/a (local) |
| `local/qwen3-4b+lora@600` | 7.35 | 12.32 | 32083 | 51689 | n/a (local) |
| `local/qwen3-4b-base` | 6.86 | 11.17 | 32089 | 51032 | n/a (local) |

Records: 387. Problems: 43.

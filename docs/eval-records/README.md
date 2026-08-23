# Graded evaluation records

The evidence for every number in [evaluation-local.md](../evaluation-local.md)
and for the fine-tune table in the [README](../../README.md). 387 records: 43
held-out problems across three surfaces (`steps`, `lesson`, `formulas`) for each
of three arms.

Published because a result that cannot be checked is an assertion. The tables
regenerate from these three files and nothing else:

```sh
python3 tools/eval/report.py docs/eval-records/*.graded.jsonl \
  | diff - docs/evaluation-local.md      # no output: the doc is stdout, not prose
```

That diff is the test. `docs/evaluation-local.md` is the generator's stdout and
nothing else, so a number that drifts from its evidence shows up as a failing
diff rather than as a paragraph nobody rechecked.

## Which file is which arm

The filenames predate the checkpoint numbering being understood, so `tuned` is
the *final* checkpoint rather than the best one. Stated here rather than left to
be inferred, for the same reason as
[adapters-525/PROVENANCE.md](../../tools/finetune/adapters-525/PROVENANCE.md).

| file | `backend` | what it is | records |
| --- | --- | --- | --- |
| `eval-base.graded.jsonl` | `local/qwen3-4b-base` | untuned `Qwen3-4B-4bit` | 129 |
| `eval-525.graded.jsonl` | `local/qwen3-4b+lora@525` | cumulative iteration 525, best validation loss | 129 |
| `eval-tuned.graded.jsonl` | `local/qwen3-4b+lora@600` | cumulative iteration 600, end of training | 129 |

All three arms were verified to be serving different weights before the run was
believed — an earlier attempt produced 129/129 byte-identical outputs from what
was supposed to be three models, and a report that looked entirely plausible.

## Schema

One JSON object per line.

| field | meaning |
| --- | --- |
| `problemId`, `topic` | the held-out problem, from `tools/finetune/problems.json` |
| `backend` | which arm produced this response |
| `surface` | `steps`, `lesson` or `formulas` |
| `ok` | the response decoded to the expected type at all |
| `itemCount` | items returned — steps in a solution, sections in a lesson, formulas listed. The completeness measure that caught the regression |
| `finalAnswer`, `expectedAnswer`, `expectedNumeric` | the answer as given, and the reference |
| `answerCorrect`, `answerNote` | symbolic-equivalence grade and the comparison behind it. `null` = undecidable, meaning the grader could not parse one side, **not** that the answer was wrong |
| `latex` | the LaTeX strings extracted from the response |
| `latexChecked`, `latexValid`, `latexErrors` | KaTeX 0.16.21 with `throwOnError: true` |
| `inputTokens`, `outputTokens`, `latencySeconds` | per request, issued serially |

## What is not in here

- **No raw model completions.** These are derived measurements: the extracted
  answer, the LaTeX, the counts and the grades. Reproducing the study needs the
  problem set and the config, both tracked; it does not need a redistribution of
  a provider's output.
- **No compliance provenance per record.** The `fenced` / `prose sliced` /
  `escapes repaired` columns are computed by `report.py` from the decode
  ladder's own `Compliance` value at grading time.
- **Nothing from the hosted API.** No Anthropic call was made in this project.
  Only the local arms were measured against each other.
- **No time to first token**, because the app does not stream, and **no
  concurrent-fetch latency**, because requests here ran one at a time while the
  app fans out four.

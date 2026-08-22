# Fine-tuning a small model for Solvr's output shape

The goal is not a better general model. It is a small model that reliably
produces **Solvr's** output shape: correct step decomposition, the lesson
structure in `LessonContent`, and LaTeX that renders.

There is now measured evidence for why that is the target rather than raw
capability. Apple's on-device model, asked through both `@Guide` descriptions and
session instructions for LaTeX, returns `∫[0,1] 3x^2 dx` — correct mathematics,
wrong notation — and firmer wording did not move it. `MathNotation` fixes the
part of that which a deterministic string pass can fix; the formulas surface
still writes the *word* "integral", and no string pass should try to rewrite
English into notation. **That gap is what a fine-tune is for.**

## Base model

`mlx-community/Qwen3-4B-4bit` — `model_type: qwen3`, `Qwen3ForCausalLM`,
36 layers, 8 KV heads, 4-bit, ~2.3 GB.

Chosen over the models already on disk because those cannot serve this purpose:

| candidate | why not |
| --- | --- |
| `gemma-4-E4B-it-MLX-4bit` | `mlx_lm` **cannot load it** — 42 layers with `num_kv_shared_layers: 18`, which `mlx_lm/models/gemma4_text.py` drops. `mlx_vlm` loads it but ships no `lora` entry point. |
| `Qwen3.5-9B`, `gemma-4-26B-A4B`, `Qwen3.8-27B` | 5.6–15 GB. Trainable here, but far too large to ever run on a phone. |

Qwen3-4B is a plain causal LM rather than a `*ForConditionalGeneration` wrapper,
has first-class `qwen3` support in both `mlx_lm` and `MLXLLM`, and carries none of
Gemma 4's per-layer-embedding quantization hazard.

**It is not, however, deployable to most iPhones.** At 4-bit it peaks around
2.3–2.5 GB, which needs an 8 GB device plus
`com.apple.developer.kernel.increased-memory-limit`. `Qwen3-1.7B` peaks near
1.06 GB and runs everywhere, shares the tokenizer and the prompt format, and
therefore takes the same dataset and the same recipe. Train 4B first, then the
1.7B sibling from the identical data.

## Choosing the teacher

The pipeline takes either, through the same downstream code, because the prompts
and the JSON schemas are shared and only the request envelope differs:

```sh
# Anthropic Messages API, output_config.format
export ANTHROPIC_API_KEY=...
swift run solvr-distill --confirm-spend                       # ~$41.60 for 400 problems

# Any OpenAI-compatible endpoint, response_format
export MOONSHOT_API_KEY=...
swift run solvr-distill --teacher openai \
    --base-url https://api.moonshot.ai/v1 \
    --key-env MOONSHOT_API_KEY --model <their-model-id> --confirm-spend
```

A cheaper teacher is a real option and the cost difference is large. Two things to
be clear about before committing a whole run to one:

**The student inherits the teacher.** Every weakness in step decomposition, in
lesson structure, in LaTeX, is copied. This is the one decision in the project
that cannot be fixed later by better engineering.

**So measure it rather than assume it.** The pipeline already does most of this
for free: `validate_targets.mjs` renders every LaTeX string a teacher produces and
drops the example if it fails, and reports the drop rate. A teacher producing
LaTeX that does not render will announce itself. Run `--limit 20` first (~80
requests), read the drop rate, hand-check five targets, and only then commit to
400. That costs a dollar or two and replaces an argument with a number.

Note also that a compatibility layer implements the *core* of an API, not
necessarily its recent additions. If `response_format` is silently ignored, the
targets come back as prose JSON rather than valid-by-construction — recoverable,
because `LLMJSON` will rescue them, but the guarantee the plan leans on is gone.
The drop rate and the compliance record will both show it.

## Data

`data/{train,valid,test}.jsonl`, in `mlx_lm.lora`'s chat format — one JSON object
per line:

```json
{"messages": [{"role": "user", "content": "<prompt>"}, {"role": "assistant", "content": "<the exact JSON Solvr expects>"}]}
```

Rules, not preferences:

- **Synthetic or mine to give.** No student work, no names, no tutoring records —
  not in the dataset, not in fixtures, not in examples.
- **Generated with `claude-opus-5`, then hand-checked.** This is distillation from
  a hosted model. Saying so is not a caveat, it is the method; people do lie about
  it.
- **The held-out split must be disjoint from the evaluation problems** in
  `Packages/SolvrCore/Sources/solvr-eval/problems.json`. If the eval set leaks
  into training, the headline number means nothing.
- Every assistant message must **parse and render**: pipe the dataset through the
  same graders the eval uses (`tools/eval/grade.sh`) before training on it.

## Training

```sh
~/.venvs/mlx/bin/mlx_lm.lora --config tools/finetune/lora-qwen3-4b.yaml --train
~/.venvs/mlx/bin/mlx_lm.fuse  --model mlx-community/Qwen3-4B-4bit \
    --adapter-path tools/finetune/adapters \
    --save-path ~/models/solvr-qwen3-4b
```

`--mask-prompt` is set deliberately: the loss belongs on the *output shape*, not
on the problem text, and the whole point is teaching a format.

Smoke-test with `--iters 2` before any long run. `mlx_lm.lora` converts
`Linear`/`QuantizedLinear`/`SwitchLinear`/`Embedding` in the last `--num-layers`
blocks generically, so anything `mlx_lm` can load is trainable — but a two-minute
check costs nothing next to discovering a layer-targeting problem an hour in.

Disk is the constraint to watch: ~89 GB free on a 96%-full volume, and `fuse`
writes a whole new copy of the model.

## Evaluating it

The fine-tune is served over the local network and measured by the same harness
as everything else, so the comparison is like-for-like:

```sh
~/.venvs/mlx/bin/mlx_lm.server --model ~/models/solvr-qwen3-4b \
    --host 127.0.0.1 --port 8131 \
    --chat-template-args '{"enable_thinking": false}'
```

Note what this backend cannot do: `mlx_lm.server` accepts no `response_format`,
JSON schema or grammar option — its only logits processors are repetition penalty
and logit bias. So it is **unconstrained**, and it is the one backend where the
`LLMJSON` repair ladder is genuinely load-bearing. That is the honest shape of the
result: constrained decoding is free compliance, and self-hosting gives it up.

**The claim to test is narrow.** A 4B fine-tune should win on format adherence and
pedagogy — section structure, step decomposition, renderable LaTeX — and is
expected to **lose on reasoning**. Both are measured. If it loses, the write-up
says by how much.

## Pipeline verified 2026-08-22, before any data was generated

Smoke-tested end to end on this Mac so that the expensive part — generating and
hand-checking the data — is not the first thing to discover a broken pipeline.

```
mlx_lm.lora   trainable 7.34M / 4022M (0.182%) over the last 16 of 36 blocks
              loss 2.680 -> 2.133 in 2 iterations, peak memory 3.56 GB
mlx_lm.fuse   2.1 GB fused model written, loads and generates
mlx_lm.generate  115 tok/s, peak memory 2.41 GB
```

Peak training memory of 3.56 GB against 64 GB means `num_layers` and
`batch_size` have plenty of headroom; the committed config is conservative, not
constrained.

### Qwen3 thinks out loud, and that has to be turned off

Generating from the fused model produced this before any answer:

```
<think>
Okay, so I need to find the derivative of f(x) = x^5. Hmm, let me remember...
```

Qwen3 has thinking enabled by default in its chat template. For a backend whose
entire job is to emit a JSON document that is *the whole response*, a reasoning
preamble is a problem. `LLMJSON.sliceJSONBody` would in fact rescue it — it takes
the outermost braces — but it would be recorded as `wasSliced`, i.e. as
non-compliance, on **every single response**, which would make the compliance
comparison meaningless.

So thinking is disabled at both ends:

- **Serving:** `--chat-template-args '{"enable_thinking": false}'`
- **Training:** the assistant turns in the dataset contain the JSON and nothing
  else, so the model is being taught to answer directly. Do not include a
  `<think>` block in a target.

This is the kind of thing that would otherwise show up as a mysterious 0%
compliance score and be blamed on the model.

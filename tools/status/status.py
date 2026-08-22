#!/usr/bin/env python3
"""Where the runs are, in one place.

Reads the artefacts the pipeline already writes -- there is no separate database
and nothing to keep in sync. That is the point: a status tool that needs its own
state is a second thing that can be wrong about what happened.

  tools/status/status.sh              one-shot terminal snapshot
  tools/status/status.sh --html       also write docs/run-status.html
  tools/status/status.sh --watch      refresh both every 10s
"""
import collections
import html
import json
import os
import pathlib
import re
import subprocess
import sys
import time

ROOT = pathlib.Path(__file__).resolve().parents[2]
RAW = ROOT / "tools/finetune/data/raw.jsonl"
DISTILL_LOG = pathlib.Path("/tmp/distill-run.err")
TRAIN_LOG = pathlib.Path("/tmp/lora-train.log")
ADAPTERS = ROOT / "tools/finetune/adapters"
EVAL_GLOB = "eval-*.graded.jsonl"

# Kimi K3 list price, USD per million tokens.
PRICE_IN, PRICE_OUT = 3.00, 15.00
# Measured averages per request, by surface (see tools/finetune/README.md).
TOKENS = {"steps": (489, 701), "lesson": (566, 1365),
          "formulas": (369, 674), "videos": (386, 700)}

SURFACE_MARKERS = [("steps", "Solve it step by step"),
                   ("lesson", "Teach the underlying math concept"),
                   ("formulas", "key mathematical formulas"),
                   ("videos", "YouTube educational videos")]


def surface_of(prompt: str) -> str:
    for name, marker in SURFACE_MARKERS:
        if marker in prompt:
            return name
    return "unknown"


def process_alive(pattern: str) -> bool:
    return subprocess.run(["pgrep", "-f", pattern],
                          capture_output=True).returncode == 0


def read_jsonl(path: pathlib.Path):
    if not path.exists():
        return []
    rows = []
    for line in path.read_text(errors="replace").splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            rows.append(json.loads(line))
        except json.JSONDecodeError:
            pass  # a line still being written
    return rows


def ledger_tokens():
    """Exact token counts, once a run has printed its ledger."""
    out = pathlib.Path("/tmp/distill-run.out")
    if not out.exists():
        return None
    m = re.search(r"tokens:\s+(\d+) in, (\d+) out", out.read_text(errors="replace"))
    return (int(m.group(1)), int(m.group(2))) if m else None


def distill_state():
    """Progress, cost and composition of the distillation run."""
    rows = read_jsonl(RAW)
    by_surface = collections.Counter(
        surface_of(r["messages"][0]["content"]) for r in rows)

    done = total = None
    rate = eta = None
    if DISTILL_LOG.exists():
        text = DISTILL_LOG.read_text(errors="replace").replace("\r", "\n")
        ticks = re.findall(r"(\d+)/(\d+)\s+([\d.]+) req/s\s+~(\d+)s left", text)
        if ticks:
            done, total, rate, eta = ticks[-1]
            done, total, rate, eta = int(done), int(total), float(rate), int(eta)
        failures = re.findall(r"(gen-\d+)/(\w+): (\w+)", text)
    else:
        failures = []

    # Prefer the run's own ledger over an extrapolation. The estimate was wrong
    # by 61% on a real run: the per-surface averages came from a six-problem probe,
    # and --limit takes the *first* six, which were all simple algebra. Integrals
    # and series reason far more, and reasoning tokens are billed as output. An
    # estimate built on the cheapest end of the distribution is worse than no
    # estimate, because it gets believed.
    ledger = ledger_tokens()
    if ledger:
        spend_in, spend_out = ledger
        estimated = False
    else:
        spend_in = sum(TOKENS.get(s, (450, 800))[0] * n for s, n in by_surface.items())
        spend_out = sum(TOKENS.get(s, (450, 800))[1] * n for s, n in by_surface.items())
        estimated = True
    cost = (spend_in * PRICE_IN + spend_out * PRICE_OUT) / 1e6

    return {
        "running": process_alive("solvr-distill"),
        "examples": len(rows),
        "bySurface": dict(by_surface),
        "done": done, "total": total, "rate": rate, "eta": eta,
        "failures": len(failures),
        "failureDetail": collections.Counter(f"{s}/{k}" for _, s, k in failures),
        "estimatedCost": cost,
        "tokensIn": spend_in, "tokensOut": spend_out,
        "costIsEstimate": estimated,
    }


def training_state():
    """Loss curves, progress and -- importantly -- how a run ended."""
    if not TRAIN_LOG.exists():
        return {"started": False, "running": process_alive("mlx_lm.lora")}
    text = TRAIN_LOG.read_text(errors="replace")
    # Offset each attempt's iteration numbers by what came before it. mlx_lm
    # restarts counting at 1 on every resume, so plotting the raw numbers drew
    # several overlapping series as one zigzag and the progress bar froze at
    # whatever the longest attempt reached.
    attempts = re.split(r"=== attempt \d+:[^=]*===", text)
    train, val, offset = [], [], 0
    for body in (attempts[1:] or [text]):
        t_here = [(int(i), float(l)) for i, l in
                  re.findall(r"Iter (\d+): Train loss ([\d.]+)", body)]
        v_here = [(int(i), float(l)) for i, l in
                  re.findall(r"Iter (\d+): Val loss ([\d.]+)", body)]
        train += [(i + offset, l) for i, l in t_here]
        val += [(i + offset, l) for i, l in v_here]
        offset += max([i for i, _ in t_here] or [0])
    peak = re.findall(r"Peak mem ([\d.]+) GB", text)
    speed = re.findall(r"Tokens/sec ([\d.]+)", text)
    trained = re.findall(r"Trained Tokens (\d+)", text)
    target = re.search(r"Starting training\.\.\., iters: (\d+)", text)
    trainable = re.search(r"Trainable parameters: ([\d.]+)% \(([\d.]+M)/", text)

    # How it ended matters as much as where it got to. A crashed run that still
    # shows its last loss looks like a finished one, which is exactly the sort of
    # thing a status page should not let you believe.
    running = process_alive("mlx_lm.lora")

    # Only look for a failure in the *last* attempt, and only report one at all if
    # nothing is running now. Showing the first error found in the whole log meant
    # a live, recovering run displayed a red box from an attempt it had already
    # recovered from -- which reads as "broken" when the truth is "retrying".
    failure = None
    if not running:
        tail = (attempts[-1] if len(attempts) > 1 else text)
        for pattern in (r"RuntimeError: (.+)", r"(\[METAL\].+)", r"(MemoryError.*)",
                        r"(KeyboardInterrupt)"):
            found = re.search(pattern, tail)
            if found:
                failure = found.group(1).strip()[:180]
                break
    retries = max(len(attempts) - 2, 0)
    last_iter = max([i for i, _ in train] + [0])
    total = int(target.group(1)) if target else None
    if running:
        outcome = "running"
    elif failure:
        outcome = "crashed"
    elif total and last_iter >= total:
        outcome = "finished"
    elif last_iter:
        outcome = "stopped early"
    else:
        outcome = "not started"

    return {
        "started": True,
        "running": running,
        "outcome": outcome,
        "failure": failure,
        "train": train, "val": val,
        "iter": last_iter, "iters": total,
        "peakMemoryGB": float(peak[-1]) if peak else None,
        "tokensPerSecond": float(speed[-1]) if speed else None,
        "trainedTokens": int(trained[-1]) if trained else None,
        "trainablePercent": trainable.group(1) if trainable else None,
        "trainableParams": trainable.group(2) if trainable else None,
        "adapterSaved": (ADAPTERS / "adapters.safetensors").exists(),
        "retries": retries,
    }


def eval_state():
    """Any graded evaluation runs sitting in the repo root."""
    runs = []
    for path in sorted(ROOT.glob(EVAL_GLOB)):
        rows = read_jsonl(path)
        if not rows:
            continue
        backends = collections.Counter(r["backend"] for r in rows)
        ok = [r for r in rows if r.get("ok")]
        clean = sum(1 for r in ok if r.get("isClean"))
        latex_checked = sum(r.get("latexChecked", 0) for r in rows)
        latex_valid = sum(r.get("latexValid", 0) for r in rows)
        graded = [r for r in rows if "answerCorrect" in r]
        runs.append({
            "file": path.name,
            "backends": dict(backends),
            "records": len(rows),
            "cleanPct": 100 * clean / len(ok) if ok else None,
            "latexPct": 100 * latex_valid / latex_checked if latex_checked else None,
            "correctPct": 100 * sum(1 for r in graded if r["answerCorrect"] is True)
                          / len(graded) if graded else None,
        })
    return runs


# ---------------------------------------------------------------- terminal view

def bar(value, total, width=28, fill="█", empty="░"):
    if not total:
        return empty * width
    filled = int(width * min(value / total, 1.0))
    return fill * filled + empty * (width - filled)


def terminal(state):
    d, t, evals = state["distill"], state["training"], state["eval"]
    out = []
    out.append("\033[1mSOLVR — RUN STATUS\033[0m   " + time.strftime("%H:%M:%S"))
    out.append("")

    # Distillation
    status = "\033[32mrunning\033[0m" if d["running"] else "\033[90midle\033[0m"
    out.append(f"\033[1mDistillation\033[0m ({status})")
    if d["done"]:
        pct = 100 * d["done"] / d["total"]
        out.append(f"  {bar(d['done'], d['total'])} {d['done']}/{d['total']}  {pct:.0f}%")
        if d["running"] and d["eta"]:
            out.append(f"  {d['rate']:.1f} req/s   ~{d['eta'] // 60} min left")
    out.append(f"  examples written  {d['examples']}")
    if d["bySurface"]:
        widest = max(len(s) for s in d["bySurface"])
        peak = max(d["bySurface"].values())
        for surface, n in sorted(d["bySurface"].items()):
            out.append(f"    {surface:<{widest}}  {bar(n, peak, 18)} {n}")
    if d["failures"]:
        out.append(f"  \033[33mfailed {d['failures']}\033[0m "
                   f"({', '.join(f'{k}:{v}' for k, v in d['failureDetail'].most_common(3))})")
    label = "spend (est)  " if d["costIsEstimate"] else "spend (actual)"
    remaining = 25.0 - d["estimatedCost"]
    out.append(f"  {label}     ${d['estimatedCost']:.2f}   "
               f"{d['tokensIn'] / 1000:.0f}k in / {d['tokensOut'] / 1000:.0f}k out")
    warn = "\033[31m" if remaining < 2 else ""
    out.append(f"  {warn}budget left       ${remaining:.2f}\033[0m  "
               f"\033[90m(list price; cache hits make the real balance higher)\033[0m")
    out.append("")

    # Training
    colours = {"running": "\033[32m", "crashed": "\033[31m",
               "finished": "\033[32m", "stopped early": "\033[33m"}
    outcome = t.get("outcome", "not started")
    out.append(f"\033[1mLoRA training\033[0m "
               f"({colours.get(outcome, '\033[90m')}{outcome}\033[0m)")
    if t["started"]:
        if t.get("iters"):
            out.append(f"  {bar(t['iter'], t['iters'])} iter {t['iter']}/{t['iters']}")
        if t["train"]:
            out.append(f"  train loss {t['train'][0][1]:.3f} → {t['train'][-1][1]:.3f}")
        if t["val"]:
            out.append(f"  val loss   {t['val'][0][1]:.3f} → {t['val'][-1][1]:.3f}")
        bits = []
        if t.get("trainablePercent"):
            bits.append(f"{t['trainableParams']} trainable ({t['trainablePercent']}%)")
        if t.get("peakMemoryGB"):
            bits.append(f"peak {t['peakMemoryGB']:.2f} GB")
        if t.get("tokensPerSecond"):
            bits.append(f"{t['tokensPerSecond']:.0f} tok/s")
        if t.get("retries"):
            bits.append(f"{t['retries']} Metal restarts")
        if bits:
            out.append("  " + " · ".join(bits))
        out.append(f"  adapter saved: {'yes' if t['adapterSaved'] else 'not yet'}")
        if t.get("failure"):
            out.append(f"  \033[31m{t['failure']}\033[0m")
    out.append("")

    # Evaluation
    out.append("\033[1mEvaluation\033[0m")
    if not evals:
        out.append("  \033[90mno graded runs yet\033[0m")
    for run in evals:
        out.append(f"  {run['file']}  ({run['records']} records)")
        for label, key, unit in [("schema clean", "cleanPct", "%"),
                                 ("latex renders", "latexPct", "%"),
                                 ("answer correct", "correctPct", "%")]:
            v = run[key]
            out.append(f"    {label:<15} " +
                       (f"{bar(v or 0, 100, 20)} {v:.0f}{unit}" if v is not None else "n/a"))
    return "\n".join(out)


# -------------------------------------------------------------------- html view

def svg_bars(items, width=520, height=None, colour="#5856D6"):
    """A horizontal bar chart, inline, no dependencies."""
    if not items:
        return "<p class='muted'>nothing yet</p>"
    rowh, gap = 26, 6
    height = height or len(items) * (rowh + gap)
    peak = max(v for _, v in items) or 1
    label_w = 108
    parts = [f"<svg viewBox='0 0 {width} {height}' role='img'>"]
    for i, (label, value) in enumerate(items):
        y = i * (rowh + gap)
        w = (width - label_w - 46) * value / peak
        parts.append(
            f"<text x='0' y='{y + 17}' class='lbl'>{html.escape(str(label))}</text>"
            f"<rect x='{label_w}' y='{y}' width='{max(w, 2):.1f}' height='{rowh}' rx='4' fill='{colour}'/>"
            f"<text x='{label_w + max(w, 2) + 8:.1f}' y='{y + 17}' class='val'>{value}</text>")
    parts.append("</svg>")
    return "".join(parts)


def svg_lines(series, width=520, height=180):
    """Loss curves. Two series, shared axes, no dependencies."""
    points = [p for _, pts in series for p in pts]
    if len(points) < 2:
        return "<p class='muted'>no loss data yet</p>"
    xs = [x for x, _ in points]
    ys = [y for _, y in points]
    x0, x1 = min(xs), max(xs) or 1
    y0, y1 = min(ys), max(ys)
    pad, span = 34, max(y1 - y0, 1e-6)

    def place(x, y):
        px = pad + (width - pad - 10) * (x - x0) / max(x1 - x0, 1)
        py = height - pad - (height - pad - 12) * (y - y0) / span
        return f"{px:.1f},{py:.1f}"

    out = [f"<svg viewBox='0 0 {width} {height}' role='img'>"]
    out.append(f"<line x1='{pad}' y1='{height - pad}' x2='{width - 6}' y2='{height - pad}' class='axis'/>")
    out.append(f"<line x1='{pad}' y1='8' x2='{pad}' y2='{height - pad}' class='axis'/>")
    out.append(f"<text x='2' y='16' class='tick2'>{y1:.2f}</text>")
    out.append(f"<text x='2' y='{height - pad}' class='tick2'>{y0:.2f}</text>")
    out.append(f"<text x='{width - 40}' y='{height - 12}' class='tick2'>iter {x1}</text>")
    for colour, (name, pts) in zip(["#5856D6", "#FF9500"], series):
        if len(pts) < 2:
            continue
        path = " ".join(place(x, y) for x, y in pts)
        out.append(f"<polyline points='{path}' fill='none' stroke='{colour}' stroke-width='2'/>")
    out.append("</svg>")
    legend = " ".join(
        f"<span class='key'><i style='background:{c}'></i>{html.escape(n)}</span>"
        for c, (n, pts) in zip(["#5856D6", "#FF9500"], series) if len(pts) >= 2)
    return "".join(out) + f"<div class='legend'>{legend}</div>"


def render_html(state):
    d, t, evals = state["distill"], state["training"], state["eval"]
    pct = 100 * d["done"] / d["total"] if d["done"] else 0
    budget = 25.0

    def summary_row(title, bits):
        """A finished stage, in one line."""
        cells = "".join(f"<span class='sm'><b>{v}</b>{k}</span>" for k, v in bits)
        return (f"<section class='done'><h2>{html.escape(title)} "
                f"<span class='tick'>done</span></h2><div class='sumrow'>{cells}</div></section>")

    def card(title, body, note=""):
        return (f"<section><h2>{html.escape(title)}</h2>{body}"
                + (f"<p class='muted'>{note}</p>" if note else "") + "</section>")

    distill_body = f"""
      <div class='row'>
        <div class='stat'><b>{d['examples']}</b><span>examples</span></div>
        <div class='stat'><b>{d['done'] or 0}/{d['total'] or 0}</b><span>requests</span></div>
        <div class='stat'><b>${d['estimatedCost']:.2f}</b><span>of ${budget:.0f} spent{' (est)' if d['costIsEstimate'] else ''}</span></div>
        <div class='stat'><b>${budget - d['estimatedCost']:.2f}</b><span>budget left</span></div>
        <div class='stat'><b>{d['failures']}</b><span>failed</span></div>
      </div>
      <div class='track'><div class='fill' style='width:{pct:.1f}%'></div></div>
      <p class='muted'>{'running — ~%d min left' % (d['eta'] // 60) if d['running'] and d['eta'] else 'idle'}</p>
      {svg_bars(sorted(d['bySurface'].items()))}"""

    if t["started"]:
        pct_iter = 100 * t["iter"] / t["iters"] if t.get("iters") else 0
        badge = {"running": "#34C759", "crashed": "#FF3B30",
                 "finished": "#34C759", "stopped early": "#FF9500"}.get(
                     t.get("outcome"), "#8E8E93")
        stats = f"""
          <div class='row'>
            <div class='stat'><b>{t['iter']}/{t.get('iters') or '?'}</b><span>iteration</span></div>
            <div class='stat'><b>{t['train'][-1][1]:.3f}</b><span>train loss</span></div>
            <div class='stat'><b>{t['val'][-1][1]:.3f}</b><span>val loss</span></div>
            <div class='stat'><b>{(t.get('peakMemoryGB') or 0):.1f} GB</b><span>peak memory</span></div>
          </div>""" if t["train"] and t["val"] else ""
        training_body = (
            f"<p><span class='badge' style='background:{badge}'></span>"
            f"{html.escape(t.get('outcome', ''))}</p>"
            + stats
            + f"<div class='track'><div class='fill' style='width:{pct_iter:.1f}%'></div></div>"
            + svg_lines([("train", t["train"]), ("validation", t["val"])])
            + (f"<p class='muted'>{t['retries']} Metal restart(s), resumed from "
               f"checkpoints · " if t.get("retries") else "<p class='muted'>")
            + (f"validation runs every 100 steps, so that figure "
               f"holds between checkpoints · {t['trainableParams']} trainable of 4.0B "
               f"({t['trainablePercent']}%) · "
               f"{(t.get('tokensPerSecond') or 0):.0f} tok/s · adapter "
               f"{'saved' if t['adapterSaved'] else 'not yet saved'}</p>"
               if t.get("trainablePercent") else "")
            + (f"<p class='err'>{html.escape(t['failure'])}</p>"
               if t.get("failure") else ""))
    else:
        training_body = "<p class='muted'>not started</p>"

    if evals:
        rows = []
        for run in evals:
            cells = "".join(
                f"<td>{'—' if run[k] is None else f'{run[k]:.0f}%'}</td>"
                for k in ("cleanPct", "latexPct", "correctPct"))
            rows.append(f"<tr><td class='mono'>{html.escape(', '.join(run['backends']))}</td>"
                        f"<td>{run['records']}</td>{cells}</tr>")
        eval_body = ("<table><thead><tr><th>backend</th><th>records</th>"
                     "<th>schema clean</th><th>latex renders</th>"
                     "<th>answer correct</th></tr></thead><tbody>"
                     + "".join(rows) + "</tbody></table>")
    else:
        eval_body = "<p class='muted'>no graded runs yet</p>"

    # Order by what is actually happening. A completed stage collapses to one
    # line, because the thing worth reading is the thing still moving -- and the
    # finished distillation card was tall enough to push a live training run below
    # the fold, which is the one job this page has.
    distill_done = not d["running"] and d["done"] and d["done"] >= (d["total"] or 0)
    sections = []

    if t["started"] and (t["running"] or not distill_done):
        sections.append(card("LoRA training (Qwen3-4B)", training_body))

    if distill_done:
        sections.append(summary_row("Distillation (Kimi K3)", [
            (" examples", d["examples"]),
            (" requests", f"{d['done']}/{d['total']}"),
            (" failed", d["failures"]),
            (" spent", f"${d['estimatedCost']:.2f}"),
        ]))
    else:
        sections.append(card("Distillation (Kimi K3)", distill_body,
            ("Spend is estimated from per-surface averages and has been wrong by 61% "
             "before. " if d["costIsEstimate"] else "Spend is the run's own token ledger. ")
            + "Kimi K3 at $3/$15 per Mtok; the console balance is authoritative, "
              "since cache-hit input bills at $0.30."))

    if not (t["started"] and (t["running"] or not distill_done)):
        sections.append(card("LoRA training (Qwen3-4B)", training_body))

    sections.append(card("Evaluation", eval_body))

    return f"""<!DOCTYPE html>
<html lang="en"><head>
<meta charset="utf-8"><title>Solvr — run status</title>
<meta http-equiv="refresh" content="10">
<style>
  :root {{ --accent:#5856D6; --bg:#F7F7FA; --card:#fff; --text:#111; --muted:#8E8E93; }}
  @media (prefers-color-scheme: dark) {{
    :root {{ --bg:#111114; --card:#1C1C20; --text:#F2F2F7; --muted:#8E8E93; }}
  }}
  * {{ box-sizing:border-box }}
  body {{ margin:0; padding:26px 20px 40px; background:var(--bg); color:var(--text);
         font:15px/1.5 -apple-system,BlinkMacSystemFont,"SF Pro Text",system-ui,sans-serif }}
  h1 {{ font-size:23px; margin:0 0 3px }}
  h2 {{ font-size:12px; text-transform:uppercase; letter-spacing:.06em;
        color:var(--muted); margin:0 0 12px }}
  .wrap {{ max-width:600px; margin:0 auto }}
  section {{ background:var(--card); border-radius:14px; padding:18px; margin:14px 0 }}
  section.done {{ padding:12px 16px }}
  section.done h2 {{ margin:0 0 6px }}
  .tick {{ color:#34C759; letter-spacing:0; text-transform:none; font-weight:600 }}
  .sumrow {{ display:flex; gap:18px; flex-wrap:wrap; font-size:12px; color:var(--muted) }}
  .sm b {{ color:var(--text); font-size:15px; margin-right:5px;
           font-variant-numeric:tabular-nums }}
  .row {{ display:flex; gap:8px; flex-wrap:wrap; margin-bottom:12px }}
  .stat {{ flex:1; min-width:96px; background:var(--bg); border-radius:10px; padding:9px 11px }}
  .stat b {{ display:block; font-size:19px; font-variant-numeric:tabular-nums }}
  .stat span {{ font-size:10px; color:var(--muted) }}
  .track {{ height:7px; background:var(--bg); border-radius:99px; overflow:hidden }}
  .fill {{ height:100%; background:var(--accent); border-radius:99px; transition:width .4s }}
  .muted {{ color:var(--muted); font-size:12px; margin:9px 0 0 }}
  svg {{ width:100%; height:auto; overflow:visible; margin-top:10px }}
  .lbl {{ font-size:12px; fill:var(--muted) }}
  .val {{ font-size:12px; fill:var(--text); font-variant-numeric:tabular-nums }}
  .axis {{ stroke:var(--muted); stroke-width:1; opacity:.3 }}
  .tick2 {{ font-size:10px; fill:var(--muted) }}
  .legend {{ margin-top:6px; font-size:11px; color:var(--muted) }}
  .key {{ margin-right:12px }} .key i {{ display:inline-block; width:9px; height:9px;
        border-radius:2px; margin-right:5px }}
  table {{ width:100%; border-collapse:collapse; font-size:13px }}
  th {{ text-align:left; font-weight:500; color:var(--muted); font-size:11px;
        padding-bottom:6px }}
  td {{ padding:6px 0; border-top:1px solid var(--bg); font-variant-numeric:tabular-nums }}
  .mono {{ font-family:ui-monospace,SFMono-Regular,monospace; font-size:11px }}
  .badge {{ display:inline-block; width:8px; height:8px; border-radius:99px;
            margin-right:7px; vertical-align:middle }}
  .err {{ background:rgba(255,59,48,.12); color:#FF6961; border-radius:8px;
          padding:9px 11px; font-size:12px; margin:12px 0 0;
          font-family:ui-monospace,SFMono-Regular,monospace }}
  footer {{ color:var(--muted); font-size:11px; text-align:center; margin-top:6px }}
</style></head><body><div class="wrap">
<h1>Solvr — run status</h1>
<p class="muted">{time.strftime('%H:%M:%S')} · refreshes every 10s ·
  <span class="mono">tools/status/watch.sh</span> keeps it current</p>
{"".join(sections)}
<footer>Reads the pipeline's own artefacts — no separate state to fall out of sync.</footer>
</div></body></html>"""


def collect():
    return {"distill": distill_state(), "training": training_state(), "eval": eval_state()}


def main():
    args = sys.argv[1:]
    watch = "--watch" in args
    want_html = "--html" in args or watch
    while True:
        state = collect()
        if want_html:
            out = ROOT / "docs/run-status.html"
            out.write_text(render_html(state))
        if not watch:
            print(terminal(state))
            if want_html:
                print(f"\nwrote {ROOT / 'docs/run-status.html'}")
            return
        os.system("clear")
        print(terminal(state))
        print("\n\033[90mwriting docs/run-status.html every 10s — ctrl-c to stop\033[0m")
        time.sleep(10)


if __name__ == "__main__":
    main()

#!/usr/bin/env node
// Checks that every LaTeX string in a distilled target would actually render.
//
// The graders the evaluation uses, pointed at the training data instead. A target
// containing LaTeX that does not render teaches the model to produce LaTeX that
// does not render, and that is the one failure mode a fine-tune can bake in
// permanently. Cheaper to catch here than to measure later and wonder why.
import { createInterface } from "node:readline";
import { createReadStream } from "node:fs";
import katex from "katex";

const [input] = process.argv.slice(2);
if (!input) {
  process.stderr.write("usage: validate_targets.mjs <raw.jsonl>\n");
  process.exit(2);
}

// Every field in Solvr's schemas that is meant to hold LaTeX.
function latexStrings(value) {
  const out = [];
  const walk = (node, key) => {
    if (node == null) return;
    if (typeof node === "string") {
      if (key === "math" || key === "formula") out.push(node);
      return;
    }
    if (Array.isArray(node)) { node.forEach((v) => walk(v, key)); return; }
    if (typeof node === "object") {
      for (const [k, v] of Object.entries(node)) walk(v, k);
    }
  };
  walk(value, null);
  return out;
}

const rl = createInterface({ input: createReadStream(input) });
let total = 0, kept = 0, badJSON = 0, badLatex = 0, checked = 0, failed = 0;

for await (const line of rl) {
  if (!line.trim()) continue;
  total++;
  const example = JSON.parse(line);
  const target = example.messages?.at(-1)?.content ?? "";

  let parsed;
  try { parsed = JSON.parse(target); }
  catch { badJSON++; continue; }

  const strings = latexStrings(parsed);
  const errors = [];
  for (const tex of strings) {
    if (!tex) continue;
    checked++;
    try { katex.renderToString(tex, { throwOnError: true, displayMode: true }); }
    catch (e) { failed++; errors.push(`${tex} :: ${String(e.message).slice(0, 90)}`); }
  }
  if (errors.length) {
    badLatex++;
    process.stderr.write(`drop: ${errors[0]}\n`);
    continue;
  }
  kept++;
  process.stdout.write(line + "\n");
}

process.stderr.write(
  `\nvalidated ${total} examples: kept ${kept}, dropped ${badJSON} unparseable, ` +
  `${badLatex} with LaTeX that does not render\n` +
  `latex strings: ${checked - failed}/${checked} render\n`);

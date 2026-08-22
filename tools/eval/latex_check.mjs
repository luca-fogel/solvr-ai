#!/usr/bin/env node
// Counts how much of a backend's LaTeX would actually render.
//
// The app cannot tell us this. HTMLBuilder renders with `throwOnError: false`,
// which is right for a shipping app -- a malformed formula should not blank the
// screen -- but it means invalid LaTeX fails silently and looks like a rendering
// quirk rather than a wrong answer. So we render the same strings here with
// `throwOnError: true`, against the same KaTeX version the app loads (0.16.21),
// and count what throws.
//
// Usage: node latex_check.mjs in.jsonl > out.jsonl
import { createInterface } from "node:readline";
import katex from "katex";

const [input] = process.argv.slice(2);
if (!input) {
  process.stderr.write("usage: latex_check.mjs <results.jsonl>\n");
  process.exit(2);
}

const rl = createInterface({ input: (await import("node:fs")).createReadStream(input) });
let checked = 0, invalid = 0;

for await (const line of rl) {
  if (!line.trim()) continue;
  const record = JSON.parse(line);
  const errors = [];
  let valid = 0;
  for (const tex of record.latex ?? []) {
    checked++;
    try {
      katex.renderToString(tex, { throwOnError: true, displayMode: true });
      valid++;
    } catch (e) {
      invalid++;
      errors.push({ tex, message: String(e.message).slice(0, 160) });
    }
  }
  record.latexChecked = (record.latex ?? []).length;
  record.latexValid = valid;
  record.latexErrors = errors;
  process.stdout.write(JSON.stringify(record) + "\n");
}

process.stderr.write(
  `latex: ${checked - invalid}/${checked} strings render under KaTeX ${
    (await import("katex/package.json", { with: { type: "json" } })).default.version
  }\n`);

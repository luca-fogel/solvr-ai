#!/usr/bin/env node
// Counts how much of a backend's LaTeX would actually render, and how much of it
// we broke ourselves.
//
// The app used to render with `throwOnError: false`, which is why this file
// existed: a malformed formula was drawn in red and looked like a rendering
// quirk rather than a wrong answer, so the only way to count them was here. The
// app now renders with `throwOnError: true` and degrades honestly, but this is
// still where the counting happens, and it has gained the more useful column.
//
// **`converterRegressions`** is the number of strings the model wrote that KaTeX
// accepted, and that `MathNotation` then turned into something KaTeX rejects.
// Every record carries both forms -- `rawMath` before conversion, `latex` after
// -- so the comparison is free, and it is the one that matters: three separate
// corruption bugs have shipped from that converter (`\sqrt16`, `\sine`,
// `\intx`), and all three would have shown up in this column on the run that
// introduced them.
//
// KaTeX comes from the app's own bundle rather than from node_modules. The npm
// copy is pinned to 0.16.21 and so is the vendored one, but "pinned to the same
// version" is not the same claim as "the same file", and the point of this
// script is to render what the app renders.
//
// Usage: node latex_check.mjs in.jsonl > out.jsonl
import { createInterface } from "node:readline";
import { createReadStream, readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import vm from "node:vm";

const here = dirname(fileURLToPath(import.meta.url));
const bundle = join(here, "..", "..", "solvr.ai", "Resources", "KaTeX", "katex.min.js");

const sandbox = {};
try {
  vm.runInNewContext(readFileSync(bundle, "utf8"), sandbox);
} catch (e) {
  process.stderr.write(`could not load ${bundle}: ${e.message}\n`);
  process.exit(1);
}
const katex = sandbox.katex;
if (!katex) {
  process.stderr.write(`no katex global after evaluating ${bundle}\n`);
  process.exit(1);
}

const [input] = process.argv.slice(2);
if (!input) {
  process.stderr.write("usage: latex_check.mjs <results.jsonl>\n");
  process.exit(2);
}

function renders(tex) {
  try {
    katex.renderToString(tex, { throwOnError: true, displayMode: true });
    return true;
  } catch (e) {
    return String(e.message);
  }
}

const rl = createInterface({ input: createReadStream(input) });
let checked = 0, invalid = 0, regressions = 0;

for await (const line of rl) {
  if (!line.trim()) continue;
  const record = JSON.parse(line);
  const errors = [];
  let valid = 0;
  for (const tex of record.latex ?? []) {
    checked++;
    const result = renders(tex);
    if (result === true) {
      valid++;
    } else {
      invalid++;
      errors.push({ tex, message: result.slice(0, 160) });
    }
  }
  record.latexChecked = (record.latex ?? []).length;
  record.latexValid = valid;
  record.latexErrors = errors;

  // What the converter did to maths that was already fine.
  //
  // `rawMath` and `convertedMath` are index-aligned by the harness, empty on
  // the converted side where the field was dropped for reading as prose. A
  // dropped field is not a regression: it was deliberately not shown.
  const raws = record.rawMath ?? [];
  const converteds = record.convertedMath ?? [];
  const broken = [];
  for (let i = 0; i < Math.min(raws.length, converteds.length); i++) {
    const raw = raws[i], converted = converteds[i];
    if (!converted) continue;                     // dropped, not rendered
    if (raw === converted) continue;              // untouched
    if (renders(raw) !== true) continue;          // it was already broken
    const after = renders(converted);
    if (after !== true) broken.push({ raw, converted, message: after.slice(0, 160) });
  }
  record.converterRegressions = broken.length;
  if (broken.length) {
    record.converterRegressionDetail = broken;
    regressions += broken.length;
  }

  process.stdout.write(JSON.stringify(record) + "\n");
}

process.stderr.write(
  `latex: ${checked - invalid}/${checked} strings render under vendored KaTeX ` +
  `${katex.version}\n`);
if (regressions) {
  process.stderr.write(
    `WARNING: ${regressions} string(s) rendered before MathNotation touched them ` +
    `and not after\n`);
}

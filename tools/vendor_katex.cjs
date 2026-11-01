// Run npm ci --ignore-scripts first: npm verifies the lockfile's integrity.
// Keep the app's bundled renderer in sync with Dependabot's package update.
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const assert = require('node:assert/strict');
const source = path.join(__dirname, 'node_modules/katex');
const destination = path.join(__dirname, '../solvr.ai/Resources/KaTeX');
const lock = require('./package-lock.json').packages['node_modules/katex'];
const version = require(path.join(source, 'package.json')).version;
assert.equal(version, require('./package.json').dependencies.katex);
assert.equal(version, lock.version);
const files = {
  'katex.min.js': 'dist/katex.min.js',
  'katex.min.css': 'dist/katex.min.css',
  'auto-render.min.js': 'dist/contrib/auto-render.min.js',
  LICENSE: 'LICENSE',
};
for (const name of fs.readdirSync(path.join(source, 'dist/fonts')).sort()) {
  if (name.endsWith('.woff2')) files[`fonts/${name}`] = `dist/fonts/${name}`;
}
const hashes = {};
for (const [target, original] of Object.entries(files)) {
  const content = fs.readFileSync(path.join(source, original));
  const output = path.join(destination, target);
  fs.mkdirSync(path.dirname(output), {recursive: true});
  fs.writeFileSync(output, content);
  hashes[target] = crypto.createHash('sha256').update(content).digest('hex');
}
fs.writeFileSync(path.join(destination, 'vendor.json'), JSON.stringify({
  package: 'katex', version, tarball: lock.resolved, integrity: lock.integrity, files: hashes,
}, null, 2) + '\n');
console.log(`Vendored KaTeX ${version}: ${Object.keys(hashes).length} verified package files`);

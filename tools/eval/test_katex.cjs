const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const crypto = require('node:crypto');
const root = path.resolve(__dirname, '../../solvr.ai/Resources/KaTeX');
const metadata = JSON.parse(fs.readFileSync(path.join(root, 'vendor.json')));
function renderer() {
  const context = vm.createContext({});
  vm.runInContext(fs.readFileSync(path.join(root, 'katex.min.js'), 'utf8'), context);
  return context;
}
test('vendored assets match the pinned release and recorded hashes', () => {
  const dependency = require('../package.json').dependencies.katex;
  assert.equal(renderer().katex.version, dependency);
  assert.equal(metadata.version, dependency);
  for (const [file, expected] of Object.entries(metadata.files)) {
    assert.equal(crypto.createHash('sha256').update(fs.readFileSync(path.join(root, file))).digest('hex'), expected, file);
  }
});
test('inherited trust cannot enable external graphics', () => {
  const context = renderer();
  vm.runInContext(`Object.prototype.trust = true;
    output = katex.renderToString('\\\\includegraphics{https://example.invalid/image.png}', {});`, context);
  assert.ok(!context.output.includes('<img'));
});
test('normal equations render and unsafe explicit commands stay untrusted', () => {
  const katex = renderer().katex;
  for (const tex of ['x^2 + 1', '\\frac{1}{2}', '\\int_0^1 x \\, dx']) {
    assert.ok(katex.renderToString(tex, {throwOnError: true, trust: false}).includes('katex'));
  }
  assert.ok(!katex.renderToString('\\includegraphics{https://example.invalid/image.png}', {trust: false}).includes('<img'));
});

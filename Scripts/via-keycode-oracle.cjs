#!/usr/bin/env node
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const [appPath, dependencies, readerPath] = process.argv.slice(2);
if (!appPath || !dependencies || !readerPath || process.argv.length !== 5) {
  throw new Error('Usage: node via-keycode-oracle.cjs <official VIA app checkout> <node_modules> <@the-via/reader directory>');
}
const ts = require(path.resolve(dependencies, 'typescript'));
const modules = new Map();
function load(filename) {
  filename = path.resolve(filename);
  if (modules.has(filename)) return modules.get(filename);
  const compiled = ts.transpileModule(fs.readFileSync(filename, 'utf8'), {
    compilerOptions: {target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.CommonJS},
    reportDiagnostics: true,
  });
  assert.equal((compiled.diagnostics || []).filter(item => item.category === ts.DiagnosticCategory.Error).length, 0);
  const exports = {};
  modules.set(filename, exports);
  const context = vm.createContext({exports, require: name => {
    if (name === '@the-via/reader') return require(path.resolve(readerPath));
    if (name.startsWith('./')) return load(path.resolve(path.dirname(filename), `${name}.ts`));
    throw new Error(`Unexpected official dependency: ${name}`);
  }});
  new vm.Script(compiled.outputText, {filename}).runInContext(context);
  return exports;
}
const keys = load(path.join(appPath, 'src/utils/key.ts'));
const dictionaries = load(path.join(appPath, 'src/utils/key-to-byte/dictionary-store.ts'));
let count = 0;
for (const protocol of [7, 10, 11, 12, 13]) {
  const dictionary = dictionaries.getBasicKeyDict(protocol, protocol === 13 ? 0 : undefined);
  const reverse = keys.getByteToKey(dictionary);
  for (const token of ['FN_MO13', 'FN_MO23']) {
    const raw = keys.getByteForCode(token, dictionary);
    assert.equal(typeof raw, 'number');
    assert.equal(keys.getCodeForByte(raw, dictionary, reverse), token);
    const layerMenu = keys.getKeycodes().find(menu => menu.keycodes.some(key => key.code === token));
    assert.ok(layerMenu);
    assert.match(layerMenu.keycodes.find(key => key.code === token).title, /Layer/);
    console.log(`PASS: protocol ${protocol} exports and imports ${token} (0x${raw.toString(16)})`);
    count++;
  }
  for (const token of ['LM(1,MOD_LCTL)', 'LM(2,MOD_LSFT | MOD_LALT)']) {
    const raw = keys.getByteForCode(token, dictionary);
    assert.equal(typeof raw, 'number');
    assert.ok(raw >= dictionary._QK_LAYER_MOD && raw <= dictionary._QK_LAYER_MOD_MAX);
    assert.equal(keys.getCodeForByte(raw, dictionary, reverse), token);
    console.log(`PASS: protocol ${protocol} exports and imports ${token} (0x${raw.toString(16)})`);
    count++;
  }
}
console.log(`PASS: ${count} official VIA layer-entry round trips; no device or runtime qualification`);

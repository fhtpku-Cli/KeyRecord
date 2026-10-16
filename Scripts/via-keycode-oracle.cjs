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

async function fileRoundTrips() {
  const {execFileSync} = require('node:child_process');
  const os = require('node:os');
  const repo = path.resolve(__dirname, '..');
  const outputs = JSON.parse(execFileSync('swift', ['run', 'KeyRecordFirmwareIntegrationProbe', '--via-file-outputs'], {cwd: repo, encoding: 'utf8'}));
  assert.ok(outputs.length > 0);
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'keyrecord-via-file-oracle-'));
  try {
    const original = path.join(directory, 'original.json');
    const patched = path.join(directory, 'patched.json');
    const base = {name: 'Synthetic file workflow', vendorProductId: 42, layers: [[...outputs.map(() => 'KC_NO'), 'FN_MO13']],
      macros: ['opaque macro'], encoders: [[['KC_A', 'KC_B']]], extra: {preserved: true}};
    fs.writeFileSync(original, JSON.stringify(base));
    process.stdout.write(execFileSync('swift', ['run', '--skip-build', 'KeyRecordFirmwareIntegrationProbe', '--via-file', original, patched], {cwd: repo, encoding: 'utf8'}));
    const edited = JSON.parse(fs.readFileSync(patched, 'utf8'));
    assert.deepEqual(edited, {...base, layers: [[...outputs, 'FN_MO13']]});
    const filename = path.join(appPath, 'src/components/panes/configure-panes/save-load.tsx');
    const source = ts.createSourceFile(filename, fs.readFileSync(filename, 'utf8'), ts.ScriptTarget.Latest, true, ts.ScriptKind.TSX);
    const declarations = new Map();
    function visit(node) {
      if (ts.isVariableDeclaration(node) && ts.isIdentifier(node.name) && ['isViaSaveFile', 'loadLayout'].includes(node.name.text)) {
        declarations.set(node.name.text, node.initializer.getText(source));
      }
      ts.forEachChild(node, visit);
    }
    visit(source);
    assert.equal(declarations.size, 2);
    const compiled = ts.transpileModule([...declarations].map(([name, initializer]) => `const ${name} = ${initializer};`).join('\n') + '\nexports.loadLayout = loadLayout;', {
      compilerOptions: {target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.CommonJS}, reportDiagnostics: true,
    });
    assert.equal((compiled.diagnostics || []).filter(item => item.category === ts.DiagnosticCategory.Error).length, 0);
    const deprecatedKeycodes = load(path.join(appPath, 'src/utils/key-to-byte/deprecated-keycodes.ts')).default;
    const versions = [7, 8, 9, 10, 11, 12].map(protocol => [protocol, undefined]).concat([[13, 0], [13, 8], [13, 9]]);
    for (const [protocol, keycodesVersion] of versions) {
      const dictionary = dictionaries.getBasicKeyDict(protocol, keycodesVersion);
      const reverse = keys.getByteToKey(dictionary);
      for (const output of outputs) {
        const raw = keys.getByteForCode(output, dictionary);
        assert.ok(Number.isInteger(raw) && raw > 0 && raw <= 255, `${protocol}: ${output}`);
        const saved = keys.getCodeForByte(raw, dictionary, reverse);
        assert.equal(keys.getByteForCode(saved, dictionary), raw);
      }
      async function importFile(value) {
        let completed, error, success;
        const writes = [], encoders = [];
        const context = vm.createContext({exports: {},
          FileReader: class {
            readAsBinaryString(file) { this.result = file; completed = this.onload(); }
          },
          setErrorMessage: value => { error = value; }, setSuccessMessage: value => { success = value; },
          t: value => value, selectedDefinition: {vendorProductId: 42},
          rawLayers: [{keymap: outputs.map(() => 0).concat([dictionary.FN_MO13])}],
          macros: {isFeatureSupported: true}, expressions: base.macros, selectedDevice: {synthetic: true},
          dispatch: async action => { writes.push(action); },
          saveMacros: (_, values) => ({kind: 'macros', values}),
          saveRawKeymapToDevice: values => ({kind: 'keymap', values}),
          basicKeyToByte: dictionary, getByteForCode: keys.getByteForCode, deprecatedKeycodes,
          api: {setEncoderValue: async (...args) => { encoders.push(args); }},
        });
        new vm.Script(compiled.outputText, {filename}).runInContext(context);
        context.exports.loadLayout([JSON.stringify(value)]);
        await completed;
        return {error, success, writes: JSON.parse(JSON.stringify(writes)), encoders: JSON.parse(JSON.stringify(encoders))};
      }
      const result = await importFile(edited);
      assert.equal(result.error, null);
      assert.equal(result.success, 'Successfully updated layout!');
      assert.deepEqual(result.writes, [{kind: 'macros', values: base.macros},
        {kind: 'keymap', values: [[...outputs.map(key => keys.getByteForCode(key, dictionary)), dictionary.FN_MO13]]}]);
      assert.deepEqual(result.encoders, [[0, 0, false, dictionary.KC_A], [0, 0, true, dictionary.KC_B]]);
      for (const invalid of [{...edited, vendorProductId: 43}, {...edited, layers: [['KC_A']]}, {...edited, macros: []}]) {
        const rejected = await importFile(invalid);
        assert.ok(rejected.error); assert.equal(rejected.success, null); assert.deepEqual(rejected.writes, []);
      }
    }
    console.log(`PASS: ${outputs.length} VIA file output keycodes across ${versions.length} dictionary variants; official file import, shape/device/macro rejection and encrypted Swift export`);
  } finally { fs.rmSync(directory, {recursive: true, force: true}); }
}
fileRoundTrips().catch(error => { console.error(error); process.exitCode = 1; });

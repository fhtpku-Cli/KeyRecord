#!/usr/bin/env node
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const [appPath, dependencies] = process.argv.slice(2);
if (!appPath || !dependencies || process.argv.length !== 4) throw new Error('Usage: node via-session-oracle.cjs <official VIA app checkout> <node_modules>');
const ts = require(path.resolve(dependencies, 'typescript'));
const {createSelector} = require(path.resolve(dependencies, '@reduxjs/toolkit'));

function loadSelectors(relativePath, names, bindings = {}) {
  const filename = path.join(appPath, relativePath);
  const source = ts.createSourceFile(filename, fs.readFileSync(filename, 'utf8'), ts.ScriptTarget.Latest, true);
  const statements = names.map(name => {
    const matches = source.statements.filter(statement => ts.isVariableStatement(statement)
      && statement.declarationList.declarations.some(declaration => ts.isIdentifier(declaration.name)
        && declaration.name.text === name));
    assert.equal(matches.length, 1, `Missing or ambiguous official selector: ${name}`);
    return matches[0].getText(source);
  });
  const compiled = ts.transpileModule(statements.join('\n'), {
    compilerOptions: {target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.CommonJS},
    reportDiagnostics: true,
  });
  assert.equal((compiled.diagnostics || []).filter(item => item.category === ts.DiagnosticCategory.Error).length, 0);
  const context = vm.createContext({exports: {}, createSelector, ...bindings});
  new vm.Script(compiled.outputText, {filename}).runInContext(context);
  return context.exports;
}

const devices = loadSelectors('src/store/devicesSlice.ts', [
  'getConnectedDevices', 'getSelectedDevicePath', 'getIsSelectedDeviceReady', 'getSelectedConnectedDevice',
]);
const definitions = loadSelectors('src/store/definitionsSlice.ts', [
  'getBaseDefinitions', 'getCustomDefinitions', 'getLayoutOptionsMap', 'getDefinitions',
  'getSelectedDefinition', 'getSelectedLayoutOptions', 'getSelectedOptionKeys', 'getSelectedKeyDefinitions',
], devices);

const id = 65538;
const key = column => ({matrix: [0, column]});
const definition = (name, column) => ({name, vendorProductId: id, layouts: {
  keys: [key(column)], labels: [['Layout', 'A', 'B']],
  optionKeys: {0: {0: [key(1)], 1: [key(2)]}},
}});
const catalog = definition('catalog-v3', 0);
const custom = definition('custom-v3', 3);
const customV2 = definition('custom-v2', 0);
function state() {
  return {devices: {selectedDevicePath: 'keyboard-a', readyDevicePath: 'keyboard-a',
    connectedDevicePaths: {
      'keyboard-a': {path: 'keyboard-a', vendorProductId: id, requiredDefinitionVersion: 'v3'},
      'keyboard-b': {path: 'keyboard-b', vendorProductId: id, requiredDefinitionVersion: 'v3'},
    }}, definitions: {definitions: {[id]: {v3: catalog}}, customDefinitions: {}, layoutOptionsMap: {}}};
}
const cases = [];
function scenario(name, verify) {
  verify();
  cases.push(name);
}
scenario('catalog selection', () => {
  const current = state();
  assert.equal(definitions.getSelectedDefinition(current), catalog);
  assert.equal(devices.getIsSelectedDeviceReady(current), true);
});
scenario('custom definition overrides the same catalog identity', () => {
  const current = state();
  current.definitions.customDefinitions = {[id]: {v3: custom}};
  assert.equal(definitions.getSelectedDefinition(current), custom);
  assert.notEqual(definitions.getSelectedDefinition(current), current.definitions.definitions[id].v3);
});
scenario('custom override is specific to a definition generation', () => {
  const current = state();
  current.definitions.customDefinitions = {[id]: {v2: customV2}};
  assert.equal(definitions.getSelectedDefinition(current), catalog);
  current.devices = {...current.devices, connectedDevicePaths: {'keyboard-a': {
    ...current.devices.connectedDevicePaths['keyboard-a'], requiredDefinitionVersion: 'v2',
  }}};
  assert.equal(definitions.getSelectedDefinition({...current}), customV2);
});
scenario('separate runtime state with equal VID/PID selects different content', () => {
  const first = state(), second = state();
  second.definitions.customDefinitions = {[id]: {v3: custom}};
  assert.equal(definitions.getSelectedDefinition(first), catalog);
  assert.equal(definitions.getSelectedDefinition(second), custom);
});
scenario('changing selection can retain a definition while the device is not ready', () => {
  const current = state();
  current.devices = {...current.devices, selectedDevicePath: 'keyboard-b'};
  current.definitions.layoutOptionsMap = {'keyboard-a': [1]};
  assert.equal(definitions.getSelectedDefinition(current), catalog);
  assert.equal(devices.getSelectedConnectedDevice(current).path, 'keyboard-b');
  assert.equal(devices.getIsSelectedDeviceReady(current), false);
  assert.equal(JSON.stringify(definitions.getSelectedLayoutOptions(current)), '[0]');
});
scenario('disconnect removes active definition even when the catalog remains', () => {
  const current = state();
  current.devices.connectedDevicePaths = {};
  assert.equal(Boolean(definitions.getSelectedDefinition(current)), false);
  assert.equal(devices.getIsSelectedDeviceReady(current), true);
  assert.equal(current.definitions.definitions[id].v3, catalog);
});
scenario('deselection removes active definition', () => {
  const current = state();
  current.devices.selectedDevicePath = null;
  assert.equal(Boolean(definitions.getSelectedDefinition(current)), false);
});
scenario('a missing required generation cannot fall back to another generation', () => {
  const current = state();
  current.devices.connectedDevicePaths['keyboard-a'].requiredDefinitionVersion = 'v2';
  assert.equal(Boolean(definitions.getSelectedDefinition(current)), false);
});
scenario('replacement under unchanged device identity changes active content', () => {
  const first = state();
  const replacement = definition('catalog-v3', 3);
  assert.equal(definitions.getSelectedDefinition(first), catalog);
  const second = {...first, definitions: {...first.definitions, definitions: {[id]: {v3: replacement}}}};
  assert.equal(definitions.getSelectedDefinition(second), replacement);
  assert.notDeepEqual(definitions.getSelectedKeyDefinitions(first), definitions.getSelectedKeyDefinitions(second));
});
scenario('layout choice changes active keys without changing the definition object', () => {
  const first = state();
  const second = {...first, definitions: {...first.definitions, layoutOptionsMap: {'keyboard-a': [1]}}};
  assert.equal(definitions.getSelectedDefinition(first), definitions.getSelectedDefinition(second));
  assert.equal(JSON.stringify(definitions.getSelectedKeyDefinitions(first).map(item => item.matrix)), '[[0,0],[0,1]]');
  assert.equal(JSON.stringify(definitions.getSelectedKeyDefinitions(second).map(item => item.matrix)), '[[0,0],[0,2]]');
});
for (const name of cases) console.log(`PASS: ${name}`);
console.log(`PASS: ${cases.length} official VIA active-source selection scenarios; runtime importer identity remains unknown`);

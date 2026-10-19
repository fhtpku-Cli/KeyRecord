#!/usr/bin/env node
const fs = require('node:fs');
const path = require('node:path');
const [readerPath, appPath, output] = process.argv.slice(2);
if (!readerPath || !appPath || !output) throw new Error('Usage: node via-definition-oracle.cjs <@the-via/reader directory> <official VIA app checkout> <output>');
const reader = require(path.resolve(readerPath));
const raw = {
  name: 'synthetic-definition', vendorId: '0x0001', productId: '0x0002',
  matrix: {rows: 2, cols: 2},
  layouts: {keymap: [['1,0', {w: 2}, '0,1'], [{x: 0.5}, '0,0', '1,1']]}
};
const fixtures = [];
const geometryInputs = [
  {...raw, name: 'rotation-reference', matrix: {rows: 2, cols: 1},
    layouts: {keymap: [[{r: 90, rx: 2, ry: 3}, '0,0'], ['1,0']]}},
  {...raw, name: 'option-reference', matrix: {rows: 1, cols: 3},
    layouts: {labels: ['Split'], keymap: [['0,0', '0,1\n\n\n0,0'], [{x: 4, w: 2}, '0,2\n\n\n0,1']]}}
];
const geometryFixtures = [];
for (const version of ['v2', 'v3']) {
  const input = version === 'v2' ? {...raw, lighting: 'none'} : {...raw, menus: []};
  const compiled = version === 'v2'
    ? reader.keyboardDefinitionV2ToVIADefinitionV2(input)
    : reader.keyboardDefinitionV3ToVIADefinitionV3(input);
  const validate = version === 'v2' ? reader.isVIADefinitionV2 : reader.isVIADefinitionV3;
  if (!validate(compiled)) throw new Error(JSON.stringify(validate.errors));
  fixtures.push({version, raw: input, compiled});
  for (const geometryInput of geometryInputs) {
    const rawGeometry = version === 'v2' ? {...geometryInput, lighting: 'none'} : {...geometryInput, menus: []};
    const compiledGeometry = version === 'v2'
      ? reader.keyboardDefinitionV2ToVIADefinitionV2(rawGeometry)
      : reader.keyboardDefinitionV3ToVIADefinitionV3(rawGeometry);
    if (!validate(compiledGeometry)) throw new Error(JSON.stringify(validate.errors));
    geometryFixtures.push({version, raw: rawGeometry, compiled: compiledGeometry});
  }
}
const source = fs.readFileSync(path.join(appPath, 'src/store/devicesThunks.ts'), 'utf8');
const expression = source.match(/requiredDefinitionVersion:\s*([^,\n]+)/)?.[1];
if (!expression) throw new Error('Official definition-version selection expression not found');
const required = new Function('protocol', `return (${expression});`);
const protocolDefinitions = Object.fromEntries([7,8,9,10,11,12,13].map(protocol => [protocol, required(protocol)]));
fs.writeFileSync(output, JSON.stringify({reader: require(path.join(path.resolve(readerPath), 'package.json')).version, protocolDefinitions, fixtures, geometryFixtures}, null, 2) + '\n');
console.log('PASS: official V2/V3 transformation and compiled-definition validators executed offline');

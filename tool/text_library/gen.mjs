// Regenerates the design editor's Text library data from the web app:
//   lib/features/editor/text_library/text_combo_data.dart  (Templates: themes + combos)
//   lib/features/editor/text_library/text_look_data.dart   (Effects: look rows + looks)
//
// Usage (from the Flutter repo root):
//   node tool/text_library/gen.mjs [path/to/web/creative-klux]
//
// The web modules are ES modules with extension-less relative imports, which
// Node won't resolve — so they're copied to a temp dir as .mjs with their
// imports rewritten, then imported and serialised as they evaluate. Nothing is
// re-implemented here: the Dart side reads exactly what the web's
// TEXT_COMBOS / COMBO_THEMES / LOOKS / LOOK_ROWS hold.
//
// `undefined` is kept as JSON null on purpose: the web spreads part fields over
// look fields over defaults, and a key that is present-but-undefined still
// overrides there. Dart maps with null values spread the same way.

import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { pathToFileURL } from 'node:url';

const webRoot = path.resolve(process.argv[2] || 'C:/Users/HomePC/Pictures/Coding/Frontend/creative-klux');
const outDir = path.resolve(process.argv[3] || 'lib/features/editor/text_library');
const textDir = path.join(webRoot, 'src/app/design/[id]/_components/panels/text');
const templatesDir = path.join(textDir, 'templates');
const looksDir = path.join(textDir, 'looks');

const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'ck-text-library-'));

/** Copy a web module as .mjs, giving its relative imports a .mjs extension. */
function copyModule(src, dest) {
  const code = fs
    .readFileSync(src, 'utf8')
    .replace(/(from\s+['"])(\.{1,2}\/[^'"]+?)(['"])/g, (_m, a, spec, b) =>
      spec.endsWith('.js') ? `${a}${spec.slice(0, -3)}.mjs${b}` : `${a}${spec}.mjs${b}`,
    );
  if (/from\s+['"]@\//.test(code)) throw new Error(`${src} imports from "@/" — extend gen.mjs to stub it.`);
  fs.mkdirSync(path.dirname(dest), { recursive: true });
  fs.writeFileSync(dest, code);
}

copyModule(path.join(templatesDir, 'comboParts.js'), path.join(tmp, 'templates/comboParts.mjs'));
copyModule(path.join(templatesDir, 'textCombos.js'), path.join(tmp, 'templates/textCombos.mjs'));
for (const f of fs.readdirSync(path.join(templatesDir, 'themes'))) {
  if (f.endsWith('.js')) {
    copyModule(path.join(templatesDir, 'themes', f), path.join(tmp, 'templates/themes', f.replace(/\.js$/, '.mjs')));
  }
}
copyModule(path.join(looksDir, 'lookData.js'), path.join(tmp, 'looks/lookData.mjs'));

const combosMod = await import(pathToFileURL(path.join(tmp, 'templates/textCombos.mjs')).href);
const looksMod = await import(pathToFileURL(path.join(tmp, 'looks/lookData.mjs')).href);
fs.rmSync(tmp, { recursive: true, force: true });

const { COMBO_THEMES, TEXT_COMBOS } = combosMod;
const { LOOKS, LOOK_ROWS, LOOK_SAMPLE } = looksMod;

const keepUndefined = (_k, v) => (v === undefined ? null : v);
const json = (v) => JSON.stringify(v, keepUndefined);

function rawString(name, body) {
  if (body.includes("'''")) throw new Error(`${name}: data contains ''' and can't go in a raw Dart string`);
  return `const String ${name} = r'''\n${body}\n''';\n`;
}

const dartString = (s) => `'${String(s).replace(/\\/g, '\\\\').replace(/'/g, "\\'").replace(/\$/g, '\\$')}'`;

const ids = new Set();
for (const combo of TEXT_COMBOS) {
  if (ids.has(combo.id)) throw new Error(`Duplicate combo id ${combo.id}`);
  ids.add(combo.id);
}

const header = (what) =>
  `// GENERATED from the web app's ${what}\n` +
  '// by tool/text_library/gen.mjs — do not edit by hand; regenerate instead.\n' +
  '// ignore_for_file: lines_longer_than_80_chars\n\n';

const comboDart =
  header('panels/text/templates/textCombos.js (+ themes/*.js, comboParts.js)') +
  '/// The Templates tab\'s themes, in catalogue order: (id, label).\n' +
  'const List<(String, String)> comboThemes = [\n' +
  COMBO_THEMES.map((t) => `  (${dartString(t.id)}, ${dartString(t.label)}),\n`).join('') +
  '];\n\n' +
  '/// Every combo (TEXT_COMBOS), each stamped with its `theme`, in theme order —\n' +
  '/// one JSON object per line. Decoded once by text_combos.dart.\n' +
  rawString('textCombosJson', `[\n${TEXT_COMBOS.map(json).join(',\n')}\n]`);

const lookDart =
  header('panels/text/looks/lookData.js') +
  '/// What every effect card says (LOOK_SAMPLE).\n' +
  `const String lookSample = ${dartString(LOOK_SAMPLE)};\n\n` +
  '/// The Effects category rows (LOOK_ROWS), as look ids.\n' +
  rawString('lookRowsJson', `[\n${LOOK_ROWS.map(json).join(',\n')}\n]`) +
  '\n/// Every look (LOOKS) by id — one per line. Decoded once by text_looks.dart.\n' +
  rawString(
    'looksJson',
    `{\n${Object.entries(LOOKS)
      .map(([id, look]) => `${JSON.stringify(id)}:${json(look)}`)
      .join(',\n')}\n}`,
  );

fs.mkdirSync(outDir, { recursive: true });
fs.writeFileSync(path.join(outDir, 'text_combo_data.dart'), comboDart);
fs.writeFileSync(path.join(outDir, 'text_look_data.dart'), lookDart);

console.log(
  `themes ${COMBO_THEMES.length}, combos ${TEXT_COMBOS.length}, look rows ${LOOK_ROWS.length}, ` +
    `looks ${Object.keys(LOOKS).length}, row items ${LOOK_ROWS.reduce((n, r) => n + r.items.length, 0)}`,
);

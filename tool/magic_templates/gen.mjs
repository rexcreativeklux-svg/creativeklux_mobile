// Regenerates the Magic Studio Templates canvas data from the web app:
//   assets/magic_templates/<toolId>.json   (one catalog per tool)
//
// Usage (from the Flutter repo root):
//   node tool/magic_templates/gen.mjs [path/to/web/creative-klux] [out dir]
//
// Same approach as tool/text_library/gen.mjs: the web modules are ES modules
// with extension-less relative imports, which Node won't resolve — so they're
// copied to a temp dir as .mjs with their imports rewritten, then imported and
// serialised exactly as they evaluate. Nothing is re-implemented here: the
// shaping (Pexels sizes, aspect, values, source image/clip) is the web's own
// `shape()` from textToImageTemplates.js and mediaTemplates.js.
//
// mediaTemplates.js imports React for its hook. React isn't needed to shape a
// catalog, so that import is stubbed, and the module's private CATALOGS + shape
// are exported from the copy so this script can call them.
//
// Only the fields MagicTemplate (lib/features/magic_studio/magic_studio_types.dart)
// and the gallery's cards read are kept, and nulls / empty objects are dropped.

import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { pathToFileURL } from 'node:url';

const webRoot = path.resolve(process.argv[2] || 'C:/Users/HomePC/Pictures/Coding/Frontend/creative-klux');
const outDir = path.resolve(process.argv[3] || 'assets/magic_templates');
const studioDir = path.join(webRoot, 'src/app/(dashboard)/(pages)/magic-studio');

const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'ck-magic-templates-'));

const withMjs = (spec) => (spec.endsWith('.js') ? `${spec.slice(0, -3)}.mjs` : `${spec}.mjs`);

/** Copy a web module as .mjs, giving its relative imports (static and dynamic) a .mjs extension. */
function copyModule(src, dest, patch = (code) => code) {
  let code = fs
    .readFileSync(src, 'utf8')
    .replace(/(from\s+['"])(\.{1,2}\/[^'"]+?)(['"])/g, (_m, a, spec, b) => `${a}${withMjs(spec)}${b}`)
    .replace(/(import\(\s*['"])(\.{1,2}\/[^'"]+?)(['"]\s*\))/g, (_m, a, spec, b) => `${a}${withMjs(spec)}${b}`);
  code = patch(code);
  if (/from\s+['"]@\//.test(code)) throw new Error(`${src} imports from "@/" — extend gen.mjs to stub it.`);
  fs.mkdirSync(path.dirname(dest), { recursive: true });
  fs.writeFileSync(dest, code);
}

copyModule(path.join(studioDir, 'designTemplates.js'), path.join(tmp, 'designTemplates.mjs'));
copyModule(path.join(studioDir, 'textToImageTemplates.js'), path.join(tmp, 'textToImageTemplates.mjs'));
copyModule(path.join(studioDir, 'mediaTemplates.js'), path.join(tmp, 'mediaTemplates.mjs'), (code) => {
  const stubbed = code.replace(
    /import\s*\{[^}]*\}\s*from\s*['"]react['"];?/,
    'const useEffect = () => {}; const useState = (v) => [typeof v === "function" ? v() : v, () => {}];',
  );
  if (stubbed === code) throw new Error('mediaTemplates.js no longer imports React the way gen.mjs expects.');
  return `${stubbed}\nexport { CATALOGS as __CATALOGS, shape as __shape };\n`;
});
for (const f of fs.readdirSync(path.join(studioDir, 'templates'))) {
  if (f.endsWith('.js')) {
    copyModule(path.join(studioDir, 'templates', f), path.join(tmp, 'templates', f.replace(/\.js$/, '.mjs')));
  }
}

const stockMod = await import(pathToFileURL(path.join(tmp, 'textToImageTemplates.mjs')).href);
const mediaMod = await import(pathToFileURL(path.join(tmp, 'mediaTemplates.mjs')).href);

/** "3 / 4" → 0.75 */
const aspectOf = (aspect) => {
  const [w, h] = String(aspect || '')
    .split('/')
    .map((v) => Number(v.trim()));
  return w > 0 && h > 0 ? Math.round((w / h) * 10000) / 10000 : undefined;
};

const empty = (v) =>
  v == null || v === '' || (typeof v === 'object' && !Array.isArray(v) && Object.keys(v).length === 0);

/** Drop null / undefined / "" / {} so the asset stays small. */
const compact = (obj) => Object.fromEntries(Object.entries(obj).filter(([, v]) => !empty(v)));

/** A shaped web template → the JSON MagicTemplate is read from. */
const toJson = (t) =>
  compact({
    id: String(t.id),
    prompt: t.prompt,
    title: t.formatLabel,
    thumb: t.thumb,
    image: t.image,
    video: t.video,
    aspectRatio: aspectOf(t.aspect),
    values: t.values && !t.design ? compact(t.values) : undefined,
    sourceImage: t.sourceImage,
    sourceVideo: t.sourceVideo,
    designFormat: t.design?.format,
    design: t.design ? compact(t.design) : undefined,
    // The persona generator makes images, clips or copy — its content type is
    // the one grouping worth carrying.
    category: t.values?.contentType,
    credit: t.credit,
    link: t.source,
  });

const catalogs = {
  // Stock Image ("image-design") reads the same file — see magic_templates.dart.
  text_to_image: stockMod.TEXT_TO_IMAGE_TEMPLATES,
  'social-design': stockMod.SOCIAL_DESIGN_TEMPLATES,
  'ad-design': stockMod.AD_DESIGN_TEMPLATES,
};
for (const [toolId, spec] of Object.entries(mediaMod.__CATALOGS)) {
  const module = await spec.load();
  catalogs[toolId] = module.default.map((entry) => mediaMod.__shape(toolId, spec, entry));
}
fs.rmSync(tmp, { recursive: true, force: true });

fs.mkdirSync(outDir, { recursive: true });
for (const f of fs.readdirSync(outDir)) {
  if (f.endsWith('.json')) fs.rmSync(path.join(outDir, f));
}
let total = 0;
for (const [toolId, list] of Object.entries(catalogs)) {
  const json = JSON.stringify(list.map(toJson));
  fs.writeFileSync(path.join(outDir, `${toolId}.json`), json);
  total += Buffer.byteLength(json);
  console.log(`${toolId.padEnd(26)} ${String(list.length).padStart(4)} templates  ${(Buffer.byteLength(json) / 1024).toFixed(1)} KB`);
}
console.log(`${'total'.padEnd(26)}                 ${(total / 1024).toFixed(1)} KB`);

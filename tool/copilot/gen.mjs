// Regenerates the Copilot section's catalog data from the web app:
//   lib/features/copilot/data/copilot_catalog.dart
//
// Usage (from the Flutter repo root):
//   node tool/copilot/gen.mjs [path/to/web/creative-klux] [out.dart]
//
// What it reads, and how:
//   · _data/ideas.js, _data/skills.js — imported and serialised as they
//     evaluate (same trick as tool/text_library/gen.mjs: copied to a temp dir as
//     .mjs). skills.js imports React for its tiny "added skills" store; that
//     import is stubbed, because the store itself is re-implemented in Dart.
//   · (lib)/integrations/platforms.jsx — JSX, which Node can't import, so the
//     platform rows and their white-fill brand SVGs are read with regexes. The
//     SVG markup is turned back into plain SVG (camelCase attributes → kebab,
//     className dropped) for flutter_svg's SvgPicture.string.
//   · (components)/studio/modelIcons.jsx — the Claude / OpenAI marks the
//     General settings panel's model picker shows, read the same way.
//
// Nothing is re-written by hand here: change the web's lists and re-run.

import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { pathToFileURL } from 'node:url';

const webRoot = path.resolve(process.argv[2] || 'C:/Users/HomePC/Pictures/Coding/Frontend/creative-klux');
const outFile = path.resolve(process.argv[3] || 'lib/features/copilot/data/copilot_catalog.dart');
const src = path.join(webRoot, 'src');
const dataDir = path.join(src, 'app/(dashboard)/(pages)/copilot/_data');

// ── ideas.js + skills.js ────────────────────────────────────────────────────
const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'ck-copilot-'));
function copyModule(file, stubs = {}) {
  let code = fs.readFileSync(path.join(dataDir, file), 'utf8');
  for (const [from, to] of Object.entries(stubs)) {
    if (!code.includes(from)) throw new Error(`${file}: expected to find ${from}`);
    code = code.replace(from, to);
  }
  if (/from\s+['"]/.test(code)) throw new Error(`${file} still imports something — extend gen.mjs to stub it.`);
  const dest = path.join(tmp, file.replace(/\.js$/, '.mjs'));
  fs.writeFileSync(dest, code);
  return dest;
}
const ideasMod = await import(pathToFileURL(copyModule('ideas.js')).href);
const skillsMod = await import(
  pathToFileURL(
    copyModule('skills.js', {
      'import { useSyncExternalStore } from "react";': 'const useSyncExternalStore = () => {};',
    }),
  ).href
);
fs.rmSync(tmp, { recursive: true, force: true });

const { CATEGORIES, IDEAS } = ideasMod;
const { SKILL_CATEGORIES, FEATURED_SKILLS, SKILLS, SKILL_AUTHOR, CREATE_SKILL_PROMPT } = skillsMod;

// ── JSX → SVG ───────────────────────────────────────────────────────────────
// Attributes that really are camelCase in SVG itself — any other camelCase
// attribute is JSX's spelling of a kebab-case one (fillRule → fill-rule).
const SVG_CAMEL = new Set(['viewBox', 'preserveAspectRatio', 'gradientUnits', 'gradientTransform', 'patternUnits']);
const kebab =(name) => name.replace(/[A-Z]/g, (m) => `-${m.toLowerCase()}`);
function toSvg(raw) {
  // The size class (literal or the `{className}` prop) is the caller's to set.
  const jsx = raw.replace(/\s+className=(?:"[^"]*"|\{\w+\})/g, '');
  if (/[{}]/.test(jsx)) throw new Error(`SVG has a JSX expression in it:\n${jsx.slice(0, 200)}`);
  return jsx
    .replace(/\s+aria-hidden="[^"]*"/g, '')
    .replace(/\s([a-z]+[A-Z][A-Za-z]*)=/g, (_m, a) => ` ${SVG_CAMEL.has(a) ? a : kebab(a)}=`)
    .replace('<svg', '<svg xmlns="http://www.w3.org/2000/svg"')
    .replace(/\s*\n\s*/g, ' ')
    .trim();
}

/** `export const XIcon = () => (<svg…/svg>)` and `export function XIcon(…) { return (<svg…/svg>) }` */
function readIcons(file) {
  const code = fs.readFileSync(file, 'utf8');
  const icons = {};
  const re = /export\s+(?:const\s+(\w+)\s*=\s*\([^)]*\)\s*=>|function\s+(\w+)\s*\([^)]*\)\s*\{\s*return)\s*\(\s*(<svg[\s\S]*?<\/svg>)/g;
  for (const m of code.matchAll(re)) icons[m[1] || m[2]] = toSvg(m[3]);
  return icons;
}

// ── platforms.jsx ───────────────────────────────────────────────────────────
const platformsFile = path.join(src, '(lib)/integrations/platforms.jsx');
const platformIcons = readIcons(platformsFile);
const platformsCode = fs.readFileSync(platformsFile, 'utf8');

function readPlatforms(listName) {
  const start = platformsCode.indexOf(`export const ${listName} = [`);
  if (start < 0) throw new Error(`${listName} not found in platforms.jsx`);
  const body = platformsCode.slice(start, platformsCode.indexOf('\n];', start));
  const rows = [];
  for (const block of body.split(/\n\s*\{\s*\n/).slice(1)) {
    const field = (key) => {
      const m = block.match(new RegExp(`${key}:\\s*\\n?\\s*"((?:[^"\\\\]|\\\\.)*)"`));
      return m ? m[1] : null;
    };
    const icon = block.match(/Icon:\s*(\w+)/)?.[1];
    const bg = field('iconBg') || '';
    const colors = [...bg.matchAll(/#([0-9a-fA-F]{3,6})\b/g)].map((m) => {
      const h = m[1].length === 3 ? [...m[1]].map((c) => c + c).join('') : m[1];
      return `0xFF${h.toUpperCase()}`;
    });
    if (!platformIcons[icon]) throw new Error(`No SVG for ${icon} (${field('id')})`);
    rows.push({ id: field('id'), name: field('name'), description: field('description'), icon, colors });
  }
  return rows;
}
const social = readPlatforms('SOCIAL_PLATFORMS');
const ads = readPlatforms('AD_PLATFORMS');

const modelIcons = readIcons(path.join(src, 'app/(components)/studio/modelIcons.jsx'));

// ── Dart ────────────────────────────────────────────────────────────────────
const iconConst = (name) => `_${name[0].toLowerCase()}${name.slice(1)}`;
const str = (s) => (s == null ? 'null' : JSON.stringify(String(s)).replace(/\$/g, '\\$'));
const strList = (list) => `[${(list || []).map(str).join(', ')}]`;

const out = [];
out.push(`// GENERATED by tool/copilot/gen.mjs from the web app — do not edit by hand.
// Sources: copilot/_data/ideas.js, copilot/_data/skills.js,
// (lib)/integrations/platforms.jsx and (components)/studio/modelIcons.jsx.
// Regenerate: node tool/copilot/gen.mjs

import 'copilot_types.dart';
`);

out.push(`/// Starter-idea categories, one per product surface, in sidebar order (ideas.js).
const copilotCategories = ${strList(CATEGORIES)};
`);

out.push('/// Starter ideas per category (ideas.js `IDEAS`).');
out.push('const copilotIdeas = <String, List<CopilotIdea>>{');
for (const [cat, list] of Object.entries(IDEAS)) {
  out.push(`  ${str(cat)}: [`);
  for (const idea of list) {
    out.push(`    CopilotIdea(title: ${str(idea.title)}, platforms: ${strList(idea.platforms)}, description: ${str(idea.description)}),`);
  }
  out.push('  ],');
}
out.push('};\n');

out.push(`/// Skill browse pills, in order (skills.js \`SKILL_CATEGORIES\`).
const skillCategories = ${strList(SKILL_CATEGORIES)};

/// Who publishes the skills (skills.js \`SKILL_AUTHOR\`).
const skillAuthor = ${str(SKILL_AUTHOR)};

/// What "Create skill in chat" opens the conversation with.
const createSkillPrompt = ${str(CREATE_SKILL_PROMPT)};
`);

const skill = (s, featured) =>
  `  CopilotSkill(slug: ${str(s.slug)}, name: ${str(s.name)}, category: ${str(s.category)}, surface: ${str(s.surface)}, ` +
  `updated: ${str(s.updated)}, preview: ${str(s.preview)}, tint: ${str(s.tint)}, platforms: ${strList(s.platforms)}, ` +
  `featured: ${featured}, description: ${str(s.description)}),`;
out.push('/// The three featured skills, each with a preview mock (skills.js `FEATURED_SKILLS`).');
out.push('const featuredSkills = <CopilotSkill>[');
for (const s of FEATURED_SKILLS) out.push(skill(s, true));
out.push('];\n');
out.push('/// The browse list (skills.js `SKILLS`).');
out.push('const browseSkills = <CopilotSkill>[');
for (const s of SKILLS) out.push(skill(s, false));
out.push('];\n');

const platform = (p, category) =>
  `  CopilotPlatform(id: ${str(p.id)}, name: ${str(p.name)}, description: ${str(p.description)}, category: ${str(category)}, ` +
  `colors: [${p.colors.map((c) => `Color(${c})`).join(', ')}], svg: ${iconConst(p.icon)}),`;
out.push(`/// The connectable platforms, in the registry's own order — which IS "Most
/// popular" (see the ⚠️ in copilot/_data/connectors.js).`);
out.push('const copilotPlatforms = <CopilotPlatform>[');
for (const p of social) out.push(platform(p, 'Social'));
for (const p of ads) out.push(platform(p, 'Advertising'));
out.push('];\n');

out.push('// ── Brand marks (white fill, drawn on the platform\'s gradient) ──');
const used = new Set([...social, ...ads].map((p) => p.icon));
for (const name of [...used].sort()) out.push(`const ${iconConst(name)} = ${str(platformIcons[name])};`);
out.push('');
out.push('// ── Model marks (currentColor) for the General panel\'s model picker ──');
out.push(`const claudeSvg = ${str(modelIcons.ClaudeIcon)};`);
out.push(`const openAiSvg = ${str(modelIcons.OpenAIIcon)};`);
out.push('');

let dart = out.join('\n');
dart = dart.replace("import 'copilot_types.dart';", "import 'dart:ui' show Color;\n\nimport 'copilot_types.dart';");
fs.mkdirSync(path.dirname(outFile), { recursive: true });
fs.writeFileSync(outFile, dart);
console.log(
  `Wrote ${path.relative(process.cwd(), outFile)}: ${CATEGORIES.length} idea categories, ` +
    `${FEATURED_SKILLS.length + SKILLS.length} skills, ${social.length + ads.length} platforms.`,
);

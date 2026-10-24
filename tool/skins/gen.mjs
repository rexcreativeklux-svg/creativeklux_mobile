// Generates lib/core/theme/skins_data.dart from the web app's own skin files:
//   src/app/(components)/appearance/skins.js   → the line-up (id, label, order)
//   src/app/skins.css                          → each skin's light + dark values
//
//   node tool/skins/gen.mjs <web repo root> lib/core/theme/skins_data.dart
//
// The CSS is the source of truth on the web (a skin IS its CSS block), so the
// app reads the same file rather than a hand-copied palette that would drift.
// Only the gradient forms skins.css actually uses are understood; anything
// else fails loudly here instead of silently painting nothing in the app.
import fs from 'fs';
import path from 'path';

const [, , webRoot, outFile] = process.argv;
if (!webRoot || !outFile) {
  console.error('usage: node tool/skins/gen.mjs <web repo root> <out.dart>');
  process.exit(1);
}

const skinsJs = fs.readFileSync(path.join(webRoot, 'src/app/(components)/appearance/skins.js'), 'utf8');
const css = fs.readFileSync(path.join(webRoot, 'src/app/skins.css'), 'utf8').replace(/\/\*[\s\S]*?\*\//g, '');

// ── Line-up ────────────────────────────────────────────────────────────────
const lineup = [...skinsJs.matchAll(/\{\s*id:\s*(DEFAULT_SKIN_ID|"([\w-]+)"),\s*label:\s*"([^"]+)"\s*\}/g)].map((m) => ({
  id: m[2] ?? 'default',
  label: m[3],
}));
if (lineup.length < 5) throw new Error('could not read SKINS from skins.js');

// ── CSS blocks ─────────────────────────────────────────────────────────────
const blocks = {};
for (const m of css.matchAll(/(:where\(\.dark, \.dark \*\))?\[data-skin="([\w-]+)"\]\s*\{([^}]*)\}/g)) {
  const [, dark, id, body] = m;
  const vars = {};
  for (const v of body.matchAll(/--ck-skin-([\w-]+):\s*([\s\S]*?);/g)) vars[v[1]] = v[2].replace(/\s+/g, ' ').trim();
  (blocks[id] ??= {})[dark ? 'dark' : 'light'] = vars;
}

// The neutral "glass" palette a photo gets when no skin is on.
const glass = {};
for (const m of css.matchAll(/:root(\.dark)?\[data-wallpaper\]:not\(\[data-skin\]\)\s*\{([^}]*)\}/g)) {
  const vars = {};
  for (const v of m[2].matchAll(/--color-([\w-]+):\s*([^;]+);/g)) vars[v[1]] = v[2].trim();
  glass[m[1] ? 'dark' : 'light'] = vars;
}

// ── Parsing helpers ────────────────────────────────────────────────────────
function splitTop(s) {
  const out = [];
  let depth = 0;
  let cur = '';
  for (const ch of s) {
    if (ch === '(') depth++;
    if (ch === ')') depth--;
    if (ch === ',' && depth === 0) {
      out.push(cur.trim());
      cur = '';
    } else cur += ch;
  }
  if (cur.trim()) out.push(cur.trim());
  return out;
}

function color(s) {
  s = s.trim();
  if (s === 'transparent') return 0x00000000;
  let m = s.match(/^#([0-9a-f]{3}|[0-9a-f]{6})$/i);
  if (m) {
    let h = m[1];
    if (h.length === 3) h = [...h].map((c) => c + c).join('');
    return (0xff000000 | parseInt(h, 16)) >>> 0;
  }
  m = s.match(/^rgba?\(\s*([\d.]+)[\s,]+([\d.]+)[\s,]+([\d.]+)\s*(?:[/,]\s*([\d.]+%?))?\s*\)$/);
  if (m) {
    let a = m[4] == null ? 1 : m[4].endsWith('%') ? parseFloat(m[4]) / 100 : parseFloat(m[4]);
    const A = Math.round(a * 255);
    return ((A << 24) | (Math.round(+m[1]) << 16) | (Math.round(+m[2]) << 8) | Math.round(+m[3])) >>> 0;
  }
  throw new Error('unknown colour: ' + s);
}

const hex = (n) => `Color(0x${n.toString(16).padStart(8, '0').toUpperCase()})`;

/** "rgb(…) 0%" | "#abc 55%" | "transparent 2px 34px" → {color, positions[] (raw strings)} */
function stop(s) {
  const m = s.match(/^((?:rgba?\([^)]*\))|#[0-9a-f]+|transparent)\s*(.*)$/i);
  if (!m) throw new Error('bad stop: ' + s);
  return { color: color(m[1]), pos: m[2] ? m[2].split(/\s+/) : [] };
}

/** A % position → 0..1, or null when the stop has none (CSS spreads them). */
const pct = (p) => (p == null ? null : p.endsWith('%') ? parseFloat(p) / 100 : p === '0' ? 0 : NaN);
const px = (p) => (p == null ? null : p.endsWith('px') ? parseFloat(p) : p === '0' ? 0 : NaN);

/** Fill CSS's implicit positions: first 0, last 1, gaps evenly between. */
function spread(stops) {
  const out = stops.map((s) => s);
  if (out[0] == null) out[0] = 0;
  if (out[out.length - 1] == null) out[out.length - 1] = 1;
  for (let i = 1; i < out.length - 1; i++) {
    if (out[i] != null) continue;
    let j = i;
    while (out[j] == null) j++;
    const a = out[i - 1];
    const b = out[j];
    for (let k = i; k < j; k++) out[k] = a + ((b - a) * (k - i + 1)) / (j - i + 1);
  }
  return out;
}

/** One art layer → a Dart `SkinLayer…` constructor call. [size] is its background-size entry. */
function layer(src, size) {
  const m = src.match(/^(repeating-linear|linear|radial)-gradient\(([\s\S]*)\)$/);
  if (!m) throw new Error('unknown layer: ' + src);
  const [, kind, inner] = m;
  const args = splitTop(inner);
  const tile = size && size !== 'auto' && size !== 'cover' ? size.split(/\s+/).map(px) : null;

  if (kind === 'repeating-linear') {
    const angle = parseFloat(args[0]);
    const [a, b] = args.slice(1).map(stop);
    // "c 0 Wpx, transparent Wpx Ppx" → a band W wide every P.
    return `SkinLayer.stripes(angle: ${angle}, color: ${hex(a.color)}, width: ${px(a.pos[1])}, period: ${px(b.pos[1])})`;
  }

  if (kind === 'linear') {
    let angle = 180;
    let rest = args;
    if (/deg$/.test(args[0])) {
      angle = parseFloat(args[0]);
      rest = args.slice(1);
    }
    const stops = rest.map(stop);
    if (tile) {
      // "c 1px, transparent 1px" tiled → a 1px rule every tile.
      return `SkinLayer.lines(angle: ${angle}, color: ${hex(stops[0].color)}, thickness: ${px(stops[0].pos[0])}, tileWidth: ${tile[0]}, tileHeight: ${tile[1]})`;
    }
    const pos = spread(stops.map((s) => pct(s.pos[0])));
    return `SkinLayer.linear(angle: ${angle}, colors: [${stops.map((s) => hex(s.color)).join(', ')}], stops: [${pos.join(', ')}])`;
  }

  // radial
  const shape = args[0].match(/^([\d.]+)% ([\d.]+)% at (-?[\d.]+)% (-?[\d.]+)%$/);
  if (shape) {
    const stops = args.slice(1).map(stop);
    const pos = spread(stops.map((s) => pct(s.pos[0])));
    return `SkinLayer.radial(rx: ${shape[1] / 100}, ry: ${shape[2] / 100}, cx: ${shape[3] / 100}, cy: ${shape[4] / 100}, colors: [${stops.map((s) => hex(s.color)).join(', ')}], stops: [${pos.join(', ')}])`;
  }
  // "c Rpx, transparent R2px" tiled → a dot per tile (a star field, a petal drift).
  const stops = args.map(stop);
  if (!tile) throw new Error('px radial without a tile size: ' + src);
  return `SkinLayer.dots(color: ${hex(stops[0].color)}, radius: ${(px(stops[0].pos[0]) + px(stops[1].pos[0])) / 2}, tileWidth: ${tile[0]}, tileHeight: ${tile[1]})`;
}

function palette(v, id, theme) {
  for (const k of ['base', 'page', 'surface', 'ink', 'accent', 'accent-strong', 'accent-soft', 'art']) {
    if (!v[k]) throw new Error(`${id} (${theme}) has no --ck-skin-${k}`);
  }
  const sizes = v['art-size'] ? splitTop(v['art-size']) : [];
  const layers = splitTop(v.art).map((l, i) => layer(l, sizes[i + 1]));
  const image = v.image?.match(/url\("\/skins\/([^"]+)"\)/)?.[1];
  return `SkinPalette(
      base: ${hex(color(v.base))},
      page: ${hex(color(v.page))},
      surface: ${hex(color(v.surface))},
      ink: ${hex(color(v.ink))},
      accent: ${hex(color(v.accent))},
      accentStrong: ${hex(color(v['accent-strong']))},
      accentSoft: ${hex(color(v['accent-soft']))},${image ? `\n      image: 'assets/skins/${image}',` : ''}
      layers: [
        ${layers.join(',\n        ')},
      ],
    )`;
}

// ── Output ─────────────────────────────────────────────────────────────────
let out = `// GENERATED by tool/skins/gen.mjs from the web app's skins.js + skins.css.
// Do not edit by hand — re-run the generator.
// ignore_for_file: prefer_int_literals

import 'package:flutter/painting.dart';

import 'skins.dart';

const skinSpecs = <SkinSpec>[
`;
for (const { id, label } of lineup) {
  if (id === 'default') {
    out += `  SkinSpec(id: 'default', label: '${label}'),\n`;
    continue;
  }
  const b = blocks[id];
  if (!b?.light || !b?.dark) throw new Error(`skin "${id}" is listed in skins.js but has no light+dark block in skins.css`);
  out += `  SkinSpec(
    id: '${id}',
    label: '${label.replace(/'/g, "\\'")}',
    light: ${palette(b.light, id, 'light')},
    dark: ${palette(b.dark, id, 'dark')},
  ),\n`;
}
out += `];

/// The neutral glass a photo wallpaper gets when no skin is on
/// (\`:root[data-wallpaper]:not([data-skin])\` in skins.css).
const glassPageLight = ${hex(color(glass.light.page))};
const glassSurfaceLight = ${hex(color(glass.light.surface))};
const glassPageDark = ${hex(color(glass.dark.page))};
const glassSurfaceDark = ${hex(color(glass.dark.surface))};
`;
fs.writeFileSync(outFile, out, 'utf8');
console.log(`wrote ${lineup.length} skins → ${outFile}`);

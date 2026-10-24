// One-off: search Pexels with the web app's key and write the picks to JSON.
// usage: node pexels_fetch.mjs <web .env path> <out.json>
import fs from "node:fs";

const [envPath, outPath] = process.argv.slice(2);
const key = fs.readFileSync(envPath, "utf8").match(/^PEXELS_API_KEY\s*=\s*"?([^"\r\n]+)"?/m)?.[1];
if (!key) throw new Error("PEXELS_API_KEY not found");

const STOP = new Set("a an the of on in with and at to from for is are its it this that close up closeup video footage shot person woman man someone people slow motion".split(" "));
const titleFromSlug = (url) => {
  const slug = url.split("/").filter(Boolean).pop().replace(/-\d+$/, "");
  const words = slug.split("-").filter((w) => w && !STOP.has(w) && !/^\d+$/.test(w)).slice(0, 3);
  return words.map((w) => w[0].toUpperCase() + w.slice(1)).join(" ");
};

const used = new Set();
const get = async (url) => {
  const r = await fetch(url, { headers: { Authorization: key } });
  if (!r.ok) throw new Error(`${r.status} ${url}`);
  return r.json();
};

// Smallest file that is still sharp enough on a phone card / hero.
const pickFile = (files, portrait) => {
  const mp4 = files.filter((f) => f.file_type === "video/mp4" && f.width && f.height);
  const short = (f) => Math.min(f.width, f.height);
  const target = portrait ? 540 : 720;
  const ok = mp4.filter((f) => short(f) >= (portrait ? 360 : 540)).sort((a, b) => short(a) - short(b));
  return ok.find((f) => short(f) >= target) ? ok.filter((f) => short(f) >= target)[0] : ok.at(-1);
};

async function videos(query, n, orientation) {
  const data = await get(`https://api.pexels.com/videos/search?query=${encodeURIComponent(query)}&orientation=${orientation}&size=medium&per_page=40`);
  const out = [];
  for (const v of data.videos) {
    if (out.length >= n) break;
    if (used.has("v" + v.id) || v.duration > 30) continue;
    const file = pickFile(v.video_files, orientation === "portrait");
    if (!file) continue;
    used.add("v" + v.id);
    out.push({ kind: "video", id: v.id, title: titleFromSlug(v.url), page: v.url, by: v.user?.name ?? "", poster: v.image, video: file.link, w: file.width, h: file.height, dur: v.duration });
  }
  return out;
}

async function photos(query, n, orientation) {
  const data = await get(`https://api.pexels.com/v1/search?query=${encodeURIComponent(query)}&orientation=${orientation}&per_page=40`);
  const out = [];
  for (const p of data.photos) {
    if (out.length >= n) break;
    if (used.has("p" + p.id)) continue;
    used.add("p" + p.id);
    const src = orientation === "portrait"
      ? p.src.portrait.replace(/h=\d+/, "h=750").replace(/w=\d+/, "w=500")
      : p.src.landscape;
    out.push({ kind: "photo", id: p.id, title: titleFromSlug(p.url), alt: p.alt, page: p.url, by: p.photographer, image: src });
  }
  return out;
}

const plan = {
  hero: [
    ["abstract colorful ink in water", "Create with AI"],
    ["cinematic slow motion splash", "Video Effects"],
    ["perfume bottle commercial", "Product Studio"],
    ["content creator filming smartphone", "Social Creatives"],
    ["sneakers product commercial", "Ads that Convert"],
  ],
  creative: [
    ["luxury product advertisement", 8],
    ["perfume cosmetics", 8],
    ["drink pouring", 8],
    ["fashion model", 8],
    ["smartphone gadget", 8],
    ["cinematic aerial", 8],
  ],
  practicalVideos: [["skincare product showcase", 8]],
  practicalPhotos: [
    ["product photography minimal", 8],
    ["flat lay lifestyle", 8],
    ["cosmetics product display", 8],
    ["brand identity mockup", 8],
  ],
};

const result = { hero: [], creative: [], practicalVideos: [], practicalPhotos: [] };
for (const [q, title] of plan.hero) {
  const [v] = await videos(q, 1, "landscape");
  if (v) result.hero.push({ ...v, title, query: q });
}
for (const [q, n] of plan.creative) result.creative.push({ query: q, items: await videos(q, n, "portrait") });
for (const [q, n] of plan.practicalVideos) result.practicalVideos.push({ query: q, items: await videos(q, n, "portrait") });
for (const [q, n] of plan.practicalPhotos) result.practicalPhotos.push({ query: q, items: await photos(q, n, "portrait") });

fs.writeFileSync(outPath, JSON.stringify(result, null, 1));
// Compact review list (no key, no URLs).
for (const [k, rows] of Object.entries(result)) {
  if (k === "hero") { console.log("HERO:", rows.map((h) => `${h.title}[${h.id} ${h.w}x${h.h} ${h.dur}s]`).join(" | ")); continue; }
  for (const r of rows) console.log(`${k} «${r.query}»:`, r.items.map((i) => `${i.id}:${i.title}${i.dur ? ` ${i.w}x${i.h}` : ""}`).join(" | "));
}


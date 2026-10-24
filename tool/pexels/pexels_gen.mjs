// pexels.json → lib/features/home/pexels_media.dart
import fs from "node:fs";
const [inPath, outPath] = process.argv.slice(2);
const j = JSON.parse(fs.readFileSync(inPath, "utf8"));

const exclude = new Set([7852500, 4612266]);
const titles = {
  10322273: "Noir Perfume", 38161395: "Skincare Shoot", 7815973: "Golden Cap", 7316099: "Shopping Bags", 7316071: "Unboxing", 38465228: "Elegant Bottle", 38502397: "Crystal Scent", 5925313: "Sale Day",
  8447669: "Scent Story", 8447560: "Pure Pour", 31040463: "Beauty Essentials", 8447672: "Signature Scent", 39660830: "Blue Mist", 7815967: "Gold Top", 7815962: "Spin & Shine", 7754395: "Beauty Shelf",
  36718216: "Bartender Mix", 30211510: "Ink Pour", 30211437: "Artistic Pour", 32699351: "Color Cocktail", 40137844: "Crystal Clear", 32054972: "Rum Pour", 38702518: "Perfect Pour", 35607981: "Cold Beer",
  15396486: "Studio Pose", 16093155: "Orange Mood", 8798401: "Green Room", 8478619: "Street Style", 8047343: "Disco Night", 39993720: "Glam Model", 8478627: "Smart Casual", 15411007: "Runway Ready",
  6374207: "Desk Setup", 13929629: "Scroll Time", 16407857: "Case Reveal", 8165989: "In Hand", 6375965: "Blank Screen", 6612199: "Screen Demo", 6612204: "App Promo", 8166027: "Tap & Swipe",
  39752936: "Sky High", 28849812: "Iconic City", 32319602: "Old Town", 34863830: "Lakeside", 38675833: "Idyllic Drone", 40414896: "Coastline", 36719916: "Mountain Trek", 30176747: "Dramatic Peaks",
  6801520: "Cosmetic Bottle", 7316385: "Grooming Set", 6801666: "Dropper Drop", 7317019: "Stacked Jars", 7316967: "Clean Containers", 7614789: "Table Display",
  28988956: "Natural Skincare", 940299: "Glass Bottle", 34159010: "Trio", 8128067: "Pastel Set", 14973938: "On Display", 8128064: "Soft Shadows", 18848964: "Luxe Rug", 6767761: "Skin Care",
  6675841: "Feminine Flat Lay", 29098062: "Stylish Flat Lay", 27697741: "Reading Nook", 5405645: "Summer Still", 8004099: "Tech Flat Lay", 13885369: "Perfume Flat Lay", 5405629: "Vacation Mood", 23884483: "Tea & Camera",
  29709958: "Makeup Aisle", 29709957: "Store Aisle", 3735655: "Skincare Store", 14564859: "Vanity", 5042592: "Shelf Display", 29709955: "Lip Wall", 3735630: "Beauty Shelves", 3735618: "Beauty Counter",
  7598016: "Brand Strategy", 4466420: "Black Cards", 8490097: "Business Cards", 7965807: "Color Palette", 4466104: "Stationery Set", 10932011: "Card Stack", 5420976: "Paper & Pen", 5420989: "Blank Cards",
};

// Row key → (source rows, destination path)
const rows = {
  trending: [j.creative[0], "/magic-studio"],
  beauty: [j.creative[1], "/magic-studio"],
  drinks: [j.creative[2], "/magic-studio"],
  fashion: [j.creative[3], "/magic-studio"],
  tech: [j.creative[4], "/magic-studio"],
  travel: [j.creative[5], "/magic-studio"],
  productVideos: [j.practicalVideos[0], "/product-studio"],
  productPhotos: [j.practicalPhotos[0], "/product-studio"],
  flatLays: [j.practicalPhotos[1], "/social-content"],
  retail: [j.practicalPhotos[2], "/ads-content"],
  brandKits: [j.practicalPhotos[3], "/brand/reuse"],
};
const heroPaths = ["/studio/ai-chat-page", "/magic-studio", "/product-studio", "/creatives", "/ads-content"];

const s = (v) => `'${String(v).replace(/\\/g, "\\\\").replace(/'/g, "\\'").replace(/\$/g, "\\$")}'`;
const card = (i, path) =>
  `    HomeCard(title: ${s(titles[i.id] ?? i.title)}, image: ${s(i.kind === "video" ? i.poster.replace(/h=\d+&w=\d+/, "h=800&w=450") : i.image)}, ` +
  (i.kind === "video" ? `video: ${s(i.video)}, ` : "") +
  `path: ${s(path)}, credit: ${s(i.by)}),`;

let out = `// GENERATED — curated Pexels media for the home screen.
// Picked once with the Pexels API (key from the web app's .env) and stored as
// direct CDN links, so the app ships no API key and makes no API calls.
// Regenerate with the script described in CLAUDE.md, or edit by hand.
// Pexels licence: free to use; we credit Pexels on the home screen.

import 'home_catalog.dart';

const pexelsHero = <HeroSlide>[
${j.hero.map((h, i) => `  HeroSlide(title: ${s(h.title)}, image: ${s(h.poster)}, video: ${s(h.video)}, path: ${s(heroPaths[i])}),`).join("\n")}
];
`;
for (const [key, [row, path]] of Object.entries(rows)) {
  out += `\nconst pexels${key[0].toUpperCase() + key.slice(1)} = <HomeCard>[\n${row.items.filter((i) => !exclude.has(i.id)).map((i) => card(i, path)).join("\n")}\n];\n`;
}
fs.writeFileSync(outPath, out);
console.log("written", out.length, "chars");


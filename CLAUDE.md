# Creative Klux — Flutter app

Mobile (Android/iOS) port of the Creative Klux web app, done **one screen at a time**.
Rule for now: **copy the web UI/behaviour as-is, made mobile-friendly and responsive**. UI changes come later, when the user asks for them.
Exception already agreed: **Home uses the Pixury-style layout** (hero carousel, Creative/Practical tabs, rows of portrait cards, bottom nav with an indicator bar). It doesn't copy the web home.

## Where the source of truth lives

- Web app (Next.js 16 / React 19): `C:\Users\HomePC\Pictures\Coding\Frontend\creative-klux` (note the hyphen; there is no `frontend/creativeklux`)
  - Pages: `src/app/(auth)/…`, `src/app/(dashboard)/(pages)/…`
  - Shared components: `src/app/(components)/…`
  - **All API calls**: `src/context/AuthContext.jsx` (~4k lines, one giant context) plus `src/(lib)/*-api.js`
  - Error helpers: `src/utils/errorHelper.js`, `src/utils/authErrors.js`
  - Design tokens: `src/app/globals.css` (Tailwind v4 defaults + `.dark` overrides)
- Backend API: `https://api.creativeklux.com/api/creativeklux-userend` (Laravel, Bearer token). Backend repo: `Coding/Backend`.

When porting a screen: read the web page and its components first, then mirror them. Keep the web's **route paths** (e.g. `/product-studio`, `/brand/manage`) so either side is easy to find from the other.

## Architecture (lib/)

```
core/
  config.dart              API base URL / origin
  api/api_client.dart      Dio wrapper; never throws; 401 → AuthController clears session
  api/api_result.dart      port of classifyResult()
  api/app_exception.dart   AppException, toUserMessage(), throwClassified()  (port of authErrors.js)
  storage/session_store.dart  token → secure storage, user → shared_prefs
  theme/app_colors.dart    AppColors ThemeExtension → use `context.colors.gray500` like `text-gray-500`
  theme/app_theme.dart, theme_controller.dart (light/system/dark, persisted)
  router/app_router.dart   go_router; auth/verify redirects; `_pending` list = unported pages
  ui/                      Toast (sonner stand-in), AppInput, PrimaryButton
features/
  auth/                    AuthController (= AuthProvider) + login/register/verify/forgot/change-password
  brand/                   Brand model, avatar, switcher sheet, blocking BrandSelectGate (= ModalPage.jsx)
  shell/                   DashboardShell (= (dashboard)/layout.js), nav items, drawer/rail, bottom nav, top bar, account sheet
  home/                    Pixury-style home; content in home_catalog.dart
  creatives/               Creative Studio ("My Creations")
  studio/                  AI chat studio + Magic Designs
  publish/                 PublishModal port (shared by creatives + studio)
  editor/                  Design Editor (/design/:id): controller, stage, panels, context bar, sheets
core/design/               layout-JSON renderer (renderDesign.js port)
```

- State: `provider` + `ChangeNotifier`. Navigation: `go_router` (ShellRoute for the signed-in area).
- **Don't grow AuthController into another 4k-line file.** It holds only session, profile, brands and package. Each feature gets its own repository/controller that takes `context.read<AuthController>().api`.
- Responsive: under 1024px wide (the web's `lg`), phone layout with bottom nav + "More" drawer. At 1024px and up, a permanent sidebar rail.
- Colours: only use `context.colors.*` / `AppColors.*` tokens so dark mode keeps working. Dark mode re-points the gray ramp, exactly like the web.
- **Sizing is mobile-native, not web.** The user asked for this explicitly: copy the web's layout and behaviour, NOT its pixel sizes.
  - Text: body 13–14, secondary 11–12.5, section/page headings 15–18, big hero text ≤24.
  - Chrome: top bar 56, bottom nav 58 (21px icons), round header buttons 36, inputs ~42 and primary buttons 44 tall.
  - `AppTheme._compact` shrinks Material's defaults; `app.dart` caps the phone's font-size setting at 1.1×.
  - When porting a web page, scale `text-xl`/`text-2xl` headings down rather than copying 20–30px.
  - Spacing: 16 page gutters on BOTH sides (sheet headers with a close IconButton may use 8 on the right), ~24–28 between sections, 12 under a section header.
  - Top bar: wordmark + brand logo (switcher) + user avatar only. The user found more items cluttered on a 360dp phone, so the web's calendar button lives in the More drawer ("Content Calendar").
- **Sheets and full-screen viewers open on the ROOT navigator.** The shell's pages live in go_router's nested navigator, which sits above the bottom nav. A sheet or viewer opened there stops at the nav and leaves it tappable underneath.
  - Sheets: always pass `useRootNavigator: true` to `showModalBottomSheet`.
  - Viewers: push with `Navigator.of(context, rootNavigator: true)`.
  - Close a sheet with the sheet's OWN context (its builder's or its widget's), never the page's.
- Icons: `lucide_icons_flutter` (`LucideIcons.x`), same icon set as the web's lucide-react.
- Comments: explain *why*, in the same style as the web code. Note the web file a widget ports from.

## Porting a page (checklist)

1. Read the web page + components + the API calls it uses in AuthContext.
2. Add an API/repository class under `features/<name>/` using `ApiClient`.
3. Build the screen; replace its entry in `_pending` in `app_router.dart` with a real `GoRoute`.
4. `flutter analyze` must be clean. `dart format lib --line-length 120`.

## Gotchas

- **google_fonts is pinned to 8.0.0.** v9 moved onto the separate `material_ui` package and its `TextTheme` type doesn't match Flutter's. Don't upgrade until the app moves too.
- **Never rewrite source files with PowerShell `Get-Content`/`Set-Content`.** Windows PowerShell 5.1 reads BOM-less UTF-8 as ANSI, which garbles every `—`, `✓` and `…` (this happened once and was repaired). Use the editor tools, or .NET `ReadAllText`/`WriteAllText` with explicit UTF-8.
- **Windows Developer Mode** must be on for plugin builds (symlinks): `start ms-settings:developers`.
- **Web build can't sign in from localhost**: the API sends no CORS headers for localhost. Mobile apps aren't affected by CORS. To preview UI on web, use a throwaway entrypoint outside `lib/` that fakes `AuthController` (subclass and override its getters).
- **The backend is a separate Laravel codebase and isn't on this machine** (`Coding/Backend` is empty). Server changes the app needs are written up in `docs/backend-mobile-auth.md`, for the backend developer.
- **Social sign-in (Google/Facebook/TikTok) isn't wired.** The web uses a popup + `postMessage` from the backend callback. Mobile needs the backend change in `docs/backend-mobile-auth.md` §1: `platform=mobile`, a redirect to `creativeklux://auth-callback?code=…`, and `POST /auth/mobile/exchange`. Once that ships, add `flutter_web_auth_2` and the custom-scheme intent filter. The buttons show a "coming soon" toast for now.
- **Deep links:**
  - `/invites/:token` is built (`brand_invite_screen.dart`), and the router keeps a cold-start deep link through the splash (`/splash?from=`).
  - The Android manifest has an `autoVerify` filter for `https://app.creativeklux.com/invites/`.
  - The web repo now has `public/.well-known/assetlinks.json` for `com.creativeklux.app`, with the **debug** key only. Add the release (Play signing) SHA-256 to it before launch.
  - iOS still needs Associated Domains + a Team ID.
- **Home media comes from Pexels.** `lib/features/home/pexels_media.dart` is GENERATED: direct Pexels CDN links, so there's no API key in the app and no API calls at runtime (the API limit is 200 requests an hour per key, shared by every user).
  - To regenerate:
    1. `node tool/pexels/pexels_fetch.mjs <web .env> out.json` (reads `PEXELS_API_KEY` from the web app's `.env`).
    2. Review the printed picks.
    3. `node tool/pexels/pexels_gen.mjs out.json lib/features/home/pexels_media.dart`.
  - Card titles and the exclude list live in `pexels_gen.mjs`.
  - Pexels terms ask for attribution. Home shows "Photos and videos provided by Pexels" at the bottom.
  - Videos play muted, only while ≥60% visible (`core/ui/media.dart` `AutoplayVideo`). Players are disposed when they scroll off-screen.
  - Before launch, consider copying the clips to our own CDN (cloudfront), not hotlinking Pexels.
- The cutout.pro video-effect stills the web uses (`public/templates/video-effects`) are NOT in this app. Don't add them: they aren't ours.
- Backend design templates are layout JSON, drawn by `core/design/` (the port of the web's `renderDesign.js`). Home still uses static poster PNGs for its template row.
- Lucide v4 has **no brand logos** (facebook, instagram, linkedin…). Use neutral icons on brand-coloured tiles, or add real logo assets.
- Brand web quirks, and what we did about them:
  - `updateBrandById` never sends `industry`, so the web loses Industry edits. **We send it.**
  - Delete brand: added a loading state.
  - The allocation input starts at the current total, not 0.
  - Members Export / Filter buttons were dead on the web. **We made them work** (CSV via share sheet, role filter).
  - The Manage → Integrations tab is mock-only on the web too.
- App id / bundle id is `com.creativeklux.app` (Android `build.gradle.kts` + `MainActivity` package, iOS `project.pbxproj`). It's also in the web's `assetlinks.json`, so change them together.
- Release signing isn't set up: release builds still sign with the debug key (`build.gradle.kts`).
- **Opening animation** (`features/shell/splash_screen.dart`):
  - Its first frame matches the native launch screen exactly: logo in a white 160 circle on navy `#0A1A55`.
  - The native side lives in Android `res/values/colors.xml`, `drawable*/launch_background.xml`, `values-v31` (Android 12 splash API), and iOS `LaunchScreen.storyboard` + `LaunchImage.imageset`. Keep all of them in sync with `_navy`.
  - The router holds `/splash` until `IntroGate.done` AND the session is confirmed.
  - To review frames, render them from a throwaway widget test: step `tester.pump`, then `RenderRepaintBoundary.toImage`. Headless Chrome can't advance Flutter's animation clock.

## Progress

Next up: Product Studio and the Photo editor (`/edit_a_photo`), then Social/Ads content. The editor's AI image tools wait on the native-ML-vs-server decision (see the editor entry).

- [x] Foundation: theme (light/dark), API client, error classification, session storage, router
- [x] Auth: login, register, verify email, forgot password, change password (code-based reset)
- [x] Shell: bottom nav, More drawer / wide rail, top bar, brand switcher, account sheet, logout, brand gate
- [x] Home (Pixury layout, Pexels videos/photos + local tool tiles/posters)
- [ ] Social sign-in (needs backend deep-link support)
- [x] Brand (step 2), all under `features/brand/`. Endpoints are in `brand_api.dart`:
  - Brand Kits `/brand/reuse`: grid/list views, search, detail bottom sheet, delete
  - Create `/brand/create`: Smart Import + Manual, logo upload via `POST /gallery`, live preview
  - Edit `/brand/edit/:id`
  - Brand Settings `/brand/manage`:
    - working: Basic info, Leave, Members, Allocation, AI Keys
    - Integrations: mock, same as the web
    - coming soon: Auth, Skills, Configuration
- [x] Brand invite acceptance `/invites/:token`: screen + Android App Link filter done. The link only auto-opens the app once `assetlinks.json` is hosted.
- [x] Members: Export (CSV via share sheet) and Filter by role. Both were dead buttons on the web; here they work.
- [x] Design renderer `core/design/` (port of `(lib)/design/renderDesign.js`): `renderDesign`, `renderDesignPng`, `DesignCanvas`, `fromScraiveElements`.
  - Skipped: image perspective/tint and the image tone sliders. (`chart` / `graphic` are now drawn.) Image filters/adjust/shadows ARE drawn (`image_filters.dart`).
  - `DesignScene` is the live, synchronous mode the editor stage uses; `paint(clip: false)` lets previews spill shadows.
  - A video element draws its `poster`, or nothing if it has none.
- [x] Creative Studio `/creatives` (`features/creatives/`): search, tabs, paging, bulk delete, favourites, detail sheet, Edit Copy, Download to gallery, Publish/Schedule.
- [x] AI chat `/studio/ai-chat-page` (`features/studio/`): sessions/history, attachments, dictation, Studio Designs (create-design), Magic Designs, card actions (preview/edit/publish/download/save).
  - Magic Designs: `magic_design.dart` ports magicDesign.js plus the slice of Magic Studio it calls. A cut-off `/magic-studio/generate` request is recovered through history plus status polling.
  - Magic video results have no still frame (the web grabs one with a `<video>` element), so a saved Magic video's thumbnail is black.
  - The web's "use Magic Studio instead?" offer only fires on the template (redesign) path, which the chat no longer uses. Not ported.
- [x] Publish sheet `features/publish/` (port of `PublishModal.jsx`), used by Creative Studio and the chat:
  - Social posting via `creatives/publish`, ads via `creatives/ads`.
  - Scheduling: the picker is there, but the API can't schedule yet, so confirming shows the web's own "Scheduling isn't available yet" error.
  - "Connect More Platforms" goes to `/integrations`, which is still a placeholder.
- [x] Design Editor `/design/:id` (except the AI image tools) (`features/editor/`; web: `app/design/[id]/` — ~32k lines, being ported in phases):
  - **Phase 1 done:**
    - load/save (`PUT /creative-designs/{id}`, the canvas JSON blob + a PNG thumbnail capped at 1080px), autosave every 15s, a silent save on open, the unsaved-changes guard, rename, undo/redo;
    - Download (gallery) and Share (the publish sheet).
  - **Architecture:**
    - `DesignEditorController` = `useDesignEditor.js`.
    - `DesignStage` paints with `DesignScene`, the renderer's live, synchronous mode, so the stage is pixel-identical to the export. It owns all pointer handling through one raw `Listener`: move with centre snapping, corner = scale, edge = crop, rotate with a 45° snap, a second tap on text = inline edit, pinch/pan the view.
    - Resize maths: `core/design/resize_element.dart` (port of resizeElement.js, scaleProps.js and clip.js).
    - Shape categories: `core/design/shape_categories.dart`, GENERATED from the web's shapes.js.
  - **Panels:**
    - Creatives (apply one of your saved designs as a template; `editor_templates_panel.dart`)
    - Text
    - Elements: sticky notes (their type auto-fits on commit) + 13 shape categories
    - Uploads (gallery + upload)
    - Draw (`editor_draw_panel.dart`): pen / marker / highlighter / eraser, colour, weight, transparency, line shapes. While it's open the stage draws instead of selecting.
    - Brand
    - Klux AI (`editor_klux_panel.dart`): `POST /creatives/ai-redesign` with a 4-minute timeout and a Stop button. `?panel=klux` ("Edit with AI") opens it and starts a redesign.
    - Layers (reorder / hide / lock)
    - Resize
  - **Context bar:**
    - text: font, size, colour, B/I/U, align, spacing, Effects
    - shape: fill, outline, weight, Effects, corners
    - image: Edit image, replace, flip, uncrop
    - group: ungroup
    - plus transparency, position (layer order, align to page, rotation), duplicate, copy, lock, delete
    - several selected: Group / Copy / Duplicate / Deselect / Delete
    - nothing selected: background, fit, paste
  - **Effects:** `editor_effects.dart` (text + shape effects; the tiles preview with the renderer). Edit image: `editor_image_sheet.dart` (Filters + 50 looks, Adjust, 42 Shadows) on `core/design/image_filters.dart`, a CSS-filter engine (W3C colour matrices). The tone sliders are skipped.
  - **Phone stand-ins for Shift:**
    - hold an edge handle ~0.4s (haptic buzz, the grip fills blue), then drag = stretch instead of crop;
    - long-press an element = add it to / remove it from the selection;
    - rotation snaps near multiples of 45°.
  - **Copy/paste:** the system clipboard as JSON behind `creative-klux/design-elements@1` (same key as the web, so copies move between web and app), plus an in-memory mirror.
  - **Image shadows on rounded images** are cut off at the rounded box. That's deliberate: it matches the web's EXPORT; the web's stage shows them, which is a web inconsistency.
  - **Phase 3 done:**
    - **Text panel:** Templates (404 combos in 28 themes) + Effects looks (391), in `text_library/`. The data is GENERATED by `node tool/text_library/gen.mjs`, which imports the web's own modules.
    - **Elements:** Graphics / Charts / Tables / Frames / Grids in `element_libraries/`. The renderer now draws `chart` + `graphic` (`core/design/charts.dart`, `graphics.dart`).
      - A second tap on a selected table opens that cell; on a grid cell, frame or chart it opens the matching sheet (`DesignStage.onTapAgain`).
      - Context-bar branches: Edit data / Edit table + colours / Grid / Frame.
    - **Signature:** Draw panel → `showSignatureSheet` (Text / Draw / Upload).
    - **Magic Studio tab:** `magic_panel/` (Images / Variations / Persona; Graphics and 3D are placeholders, as on the web).
      - `MagicApi.run` now waits up to 5 min for `/magic-studio/generate`, because history recovery can't find design-tool runs (they're filed under another tool).
    - **Uploads** (`editor_uploads_panel.dart`): Images / Videos tabs plus Pexels stock search through the WEB app's `/api/pexels` (the key stays server-side).
    - **Video** (`editor_video.dart`):
      - insert from gallery / stock / phone;
      - Edit video sheet: preview player, trim (RangeSlider), speed, volume / mute, repeat;
      - Replace; flip.
      - ⚠️ There's no poster capture (no frame-grab plugin), so a phone-uploaded clip paints nothing on the canvas or in exports until it has a poster. Stock clips carry one.
    - **Animation** (`editor_animate.dart`):
      - 12 animations, 6 page styles and 3 speeds, on the element or the whole page.
      - Preview plays on the stage (`DesignStageState.playAnimations`, painting each element with its frame). It's preview-only, like the web: exports are still.
    - **Line endpoint handles:** straight lines get end dots (drag one, the other stays) plus a bend handle for bendable lines.
    - **Group members:** with a group selected, tap a member to select it. The controller routes member patches through `_patchGroupChild` (absolute ↔ group-relative, rotation-aware); deleting down to one member dissolves the group.
    - **More menu:**
      - Notes (saved in the canvas JSON)
      - Collaborators (`/teams` list / invite / remove)
      - Timer: floating countdown. At zero it plays the system alert sound + haptic instead of the web's synthesised tones.
  - **Not ported (needs a decision):** the AI image tools: background remover, upscale/enhance, face cutout, magic grab, auto-select, grab text, sketchify, bg scene.
    - On the web they run ONNX models in the browser (`(lib)/ai-engine`). On mobile that means either a native ML runtime + model downloads, or server endpoints.
    - Also not ported: image perspective, tint and tone sliders.
- [x] Custom Creation (`features/studio/custom/`; web: `(pages)/studio/`):
  - Screens:
    - `/studio/select`: the chooser (`StudioSelectScreen`).
    - `/studio?creative=…`: `CustomStudioScreen`, with category pills, the form and the results.
    - `/studio/create-from-url`: `CreateFromUrlScreen`.
  - `studio_form_kit.dart` holds the pieces every web form repeats: step bar, Field, URL import box, colour/logo/image pickers, OptionChip, nav.
  - Forms live in `forms/`. `forms/studio_forms.dart` is the web's `renderForm()` switch, and `infographic_form.dart` is the reference port.
  - Engine: create-design via `StudioApi.createDesigns`, shared with the chat. Template fetching (`fetchDesignTemplates`, the redesign engine) is NOT ported.
  - The screen streams batches into `DesignResultsView`, a port of Adpreview's DesignResultPanel (select + save).
  - Images (logo, product, references) upload to `/gallery` when picked, and the payload carries hosted URLs. The web sends logos as data URLs.
  - Not ported:
    - the image cropper (no crop package);
    - the media picker's Magic Studio tab;
    - video thumbnails (no frame grab).
  - The web doesn't offer the Magic Studio forms from /studio/select either (its card is commented out).
  - Fixed vs the web:
    - Image Ads now sends `visualStyle`.
    - Packaging and Digital Business Card actually generate (the web faked them).
    - Banners sends the bleed/DPI it shows as selected.
  - Layout check: every form walks all its steps at 360dp and 1.1× text with no overflow, in a throwaway test that loads Segoe UI as the font. The default test font draws letters as wide boxes and reports false overflows.
- [x] Magic Studio `/magic-studio/:tool` (`features/magic_studio/`; web: `(pages)/magic-studio/`):
  - `magic_studio_types.dart` is the shared contract (tools list = magicTools.js, MagicItem, composer status/refill, templates).
  - `magic_studio_screen.dart` joins three parts:
    - the composer: `magic_composer*.dart` + `magic_configs.dart` (port of StudioComposer + magicStudioConfigs);
    - the lattice: `magic_lattice.dart` (HistoryLattice; slivers) + `magic_history.dart` (useMagicHistory);
    - the templates: `magic_templates.dart` (TemplateGallery).
  - Bare `/magic-studio` redirects to the first tool. The phone picks tools from a sheet off the tool name, standing in for the web's side nav.
  - Template data is GENERATED: `node tool/magic_templates/gen.mjs` writes `assets/magic_templates/<tool>.json` from the web's own modules (~0.9 MB).
  - All tools run on the backend.
  - Not ported:
    - picking or recording audio from the phone (no file_picker / record package);
    - voice previews;
    - Video Effects sample media (cutout.pro, not ours).
  - Phone deviations from the web:
    - square lattice cells (the web's are 3:2);
    - the composer's chips show their value;
    - the template "Use" button is a small ✨.
- [x] Templates `/designs` (`features/designs/`). Two tabs:
  - Klux Templates: the Scraive public pool, `POST api.scraive.com/api/design-templates/public-template-fetch` (it was down with a PHP fatal error for a while; their side). Details sheet → Save to Designs → /creatives.
  - Posters: 49 static PNGs in `assets/images/posters/` (the web's old /designs page).
- [x] Appearance (`core/theme/skins.dart`, `features/appearance/`; web: `(components)/appearance/` + `app/skins.css`):
  - 19 skins. The data is GENERATED: `node tool/skins/gen.mjs <web repo> lib/core/theme/skins_data.dart`.
  - A skin's 7 authored values become the whole gray ramp, mixed in oklab exactly like skins.css.
  - Its art is painted by `SkinArtPainter` (radial / linear / dots / lines / stripes only, the forms skins.css uses), and the illustrated ones add an SVG plate from `assets/skins/`.
  - ⚠️ `AppColors.blue600` / `blue500` are GETTERS now, not const, because a skin re-points the accent (`AppColors.applyAccent`). Never use them inside `const` expressions or as default parameters. `app.dart` rebuilds every element when the accent changes.
  - The backdrop is painted under the whole app in `MaterialApp.builder`.
  - While a skin or photo is on:
    - The shell Scaffold paints the skin's translucent `page`, the web's bg-page main area.
    - The top bar, bottom nav and home tab strip use `context.chromeColor` (page), so the art runs through the header and footer. The user asked for that.
  - Floating things (sheets, dialogs, menus, the drawer) use the surface at FULL alpha (`floating` in `AppTheme`). At the skin's ~0.94 alpha, the page text behind them ghosted through.
  - The status-bar icon colour follows the theme (`AnnotatedRegion` in app.dart). They used to be white on the light app.
  - Art/Images wallpapers are Pexels photos through the web app's `/api/pexels`. The phone asks for portrait; the web asks for landscape.
  - Opened from the Appearance button by the theme control (More drawer + account menu). The sheet has no dimming, so the live app is the preview.
- [x] Copilot (`features/copilot/`; web: `(pages)/copilot/`):
  - `/copilot` and `/copilot/all` are in the shell. `/copilot/:id` (and `/workflows`, `/plugins`) are full screen, declared after the ShellRoute.
  - Catalog data is generated by `tool/copilot/gen.mjs`.
  - Real endpoints: the copilots CRUD, `copilot/chat`, messages and integrations. The rest is mock/local, as on the web.
  - Skill upload picks a real .zip/.skill (file_picker, FileType.any + extension check, since Android has no MIME for .skill). Like the web, nothing is sent: no endpoint exists yet, so it reports pending.
  - The channel connect view shows a QR code (qr_flutter).
  - Messages can be read aloud: `widgets/read_aloud.dart` uses flutter_tts and needs the TTS_SERVICE <queries> intent in AndroidManifest.
- [ ] Product Studio, Photo editor (`/edit_a_photo`) — heavy on-device AI on web (ONNX/transformers.js); decide per tool: native ML vs server
- [ ] Social content, Ads content, Ad Intelligence, Copilot
- [ ] Settings: profile, team, billing, socials, sessions & password, resell, custom domain
- [ ] Gallery, Integrations, Help

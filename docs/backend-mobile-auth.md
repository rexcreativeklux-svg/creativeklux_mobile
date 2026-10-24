# Backend changes needed for the mobile app

For: whoever maintains the Laravel API (`api.creativeklux.com`).
Nothing below changes how the web app behaves. Each change only applies when a request says it comes from the mobile app.

## 1. Social sign-in (Google / Facebook / TikTok)

### Why the web flow doesn't work in the app

Today:

1. The web calls `GET /auth/{provider}/redirect` and opens the returned `redirect_url` in a popup.
2. The provider sends the user back to the backend's callback.
3. The callback page calls `window.opener.postMessage({...})` with `{ success, token, user, is_new }`. For a first-time TikTok user with no email it sends `{ needs_email, pending_token, suggested_name }` instead.

A mobile app has no `window.opener`, so that message never reaches it. Google also blocks sign-in inside embedded WebViews. The app therefore has to open the flow in the system browser (Android Custom Tab / iOS `ASWebAuthenticationSession`). The browser can only hand the result back by **redirecting to the app's URL scheme** at the end.

### What we need

**a) Let the redirect endpoint know it's the app.**

```
GET /auth/{provider}/redirect?platform=mobile
```

When `platform=mobile`, keep that fact in the OAuth `state` (or the session) so the callback can see it. The response is unchanged: `{ "redirect_url": "…" }`.

**b) In the callback, redirect instead of rendering the postMessage page.**

When the flow started with `platform=mobile`, respond with an HTTP 302 to one of these:

| Outcome | Redirect to |
|---|---|
| Signed in / signed up | `creativeklux://auth-callback?code=<one-time code>&is_new=<0\|1>` |
| TikTok, needs an email | `creativeklux://auth-callback?needs_email=1&pending_token=<…>&suggested_name=<urlencoded>` |
| Failed or cancelled | `creativeklux://auth-callback?error=<urlencoded user-facing message>` |

**c) Exchange the one-time code for the session token.**

```
POST /auth/mobile/exchange
{ "code": "<one-time code>" }
→ 200 { "token": "…", "user": { … }, "is_new": true|false, "message": "…" }
```

This returns the same body the web currently gets via `postMessage`.

Rules for the code:
- single use
- expires after about 60 seconds
- invalid or expired → 422 with `{ "message": "…" }`

Why a code rather than putting the token in the URL: another app on the phone can register the same `creativeklux://` scheme and read the URL. A code that expires in a minute is useless to it. The token itself never appears in a URL.

The existing `POST /auth/social/complete` (the TikTok email step) needs no change. The app calls it the same way the web does.

**d) Provider consoles: no change.** Providers still redirect to the backend's existing callback URL. Only the backend's final response is different.

## 2. Brand invite links opening in the app

The app is already set up to open `https://app.creativeklux.com/invites/<token>` links (Android App Links).

### Android

Android only opens these links in the app automatically once the **web frontend** serves this file at `https://app.creativeklux.com/.well-known/assetlinks.json`. In the Next.js app that means putting it in `public/.well-known/assetlinks.json`.

```json
[{
  "relation": ["delegate_permission/common.handle_all_urls"],
  "target": {
    "namespace": "android_app",
    "package_name": "<final Android application id>",
    "sha256_cert_fingerprints": ["<release signing key SHA-256>"]
  }
}]
```

**Done in the web repo:** `public/.well-known/assetlinks.json` exists with package `com.creativeklux.app`. It only lists the **debug** key's SHA-256 (`F9:F9:8C:…:A8:8B`), which this machine's builds are signed with.

Still to do before release: add the release (Play App Signing) key's SHA-256 to `sha256_cert_fingerprints` in that file. Without it, store installs won't open invite links automatically.

### iOS

iOS needs an `apple-app-site-association` file served at the same `.well-known` path. It also needs an Apple Developer Team ID, which we don't have yet.

The invite API endpoints themselves (`GET /brand-invite/{token}`, `POST /brand-invite/{token}/accept`) need no change.

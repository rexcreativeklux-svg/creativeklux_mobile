/// App-wide constants. Mirrors the hardcoded values in the web app's
/// `src/context/AuthContext.jsx` (BASE_URL) so both clients hit the same API.
class AppConfig {
  AppConfig._();

  /// Origin of the backend — used to resolve relative asset paths (brand logos).
  static const apiOrigin = 'https://api.creativeklux.com';

  /// Every userend endpoint hangs off this prefix.
  static const apiBaseUrl = '$apiOrigin/api/creativeklux-userend';

  /// Public web app — used for links that open in the browser (terms, privacy…).
  static const webAppUrl = 'https://app.creativeklux.com';
}

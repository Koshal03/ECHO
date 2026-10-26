/// Google Sign-In configuration.
///
/// Pass your OAuth *Web application* client ID at build time (it is not a secret):
///   flutter build appbundle --release \
///     --dart-define=GOOGLE_WEB_CLIENT_ID=1234567890-abc.apps.googleusercontent.com
///
/// The SAME id must be set on the server as GOOGLE_CLIENT_IDS. See server/SERVER_ENV.md
/// for the Google Cloud steps (Android OAuth client with package + SHA-1 as well).
class AuthConfig {
  static const String googleWebClientId = String.fromEnvironment('GOOGLE_WEB_CLIENT_ID');
}

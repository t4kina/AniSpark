import 'package:flutter/foundation.dart' show debugPrint;
import 'package:url_launcher/url_launcher.dart';

/// Returns [url] as a [Uri] only if it is an http(s) link with a host, so a
/// link coming from AniList data can't launch other URL schemes.
Uri? safeExternalUri(String url) {
  final uri = Uri.tryParse(url.trim());
  if (uri == null) return null;
  if (uri.scheme != 'https' && uri.scheme != 'http') return null;
  return uri.host.isEmpty ? null : uri;
}

/// Opens an http(s) [url] in the browser or the matching app.
Future<void> openExternalUrl(String url) async {
  final uri = safeExternalUri(url);
  if (uri == null) {
    debugPrint('[ExternalUrl] Refusing to open: $url');
    return;
  }
  // canLaunchUrl() needs package-visibility queries on Android 11+ and would
  // report false for https links, so launch directly.
  final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
  if (!launched) debugPrint('[ExternalUrl] No app could open $uri');
}

import 'package:web/web.dart' as web;

void webRedirectTo(String url) => web.window.location.href = url;
void webClearUrlParams() => web.window.history.replaceState(null, '', '/');

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// A GraphQL request captured by [mockAniList].
class RecordedRequest {
  RecordedRequest(this.request)
      : body = jsonDecode(request.body) as Map<String, dynamic>;

  final http.Request request;
  final Map<String, dynamic> body;

  String get query => body['query'] as String;

  Map<String, dynamic> get variables =>
      (body['variables'] as Map?)?.cast<String, dynamic>() ?? const {};

  String? get authorization => request.headers['Authorization'];
}

/// Builds a [MockClient] that records every request into [log] and answers
/// with [handler].
MockClient mockAniList(
  List<RecordedRequest> log,
  http.Response Function(RecordedRequest request) handler,
) =>
    MockClient((request) async {
      final recorded = RecordedRequest(request);
      log.add(recorded);
      return handler(recorded);
    });

/// A JSON response encoded as UTF-8, like the real AniList API returns.
http.Response jsonResponse(
  Object body, {
  int status = 200,
  Map<String, String> headers = const {},
}) =>
    http.Response.bytes(
      utf8.encode(jsonEncode(body)),
      status,
      headers: {'content-type': 'application/json', ...headers},
    );

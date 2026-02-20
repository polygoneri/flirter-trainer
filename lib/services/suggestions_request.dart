// lib/services/suggestions_requests.dart
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

class SuggestionsResponse {
  final double? time; // seconds (double/float), optional
  final List<dynamic>? imagesByOrder;

  /// Resolved flow coming back from backend (can be null).
  /// "opening_line" | "respond_message" | "ignite_chat" | null
  final String? flow;

  /// Each item:
  /// { "text": "...", "exp": "...", "tag": "...|null", "recommended": bool }
  final List<Map<String, dynamic>> suggestions;

  final String? userGender;
  final String? targetGender;
  final Map<String, dynamic>? summary;

  SuggestionsResponse({
    required this.time,
    required this.imagesByOrder,
    required this.suggestions,
    required this.flow,
    required this.userGender,
    required this.targetGender,
    required this.summary,
  });
}

class SuggestionsRequests {
  static const String _baseFunctionsUrl =
      'https://us-central1-vibe8-51766.cloudfunctions.net';

  /// Hardcoded uid for backend validation. Create document users/flirty-trainer-uid in Firestore (can be empty).
  static const String _uid = 'flirty-trainer-uid';

  /// Sends 1-5 images as multipart/form-data with:
  /// - field "uid": required by backend (user must exist in Firestore users collection)
  /// - field "meta": JSON string
  /// - files named image0, image1, ... in UI order
  ///
  /// flow can be null (decided by model). If provided it MUST be one of:
  /// "opening_line" | "respond_message" | "ignite_chat"
  static Future<SuggestionsResponse> generate({
    required String userGender,
    required String theirGender,
    required String userGoal,
    required String vibe,
    required List<Uint8List> imagesInOrder,
    required bool routeToV1,
    String? flow,
    Duration timeout = const Duration(seconds: 120),
  }) async {
    if (imagesInOrder.isEmpty) {
      throw ArgumentError('imagesInOrder is empty');
    }
    if (imagesInOrder.length > 5) {
      throw ArgumentError('Max 5 images allowed');
    }
    if (flow != null &&
        flow != 'opening_line' &&
        flow != 'respond_message' &&
        flow != 'ignite_chat') {
      throw ArgumentError('Invalid flow: $flow');
    }

    final endpoint = routeToV1
        ? '$_baseFunctionsUrl/visionBytesTest'
        : '$_baseFunctionsUrl/visionBytesTestV2';
    final uri = Uri.parse(endpoint);
    final req = http.MultipartRequest('POST', uri);

    // Backend requires uid first (must exist in Firestore users collection)
    req.fields['uid'] = _uid;

    // meta must be a STRING field containing JSON
    final meta = <String, dynamic>{
      'userGender': userGender,
      'targetGender': theirGender,
      'userGoal': userGoal,
      'vibe': vibe,
    };

    // Only include flow if not null (backend treats missing as null)
    if (flow != null) {
      meta['flow'] = flow;
    }

    req.fields['meta'] = jsonEncode(meta);

    // Attach files as image0..imageN
    for (var i = 0; i < imagesInOrder.length; i++) {
      final bytes = imagesInOrder[i];

      final file = http.MultipartFile.fromBytes(
        'image$i',
        bytes,
        filename: 'image$i.jpg',
        contentType: MediaType('image', 'jpeg'),
      );
      req.files.add(file);
    }

    http.StreamedResponse streamed;
    try {
      streamed = await req.send().timeout(timeout);
    } on TimeoutException {
      throw Exception('Request timed out after ${timeout.inSeconds}s');
    } catch (e) {
      throw Exception('Network error: $e');
    }

    final status = streamed.statusCode;
    final body = await streamed.stream.bytesToString();

    if (status < 200 || status >= 300) {
      throw Exception('HTTP $status: $body');
    }

    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) {
      throw Exception('Unexpected JSON shape (expected object): $decoded');
    }

    double _asDouble(Object? v, {double fallback = 0.0}) {
      if (v is num) return v.toDouble();
      if (v is String) return double.tryParse(v) ?? fallback;
      return fallback;
    }

    final time = decoded.containsKey('time')
        ? _asDouble(decoded['time'], fallback: 0.0)
        : null;

    final imagesByOrder = (decoded['imagesByOrder'] is List)
        ? List<dynamic>.from(decoded['imagesByOrder'] as List)
        : null;

    final resolvedFlow = (decoded['flow'] is String)
        ? decoded['flow'] as String
        : null;
    final userGender = (decoded['userGender'] is String)
        ? decoded['userGender'] as String
        : null;
    final targetGender = (decoded['targetGender'] is String)
        ? decoded['targetGender'] as String
        : null;
    final summary = (decoded['summary'] is Map)
        ? Map<String, dynamic>.from(decoded['summary'] as Map)
        : null;

    final rawSuggestions = decoded['suggestions'];
    final suggestions = <Map<String, dynamic>>[];

    if (rawSuggestions is List) {
      for (final item in rawSuggestions) {
        if (item is Map) {
          final m = Map<String, dynamic>.from(item);

          final text = (m['text'] ?? '').toString();
          final exp = m['exp']?.toString();
          final tag = m['tag']?.toString();
          final recommended = (m['recommended'] == true);

          suggestions.add({
            'text': text,
            'exp': exp,
            'tag': tag,
            'recommended': recommended,
          });
        } else if (item is String) {
          // fallback in case backend returns strings
          suggestions.add({
            'text': item,
            'exp': null,
            'tag': null,
            'recommended': false,
          });
        }
      }
    }

    return SuggestionsResponse(
      time: time,
      imagesByOrder: imagesByOrder,
      suggestions: suggestions,
      flow: resolvedFlow,
      userGender: userGender,
      targetGender: targetGender,
      summary: summary,
    );
  }
}

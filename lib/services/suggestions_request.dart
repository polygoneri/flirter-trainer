// lib/services/suggestions_requests.dart
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

class SuggestionsResponse {
  final List<dynamic> imagesByOrder;
  final List<Map<String, dynamic>> suggestions;

  SuggestionsResponse({required this.imagesByOrder, required this.suggestions});
}

class SuggestionsRequests {
  // Cloud Run endpoint (no trailing slash)
  static const String _endpoint =
      'https://visionbytestest-jrk2llvjbq-uc.a.run.app';

  /// Sends 1–5 images as multipart/form-data with:
  /// - field "meta": JSON string
  /// - files named image0, image1, ... in UI order
  ///
  /// Expects JSON response containing at least:
  /// - imagesByOrder: []
  /// - suggestions: [{text, exp, tag}, ...]
  static Future<SuggestionsResponse> generate({
    required String flow,
    required String myGender,
    required String theirGender,
    required int age,
    required String vibe,
    required List<Uint8List> imagesInOrder,
    Duration timeout = const Duration(seconds: 120),
  }) async {
    if (imagesInOrder.isEmpty) {
      throw ArgumentError('imagesInOrder is empty');
    }
    if (imagesInOrder.length > 5) {
      throw ArgumentError('Max 5 images allowed');
    }

    final uri = Uri.parse(_endpoint);

    final req = http.MultipartRequest('POST', uri);

    // meta must be a STRING field containing JSON
    final meta = <String, dynamic>{
      'flow': flow,
      'myGender': myGender,
      'theirGender': theirGender,
      'age': age,
      'vibe': vibe,
    };
    req.fields['meta'] = jsonEncode(meta);

    // Attach files as image0..imageN
    for (var i = 0; i < imagesInOrder.length; i++) {
      final bytes = imagesInOrder[i];

      // Default to jpeg content type. Your backend tolerates image/*.
      // Filename just helps debugging.
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
      // Cloud Run returns JSON on errors too, but don't assume.
      throw Exception('HTTP $status: $body');
    }

    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) {
      throw Exception('Unexpected JSON shape (expected object): $decoded');
    }

    final imagesByOrder = (decoded['imagesByOrder'] is List)
        ? List<dynamic>.from(decoded['imagesByOrder'] as List)
        : <dynamic>[];

    final rawSuggestions = decoded['suggestions'];
    final suggestions = <Map<String, dynamic>>[];

    if (rawSuggestions is List) {
      for (final item in rawSuggestions) {
        if (item is Map) {
          suggestions.add(Map<String, dynamic>.from(item));
        } else if (item is String) {
          // Fallback if backend ever returns strings
          suggestions.add({'text': item});
        }
      }
    }

    return SuggestionsResponse(
      imagesByOrder: imagesByOrder,
      suggestions: suggestions,
    );
  }
}

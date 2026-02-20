// lib/screens/trainer_screen.dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';

import '../models/enums.dart';
import '../services/suggestions_request.dart';

class TrainerScreen extends StatefulWidget {
  const TrainerScreen({super.key, required this.routeToV1});

  final bool routeToV1;

  @override
  State<TrainerScreen> createState() => _TrainerScreenState();
}

class _TrainerScreenState extends State<TrainerScreen> {
  // Required fields for backend
  String userGender = 'man';
  String targetGender = 'woman';
  String userGoal = 'short_term';
  String vibe = 'mix';

  // Flow UI
  static const String _flowDecidedByModel = '__ai__';
  String flow = _flowDecidedByModel; // default: decided by model

  // Images
  List<PlatformFile> images = [];
  List<Uint8List> imageBytes = [];

  // Candidates from backend
  bool showCandidates = false;
  bool isGenerating = false;

  // Analysis toggle + last engine meta
  bool showAnalysis = false;
  double? _lastTime; // backend "time" (seconds)
  List<dynamic>? _lastImagesByOrder;

  // Resolved flow returned by backend
  String? _lastResolvedFlow;
  String? _lastUserGender;
  String? _lastTargetGender;
  Map<String, dynamic>? _lastSummary;

  List<String> candidates = const [
    "Option A: ...",
    "Option B: ...",
    "Option C: ...",
    "Option D: ...",
    "Option E: ...",
    "Option F: ...",
  ];

  // Each item: {text, exp, tag, recommended}
  List<Map<String, dynamic>> engineCandidates = [];

  // Ratings / tags / comments
  final Map<int, int> ratings = {};
  final Map<int, List<TagOption>> tags = {};
  final Map<int, TextEditingController> comments = {};

  final List<TagOption> tagOptions = TagOption.values;

  @override
  void initState() {
    super.initState();
    _ensureSignedIn();
  }

  Future<void> _ensureSignedIn() async {
    try {
      final current = FirebaseAuth.instance.currentUser;
      if (current == null) {
        final cred = await FirebaseAuth.instance.signInAnonymously();
        // ignore: avoid_print
        print("Trainer signed in anonymously: ${cred.user?.uid}");
      } else {
        // ignore: avoid_print
        print("Trainer already signed in: ${current.uid}");
      }
    } catch (e) {
      // ignore: avoid_print
      print("Error signing in trainer: $e");
    }
  }

  @override
  void dispose() {
    for (final c in comments.values) {
      c.dispose();
    }
    super.dispose();
  }

  // ---------- IMAGE PICKING ----------

  Future<void> _pickImages() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.image,
      withData: true,
      withReadStream: false,
    );

    if (result == null || result.files.isEmpty) return;

    final remaining = 5 - images.length;
    if (remaining <= 0) return;

    final files = result.files.take(remaining).toList();

    final newFiles = <PlatformFile>[];
    final newBytes = <Uint8List>[];

    for (final f in files) {
      final already = images.any((x) => x.name == f.name && x.size == f.size);
      if (already) continue;

      final bytes = f.bytes;
      if (bytes == null || bytes.isEmpty) {
        // ignore: avoid_print
        print('Skipping file ${f.name}: no bytes available');
        continue;
      }

      newFiles.add(f);
      newBytes.add(bytes);
    }

    if (newFiles.isEmpty) return;

    setState(() {
      images.addAll(newFiles);
      imageBytes.addAll(newBytes);
    });
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // ---------- GENERATE ----------

  Future<void> _onGenerate() async {
    if (images.isEmpty) {
      _toast("Please add at least one image.");
      return;
    }
    if (images.length > 5) {
      _toast("Max 5 images allowed.");
      return;
    }

    // Rule: "Decided by the model" only allowed for 1 image.
    if (flow == _flowDecidedByModel && images.length != 1) {
      _toast(
        '"Decided by the model" works only for 1 image. Remove images back to 1 or select a specific flow.',
      );
      return;
    }

    setState(() {
      isGenerating = true;
    });

    try {
      final bytesList = imageBytes;
      if (bytesList.isEmpty) {
        _toast("Could not read image bytes.");
        return;
      }

      // If UI flow is "Decided by the model", send flow = null.
      final String? flowToSend = (flow == _flowDecidedByModel) ? null : flow;

      final resp = await SuggestionsRequests.generate(
        userGender: userGender,
        targetGender: targetGender,
        userGoal: userGoal,
        vibe: vibe,
        imagesInOrder: bytesList,
        routeToV1: widget.routeToV1,
        flow: flowToSend,
      );

      _lastTime = resp.time;
      _lastImagesByOrder = resp.imagesByOrder;
      _lastResolvedFlow = resp.flow;
      _lastUserGender = resp.userGender;
      _lastTargetGender = resp.targetGender;
      _lastSummary = resp.summary;

      final parsedCandidates = <Map<String, dynamic>>[];
      final flattened = <String>[];

      for (final s in resp.suggestions) {
        final text = (s['text'] ?? '').toString();
        if (text.trim().isEmpty) continue;

        flattened.add(text);
        parsedCandidates.add({
          'text': text,
          'exp': s['exp'],
          'tag': s['tag'],
          'recommended': (s['recommended'] == true),
        });
      }

      if (flattened.isEmpty) {
        _toast("No suggestions returned.");
        return;
      }

      if (!mounted) return;

      setState(() {
        candidates = flattened;
        engineCandidates = parsedCandidates;
        showCandidates = true;
        showAnalysis = false;

        ratings.clear();
        tags.clear();
        for (final c in comments.values) {
          c.dispose();
        }
        comments.clear();
      });
    } catch (e) {
      // ignore: avoid_print
      print("Generate error: $e");
      if (!mounted) return;
      _toast("Generate error: $e");
    } finally {
      if (mounted) {
        setState(() {
          isGenerating = false;
        });
      }
    }
  }

  // ---------- HELPERS FOR CAPTIONING / CHAT ----------

  String? _captionAt(List<dynamic> imagesByOrder, int index) {
    if (index < 0 || index >= imagesByOrder.length) return null;
    final item = imagesByOrder[index];
    if (item is! Map) return null;
    final cap = item['captioning'];
    return cap is String && cap.trim().isNotEmpty ? cap : null;
  }

  String? _chatTextAt(List<dynamic> imagesByOrder, int index) {
    if (index < 0 || index >= imagesByOrder.length) return null;
    final item = imagesByOrder[index];
    if (item is! Map) return null;
    if (item['isChat'] != true) return null;

    final msgs = item['messages'];
    if (msgs is! List) return null;

    final buffer = StringBuffer();
    for (final m in msgs) {
      if (m is! Map) continue;
      final speaker = (m['speaker'] ?? m['sender'] ?? '').toString();
      final text = (m['text'] ?? '').toString().trim();
      if (text.isEmpty) continue;
      if (buffer.isNotEmpty) buffer.writeln();
      buffer.write('$speaker: $text');
    }

    final result = buffer.toString();
    return result.isEmpty ? null : result;
  }

  String _prettyJson(Object? value) {
    try {
      const encoder = JsonEncoder.withIndent("  ");
      return encoder.convert(value);
    } catch (_) {
      return value?.toString() ?? "";
    }
  }

  // ---------- SUBMIT FEEDBACK ----------

  Future<void> _onSubmitFeedback() async {
    // ignore: avoid_print
    print("Firebase projectId in app: ${Firebase.app().options.projectId}");

    for (var i = 0; i < candidates.length; i++) {
      if (!ratings.containsKey(i) || ratings[i] == null) {
        _toast("Please rate all candidates before sending.");
        return;
      }
    }

    final firestore = FirebaseFirestore.instance;
    final imagesByOrder = _lastImagesByOrder ?? const [];

    final image1 = _captionAt(imagesByOrder, 0);
    final image2 = _captionAt(imagesByOrder, 1);
    final image3 = _captionAt(imagesByOrder, 2);
    final image4 = _captionAt(imagesByOrder, 3);
    final image5 = _captionAt(imagesByOrder, 4);

    final chat1 = _chatTextAt(imagesByOrder, 0);
    final chat2 = _chatTextAt(imagesByOrder, 1);
    final chat3 = _chatTextAt(imagesByOrder, 2);
    final chat4 = _chatTextAt(imagesByOrder, 3);
    final chat5 = _chatTextAt(imagesByOrder, 4);

    try {
      for (var i = 0; i < candidates.length; i++) {
        final selectedTags = tags[i] ?? const <TagOption>[];
        final tagStrings = selectedTags.map((t) => t.name).toList();

        final Map<String, dynamic>? engine = (i < engineCandidates.length)
            ? engineCandidates[i]
            : null;

        await firestore.collection('trainerFeedback').add({
          'createdAt': FieldValue.serverTimestamp(),
          '_trainer': 'ori',
          '_passcode': '4321',

          // context (from UI)
          'userGender': userGender,
          'targetGender': targetGender,
          'userGoal': userGoal,
          'vibe': vibe,

          // IMPORTANT: store resolved flow from backend, not the UI choice
          'flow': _lastResolvedFlow,

          // engine meta
          'time': _lastTime,

          // per-suggestion engine fields (optional but useful)
          'engineTag': engine?['tag'],
          'engineExp': engine?['exp'],
          'engineRecommended': engine?['recommended'] == true,

          // captioning columns
          'image1': image1,
          'image2': image2,
          'image3': image3,
          'image4': image4,
          'image5': image5,

          // chat text columns
          'chat1': chat1,
          'chat2': chat2,
          'chat3': chat3,
          'chat4': chat4,
          'chat5': chat5,

          // suggestion + label
          'suggestion': candidates[i],
          'rating': ratings[i],
          'tags': tagStrings,
          'freeText': comments[i]?.text.trim(),
        });
      }

      if (!mounted) return;

      setState(() {
        userGender = 'man';
        targetGender = 'woman';
        userGoal = 'long_term';
        vibe = 'mix';
        flow = _flowDecidedByModel; // reset default

        images = [];
        imageBytes = [];

        showCandidates = false;
        isGenerating = false;
        showAnalysis = false;

        ratings.clear();
        tags.clear();
        for (final c in comments.values) {
          c.dispose();
        }
        comments.clear();

        candidates = const [
          "Option A: ...",
          "Option B: ...",
          "Option C: ...",
          "Option D: ...",
          "Option E: ...",
          "Option F: ...",
        ];

        _lastImagesByOrder = null;
        _lastTime = null;
        _lastResolvedFlow = null;
        _lastUserGender = null;
        _lastTargetGender = null;
        _lastSummary = null;
        engineCandidates = [];
      });

      _toast("Feedback sent. Thank you!");
    } catch (e) {
      // ignore: avoid_print
      print("Error sending feedback: $e");
      if (!mounted) return;
      _toast("Error sending feedback: $e");
    }
  }

  // ---------- UI ----------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.blue[50],
      appBar: AppBar(
        title: const Text("Trainer"),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Card(
                  elevation: 4,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          "Context",
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: Colors.grey.shade300,
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      "My Gender",
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    DropdownButton<String>(
                                      value: userGender,
                                      isExpanded: true,
                                      items: const [
                                        DropdownMenuItem(
                                          value: "man",
                                          child: Text("Man"),
                                        ),
                                        DropdownMenuItem(
                                          value: "woman",
                                          child: Text("Woman"),
                                        ),
                                      ],
                                      onChanged: (v) =>
                                          setState(() => userGender = v!),
                                    ),
                                    const SizedBox(height: 16),
                                    const Text(
                                      "Their Gender",
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    DropdownButton<String>(
                                      value: targetGender,
                                      isExpanded: true,
                                      items: const [
                                        DropdownMenuItem(
                                          value: "man",
                                          child: Text("Man"),
                                        ),
                                        DropdownMenuItem(
                                          value: "woman",
                                          child: Text("Woman"),
                                        ),
                                      ],
                                      onChanged: (v) =>
                                          setState(() => targetGender = v!),
                                    ),
                                    const SizedBox(height: 16),
                                    const Text(
                                      "User goal",
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    DropdownButton<String>(
                                      value: userGoal,
                                      isExpanded: true,
                                      items: DropdownModels.userGoalItems(),
                                      onChanged: (v) =>
                                          setState(() => userGoal = v!),
                                    ),
                                    const SizedBox(height: 16),
                                    const Text(
                                      "Vibe",
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    DropdownButton<String>(
                                      value: vibe,
                                      isExpanded: true,
                                      items: DropdownModels.vibeItems(),
                                      onChanged: (v) =>
                                          setState(() => vibe = v!),
                                    ),

                                    // FLOW DROPDOWN (default: decided by model)
                                    const SizedBox(height: 16),
                                    const Text(
                                      "Flow",
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    DropdownButton<String>(
                                      value: flow,
                                      isExpanded: true,
                                      items: [
                                        const DropdownMenuItem<String>(
                                          value: _flowDecidedByModel,
                                          child: Text("Decided by the model"),
                                        ),
                                        ...FlowType.values.map(
                                          (f) => DropdownMenuItem<String>(
                                            value: f.value, // API string
                                            child: Text(f.label),
                                          ),
                                        ),
                                      ],
                                      onChanged: (v) {
                                        if (v == null) return;
                                        setState(() => flow = v);
                                      },
                                    ),

                                    const SizedBox(height: 16),
                                    const Text(
                                      "Images (1 to 5)",
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    _imagePickerSection(
                                      files: images,
                                      onPick: _pickImages,
                                      onDelete: (index) {
                                        setState(() {
                                          images.removeAt(index);
                                          imageBytes.removeAt(index);
                                        });
                                      },
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),
                        Center(
                          child: ElevatedButton(
                            onPressed: isGenerating ? null : _onGenerate,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue,
                              foregroundColor: Colors.white,
                              minimumSize: const Size.fromHeight(48),
                            ),
                            child: isGenerating
                                ? const SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        Colors.white,
                                      ),
                                    ),
                                  )
                                : const Text("Generate"),
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                if (showCandidates) ..._buildCandidates(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _imagePickerSection({
    required List<PlatformFile> files,
    required Future<void> Function() onPick,
    required void Function(int index) onDelete,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ElevatedButton(onPressed: onPick, child: const Text("Pick image(s)")),
        const SizedBox(height: 8),
        if (files.isNotEmpty)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (int i = 0; i < files.length; i++)
                Stack(
                  alignment: Alignment.topRight,
                  children: [
                    Container(
                      padding: const EdgeInsets.only(right: 20),
                      child: Chip(
                        label: Text(
                          files[i].name,
                          overflow: TextOverflow.ellipsis,
                        ),
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                    GestureDetector(
                      onTap: () => onDelete(i),
                      child: Container(
                        decoration: const BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                        ),
                        padding: const EdgeInsets.all(4),
                        child: const Icon(
                          Icons.close,
                          size: 16,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          )
        else
          const Text(
            "No images selected yet",
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
      ],
    );
  }

  List<Widget> _buildCandidates() {
    final analysisPayload = <String, dynamic>{};
    if (_lastTime != null) {
      analysisPayload['time'] = _lastTime;
    }
    if (_lastImagesByOrder != null) {
      analysisPayload['imagesByOrder'] = _lastImagesByOrder;
    }
    if (_lastResolvedFlow != null) {
      analysisPayload['flow'] = _lastResolvedFlow;
    }
    if (userGoal.trim().isNotEmpty) {
      analysisPayload['userGoal'] = userGoal;
    }
    if (_lastUserGender != null) {
      analysisPayload['userGender'] = _lastUserGender;
    }
    if (_lastTargetGender != null) {
      analysisPayload['targetGender'] = _lastTargetGender;
    }
    if (_lastSummary != null) {
      analysisPayload['summary'] = _lastSummary;
    }

    return [
      Card(
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      "Results",
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () =>
                        setState(() => showAnalysis = !showAnalysis),
                    child: Text(
                      showAnalysis ? "Hide analysis" : "Show analysis",
                    ),
                  ),
                ],
              ),
              if (showAnalysis) ...[
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: SelectableText(
                    _prettyJson(analysisPayload),
                    style: const TextStyle(fontSize: 12, height: 1.3),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              const Text(
                "Rate Candidates",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              for (var i = 0; i < candidates.length; i++) _candidateBox(i),
              const SizedBox(height: 16),
              Center(
                child: ElevatedButton(
                  onPressed: _onSubmitFeedback,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(48),
                  ),
                  child: const Text("Send feedback"),
                ),
              ),
            ],
          ),
        ),
      ),
    ];
  }

  Widget _pill({required String text, required Color color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
      ),
    );
  }

  Widget _candidateBox(int i) {
    comments[i] ??= TextEditingController();

    final Map<String, dynamic>? engine = (i < engineCandidates.length)
        ? engineCandidates[i]
        : null;

    final String? engineTag = engine?["tag"] != null
        ? engine!["tag"].toString()
        : null;

    final String? engineExp = engine?["exp"] != null
        ? engine!["exp"].toString()
        : null;

    final bool engineRecommended = (engine?["recommended"] == true);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            candidates[i],
            style: const TextStyle(fontSize: 16, color: Colors.black),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (engineTag != null && engineTag.trim().isNotEmpty)
                _pill(text: engineTag, color: Colors.red.shade600),
              if (engineRecommended)
                _pill(text: "Recommend", color: Colors.green.shade700),
            ],
          ),
          if (engineExp != null && engineExp.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8.0),
              child: Text(
                '($engineExp)',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey.shade700,
                  height: 1.3,
                ),
              ),
            ),
          const SizedBox(height: 12),
          const Text("Rating (1 to 5)"),
          DropdownButton<int>(
            value: ratings[i],
            hint: const Text("Pick rating"),
            items: List.generate(5, (x) => x + 1)
                .map((r) => DropdownMenuItem(value: r, child: Text("$r")))
                .toList(),
            onChanged: (v) => setState(() => ratings[i] = v!),
          ),
          const SizedBox(height: 8),
          const Text("Tags (optional, multi-select)"),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: tagOptions
                .map(
                  (t) => ChoiceChip(
                    label: Text(t.name),
                    selected: tags[i]?.contains(t) ?? false,
                    onSelected: (s) {
                      setState(() {
                        tags[i] ??= [];
                        if (s) {
                          if (!tags[i]!.contains(t)) tags[i]!.add(t);
                        } else {
                          tags[i]!.remove(t);
                        }
                      });
                    },
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 12),
          const Text("Comment (optional)"),
          const SizedBox(height: 4),
          TextField(
            controller: comments[i],
            maxLines: 3,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: "Extra thoughts, tweaks to wording, etc.",
            ),
          ),
        ],
      ),
    );
  }
}

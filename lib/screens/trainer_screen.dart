import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';

import '../models/enums.dart';
import '../services/suggestions_request.dart';

class TrainerScreen extends StatefulWidget {
  const TrainerScreen({super.key});

  @override
  State<TrainerScreen> createState() => _TrainerScreenState();
}

class _TrainerScreenState extends State<TrainerScreen> {
  // Required fields for backend
  String myGender = 'man';
  String theirGender = 'woman';
  String flow = 'opening_line';
  String vibe = 'mix';

  // Age is required, default 28
  final ageController = TextEditingController(text: '28');

  // Images
  List<PlatformFile> images = [];
  List<Uint8List> imageBytes = [];

  // Candidates from backend
  bool showCandidates = false;
  bool isGenerating = false;

  List<String> candidates = const [
    "Option A: Example flirty line…",
    "Option B: Another option…",
    "Option C: A third option…",
  ];

  List<Map<String, dynamic>> engineCandidates = []; // {text, exp, tag}

  // Last engine response for feedback fields
  List<dynamic> _lastImagesByOrder = const [];

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
    ageController.dispose();
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

  // ---------- GENERATE FLOW (Cloud Run via VisionBytesClient) ----------

  Future<void> _onGenerate() async {
    if (images.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please add at least one image.")),
      );
      return;
    }
    if (images.length > 5) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Max 5 images allowed.")));
      return;
    }

    final ageText = ageController.text.trim();
    if (ageText.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Age is required.")));
      return;
    }

    final ageInt = int.tryParse(ageText);
    if (ageInt == null || ageInt < 18 || ageInt > 120) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Age must be between 18 and 120.")),
      );
      return;
    }

    setState(() {
      isGenerating = true;
    });

    try {
      final bytesList = imageBytes;

      if (bytesList.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Could not read image bytes.")),
        );
        return;
      }

      // Call Cloud Run via client (file #2)
      final resp = await SuggestionsRequests.generate(
        flow: flow,
        myGender: myGender,
        theirGender: theirGender,
        age: ageInt,
        vibe: vibe,
        imagesInOrder: bytesList,
        // Optional: pass filenames too, if you want in the client
        // filenamesInOrder: images.map((f) => f.name).toList(),
      );

      // Parse suggestions
      final parsedCandidates = <Map<String, dynamic>>[];
      final flattened = <String>[];
      _lastImagesByOrder = resp.imagesByOrder;

      for (final s in resp.suggestions) {
        final text = (s['text'] ?? '').toString();
        if (text.trim().isEmpty) continue;

        flattened.add(text);
        parsedCandidates.add({'text': text, 'exp': s['exp'], 'tag': s['tag']});
      }

      if (flattened.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("No suggestions returned.")),
        );
        return;
      }

      if (!mounted) return;

      setState(() {
        candidates = flattened;
        engineCandidates = parsedCandidates;
        showCandidates = true;

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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Generate error: $e")));
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

  // ---------- SUBMIT FEEDBACK (1 doc per suggestion) ----------

  Future<void> _onSubmitFeedback() async {
    print("Firebase projectId in app: ${Firebase.app().options.projectId}");
    for (var i = 0; i < candidates.length; i++) {
      if (!ratings.containsKey(i) || ratings[i] == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Please rate all candidates before sending."),
          ),
        );
        return;
      }
    }

    final firestore = FirebaseFirestore.instance;

    final imagesByOrder = _lastImagesByOrder;

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

    final int? ageInt = int.tryParse(ageController.text.trim());

    try {
      for (var i = 0; i < candidates.length; i++) {
        final selectedTags = tags[i] ?? const <TagOption>[];
        final tagStrings = selectedTags.map((t) => t.name).toList();
        print("Writing to trainerFeedback with trainer=ori passcode=4321");
        await firestore.collection('trainerFeedback').add({
          'createdAt': FieldValue.serverTimestamp(),
          '_trainer': 'ori',
          '_passcode': '4321',

          // context (from UI, no engine guessing)
          'myGender': myGender,
          'targetGender': theirGender,
          'age': ageInt,
          'vibe': vibe,
          'flow': flow,

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
        myGender = 'man';
        theirGender = 'woman';
        flow = 'opening_line';
        vibe = 'mix';

        ageController.text = '28';

        images = [];
        imageBytes = [];

        showCandidates = false;
        isGenerating = false;

        ratings.clear();
        tags.clear();
        for (final c in comments.values) {
          c.dispose();
        }
        comments.clear();

        candidates = const [
          "Option A: Example flirty line…",
          "Option B: Another option…",
          "Option C: A third option…",
        ];

        _lastImagesByOrder = const [];
        engineCandidates = [];
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Feedback sent. Thank you!")),
      );
    } catch (e) {
      // ignore: avoid_print
      print("Error sending feedback: $e");
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Error sending feedback: $e")));
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
                                      value: myGender,
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
                                          setState(() => myGender = v!),
                                    ),
                                    const SizedBox(height: 16),
                                    const Text(
                                      "Their Gender",
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    DropdownButton<String>(
                                      value: theirGender,
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
                                          setState(() => theirGender = v!),
                                    ),
                                    const SizedBox(height: 16),
                                    const Text(
                                      "Flow type",
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    DropdownButton<String>(
                                      value: flow,
                                      isExpanded: true,
                                      items: DropdownModels.flowItems(),
                                      onChanged: (v) =>
                                          setState(() => flow = v!),
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
                            const SizedBox(width: 16),
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
                                    _input(
                                      "Age",
                                      ageController,
                                      optional: false,
                                      number: true,
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

  Widget _input(
    String label,
    TextEditingController c, {
    bool optional = false,
    bool number = false,
    String? customHint,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label),
        const SizedBox(height: 6),
        TextField(
          controller: c,
          keyboardType: number ? TextInputType.number : TextInputType.text,
          decoration: InputDecoration(
            border: const OutlineInputBorder(),
            hintText: customHint ?? (optional ? "Optional" : "Required"),
          ),
        ),
        const SizedBox(height: 12),
      ],
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
    return [
      Card(
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
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
          RichText(
            text: TextSpan(
              style: const TextStyle(fontSize: 16, color: Colors.black),
              children: [
                TextSpan(text: candidates[i]),
                if (engineTag != null && engineTag.trim().isNotEmpty) ...[
                  const TextSpan(text: " "),
                  WidgetSpan(
                    alignment: PlaceholderAlignment.middle,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.red.shade600,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        engineTag,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (engineExp != null && engineExp.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6.0),
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
          const Text("Rating (1–5)"),
          DropdownButton<int>(
            value: ratings[i],
            hint: const Text("Pick rating"),
            items: List.generate(5, (x) => x + 1)
                .map(
                  (r) => DropdownMenuItem(value: r, child: Text(r.toString())),
                )
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

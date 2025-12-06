import 'dart:typed_data';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';

class TrainerScreen extends StatefulWidget {
  const TrainerScreen({super.key});

  @override
  State<TrainerScreen> createState() => _TrainerScreenState();
}

class _TrainerScreenState extends State<TrainerScreen> {
  // Required fields for backend
  String myGender = 'man';
  String theirGender = 'woman';
  String flow =
      'opening_line'; // opening_line / reply_to_last_message / reignite_chat etc
  String vibe =
      'neutral'; // neutral / witty / playful / funny / flirty / mixture

  // Age is required, default 28
  final ageController = TextEditingController(text: '28');

  // Images (single list, backend will decide chat vs profile)
  List<PlatformFile> images = [];
  List<String> imageUrls = [];
  bool _imagesDirty = false;

  // Candidates from backend
  bool showCandidates = false;
  bool isGenerating = false;
  List<String> candidates = [
    "Option A: Example flirty line…",
    "Option B: Another option…",
    "Option C: A third option…",
  ];

  // Session id + raw engine data
  String? _sessionId;
  Map<String, dynamic>? _lastEngineData; // <--- holds full JSON from backend

  // Ratings / tags / comments
  final Map<int, int> ratings = {};
  final Map<int, List<String>> tags = {};
  final Map<int, TextEditingController> comments = {};

  final List<String> tagOptions = [
    "witty",
    "smart",
    "flirty",
    "funny",
    "trying_to_be_funny",
    "charming",
    "romantic",
    "cringy",
    "flat",
    "sexy_in_a_good_way",
    "slizzy",
    "too_direct",
    "too_long",
    "too_much_effort",
    "emoji_not_neccery",
    "not_give_continuation",
    "bingo",
    "generic",
    "off_topic",
    "too_sexual",
    "inappropriate",
    "creepy",
    "sweet",
    "looks_AI_not_human",
    "no_refernce_to_images",
    "not_learning_from_images",
    "overly_interested",
    "too_eager",
  ];

  @override
  void dispose() {
    ageController.dispose();
    for (final c in comments.values) {
      c.dispose();
    }
    super.dispose();
  }

  // ---------- IMAGE PICKING (single list) ----------

  Future<void> _pickImages() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.image,
      withData: true,
      withReadStream: true,
    );

    if (result != null && result.files.isNotEmpty) {
      // Limit to 5 images
      final picked = result.files.take(5).toList();
      setState(() {
        images = picked;
        imageUrls = [];
        _imagesDirty = true;
      });
    }
  }

  Future<List<String>> _uploadFiles(List<PlatformFile> files) async {
    final storage = FirebaseStorage.instance;

    if (files.isEmpty) return [];

    final List<String> urls = [];

    for (final f in files) {
      Uint8List? bytes = f.bytes;

      // Web fallback: read from readStream if bytes is null
      if (bytes == null && f.readStream != null) {
        final builder = BytesBuilder();
        await for (final chunk in f.readStream!) {
          builder.add(chunk);
        }
        bytes = builder.toBytes();
      }

      if (bytes == null) {
        print(
          'Skipping file ${f.name}: STILL no bytes available (web upload issue?)',
        );
        continue;
      }

      final ext = (f.extension?.isNotEmpty ?? false) ? f.extension! : 'jpg';

      final ref = storage.ref().child(
        'trainerUploads/mixed/${DateTime.now().millisecondsSinceEpoch}_${f.name}',
      );

      final taskSnapshot = await ref.putData(
        bytes,
        SettableMetadata(contentType: 'image/$ext'),
      );

      final url = await taskSnapshot.ref.getDownloadURL();
      urls.add(url);
    }

    print('Uploaded ${urls.length} of ${files.length} files to Storage');
    return urls;
  }

  Future<List<String>> _ensureImagesUploaded() async {
    // If no images, clear URLs and mark clean
    if (images.isEmpty) {
      if (mounted) {
        setState(() {
          imageUrls = [];
          _imagesDirty = false;
        });
      }
      return [];
    }

    // If nothing changed and we already have URLs, reuse them
    if (!_imagesDirty &&
        imageUrls.isNotEmpty &&
        imageUrls.length == images.length) {
      return imageUrls;
    }

    // Otherwise, upload current images
    final uploadedUrls = await _uploadFiles(images);

    if (mounted) {
      setState(() {
        imageUrls = uploadedUrls;
        _imagesDirty = false;
      });
    }

    return uploadedUrls;
  }

  // ---------- GENERATE FLOW (talks to vibe8 backend) ----------

  void _onGenerate() async {
    // require 1–5 images
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

    // Age is REQUIRED and must be 15–70
    final ageText = ageController.text.trim();
    if (ageText.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Age is required.")));
      return;
    }

    final ageInt = int.tryParse(ageText);
    if (ageInt == null || ageInt < 15 || ageInt > 70) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Age must be between 15 and 70.")),
      );
      return;
    }

    setState(() {
      isGenerating = true;
    });

    try {
      final uploadedUrls = await _ensureImagesUploaded();

      // DEBUG
      print("Trainer sending to vibe8Generate:");
      print("  flow: $flow");
      print("  myGender: $myGender");
      print("  theirGender: $theirGender");
      print("  age: $ageInt");
      print("  vibe: $vibe");
      print("  imageUrls (${uploadedUrls.length}): $uploadedUrls");

      // Call the main Vibe8 function
      final callable = FirebaseFunctions.instance.httpsCallable(
        'vibe8Generate',
      );

      final result = await callable.call({
        "flow": flow,
        "myGender": myGender,
        "theirGender": theirGender,
        "age": ageInt,
        "vibe": vibe,
        "imageUrls": uploadedUrls,
      });

      print("============== RAW CLOUD FUNCTION RESPONSE ==============");
      print(result.data);
      print("=========================================================");

      final data = Map<String, dynamic>.from(result.data as Map);
      _lastEngineData = data; // save engine JSON for feedback step

      final rawSuggestions = data["suggestions"];
      final String? sessionIdFromBackend = data["sessionId"] as String?;

      final List<String> flattened = [];
      if (rawSuggestions is List) {
        for (final s in rawSuggestions) {
          if (s is String) {
            flattened.add(s);
          } else if (s is Map && s["text"] is String) {
            flattened.add(s["text"] as String);
          }
        }
      }

      if (flattened.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("No suggestions returned.")),
        );
        return;
      }

      setState(() {
        candidates = flattened;
        _sessionId = sessionIdFromBackend;
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
      print("Error calling function: $e");
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Function error: $e")));
    } finally {
      if (mounted) {
        setState(() {
          isGenerating = false;
        });
      }
    }
  }

  // ---------- HELPERS FOR CAPTIONING / CHAT / FLOW ----------

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

  // ---------- SUBMIT FEEDBACK (flat schema, 1 doc per suggestion) ----------

  Future<void> _onSubmitFeedback() async {
    // make sure all candidates have a rating
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

    // engine data from last generation
    final engine = _lastEngineData ?? {};
    final imagesByOrder =
        (engine['imagesByOrder'] as List<dynamic>?) ?? const [];

    // flow from engine: code "a"/"b"/"c"/"d"
    final String? flowCode = engine['whoSentTheLastMessage'] as String?;

    // map to human-readable flow
    String? flowFromEngine;
    switch (flowCode) {
      case 'a':
        flowFromEngine = 'ignite'; // I sent last
        break;
      case 'b':
        flowFromEngine = 'respond'; // they sent last
        break;
      case 'c':
        flowFromEngine = 'chat'; // unclear but chat exists
        break;
      case 'd':
        flowFromEngine = 'no_chats'; // only captioning
        break;
      default:
        flowFromEngine = null;
    }

    // captioning + chat columns
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
      // one document per suggestion
      for (var i = 0; i < candidates.length; i++) {
        await firestore.collection('trainerFeedback').add({
          'createdAt': FieldValue.serverTimestamp(),

          // context
          'myGender': myGender,
          'targetGender': theirGender,
          'age': ageInt,
          'vibe': vibe,
          'flow': flowFromEngine, // from engine, not UI
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
          'candidateIndex': i,
          'rating': ratings[i],
          'tags': tags[i] ?? <String>[],
          'freeText': comments[i]?.text.trim(),
        });
      }

      if (!mounted) return;

      // Reset / refresh the whole page state
      setState(() {
        myGender = 'man';
        theirGender = 'woman';
        flow = 'opening_line';
        vibe = 'neutral';

        ageController.text = '28';

        images = [];
        imageUrls = [];
        _imagesDirty = false;

        showCandidates = false;
        isGenerating = false;

        ratings.clear();
        tags.clear();
        for (final c in comments.values) {
          c.dispose();
        }
        comments.clear();

        candidates = [
          "Option A: Example flirty line…",
          "Option B: Another option…",
          "Option C: A third option…",
        ];
        _sessionId = null;
        _lastEngineData = null;
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
                            // LEFT BOX - genders, flow, vibe, images
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
                                      items: const [
                                        DropdownMenuItem(
                                          value: "opening_line",
                                          child: Text("Opening line"),
                                        ),
                                        DropdownMenuItem(
                                          value: "reply_to_last_message",
                                          child: Text(
                                            "Reply to their last message",
                                          ),
                                        ),
                                        DropdownMenuItem(
                                          value: "reignite_chat",
                                          child: Text("Reignite chat"),
                                        ),
                                      ],
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
                                      items: const [
                                        DropdownMenuItem(
                                          value: "neutral",
                                          child: Text("Neutral"),
                                        ),
                                        DropdownMenuItem(
                                          value: "witty",
                                          child: Text("Witty"),
                                        ),
                                        DropdownMenuItem(
                                          value: "playful",
                                          child: Text("Playful"),
                                        ),
                                        DropdownMenuItem(
                                          value: "funny",
                                          child: Text("Funny"),
                                        ),
                                        DropdownMenuItem(
                                          value: "flirty",
                                          child: Text("Flirty"),
                                        ),
                                        DropdownMenuItem(
                                          value: "assertive",
                                          child: Text("Assertive"),
                                        ),
                                        DropdownMenuItem(
                                          value: "mixture",
                                          child: Text("Mixture"),
                                        ),
                                      ],
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
                                          imageUrls = [];
                                          _imagesDirty = true;
                                        });
                                      },
                                    ),
                                  ],
                                ),
                              ),
                            ),

                            const SizedBox(width: 16),

                            // RIGHT BOX - age
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
          Text(candidates[i], style: const TextStyle(fontSize: 16)),
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
                    label: Text(t),
                    selected: tags[i]?.contains(t) ?? false,
                    onSelected: (s) {
                      setState(() {
                        tags[i] ??= [];
                        if (s) {
                          if (!tags[i]!.contains(t)) {
                            tags[i]!.add(t);
                          }
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

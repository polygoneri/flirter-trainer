import 'dart:typed_data';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';

class TrainerScreen extends StatefulWidget {
  const TrainerScreen({super.key});

  @override
  State<TrainerScreen> createState() => _TrainerScreenState();
}

class _TrainerScreenState extends State<TrainerScreen> {
  // Required fields
  String myGender = 'male';
  String theirGender = 'female';

  // Goal is required (with placeholder). App is optional.
  String? goal;
  String? app;

  // Optional text fields (except last message, which is required OR images)
  final lastMsgController = TextEditingController();
  final ageController = TextEditingController();
  final hobbiesController = TextEditingController();
  final countryController = TextEditingController();
  final occupationController = TextEditingController();

  // Images (real files for web)
  List<PlatformFile> profileImages = [];
  List<PlatformFile> chatImages = [];

  // After upload (optional to keep in UI)
  List<String> profileImageUrls = [];
  List<String> chatImageUrls = [];

  // Track if images changed (to avoid re-upload)
  bool _profileDirty = false;
  bool _chatDirty = false;

  // Candidates from backend
  bool showCandidates = false;
  bool isGenerating = false;
  List<String> candidates = [
    "Option A: Example flirty line…",
    "Option B: Another option…",
    "Option C: A third option…",
  ];

  // Session id from backend (for linking feedback)
  String? _sessionId;

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

  static const String _goalPlaceholder = "please choose";

  @override
  void dispose() {
    lastMsgController.dispose();
    ageController.dispose();
    hobbiesController.dispose();
    countryController.dispose();
    occupationController.dispose();
    for (final c in comments.values) {
      c.dispose();
    }
    super.dispose();
  }

  // ---------- IMAGE PICKING ----------

  Future<void> _pickProfileImages() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.image,
      withData: true,
      withReadStream: true,
    );

    if (result != null && result.files.isNotEmpty) {
      setState(() {
        profileImages = result.files;
        profileImageUrls = [];
        _profileDirty = true;
      });
    }
  }

  Future<void> _pickChatImages() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.image,
      withData: true,
      withReadStream: true,
    );

    if (result != null && result.files.isNotEmpty) {
      setState(() {
        chatImages = result.files;
        chatImageUrls = [];
        _chatDirty = true;
      });
    }
  }

  Future<List<String>> _uploadFiles(
    List<PlatformFile> files,
    String folder,
  ) async {
    final storage = FirebaseStorage.instance;

    // Filter out files with no bytes
    final validFiles = files.where((f) => f.bytes != null).toList();
    if (validFiles.isEmpty) return [];

    // Upload all files in parallel
    final futures = validFiles.map((f) async {
      final ext = f.extension ?? 'jpg';
      final ref = storage.ref().child(
        'trainerUploads/$folder/${DateTime.now().millisecondsSinceEpoch}_${f.name}',
      );

      final taskSnapshot = await ref.putData(
        f.bytes as Uint8List,
        SettableMetadata(contentType: 'image/$ext'),
      );

      return await taskSnapshot.ref.getDownloadURL();
    }).toList();

    return Future.wait(futures);
  }

  Future<List<String>> _ensureProfileUploaded() async {
    // No images at all
    if (profileImages.isEmpty) {
      if (mounted) {
        setState(() {
          profileImageUrls = [];
          _profileDirty = false;
        });
      }
      return [];
    }

    // Already uploaded and not changed
    if (!_profileDirty && profileImageUrls.isNotEmpty) {
      return profileImageUrls;
    }

    // Need to upload
    final urls = await _uploadFiles(profileImages, 'profile');
    if (mounted) {
      setState(() {
        profileImageUrls = urls;
        _profileDirty = false;
      });
    }
    return urls;
  }

  Future<List<String>> _ensureChatUploaded() async {
    if (chatImages.isEmpty) {
      if (mounted) {
        setState(() {
          chatImageUrls = [];
          _chatDirty = false;
        });
      }
      return [];
    }

    if (!_chatDirty && chatImageUrls.isNotEmpty) {
      return chatImageUrls;
    }

    final urls = await _uploadFiles(chatImages, 'chat');
    if (mounted) {
      setState(() {
        chatImageUrls = urls;
        _chatDirty = false;
      });
    }
    return urls;
  }

  // ---------- GENERATE FLOW ----------

  void _onGenerate() async {
    // goal required
    if (goal == null || goal == _goalPlaceholder) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Please choose a goal.")));
      return;
    }

    // last message OR image required
    final lastMsg = lastMsgController.text.trim();
    final hasLastMsg = lastMsg.isNotEmpty;
    final hasImages = profileImages.isNotEmpty || chatImages.isNotEmpty;

    if (!hasLastMsg && !hasImages) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Add their last message or at least one image."),
        ),
      );
      return;
    }

    // age optional, but if present must be 16–90
    final ageText = ageController.text.trim();
    if (ageText.isNotEmpty) {
      final age = int.tryParse(ageText);
      if (age == null || age < 16 || age > 90) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Age must be between 16 and 90.")),
        );
        return;
      }
    }

    // Build context payload
    final Map<String, dynamic> ctx = {
      "myGender": myGender,
      "theirGender": theirGender,
      "goal": goal,
      "app": app,
      "lastMessage": lastMsg,
      "age": ageText.isEmpty ? null : int.parse(ageText),
      "hobbies": hobbiesController.text.trim(),
      "country": countryController.text.trim(),
      "occupation": occupationController.text.trim(),
    };

    setState(() {
      isGenerating = true;
    });

    try {
      // Upload profile + chat images in parallel, only if needed
      final results = await Future.wait<List<String>>([
        _ensureProfileUploaded(),
        _ensureChatUploaded(),
      ]);

      final uploadedProfileUrls = results[0];
      final uploadedChatUrls = results[1];

      // Call Cloud Function with real URLs
      final callable = FirebaseFunctions.instance.httpsCallable(
        'generateCandidates',
      );

      final result = await callable.call({
        "context": ctx,
        "profileImageUrls": uploadedProfileUrls,
        "chatImageUrls": uploadedChatUrls,
      });

      final data = result.data as Map<String, dynamic>;
      final List<dynamic> returnedCandidates = data["candidates"];
      final String? sessionIdFromBackend = data["sessionId"] as String?;

      setState(() {
        candidates = returnedCandidates
            .map((c) => c["text"] as String)
            .toList();
        _sessionId = sessionIdFromBackend;
        showCandidates = true;
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

  // ---------- SUBMIT FEEDBACK ----------

  Future<void> _onSubmitFeedback() async {
    // 1) Make sure all candidates have a rating
    for (var i = 0; i < candidates.length; i++) {
      if (!ratings.containsKey(i) || ratings[i] == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Please rate all candidates before sending."),
          ),
        );
        return; // stop here, do not send
      }
    }

    // 2) Build feedback payload (now guaranteed all have ratings)
    final feedback = <Map<String, dynamic>>[];

    for (var i = 0; i < candidates.length; i++) {
      feedback.add({
        "candidateIndex": i,
        "candidate": candidates[i],
        "rating": ratings[i],
        "tags": tags[i] ?? <String>[],
        "comment": comments[i]?.text.trim(),
      });
    }

    try {
      final callable = FirebaseFunctions.instance.httpsCallable(
        'saveTrainerFeedback',
      );
      await callable.call({"sessionId": _sessionId, "feedback": feedback});

      if (!mounted) return;

      // Reset / refresh the whole page state
      setState(() {
        myGender = 'male';
        theirGender = 'female';
        goal = null;
        app = null;

        lastMsgController.clear();
        ageController.clear();
        hobbiesController.clear();
        countryController.clear();
        occupationController.clear();

        profileImages = [];
        chatImages = [];
        profileImageUrls = [];
        chatImageUrls = [];
        _profileDirty = false;
        _chatDirty = false;

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

                        // TWO COLUMNS
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // LEFT BOX
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
                                          value: "male",
                                          child: Text("Male"),
                                        ),
                                        DropdownMenuItem(
                                          value: "female",
                                          child: Text("Female"),
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
                                          value: "male",
                                          child: Text("Male"),
                                        ),
                                        DropdownMenuItem(
                                          value: "female",
                                          child: Text("Female"),
                                        ),
                                      ],
                                      onChanged: (v) =>
                                          setState(() => theirGender = v!),
                                    ),
                                    const SizedBox(height: 16),
                                    const Text("Goal"),
                                    DropdownButton<String>(
                                      value: goal ?? _goalPlaceholder,
                                      isExpanded: true,
                                      items: const [
                                        DropdownMenuItem(
                                          value: _goalPlaceholder,
                                          child: Text("please choose"),
                                        ),
                                        DropdownMenuItem(
                                          value: "opening line",
                                          child: Text("Opening line"),
                                        ),
                                        DropdownMenuItem(
                                          value: "reply_to_last_message",
                                          child: Text(
                                            "Reply to their last message",
                                          ),
                                        ),
                                        DropdownMenuItem(
                                          value: "flirty",
                                          child: Text("Flirty"),
                                        ),
                                        DropdownMenuItem(
                                          value: "witty",
                                          child: Text("Witty"),
                                        ),
                                        DropdownMenuItem(
                                          value: "romantic",
                                          child: Text("Romantic"),
                                        ),
                                      ],
                                      onChanged: (v) =>
                                          setState(() => goal = v),
                                    ),
                                    const SizedBox(height: 16),
                                    const Text("App"),
                                    DropdownButton<String>(
                                      value: app ?? '',
                                      isExpanded: true,
                                      items: const [
                                        DropdownMenuItem(
                                          value: '',
                                          child: Text("Optional / leave empty"),
                                        ),
                                        DropdownMenuItem(
                                          value: "tinder",
                                          child: Text("Tinder"),
                                        ),
                                        DropdownMenuItem(
                                          value: "feeld",
                                          child: Text("Feeld"),
                                        ),
                                        DropdownMenuItem(
                                          value: "other dating app",
                                          child: Text("Other dating app"),
                                        ),
                                        DropdownMenuItem(
                                          value: "whatsapp",
                                          child: Text("WhatsApp"),
                                        ),
                                        DropdownMenuItem(
                                          value: "instagram",
                                          child: Text("Instagram"),
                                        ),
                                        DropdownMenuItem(
                                          value: "sms",
                                          child: Text("SMS"),
                                        ),
                                      ],
                                      onChanged: (v) => setState(
                                        () => app = (v == '' ? null : v),
                                      ),
                                    ),
                                    const SizedBox(height: 16),
                                    const Text("Profile Images"),
                                    _imagePickerSection(
                                      files: profileImages,
                                      onPick: _pickProfileImages,
                                      onDelete: (index) {
                                        setState(() {
                                          profileImages.removeAt(index);
                                          profileImageUrls = [];
                                          _profileDirty = true;
                                        });
                                      },
                                    ),
                                    const SizedBox(height: 16),
                                    const Text("Chat Screenshots"),
                                    _imagePickerSection(
                                      files: chatImages,
                                      onPick: _pickChatImages,
                                      onDelete: (index) {
                                        setState(() {
                                          chatImages.removeAt(index);
                                          chatImageUrls = [];
                                          _chatDirty = true;
                                        });
                                      },
                                    ),
                                  ],
                                ),
                              ),
                            ),

                            const SizedBox(width: 16),

                            // RIGHT BOX
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
                                      "Last message they sent (optional if file added)",
                                      lastMsgController,
                                      optional: true,
                                      customHint:
                                          "Optional if you added an image",
                                    ),
                                    _input(
                                      "Age",
                                      ageController,
                                      optional: true,
                                      number: true,
                                    ),
                                    _input(
                                      "Hobbies",
                                      hobbiesController,
                                      optional: true,
                                    ),
                                    _input(
                                      "Country",
                                      countryController,
                                      optional: true,
                                    ),
                                    _input(
                                      "Occupation",
                                      occupationController,
                                      optional: true,
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

                    // ❌ DELETE BUTTON
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
    // Ensure comment controller exists
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

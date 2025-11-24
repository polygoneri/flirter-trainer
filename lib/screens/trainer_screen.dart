import 'package:flutter/material.dart';
import 'package:cloud_functions/cloud_functions.dart';

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

  // Optional text fields (except last message, which we'll treat as required/OR with images)
  final lastMsgController = TextEditingController();
  final ageController = TextEditingController();
  final hobbiesController = TextEditingController();
  final countryController = TextEditingController();
  final occupationController = TextEditingController();

  // Images (for now: just filenames)
  List<String> profileImages = [];
  List<String> chatImages = [];

  // Candidates from backend
  bool showCandidates = false;
  List<String> candidates = [
    "Option A: Example flirty line…",
    "Option B: Another option…",
    "Option C: A third option…",
  ];

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

  void _onGenerate() async {
    // ---- Validations ----

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
          content: Text("Add last message or at least one image."),
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

    // ---- Build data payload ----
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

    // TEMP: fake URLs until we upload real images
    final profileUrls = profileImages
        .map((e) => "https://fake.com/$e")
        .toList();
    final chatUrls = chatImages.map((e) => "https://fake.com/$e").toList();

    try {
      final result = await FirebaseFunctions.instance
          .httpsCallable("generateCandidates")
          .call({
            "context": ctx,
            "profileImageUrls": profileUrls,
            "chatImageUrls": chatUrls,
          });

      final data = result.data;
      final List<dynamic> returnedCandidates = data["candidates"];

      setState(() {
        candidates = returnedCandidates
            .map((c) => c["text"] as String)
            .toList();
        showCandidates = true;
      });
    } catch (e) {
      print("Error calling function: $e");
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Function error: $e")));
    }
  }

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
                                          value: "continues msg",
                                          child: Text("Continues msg"),
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
                                          child: Text("Other Dating App"),
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
                                    _fakeImageButton(profileImages),
                                    const SizedBox(height: 16),
                                    const Text("Chat Screenshots"),
                                    _fakeImageButton(chatImages),
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
                                      "Last message from her/him",
                                      lastMsgController,
                                      optional: false,
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
                            onPressed: _onGenerate,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue,
                              foregroundColor: Colors.white,
                              minimumSize: const Size.fromHeight(48),
                            ),
                            child: const Text("Generate"),
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
            hintText: optional ? "Optional" : null,
          ),
        ),
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _fakeImageButton(List<String> list) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ElevatedButton(
          onPressed: () {
            setState(() => list.add("image_${list.length + 1}.jpg"));
          },
          child: const Text("Pick image (fake)"),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (var name in list)
              Chip(label: Text(name), visualDensity: VisualDensity.compact),
          ],
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
          padding: const EdgeInsets.all(16), // <-- add `padding:`
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Rate Candidates",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              for (var i = 0; i < candidates.length; i++) _candidateBox(i),
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

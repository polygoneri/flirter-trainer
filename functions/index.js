const { onCall } = require("firebase-functions/v2/https");
const { defineSecret } = require("firebase-functions/params");
const admin = require("firebase-admin");
const OpenAI = require("openai");

const openaiKey = defineSecret("OPENAI_API_KEY");

if (!admin.apps.length) {
  admin.initializeApp();
}
const db = admin.firestore();

// ---------------- generateCandidates ----------------

exports.generateCandidates = onCall(
  { secrets: [openaiKey] },
  async (request) => {
    const openai = new OpenAI({
      apiKey: openaiKey.value(),
    });

    const data = request.data || {};
    const contextData = data.context || {};
    const profileImageUrls = data.profileImageUrls || [];
    const chatImageUrls = data.chatImageUrls || [];

    console.log(
      "[generateCandidates] incoming data:",
      JSON.stringify(data, null, 2)
    );
    console.log(
      "[generateCandidates] contextData:",
      JSON.stringify(contextData, null, 2)
    );
    console.log("[generateCandidates] profileImageUrls:", profileImageUrls);
    console.log("[generateCandidates] chatImageUrls:", chatImageUrls);

    // You can tweak these if needed
    const VISION_MODEL = "gpt-4.1-mini";
    const TEXT_MODEL = "gpt-4.1";

    // ---------- 1) CAPTION IMAGES WITH VISION ----------
    //   - Profile photos -> vibe / scene captions
    //   - Chat screenshots -> OCR: "Extract ALL text visible in this chat screenshot."

    const profileCaptions = [];
    const chatTexts = [];

    // ----- 1a) Profile photos -> vibe captions -----
    if (profileImageUrls.length > 0) {
      console.log(
        "[generateCandidates] captioning profile images, count:",
        profileImageUrls.length
      );

      const profileCaptionPromises = profileImageUrls.map(async (url, idx) => {
        console.log(
          "[generateCandidates] vision call for PROFILE image index",
          idx,
          "url:",
          url
        );

        const visionResp = await openai.chat.completions.create({
          model: VISION_MODEL,
          messages: [
            {
              role: "user",
              content: [
                {
                  type: "text",
                  text:
                    "Look at this dating profile photo and describe what is visually noticeable in one short sentence. " +
                    "Focus on activity, environment, mood, vibe, or objects around them. " +
                    "Do NOT mention physical attractiveness or specific body parts. " +
                    "Do NOT invent details that are not clearly visible.",
                },
                {
                  type: "image_url",
                  image_url: { url },
                },
              ],
            },
          ],
          temperature: 0.4,
        });

        console.log(
          "[generateCandidates] profile visionResp index",
          idx,
          ":",
          JSON.stringify(visionResp, null, 2)
        );

        const rawContent = visionResp.choices?.[0]?.message?.content;
        const caption =
          typeof rawContent === "string" && rawContent.trim().length > 0
            ? rawContent.trim()
            : "No useful profile caption.";

        console.log(
          "[generateCandidates] final PROFILE caption index",
          idx,
          ":",
          caption
        );

        return caption;
      });

      const resolvedProfileCaptions = await Promise.all(profileCaptionPromises);
      profileCaptions.push(...resolvedProfileCaptions);
    }

    // ----- 1b) Chat screenshots -> OCR text -----
    if (chatImageUrls.length > 0) {
      console.log(
        "[generateCandidates] OCR on chat images, count:",
        chatImageUrls.length
      );

      const chatTextPromises = chatImageUrls.map(async (url, idx) => {
        console.log(
          "[generateCandidates] vision call for CHAT image index",
          idx,
          "url:",
          url
        );

        const visionResp = await openai.chat.completions.create({
          model: VISION_MODEL,
          messages: [
            {
              role: "user",
              content: [
                {
                  type: "text",
                  text:
                    "Extract ALL text visible in this chat screenshot.\n" +
                    "Return ONLY the text exactly as it appears, in reading order.\n" +
                    "Do NOT summarize.\n" +
                    "Do NOT describe the image.\n" +
                    "Do NOT add commentary.\n" +
                    "Do NOT omit emojis or symbols.",
                },
                {
                  type: "image_url",
                  image_url: { url },
                },
              ],
            },
          ],
          temperature: 0.0,
        });

        console.log(
          "[generateCandidates] chat OCR visionResp index",
          idx,
          ":",
          JSON.stringify(visionResp, null, 2)
        );

        const rawContent = visionResp.choices?.[0]?.message?.content;
        const text =
          typeof rawContent === "string" && rawContent.trim().length > 0
            ? rawContent.trim()
            : "";

        console.log(
          "[generateCandidates] final CHAT TEXT index",
          idx,
          ":",
          text
        );

        return text;
      });

      const resolvedChatTexts = await Promise.all(chatTextPromises);
      chatTexts.push(...resolvedChatTexts.filter((t) => t && t.trim().length));
    }

    console.log("[generateCandidates] profileCaptions:", profileCaptions);
    console.log("[generateCandidates] chatTexts:", chatTexts);

    // Combine for the text model
    let captionsTextParts = [];

    if (profileCaptions.length > 0) {
      captionsTextParts.push(
        "Profile photos:\n" +
          profileCaptions.map((c, i) => `${i + 1}. ${c}`).join("\n")
      );
    }

    if (chatTexts.length > 0) {
      captionsTextParts.push(
        "Chat text extracted from screenshots:\n" + chatTexts.join("\n---\n")
      );
    }

    const captionsText =
      captionsTextParts.length > 0
        ? captionsTextParts.join("\n\n")
        : "No image or chat information.";

    // ---------- 2) MAIN LLM CALL FOR CANDIDATES ----------

    const userDescription = JSON.stringify(contextData);

    const prompt = `
You write short, human, flirty, funny, smart, and intriguing chat messages for dating apps and WhatsApp.

Your brain is **99 percent based on images and chat text**, and only **1 percent** on extra context.

IMAGE + CHAT PRIORITY:
1) Use the extracted chat text (if any) as if you read the conversation yourself.
2) Use the profile photos and what they show: activity, environment, mood, vibe, objects, and scene.

If there is anything visually interesting, clever, or funny in the images or chat text, that is your main material for the lines.

CONTEXT (1 percent only):
You also receive a small JSON object called context (myGender, theirGender, goal, app, lastMessage, age, hobbies, country, occupation).
Use these ONLY if they create a naturally witty, funny, smart, or intriguing connection to:
- something visible in the images,
- the vibe of the photos,
- the activity shown,
- or the extracted chat text / lastMessage.
If there is NO clever connection, IGNORE hobbies, age, country, occupation completely.

TONE:
- light
- confident
- playful
- observant
- calm energy
- never thirsty
- never overeager
- never romantic unless goal = romantic

STYLE:
- Short messages only. One sentence or two very short ones.
- No emojis.
- No dash characters. Use commas or periods only.
- No generic pickup lines.
- No cliches.
- No compliments about appearance or body parts.
- Never sound impressed or amazed.
- Never sound needy or eager.
- Never sound like an AI. Must feel like normal texting.

GOAL LOGIC:
- "opening line": treat as first message.
- "reply_to_last_message": MUST respond naturally to lastMessage and/or the extracted chat text.
- For "flirty", "witty", "romantic":
    - If lastMessage or chat text exists → treat as a reply.
    - If not → treat as an opener.
- Romantic tone ONLY if goal = romantic.

IMAGE + CHAT INPUT (from vision + OCR):
${captionsText}

CONTEXT JSON FROM APP:
${userDescription}

TASK:
Write exactly three different message options.
Each must be a realistic message the user can send immediately.

OUTPUT FORMAT:
Return JSON only, with no extra text:
{
  "candidates": [
    { "index": 0, "text": "..." },
    { "index": 1, "text": "..." },
    { "index": 2, "text": "..." }
  ]
}
Each "text" is a single concrete message the user can send as is.
`.trim();

    console.log(
      "[generateCandidates] final prompt (first 800 chars):",
      prompt.slice(0, 800)
    );

    const chatResp = await openai.chat.completions.create({
      model: TEXT_MODEL,
      messages: [
        {
          role: "user",
          content: prompt,
        },
      ],
      temperature: 0.8,
      response_format: { type: "json_object" },
    });

    console.log(
      "[generateCandidates] full chatResp:",
      JSON.stringify(chatResp, null, 2)
    );

    const rawOut = chatResp.choices?.[0]?.message?.content;
    console.log("[generateCandidates] rawOut type:", typeof rawOut);
    console.log("[generateCandidates] rawOut value:", rawOut);

    let content = "";
    if (typeof rawOut === "string") {
      content = rawOut;
    } else if (rawOut && typeof rawOut === "object" && rawOut.text) {
      content = String(rawOut.text);
    }

    console.log(
      "[generateCandidates] content (first 500 chars):",
      content.slice(0, 500)
    );

    let parsed;
    try {
      parsed = content ? JSON.parse(content) : {};
    } catch (e) {
      console.error("[generateCandidates] JSON.parse failed:", e);
      parsed = {};
    }

    // sanitize all dashes (em dash, en dash, hyphen)
    const sanitizeNoDashes = (text) =>
      text ? text.replace(/[—–-]/g, " ") : "";

    let candidatesRaw = Array.isArray(parsed.candidates)
      ? parsed.candidates
      : [];

    if (!candidatesRaw.length) {
      console.warn(
        "[generateCandidates] parsed.candidates missing or empty, using hard fallback"
      );
      candidatesRaw = [
        {
          index: 0,
          text: "Something went wrong with the generator. Try again.",
        },
      ];
    }

    const candidates = candidatesRaw.map((c, i) => {
      let text = sanitizeNoDashes(c.text ?? "").trim();
      if (!text) {
        text = "Something went wrong, try generating again.";
      }
      return {
        index: c.index ?? i,
        text,
      };
    });

    console.log(
      "[generateCandidates] final candidates:",
      JSON.stringify(candidates, null, 2)
    );

    // ---------- 3) SAVE SESSION TO FIRESTORE ----------

    const docRef = await db.collection("trainerSessions").add({
      context: contextData,
      profileImageUrls,
      chatImageUrls,
      captions: {
        profileCaptions,
        chatTexts,
      },
      candidates,
      status: "awaiting_rating",
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    console.log(
      "[generateCandidates] saved trainerSessions doc with id:",
      docRef.id
    );

    return {
      sessionId: docRef.id,
      candidates,
    };
  }
);

// ---------------- saveTrainerFeedback ----------------

exports.saveTrainerFeedback = onCall(
  { secrets: [openaiKey] },
  async (request) => {
    const data = request.data || {};
    const feedback = Array.isArray(data.feedback) ? data.feedback : [];
    const sessionId = data.sessionId || null;

    console.log("[saveTrainerFeedback] incoming sessionId:", sessionId);
    console.log("[saveTrainerFeedback] incoming feedback:", feedback);

    if (!feedback.length) {
      console.log("[saveTrainerFeedback] no feedback items, nothing to save.");
      return { ok: true, count: 0 };
    }

    const createdAt = admin.firestore.FieldValue.serverTimestamp();

    const writes = feedback.map((f) =>
      db.collection("trainerFeedback").add({
        sessionId,
        candidateIndex: f.candidateIndex ?? null,
        candidate: f.candidate ?? "",
        rating: f.rating ?? null,
        tags: Array.isArray(f.tags) ? f.tags : [],
        comment: f.comment ?? null,
        createdAt,
      })
    );

    const refs = await Promise.all(writes);
    console.log(
      "[saveTrainerFeedback] saved feedback docs:",
      refs.map((r) => r.id)
    );

    return { ok: true, count: refs.length };
  }
);

const functions = require("firebase-functions");
const admin = require("firebase-admin");

admin.initializeApp();
const db = admin.firestore();

exports.generateCandidates = functions.https.onCall(async (data, context) => {
  const {
    context: contextData = {},
    profileImageUrls = [],
    chatImageUrls = [],
  } = data || {};

  // Mock captions + candidates for now
  const captions = [
    "Mock caption: profile looks confident and fun.",
    "Mock caption: chat screenshot shows playful tone.",
  ];

  const candidates = [
    { index: 0, text: "Option A (mock): Hey, love your vibe in that pic 🔥" },
    {
      index: 1,
      text: "Option B (mock): You seem fun, what’s your go-to weekend plan?",
    },
    {
      index: 2,
      text: "Option C (mock): I like your style, what’s the story behind that photo?",
    },
  ];

  const now = admin.firestore.FieldValue.serverTimestamp();

  const doc = {
    context: contextData, // genders, age, goal, app, lastMsg, etc (from Flutter)
    profileImageUrls,
    chatImageUrls,
    captions,
    candidates,
    status: "awaiting_rating",
    createdAt: now,
    updatedAt: now,
  };

  const ref = await db.collection("trainerSessions").add(doc);

  return {
    sessionId: ref.id,
    captions,
    candidates,
  };
});

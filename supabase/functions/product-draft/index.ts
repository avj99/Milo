// Milo — photo → structured product draft.
// The app sends a food photo (base64 JPEG); Claude vision returns a draft the
// owner confirms in the app. The Anthropic key lives here (Supabase secret
// ANTHROPIC_API_KEY), never in the app. Auth: Supabase verifies the caller's
// JWT before this function runs (verify_jwt = true, the default).
import Anthropic from "npm:@anthropic-ai/sdk";

// The shape ConfirmView needs — mirrors the app's Product model plus
// AI-specific fields (confidence, caveat). Structured outputs guarantee the
// response parses; no schema drift between model output and the Swift decoder.
const DRAFT_SCHEMA = {
  type: "object",
  properties: {
    name: { type: "string", description: "Short food name, e.g. 'Chicken Jerky Bites' or 'Banana (half)'" },
    brand: { type: "string", description: "Brand if visible on packaging, else empty string" },
    emoji: { type: "string", description: "Single food emoji that best represents this food" },
    category: { type: "string", enum: ["meal", "treat", "addIn"], description: "meal = complete dog food; treat = dog treat/chew; addIn = human food given to a dog" },
    kcalPerUnit: { type: "integer", description: "Estimated kilocalories per one portionBasis unit" },
    portionBasis: { type: "string", description: "Natural serving unit, e.g. 'piece', 'cup', '¾ cup', 'slice', 'handful'" },
    ingredients: {
      type: "array",
      items: { type: "string" },
      description: "Ingredients readable on the label, lowercase, in label order. Empty if not visible. For unpackaged food, the food itself (e.g. ['banana']).",
    },
    isEstimate: { type: "boolean", description: "true unless kcal comes from a clearly readable nutrition panel" },
    confidence: { type: "string", enum: ["high", "medium", "low"], description: "How sure you are about the identification overall" },
    caveat: { type: "string", description: "One short caution if relevant (e.g. 'kcal estimated from typical values'), else empty string" },
  },
  required: ["name", "brand", "emoji", "category", "kcalPerUnit", "portionBasis", "ingredients", "isEstimate", "confidence", "caveat"],
  additionalProperties: false,
} as const;

const SYSTEM = `You identify food for a dog-nutrition tracking app. The photo shows either
packaged dog food/treats (bag, box, pouch — possibly the nutrition/ingredient label) or
plain human food being shared with a dog (fruit, meat, bread, etc.).

Rules:
- Prefer what is literally readable in the photo (product name, brand, kcal/ME values,
  ingredient list) over general knowledge. kcal on dog food labels is often kcal/kg or
  kcal/cup — convert to the portionBasis you choose and say so in caveat.
- If the label is not readable, estimate from typical published values for that food and
  set isEstimate=true with confidence medium or low.
- Never invent a brand. Never output medical advice; this app only tracks intake.
- If the photo clearly contains no food, use name "Not a food item", kcalPerUnit 0,
  confidence "low" and explain in caveat.`;

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return json({ error: "POST only" }, 405);
  }
  if (!Deno.env.get("ANTHROPIC_API_KEY")) {
    return json({ error: "AI is not configured yet (missing ANTHROPIC_API_KEY secret)" }, 503);
  }

  let body: { imageBase64?: string; mediaType?: string; ocrText?: string };
  try {
    body = await req.json();
  } catch {
    return json({ error: "invalid JSON body" }, 400);
  }
  const { imageBase64, mediaType = "image/jpeg", ocrText } = body;
  if (!imageBase64 || imageBase64.length > 8_000_000) {
    return json({ error: "imageBase64 missing or too large (send ≤ ~6MB, downscaled JPEG)" }, 400);
  }
  if (!["image/jpeg", "image/png", "image/webp"].includes(mediaType)) {
    return json({ error: "unsupported mediaType" }, 400);
  }

  const anthropic = new Anthropic(); // reads ANTHROPIC_API_KEY

  try {
    const response = await anthropic.messages.create({
      model: "claude-opus-4-8",
      max_tokens: 2048,
      system: SYSTEM,
      output_config: { format: { type: "json_schema", schema: DRAFT_SCHEMA } },
      messages: [
        {
          role: "user",
          content: [
            {
              type: "image",
              source: { type: "base64", media_type: mediaType as "image/jpeg" | "image/png" | "image/webp", data: imageBase64 },
            },
            {
              type: "text",
              text: ocrText
                ? `Draft a product entry for this food. On-device OCR read this text from the label (may contain errors):\n${ocrText.slice(0, 4000)}`
                : "Draft a product entry for this food.",
            },
          ],
        },
      ],
    });

    if (response.stop_reason === "refusal") {
      return json({ error: "The AI declined to analyze this image" }, 422);
    }
    const text = response.content.find((b) => b.type === "text");
    if (!text || text.type !== "text") {
      return json({ error: "empty AI response" }, 502);
    }
    // Structured outputs guarantee this is valid JSON matching DRAFT_SCHEMA.
    return new Response(text.text, {
      headers: { "content-type": "application/json" },
    });
  } catch (err) {
    console.error("product-draft failed:", err);
    return json({ error: "AI request failed" }, 502);
  }
});

function json(payload: unknown, status: number): Response {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { "content-type": "application/json" },
  });
}

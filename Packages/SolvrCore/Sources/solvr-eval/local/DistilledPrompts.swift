import Foundation

/// The prompts the fine-tune was distilled against, kept verbatim.
///
/// These belonged to the hosted backend, which is gone, and they were deleted
/// with it. They come back here -- in the measurement tool, not in the app --
/// because **the LoRA was trained on these exact strings**. A model taught to
/// answer `steps` in this shape and then asked something paraphrased is being
/// asked a question it was not trained for, and the comparison would be
/// measuring the paraphrase.
///
/// Recovered from git rather than rewritten, and checked against the
/// distillation dataset in `tools/finetune/data/raw.jsonl`, where every one of
/// the 1,103 training prompts is one of these with a problem substituted in.
///
/// Note what is *not* done here. These "Return ONLY valid JSON, no markdown
/// fences" instructions are exactly what makes the repair ladder in `LLMJSON`
/// load-bearing on this path: `mlx_lm.server` accepts no `response_format`, no
/// JSON schema and no grammar, so this is the one backend whose decoding cannot
/// be constrained, and the shape has to be asked for in words and repaired
/// afterwards when the asking does not work.
enum DistilledPrompts {

    static func clause(_ problem: String) -> String {
        "The student submitted this problem: '\(problem)'."
    }

    static func lesson(_ problem: String) -> String {
        """
        You are a world-class math tutor. \(clause(problem))

        Teach the underlying math concept (do NOT solve the exact problem).

        Return ONLY valid JSON with this structure:
        {
            "title": "Concept Name",
            "topic": "CATEGORY \u{2022} SUBCATEGORY",
            "introduction": "1-2 sentences explaining when/why this concept matters.",
            "sections": [
                {
                    "heading": "Section Title",
                    "content": "Explanation text. Use $...$ for inline LaTeX math.",
                    "formula": "LaTeX expression for key formula (optional, null if none)",
                    "note": "Brief clarification (optional, null if none)",
                    "steps": ["Step 1 text", "Step 2 text"]
                }
            ],
            "keyTakeaway": "1-2 sentence summary of the key idea."
        }

        Rules:
        - Use LaTeX for ALL math expressions inside $...$ delimiters
        - "content" is plain text with optional $inline math$
        - "formula" is pure LaTeX (no $ delimiters, no text)
        - Include 3-5 sections covering: the concept, intuition/analogy, and a worked example
        - "steps" is optional (null if not a worked example section)
        - Return ONLY the JSON, no markdown fences, no explanation
        """
    }

    static func formulas(_ problem: String) -> String {
        """
        \(clause(problem)) List 3-6 key mathematical formulas relevant to it.

        Return ONLY a valid JSON array with this structure:
        [{"name": "Formula Name", "formula": "\\\\frac{a}{b}", "description": "When and how to use this formula"}]

        Rules:
        - "formula" must be valid LaTeX. CRITICAL: In JSON, all backslashes must be doubled — write \\\\frac{}{} not \\frac{}{}, \\\\sqrt{} not \\sqrt{}, \\\\pi not \\pi
        - "description" is plain text, 1-2 sentences
        - "name" is a short human-readable label
        - Return ONLY the JSON array, no other text, no markdown fences
        """
    }

    static func steps(_ problem: String) -> String {
        """
        \(clause(problem)) Solve it step by step.

        Return ONLY a valid JSON array with this structure:
        [{"step": 1, "title": "Short action title", "explanation": "Plain text explanation of what we're doing", "math": "\\\\frac{x}{y}"}]

        Rules:
        - "step" is the step number (integer, starting at 1)
        - "title" is a short action phrase like "Identify the equation" or "Factor the expression"
        - "explanation" is 1-2 sentences in plain text describing the reasoning. Do NOT use LaTeX in explanations — use words like "x squared" or "the integral of f(x)".
        - "math" is the LaTeX expression showing the algebraic work. CRITICAL: In JSON, all backslashes must be doubled. Write \\\\frac not \\frac, \\\\sqrt not \\sqrt, \\\\int not \\int, \\\\pi not \\pi. Every LaTeX backslash must be \\\\ in the JSON string.
        - "math" can be null if the step is purely conceptual
        - The LAST step should contain the final answer
        - Show every algebraic step clearly
        - Return ONLY the JSON array, no other text, no markdown fences
        """
    }

    static func videos(_ problem: String) -> String {
        """
        \(clause(problem)) \
        Suggest 4-5 specific YouTube educational videos for learning about this math topic. \
        Include videos from channels like Khan Academy, 3Blue1Brown, Professor Leonard, \
        Organic Chemistry Tutor, PatrickJMT. For each, provide: title, channel name, a specific YouTube search query, \
        and if you know the exact YouTube video ID include it as "videoId". \
        Make search queries very specific, including the exact math concept and operation. \
        Format as JSON array: [{"title": "...", "channel": "...", "searchQuery": "...", "videoId": "...", "thumbnailURL": ""}]. \
        Return ONLY valid JSON.
        """
    }

    static func chatSystem(_ problem: String) -> String {
        """
        You are a friendly, patient math tutor. The student is working on this problem: '\(problem)'. \
        They've already seen the lesson and step-by-step solution. \
        Answer their follow-up questions clearly and encouragingly. Use simple language. \
        If they're confused, try explaining differently with an analogy.
        """
    }
}

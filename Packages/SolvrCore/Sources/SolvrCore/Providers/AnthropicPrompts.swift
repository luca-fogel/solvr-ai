import Foundation

/// The prompts Solvr sends to the Anthropic API.
///
/// They live with the provider rather than in the app because a prompt is a
/// property of the backend: a 4B needs shorter, more constrained instructions
/// than Opus, and a backend whose decoding is already constrained needs no schema
/// in the prompt at all.
///
/// Note what is *not* done here. Under `usesStructuredOutputs` the "Return ONLY
/// valid JSON, no markdown fences" instructions below are redundant -- the API
/// enforces the shape -- and a production implementation would delete them and
/// save the tokens. They are left in deliberately so that the constrained and
/// unconstrained arms of the evaluation differ in exactly one thing: the decoding
/// mechanism. Changing the prompt at the same time would make the comparison
/// measure two changes and attribute both to one.
enum AnthropicPrompts {

    static func clause(_ input: ProblemInput) -> String {
        switch input {
        case .text(let problem):
            return "The student submitted this problem: '\(problem)'."
        case .image:
            return "Look at the math problem in this image."
        }
    }

    static func lesson(_ input: ProblemInput) -> String {
        """
        You are a world-class math tutor. \(clause(input))

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

    static func formulas(_ input: ProblemInput) -> String {
        """
        \(clause(input)) List 3-6 key mathematical formulas relevant to it.

        Return ONLY a valid JSON array with this structure:
        [{"name": "Formula Name", "formula": "\\\\frac{a}{b}", "description": "When and how to use this formula"}]

        Rules:
        - "formula" must be valid LaTeX. CRITICAL: In JSON, all backslashes must be doubled — write \\\\frac{}{} not \\frac{}{}, \\\\sqrt{} not \\sqrt{}, \\\\pi not \\pi
        - "description" is plain text, 1-2 sentences
        - "name" is a short human-readable label
        - Return ONLY the JSON array, no other text, no markdown fences
        """
    }

    static func steps(_ input: ProblemInput) -> String {
        """
        \(clause(input)) Solve it step by step.

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

    static func videos(_ input: ProblemInput) -> String {
        """
        \(clause(input)) \
        Suggest 4-5 specific YouTube educational videos for learning about this math topic. \
        Include videos from channels like Khan Academy, 3Blue1Brown, Professor Leonard, \
        Organic Chemistry Tutor, PatrickJMT. For each, provide: title, channel name, a specific YouTube search query, \
        and if you know the exact YouTube video ID include it as "videoId". \
        Make search queries very specific, including the exact math concept and operation. \
        Format as JSON array: [{"title": "...", "channel": "...", "searchQuery": "...", "videoId": "...", "thumbnailURL": ""}]. \
        Return ONLY valid JSON.
        """
    }

    static func title(_ input: ProblemInput) -> String {
        """
        \(clause(input))

        Respond with ONLY a 3-5 word title summarizing what the problem is about. Examples: "Surface Area Integral", "Curl of Vector Field", "Quadratic Factoring", "Taylor Series Expansion", "Double Integral Polar".

        Respond with ONLY the short title, nothing else. No quotes, no period, no explanation.
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

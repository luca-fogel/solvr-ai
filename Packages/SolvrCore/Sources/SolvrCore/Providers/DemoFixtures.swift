#if SOLVR_DEMO
import Foundation

/// Canned model responses for demo mode.
///
/// Stored as JSON *text*, not as Swift values, and fed through the same
/// `LLMJSON.decode` ladder the network path uses. Two reasons: the demo exercises
/// the real parser rather than a shortcut around it, and the fixtures double as
/// a worked example of what the prompts are asking the model for.
///
/// The step fixture deliberately contains raw, unescaped LaTeX (`\frac`, not
/// `\\frac`), which is what the model actually sends and what JSON rejects. If
/// the repair layer regresses, demo mode breaks visibly on launch.
///
/// Every problem here is synthetic — written for this file, not taken from any
/// student's work.
public enum DemoFixtures {

    public static let problem = "Evaluate the definite integral of 3x^2 from 0 to 1"

    public static let title = "Definite integral of 3x²"

    public static let steps = #"""
    [
      {
        "step": 1,
        "title": "Recognise the form",
        "explanation": "This is a definite integral of a power of x, so the power rule for integration applies. Nothing here needs substitution or parts.",
        "math": "\int_{0}^{1} 3x^{2}\,dx"
      },
      {
        "step": 2,
        "title": "Apply the power rule",
        "explanation": "Raise the exponent by one and divide by the new exponent. The constant 3 comes along for the ride.",
        "math": "\int 3x^{2}\,dx = 3\cdot\frac{x^{3}}{3} = x^{3}"
      },
      {
        "step": 3,
        "title": "Evaluate at the bounds",
        "explanation": "Substitute the upper limit, then the lower limit, and subtract. This is the Fundamental Theorem of Calculus doing the work.",
        "math": "\left[x^{3}\right]_{0}^{1} = 1^{3} - 0^{3}"
      },
      {
        "step": 4,
        "title": "Final answer",
        "explanation": "The area under y = 3x² between x = 0 and x = 1 is exactly 1.",
        "math": "= 1"
      }
    ]
    """#

    public static let formulas = #"""
    [
      {
        "name": "Power rule for integration",
        "formula": "\int x^{n}\,dx = \frac{x^{n+1}}{n+1} + C, \quad n \neq -1",
        "description": "The workhorse for any polynomial term. The exception at n = -1 is where the natural logarithm comes from."
      },
      {
        "name": "Fundamental Theorem of Calculus",
        "formula": "\int_{a}^{b} f(x)\,dx = F(b) - F(a)",
        "description": "Turns an area into two substitutions, provided F is an antiderivative of f."
      },
      {
        "name": "Constant multiple rule",
        "formula": "\int c\cdot f(x)\,dx = c\int f(x)\,dx",
        "description": "Why the 3 can be pulled outside the integral instead of complicating it."
      }
    ]
    """#

    public static let lesson = #"""
    {
      "title": "Definite Integrals as Signed Area",
      "topic": "CALCULUS • INTEGRATION",
      "introduction": "A definite integral is not a new kind of algebra. It is a way of adding up infinitely many infinitely thin rectangles, and once that clicks the bounds stop looking like decoration.",
      "sections": [
        {
          "heading": "What the notation is telling you",
          "content": "The integral sign is an elongated S, for sum. dx is the width of each rectangle and f(x) is its height, so f(x)dx is an area. The bounds say where to start adding and where to stop.",
          "formula": "\int_{a}^{b} f(x)\,dx",
          "note": null,
          "steps": null
        },
        {
          "heading": "Why an antiderivative answers an area question",
          "content": "This is the part that deserves surprise rather than memorisation. Accumulated area, seen as a function of where you stop, has f as its rate of change - so undoing the differentiation gives back the accumulation.",
          "formula": "\frac{d}{dx}\int_{a}^{x} f(t)\,dt = f(x)",
          "note": "This is the Fundamental Theorem of Calculus, and it is the bridge between the two halves of the course.",
          "steps": null
        },
        {
          "heading": "Signed, not merely positive",
          "content": "Below the axis the height is negative, so the contribution is negative. An integral can come out to exactly zero over an interval where the function is never zero, which is a common source of confident wrong answers.",
          "formula": "\int_{-1}^{1} x\,dx = 0",
          "note": null,
          "steps": null
        },
        {
          "heading": "How to evaluate one, every time",
          "content": "The mechanical procedure, once the concept is in place.",
          "formula": null,
          "note": null,
          "steps": [
            "Find any antiderivative F of the integrand. Drop the constant.",
            "Evaluate F at the upper bound.",
            "Evaluate F at the lower bound.",
            "Subtract the second from the first."
          ]
        }
      ],
      "keyTakeaway": "Evaluate the antiderivative at both bounds and subtract. A negative answer means the curve spent time below the axis - that is information, not a mistake."
    }
    """#

    public static let videos = #"""
    [
      {
        "title": "Definite integrals: intro",
        "channel": "Khan Academy",
        "searchQuery": "definite integral introduction khan academy",
        "videoId": null,
        "thumbnailURL": null
      },
      {
        "title": "The Fundamental Theorem of Calculus, visually",
        "channel": "3Blue1Brown",
        "searchQuery": "3blue1brown fundamental theorem of calculus",
        "videoId": null,
        "thumbnailURL": null
      }
    ]
    """#

    public static let chatReply = """
    Yes - the constant of integration disappears in a definite integral, and it is worth \
    seeing why rather than just remembering it.

    If F(x) + C is an antiderivative, then evaluating gives (F(1) + C) - (F(0) + C). \
    The two copies of C cancel, whatever C was. So the bounds do not just give you a \
    number instead of a family of functions - they are the reason the ambiguity goes away.
    """

    public static let detectedProblems = #"""
    [
      {
        "bbox": { "top": 0.18, "left": 0.08, "width": 0.84, "height": 0.14 },
        "latex": "\int_{0}^{1} 3x^{2}\,dx"
      },
      {
        "bbox": { "top": 0.42, "left": 0.08, "width": 0.72, "height": 0.13 },
        "latex": "\frac{d}{dx}\left(x^{3} - 4x\right)"
      }
    ]
    """#
}
#endif  // SOLVR_DEMO

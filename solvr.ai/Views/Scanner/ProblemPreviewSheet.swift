import SwiftUI

struct ProblemPreviewSheet: View {
    let image: UIImage
    let problem: DetectedProblem
    let onSolve: (String) -> Void
    let onBack: () -> Void

    @State private var showTranslation = false

    var body: some View {
        VStack(spacing: 0) {
            // Drag handle
            Capsule()
                .fill(Color(UIColor.systemGray4))
                .frame(width: 36, height: 5)
                .padding(.top, 10)
                .padding(.bottom, Theme.Spacing.base)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: Theme.Spacing.xl) {

                    // YOUR HANDWRITING — cropped tightly to the problem
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 6) {
                            Image(systemName: "camera.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.Colors.textTertiary)
                            Text("Your problem")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Theme.Colors.textTertiary)
                        }

                        // Cropped image
                        croppedProblemImage
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: .infinity)
                            .frame(maxHeight: 100)
                            .padding(Theme.Spacing.md)
                            .background(Theme.Colors.secondaryBackground)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.Radii.md, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: Theme.Radii.md, style: .continuous)
                                    .stroke(Theme.Colors.separator, lineWidth: 0.5)
                            )
                    }

                    // Down arrow
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(Theme.Colors.accent)
                        .symbolRenderingMode(.hierarchical)

                    // DETECTED LaTeX — KaTeX rendering
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 6) {
                            Image(systemName: "function")
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.Colors.textTertiary)
                            Text("Detected as")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Theme.Colors.textTertiary)
                        }

                        if showTranslation {
                            MathPageView(html: buildPreviewHTML(problem.latex))
                                .frame(maxWidth: .infinity)
                                .frame(height: 80)
                                .clipShape(RoundedRectangle(cornerRadius: Theme.Radii.md, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: Theme.Radii.md, style: .continuous)
                                        .stroke(Theme.Colors.accent.opacity(0.3), lineWidth: 1)
                                )
                                .transition(.opacity.combined(with: .offset(y: 15)))
                        }
                    }
                }
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.bottom, Theme.Spacing.base)
            }

            // Bottom buttons
            VStack(spacing: 10) {
                Button {
                    Haptics.medium()
                    onSolve(problem.latex)
                } label: {
                    Text("Solve this")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(Theme.Colors.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .pressAnimation()

                Button(action: onBack) {
                    Text("Choose different problem")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Theme.Colors.accent)
                }
                .padding(.bottom, Theme.Spacing.xs)
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.bottom, Theme.Spacing.sm)
        }
        .background(Theme.Colors.background)
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.85).delay(0.2)) {
                showTranslation = true
            }
        }
    }

    // MARK: - Cropped Image

    private var croppedProblemImage: Image {
        let bbox = problem.bbox
        let imgW = image.size.width
        let imgH = image.size.height

        let padX: Double = 1.0
        let padY: Double = 0.5
        let cropX = max(0, (bbox.left - padX) / 100.0 * imgW)
        let cropY = max(0, (bbox.top - padY) / 100.0 * imgH)
        let cropW = min(imgW - cropX, (bbox.width + padX * 2) / 100.0 * imgW)
        let cropH = min(imgH - cropY, (bbox.height + padY * 2) / 100.0 * imgH)

        let cropRect = CGRect(x: cropX, y: cropY, width: cropW, height: cropH)

        if let cgImage = image.cgImage?.cropping(to: cropRect) {
            return Image(uiImage: UIImage(cgImage: cgImage))
        }
        return Image(uiImage: image)
    }

    // MARK: - Preview HTML (single formula)

    private func buildPreviewHTML(_ latex: String) -> String {
        let stripped = latex
            .replacingOccurrences(of: "$$", with: "")
            .replacingOccurrences(of: "$", with: "")
        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
        <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/katex@0.16.21/dist/katex.min.css">
        <script defer src="https://cdn.jsdelivr.net/npm/katex@0.16.21/dist/katex.min.js"></script>
        <script defer src="https://cdn.jsdelivr.net/npm/katex@0.16.21/dist/contrib/auto-render.min.js"
                onload="renderMathInElement(document.body, { delimiters: [{left:'\\\\[',right:'\\\\]',display:true}], throwOnError:false });"></script>
        <style>
            * { margin:0; padding:0; }
            body { display:flex; align-items:center; justify-content:center; min-height:100%;
                   font-family:-apple-system,system-ui,sans-serif; background:transparent; padding:8px; }
            @media (prefers-color-scheme:dark) { body { color:#fff; } }
            .katex { font-size:1.15em; }
        </style>
        </head>
        <body>\\[\(stripped)\\]</body>
        </html>
        """
    }
}

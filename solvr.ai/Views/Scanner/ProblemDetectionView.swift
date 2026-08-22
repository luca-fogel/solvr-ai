import SwiftUI
import SolvrCore

struct ProblemDetectionView: View {
    let image: UIImage
    let problems: [DetectedProblem]
    let isDetecting: Bool
    let onSelectProblem: (DetectedProblem) -> Void
    let onRetake: () -> Void

    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                // Top bar
                topBar
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 8)

                // Image with bounding boxes
                GeometryReader { geo in
                    ZStack {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: geo.size.width, height: geo.size.height)
                            .position(
                                x: geo.size.width / 2 + offset.width,
                                y: geo.size.height / 2 + offset.height
                            )
                            .scaleEffect(scale)

                        // Bounding box overlays
                        if !isDetecting {
                            ForEach(Array(problems.enumerated()), id: \.element.id) { index, problem in
                                problemHighlight(
                                    problem: problem,
                                    index: index + 1,
                                    containerSize: geo.size
                                )
                            }
                        }
                    }
                    .gesture(
                        MagnificationGesture()
                            .onChanged { value in
                                scale = lastScale * value
                            }
                            .onEnded { _ in
                                lastScale = max(1.0, min(scale, 3.0))
                                scale = lastScale
                            }
                    )
                    .simultaneousGesture(
                        DragGesture()
                            .onChanged { value in
                                guard scale > 1.0 else { return }
                                offset = CGSize(
                                    width: lastOffset.width + value.translation.width,
                                    height: lastOffset.height + value.translation.height
                                )
                            }
                            .onEnded { _ in
                                lastOffset = offset
                            }
                    )
                }

                // Loading indicator
                if isDetecting {
                    VStack(spacing: 12) {
                        ProgressView()
                            .tint(Theme.Colors.accent)
                            .scaleEffect(1.2)
                        Text("Detecting math problems...")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    .padding(.bottom, 40)
                }
            }
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack {
            Button(action: onRetake) {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Retake")
                        .font(.system(size: 15, weight: .medium))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            }

            Spacer()

            if !isDetecting && !problems.isEmpty {
                Text("\(problems.count) found")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Theme.Colors.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
        }
    }

    // MARK: - Problem Highlight

    private func problemHighlight(
        problem: DetectedProblem,
        index: Int,
        containerSize: CGSize
    ) -> some View {
        let rect = problemRect(problem.bbox, containerSize: containerSize)

        return Button {
            onSelectProblem(problem)
        } label: {
            ZStack(alignment: .topLeading) {
                // Highlight region
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Theme.Colors.accent.opacity(0.12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(Theme.Colors.accent.opacity(0.6), lineWidth: 2)
                    )

                // Number badge
                Text("\(index)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 24, height: 24)
                    .background(Theme.Colors.accent)
                    .clipShape(Circle())
                    .offset(x: -8, y: -8)
            }
        }
        .frame(width: max(40, rect.width), height: max(24, rect.height))
        .position(
            x: rect.midX + offset.width,
            y: rect.midY + offset.height
        )
        .scaleEffect(scale)
    }

    // MARK: - Coordinate Mapping (aspect-fit aware)

    /// Maps percentage-based bounding box to actual screen coordinates,
    /// accounting for aspect-fit letterboxing.
    private func problemRect(
        _ bbox: DetectedProblem.BoundingBox,
        containerSize: CGSize
    ) -> CGRect {
        let imageAspect = image.size.width / image.size.height
        let containerAspect = containerSize.width / containerSize.height

        // Calculate the actual displayed rect of the image (accounting for aspect fit)
        let displayedRect: CGRect
        if imageAspect > containerAspect {
            // Image is wider — letterboxed top/bottom
            let displayedHeight = containerSize.width / imageAspect
            let yOffset = (containerSize.height - displayedHeight) / 2
            displayedRect = CGRect(x: 0, y: yOffset, width: containerSize.width, height: displayedHeight)
        } else {
            // Image is taller — letterboxed left/right
            let displayedWidth = containerSize.height * imageAspect
            let xOffset = (containerSize.width - displayedWidth) / 2
            displayedRect = CGRect(x: xOffset, y: 0, width: displayedWidth, height: containerSize.height)
        }

        // Map percentage coordinates to the displayed image rect
        let x = displayedRect.origin.x + (bbox.left / 100.0) * displayedRect.width
        let y = displayedRect.origin.y + (bbox.top / 100.0) * displayedRect.height
        let w = (bbox.width / 100.0) * displayedRect.width
        let h = (bbox.height / 100.0) * displayedRect.height

        return CGRect(x: x, y: y, width: w, height: h)
    }
}

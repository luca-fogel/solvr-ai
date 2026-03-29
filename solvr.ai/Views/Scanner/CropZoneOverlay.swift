import SwiftUI

struct CropZoneOverlay: View {
    @Binding var cropRect: CGRect
    let containerSize: CGSize

    private let minWidth: CGFloat = 60
    private let minHeight: CGFloat = 30
    private let handleHitArea: CGFloat = 44
    private let bracketLength: CGFloat = 22
    private let bracketWidth: CGFloat = 3
    private let edgeBarLength: CGFloat = 22
    private let edgeBarThickness: CGFloat = 3

    @State private var activeHandle: Handle? = nil
    @State private var dragStartRect: CGRect = .zero
    @State private var dragStartLocation: CGPoint = .zero
    @State private var showGrid = false

    var body: some View {
        ZStack {
            // Dark overlay with cutout
            overlayMask

            // Grid (only while dragging handles)
            if showGrid {
                gridLines
                    .transition(.opacity)
            }

            // Corner brackets
            cornerBracket(at: .topLeft)
            cornerBracket(at: .topRight)
            cornerBracket(at: .bottomLeft)
            cornerBracket(at: .bottomRight)

            // Edge handles
            edgeHandle(at: .top)
            edgeHandle(at: .bottom)
            edgeHandle(at: .left)
            edgeHandle(at: .right)

            // Pan gesture layer (inside crop box)
            Color.clear
                .frame(width: max(1, cropRect.width - handleHitArea),
                       height: max(1, cropRect.height - handleHitArea))
                .contentShape(Rectangle())
                .position(x: cropRect.midX, y: cropRect.midY)
                .gesture(panGesture)
        }
    }

    // MARK: - Overlay Mask

    private var overlayMask: some View {
        Canvas { context, size in
            context.fill(
                Path(CGRect(origin: .zero, size: size)),
                with: .color(.black.opacity(0.5))
            )
            context.blendMode = .destinationOut
            context.fill(Path(cropRect), with: .color(.white))
        }
        .allowsHitTesting(false)
    }

    // MARK: - Grid Lines (3×3 rule of thirds)

    private var gridLines: some View {
        Canvas { context, _ in
            let thirdW = cropRect.width / 3
            let thirdH = cropRect.height / 3

            for i in 1...2 {
                let x = cropRect.minX + thirdW * CGFloat(i)
                var vPath = Path()
                vPath.move(to: CGPoint(x: x, y: cropRect.minY))
                vPath.addLine(to: CGPoint(x: x, y: cropRect.maxY))
                context.stroke(vPath, with: .color(.white.opacity(0.3)), lineWidth: 1)

                let y = cropRect.minY + thirdH * CGFloat(i)
                var hPath = Path()
                hPath.move(to: CGPoint(x: cropRect.minX, y: y))
                hPath.addLine(to: CGPoint(x: cropRect.maxX, y: y))
                context.stroke(hPath, with: .color(.white.opacity(0.3)), lineWidth: 1)
            }
        }
        .allowsHitTesting(false)
    }

    // MARK: - Corner Brackets (L-shaped, iOS Photos style)

    private func cornerBracket(at corner: Handle) -> some View {
        let pos = cornerPosition(corner)

        return Canvas { context, size in
            let cx = size.width / 2
            let cy = size.height / 2
            var path = Path()

            switch corner {
            case .topLeft:
                path.move(to: CGPoint(x: cx, y: cy + bracketLength))
                path.addLine(to: CGPoint(x: cx, y: cy))
                path.addLine(to: CGPoint(x: cx + bracketLength, y: cy))
            case .topRight:
                path.move(to: CGPoint(x: cx - bracketLength, y: cy))
                path.addLine(to: CGPoint(x: cx, y: cy))
                path.addLine(to: CGPoint(x: cx, y: cy + bracketLength))
            case .bottomLeft:
                path.move(to: CGPoint(x: cx, y: cy - bracketLength))
                path.addLine(to: CGPoint(x: cx, y: cy))
                path.addLine(to: CGPoint(x: cx + bracketLength, y: cy))
            case .bottomRight:
                path.move(to: CGPoint(x: cx - bracketLength, y: cy))
                path.addLine(to: CGPoint(x: cx, y: cy))
                path.addLine(to: CGPoint(x: cx, y: cy - bracketLength))
            default:
                break
            }

            context.stroke(path, with: .color(.white),
                           style: StrokeStyle(lineWidth: bracketWidth, lineCap: .round, lineJoin: .round))
        }
        .frame(width: handleHitArea, height: handleHitArea)
        .contentShape(Rectangle())
        .position(pos)
        .gesture(handleDragGesture(for: corner))
    }

    // MARK: - Edge Handles (small white rectangles)

    private func edgeHandle(at edge: Handle) -> some View {
        let pos = edgePosition(edge)
        let isHorizontal = (edge == .top || edge == .bottom)

        return RoundedRectangle(cornerRadius: 1.5)
            .fill(.white)
            .frame(
                width: isHorizontal ? edgeBarLength : edgeBarThickness,
                height: isHorizontal ? edgeBarThickness : edgeBarLength
            )
            .frame(width: handleHitArea, height: handleHitArea)
            .contentShape(Rectangle())
            .position(pos)
            .gesture(handleDragGesture(for: edge))
    }

    // MARK: - Handle Drag Gesture

    private func handleDragGesture(for handle: Handle) -> some Gesture {
        DragGesture()
            .onChanged { value in
                if activeHandle == nil {
                    activeHandle = handle
                    dragStartRect = cropRect
                    dragStartLocation = value.startLocation
                    withAnimation(.easeOut(duration: 0.15)) { showGrid = true }
                }

                let dx = value.translation.width
                let dy = value.translation.height

                var newRect = dragStartRect

                switch handle {
                // Corners
                case .topLeft:
                    let newMinX = clamp(dragStartRect.minX + dx, min: 0, max: dragStartRect.maxX - minWidth)
                    let newMinY = clamp(dragStartRect.minY + dy, min: 0, max: dragStartRect.maxY - minHeight)
                    newRect = CGRect(x: newMinX, y: newMinY,
                                     width: dragStartRect.maxX - newMinX,
                                     height: dragStartRect.maxY - newMinY)

                case .topRight:
                    let newMaxX = clamp(dragStartRect.maxX + dx, min: dragStartRect.minX + minWidth, max: containerSize.width)
                    let newMinY = clamp(dragStartRect.minY + dy, min: 0, max: dragStartRect.maxY - minHeight)
                    newRect = CGRect(x: dragStartRect.minX, y: newMinY,
                                     width: newMaxX - dragStartRect.minX,
                                     height: dragStartRect.maxY - newMinY)

                case .bottomLeft:
                    let newMinX = clamp(dragStartRect.minX + dx, min: 0, max: dragStartRect.maxX - minWidth)
                    let newMaxY = clamp(dragStartRect.maxY + dy, min: dragStartRect.minY + minHeight, max: containerSize.height)
                    newRect = CGRect(x: newMinX, y: dragStartRect.minY,
                                     width: dragStartRect.maxX - newMinX,
                                     height: newMaxY - dragStartRect.minY)

                case .bottomRight:
                    let newMaxX = clamp(dragStartRect.maxX + dx, min: dragStartRect.minX + minWidth, max: containerSize.width)
                    let newMaxY = clamp(dragStartRect.maxY + dy, min: dragStartRect.minY + minHeight, max: containerSize.height)
                    newRect = CGRect(x: dragStartRect.minX, y: dragStartRect.minY,
                                     width: newMaxX - dragStartRect.minX,
                                     height: newMaxY - dragStartRect.minY)

                // Edges
                case .top:
                    let newMinY = clamp(dragStartRect.minY + dy, min: 0, max: dragStartRect.maxY - minHeight)
                    newRect = CGRect(x: dragStartRect.minX, y: newMinY,
                                     width: dragStartRect.width,
                                     height: dragStartRect.maxY - newMinY)

                case .bottom:
                    let newMaxY = clamp(dragStartRect.maxY + dy, min: dragStartRect.minY + minHeight, max: containerSize.height)
                    newRect = CGRect(x: dragStartRect.minX, y: dragStartRect.minY,
                                     width: dragStartRect.width,
                                     height: newMaxY - dragStartRect.minY)

                case .left:
                    let newMinX = clamp(dragStartRect.minX + dx, min: 0, max: dragStartRect.maxX - minWidth)
                    newRect = CGRect(x: newMinX, y: dragStartRect.minY,
                                     width: dragStartRect.maxX - newMinX,
                                     height: dragStartRect.height)

                case .right:
                    let newMaxX = clamp(dragStartRect.maxX + dx, min: dragStartRect.minX + minWidth, max: containerSize.width)
                    newRect = CGRect(x: dragStartRect.minX, y: dragStartRect.minY,
                                     width: newMaxX - dragStartRect.minX,
                                     height: dragStartRect.height)
                }

                cropRect = newRect
            }
            .onEnded { _ in
                activeHandle = nil
                dragStartRect = .zero
                withAnimation(.easeOut(duration: 0.3)) { showGrid = false }
            }
    }

    // MARK: - Pan Gesture (move entire box)

    private var panGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                if activeHandle == nil && dragStartRect == .zero {
                    dragStartRect = cropRect
                }

                let newX = clamp(dragStartRect.origin.x + value.translation.width,
                                 min: 0, max: containerSize.width - cropRect.width)
                let newY = clamp(dragStartRect.origin.y + value.translation.height,
                                 min: 0, max: containerSize.height - cropRect.height)

                cropRect.origin = CGPoint(x: newX, y: newY)
            }
            .onEnded { _ in
                dragStartRect = .zero
            }
    }

    // MARK: - Positions

    private func cornerPosition(_ corner: Handle) -> CGPoint {
        switch corner {
        case .topLeft: return CGPoint(x: cropRect.minX, y: cropRect.minY)
        case .topRight: return CGPoint(x: cropRect.maxX, y: cropRect.minY)
        case .bottomLeft: return CGPoint(x: cropRect.minX, y: cropRect.maxY)
        case .bottomRight: return CGPoint(x: cropRect.maxX, y: cropRect.maxY)
        default: return .zero
        }
    }

    private func edgePosition(_ edge: Handle) -> CGPoint {
        switch edge {
        case .top: return CGPoint(x: cropRect.midX, y: cropRect.minY)
        case .bottom: return CGPoint(x: cropRect.midX, y: cropRect.maxY)
        case .left: return CGPoint(x: cropRect.minX, y: cropRect.midY)
        case .right: return CGPoint(x: cropRect.maxX, y: cropRect.midY)
        default: return .zero
        }
    }

    // MARK: - Helpers

    private func clamp(_ value: CGFloat, min minVal: CGFloat, max maxVal: CGFloat) -> CGFloat {
        Swift.min(Swift.max(value, minVal), maxVal)
    }

    // MARK: - Handle Enum

    enum Handle {
        case topLeft, topRight, bottomLeft, bottomRight
        case top, bottom, left, right
    }
}

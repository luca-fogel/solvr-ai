import SwiftUI
import PhotosUI

struct CameraScannerView: View {
    let onSolve: (UIImage) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var cameraManager = CameraManager()

    // Flow states
    @State private var capturedImage: UIImage?
    @State private var selectedPhotoItem: PhotosPickerItem?

    // Crop state
    @State private var cropRect: CGRect = .zero
    @State private var imageDisplaySize: CGSize = .zero
    @State private var imageDisplayOrigin: CGPoint = .zero
    @State private var cropInitialized = false

    private enum Screen { case camera, crop }

    private var currentScreen: Screen {
        capturedImage != nil ? .crop : .camera
    }

    var body: some View {
        ZStack {
            switch currentScreen {
            case .camera:
                cameraScreen
                    .transition(.opacity)
            case .crop:
                if let image = capturedImage {
                    cropScreen(image)
                        .transition(.opacity)
                }
            }
        }
        .animation(.easeInOut(duration: 0.25), value: currentScreen == .crop)
        .statusBarHidden(true)
    }

    // MARK: - Camera Screen

    private var cameraScreen: some View {
        ZStack {
            CameraPreviewView(session: cameraManager.session)
                .ignoresSafeArea()

            // Vignette
            RadialGradient(
                gradient: Gradient(colors: [.clear, .black.opacity(0.4)]),
                center: .center,
                startRadius: 150,
                endRadius: 400
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)

            // Bottom bar
            VStack {
                Spacer()

                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                    }

                    Spacer()

                    // Capture button
                    Button { capture() } label: {
                        ZStack {
                            Circle()
                                .stroke(.white, lineWidth: 3)
                                .frame(width: 70, height: 70)
                            Circle()
                                .fill(.white)
                                .frame(width: 54, height: 54)
                        }
                    }
                    .pressAnimation()

                    Spacer()

                    PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                        Image(systemName: "photo.on.rectangle")
                            .font(.system(size: 20))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                    }
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 16)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }

            // Flash toggle
            VStack {
                HStack {
                    Spacer()
                    Button {
                        cameraManager.toggleTorch()
                        Haptics.light()
                    } label: {
                        Image(systemName: cameraManager.torchOn ? "bolt.fill" : "bolt.slash.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(cameraManager.torchOn ? .yellow : .white.opacity(0.7))
                            .frame(width: 36, height: 36)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                Spacer()
            }
        }
        .onChange(of: selectedPhotoItem) { _, newItem in
            guard let newItem else { return }
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    await MainActor.run {
                        cameraManager.stop()
                        capturedImage = image
                        cropInitialized = false
                        selectedPhotoItem = nil
                    }
                }
            }
        }
        .onAppear {
            cameraManager.checkPermission()
            cameraManager.configure()
            cameraManager.start()
        }
        .onDisappear {
            cameraManager.stop()
        }
    }

    // MARK: - Crop Screen (frozen photo, edge-to-edge, with crop overlay)

    private func cropScreen(_ image: UIImage) -> some View {
        ZStack {
            Color.black.ignoresSafeArea()

            GeometryReader { geo in
                let fitRect = aspectFillRect(imageSize: image.size, containerSize: geo.size)

                ZStack {
                    // Full-screen image
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()

                    // Crop overlay (constrained to where the image actually is)
                    CropZoneOverlay(cropRect: $cropRect, containerSize: geo.size)
                }
                .onAppear {
                    if !cropInitialized {
                        // Default crop: 80% width, 25% height, centered at 50% vertical
                        let w = geo.size.width * 0.8
                        let h = geo.size.height * 0.25
                        let x = (geo.size.width - w) / 2
                        let y = (geo.size.height - h) / 2
                        cropRect = CGRect(x: x, y: y, width: w, height: h)
                        imageDisplaySize = fitRect.size
                        imageDisplayOrigin = fitRect.origin
                        cropInitialized = true
                    }
                }
            }
            .ignoresSafeArea()

            // Bottom bar
            VStack {
                Spacer()

                HStack {
                    Button {
                        retake()
                    } label: {
                        Text("Retake")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(.white)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Spacer()

                    Button {
                        solveWithCrop(image)
                    } label: {
                        HStack(spacing: 6) {
                            Text("Solve this problem")
                                .font(.system(size: 16, weight: .bold))
                            Image(systemName: "arrow.right")
                                .font(.system(size: 14, weight: .bold))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(Theme.Colors.accent)
                        .clipShape(Capsule())
                    }
                    .pressAnimation()
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 14)
                .background(.ultraThinMaterial)
            }
        }
    }

    // MARK: - Actions

    private func capture() {
        guard let frame = cameraManager.captureCurrentFrame() else { return }
        Haptics.medium()
        cameraManager.stop()
        capturedImage = frame
        cropInitialized = false
    }

    private func solveWithCrop(_ fullImage: UIImage) {
        Haptics.medium()

        // Crop the image to the crop rect, accounting for image scale
        let cropped = cropImage(fullImage)

        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            onSolve(cropped)
        }
    }

    private func retake() {
        capturedImage = nil
        cropInitialized = false
        cameraManager.start()
    }

    // MARK: - Image Cropping

    private func cropImage(_ image: UIImage) -> UIImage {
        // The image is displayed with aspectFill in the container
        // We need to figure out the mapping from screen coordinates to image coordinates
        guard let cgImage = image.cgImage else { return image }

        let imageW = CGFloat(cgImage.width)
        let imageH = CGFloat(cgImage.height)

        // Get the screen size from the crop rect's container

        // Recalculate using the actual container (we stored nothing, so compute from image aspect)
        // For aspectFill, one dimension fills exactly, the other overflows
        let containerW = Platform.activeScreenBounds.width
        let containerH = Platform.activeScreenBounds.height

        let imageAspect = imageW / imageH
        let containerAspect = containerW / containerH

        let displayW: CGFloat
        let displayH: CGFloat
        let offsetX: CGFloat
        let offsetY: CGFloat

        if imageAspect > containerAspect {
            // Image is wider — height fills, width overflows
            displayH = containerH
            displayW = containerH * imageAspect
            offsetX = (displayW - containerW) / 2
            offsetY = 0
        } else {
            // Image is taller — width fills, height overflows
            displayW = containerW
            displayH = containerW / imageAspect
            offsetX = 0
            offsetY = (displayH - containerH) / 2
        }

        let scaleX = imageW / displayW
        let scaleY = imageH / displayH

        let imgCropX = (cropRect.minX + offsetX) * scaleX
        let imgCropY = (cropRect.minY + offsetY) * scaleY
        let imgCropW = cropRect.width * scaleX
        let imgCropH = cropRect.height * scaleY

        let clampedRect = CGRect(
            x: max(0, imgCropX),
            y: max(0, imgCropY),
            width: min(imageW - max(0, imgCropX), imgCropW),
            height: min(imageH - max(0, imgCropY), imgCropH)
        )

        guard let cropped = cgImage.cropping(to: clampedRect) else { return image }
        return UIImage(cgImage: cropped, scale: image.scale, orientation: image.imageOrientation)
    }

    // MARK: - Helpers

    private func aspectFillRect(imageSize: CGSize, containerSize: CGSize) -> CGRect {
        let imageAspect = imageSize.width / imageSize.height
        let containerAspect = containerSize.width / containerSize.height
        if imageAspect > containerAspect {
            let h = containerSize.height
            let w = h * imageAspect
            return CGRect(x: -(w - containerSize.width) / 2, y: 0, width: w, height: h)
        } else {
            let w = containerSize.width
            let h = w / imageAspect
            return CGRect(x: 0, y: -(h - containerSize.height) / 2, width: w, height: h)
        }
    }
}

import SwiftUI
import PhotosUI

struct CaptureView: View {
    let cameraManager: CameraManager
    let onCapture: () -> Void
    let onPhotoSelected: (UIImage) -> Void
    let onDismiss: () -> Void

    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var showFlashHint = false

    var body: some View {
        ZStack {
            // Camera feed
            CameraPreviewView(session: cameraManager.session)
                .ignoresSafeArea()

            // Top controls
            VStack {
                HStack {
                    // Close button
                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                    }

                    Spacer()

                    // Flash toggle
                    Button {
                        cameraManager.toggleTorch()
                        Haptics.light()
                    } label: {
                        Image(systemName: cameraManager.torchOn ? "bolt.fill" : "bolt.slash.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(cameraManager.torchOn ? .yellow : .white)
                            .frame(width: 44, height: 44)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)

                Spacer()

                // Instruction text
                Text("Take a photo of your homework")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .padding(.bottom, 24)

                // Bottom controls
                HStack(spacing: 48) {
                    // Photo library
                    PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                        Image(systemName: "photo.on.rectangle")
                            .font(.system(size: 22))
                            .foregroundStyle(.white)
                            .frame(width: 50, height: 50)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                    }

                    // Capture button
                    Button(action: onCapture) {
                        ZStack {
                            Circle()
                                .stroke(Theme.Colors.accent, lineWidth: 4)
                                .frame(width: 72, height: 72)
                            Circle()
                                .fill(.white)
                                .frame(width: 60, height: 60)
                        }
                    }
                    .pressAnimation()

                    // Spacer to balance
                    Color.clear
                        .frame(width: 50, height: 50)
                }
                .padding(.bottom, 40)
            }
        }
        .onChange(of: selectedPhotoItem) { _, newItem in
            guard let newItem else { return }
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    await MainActor.run {
                        onPhotoSelected(image)
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
}

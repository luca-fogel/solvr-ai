import SwiftUI
import PhotosUI
import SwiftData
import UniformTypeIdentifiers

struct HomeView: View {
    @Bindable var viewModel: HomeViewModel
    let onSolve: (String) -> Void
    var onSolveFromImage: ((UIImage) -> Void)?
    var onLoadFromHistory: ((Problem) -> Void)?
    let onHistory: () -> Void
    let onSettings: () -> Void

    @Query(sort: \Problem.createdAt, order: .reverse) private var recentProblems: [Problem]

    // Camera (iPhone only)
    @State private var cameraManager = CameraManager()
    @State private var capturedImage: UIImage?
    @State private var selectedPhotoItem: PhotosPickerItem?

    // Crop
    @State private var cropRect: CGRect = .zero
    @State private var cropInitialized = false

    // Text input
    @State private var showTextInput = false
    @State private var textProblem = ""

    // Animation
    @State private var pulseScale: CGFloat = 1.0
    @State private var pulseOpacity: CGFloat = 0.3

    // Mac-specific state
    @State private var isDragTargeted = false
    @State private var showFilePicker = false
    @State private var macProblemText = ""

    private var isCropMode: Bool { capturedImage != nil }

    var body: some View {
        if Platform.isMac {
            macHomeView
        } else {
            iphoneHomeView
        }
    }

    // MARK: - iPhone Home View

    private var iphoneHomeView: some View {
        ZStack {
            if let image = capturedImage {
                cropScreen(image)
            } else {
                cameraScreen
            }
        }
        .animation(.easeInOut(duration: 0.25), value: isCropMode)
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
        .sheet(isPresented: $showTextInput) {
            textInputSheet
        }
        .onAppear {
            if capturedImage == nil {
                cameraManager.checkPermission()
                cameraManager.configure()
                cameraManager.start()
            }
        }
        .onDisappear {
            cameraManager.stop()
        }
        .alert("Error", isPresented: .init(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    // MARK: - Mac Home View

    private var macHomeView: some View {
        NavigationSplitView {
            macHistorySidebar
        } detail: {
            macMainArea
        }
        .navigationSplitViewStyle(.balanced)
        .alert("Error", isPresented: .init(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    private var macHistorySidebar: some View {
        List {
            Section("Recent Problems") {
                ForEach(recentProblems) { problem in
                    Button {
                        Haptics.light()
                        onLoadFromHistory?(problem)
                    } label: {
                        HStack(spacing: 12) {
                            if let imageData = problem.sourceImageData,
                               let uiImage = UIImage(data: imageData) {
                                Image(uiImage: uiImage)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: 40, height: 40)
                                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            } else {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Theme.Colors.accentSubtle)
                                    .frame(width: 40, height: 40)
                                    .overlay(
                                        Image(systemName: "function")
                                            .font(.system(size: 16))
                                            .foregroundStyle(Theme.Colors.accent.opacity(0.5))
                                    )
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text(problem.text)
                                    .font(Theme.Fonts.body)
                                    .foregroundStyle(Theme.Colors.textPrimary)
                                    .lineLimit(2)
                                Text(problem.createdAt, style: .relative)
                                    .font(Theme.Fonts.caption)
                                    .foregroundStyle(Theme.Colors.textTertiary)
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("History")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button(action: onSettings) {
                    Image(systemName: "gearshape")
                }
                .help("Settings")
            }
        }
    }

    private var macMainArea: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("solvr.")
                    .font(.system(size: 36, weight: .bold))
                    .foregroundStyle(Theme.Colors.accent)
                Spacer()
            }
            .padding(.horizontal, 32)
            .padding(.top, 24)
            .padding(.bottom, 8)

            Spacer()

            // Drop zone
            macDropZone
                .padding(.horizontal, 40)

            // Divider text
            Text("or")
                .font(Theme.Fonts.callout)
                .foregroundStyle(Theme.Colors.textTertiary)
                .padding(.vertical, 16)

            // Text input
            macTextInput
                .padding(.horizontal, 40)

            // Paste hint
            Text("\u{2318}V to paste a screenshot")
                .font(Theme.Fonts.caption)
                .foregroundStyle(Theme.Colors.textTertiary)
                .padding(.top, 12)

            Spacer()
        }
        .background(Theme.Colors.background)
        .fileImporter(isPresented: $showFilePicker, allowedContentTypes: [.image, .png, .jpeg]) { result in
            switch result {
            case .success(let url):
                if url.startAccessingSecurityScopedResource() {
                    defer { url.stopAccessingSecurityScopedResource() }
                    if let data = try? Data(contentsOf: url),
                       let image = UIImage(data: data) {
                        onSolveFromImage?(image)
                    }
                }
            case .failure:
                break
            }
        }
    }

    // MARK: - Mac Drop Zone

    private var macDropZone: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(
                    isDragTargeted ? Theme.Colors.accent : Theme.Colors.separator,
                    style: StrokeStyle(lineWidth: 2, dash: isDragTargeted ? [] : [8, 6])
                )
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(isDragTargeted ? Theme.Colors.accentSubtle : Theme.Colors.secondaryBackground)
                )
                .frame(maxWidth: 500, maxHeight: 280)

            VStack(spacing: 16) {
                Image(systemName: isDragTargeted ? "arrow.down.doc.fill" : "photo.on.rectangle.angled")
                    .font(.system(size: 44))
                    .foregroundStyle(isDragTargeted ? Theme.Colors.accent : Theme.Colors.textTertiary)
                    .contentTransition(.symbolEffect(.replace))

                Text(isDragTargeted ? "Drop to solve" : "Drop a screenshot here")
                    .font(Theme.Fonts.title3)
                    .foregroundStyle(Theme.Colors.textPrimary)

                Text("PNG, JPEG, or paste from clipboard")
                    .font(Theme.Fonts.callout)
                    .foregroundStyle(Theme.Colors.textTertiary)

                HStack(spacing: 16) {
                    Button {
                        showFilePicker = true
                    } label: {
                        Text("Browse Files...")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Theme.Colors.accent)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 8)
                            .overlay(
                                Capsule().stroke(Theme.Colors.accent, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)

                    Button {
                        if let image = UIPasteboard.general.image {
                            onSolveFromImage?(image)
                        }
                    } label: {
                        Label("Paste from Clipboard", systemImage: "doc.on.clipboard")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Theme.Colors.accent)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 8)
                            .overlay(
                                Capsule().stroke(Theme.Colors.accent.opacity(0.5), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: 500, maxHeight: 280)
        .onDrop(of: [.image, .fileURL], isTargeted: $isDragTargeted) { providers in
            handleDrop(providers)
        }
    }

    @discardableResult
    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            if provider.canLoadObject(ofClass: UIImage.self) {
                provider.loadObject(ofClass: UIImage.self) { object, _ in
                    if let image = object as? UIImage {
                        DispatchQueue.main.async {
                            self.onSolveFromImage?(image)
                        }
                    }
                }
                return true
            }

            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                    if let data = item as? Data,
                       let url = URL(dataRepresentation: data, relativeTo: nil),
                       let imageData = try? Data(contentsOf: url),
                       let image = UIImage(data: imageData) {
                        DispatchQueue.main.async {
                            self.onSolveFromImage?(image)
                        }
                    }
                }
                return true
            }

            if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                    if let data, let image = UIImage(data: data) {
                        DispatchQueue.main.async {
                            self.onSolveFromImage?(image)
                        }
                    }
                }
                return true
            }
        }
        return false
    }

    // MARK: - Mac Text Input

    private var macTextInput: some View {
        HStack(spacing: 12) {
            TextField("Type a math problem...", text: $macProblemText, axis: .vertical)
                .font(Theme.Fonts.body)
                .textFieldStyle(.plain)
                .lineLimit(1...4)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Theme.Colors.secondaryBackground)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Theme.Colors.separator, lineWidth: 1)
                )
                .onSubmit {
                    submitMacText()
                }

            Button {
                submitMacText()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(
                        macProblemText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? Theme.Colors.textTertiary
                        : Theme.Colors.accent
                    )
            }
            .buttonStyle(.plain)
            .disabled(macProblemText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .frame(maxWidth: 500)
    }

    private func submitMacText() {
        let text = macProblemText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        onSolve(text)
        macProblemText = ""
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

            // Top/bottom gradients for text readability
            VStack(spacing: 0) {
                LinearGradient(colors: [.black.opacity(0.5), .clear],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: 110)
                Spacer()
                LinearGradient(colors: [.clear, .black.opacity(0.55)],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: recentProblems.isEmpty ? 160 : 240)
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)

            // Permission denied
            if cameraManager.permissionDenied {
                permissionDeniedOverlay
            }

            // Overlay UI
            VStack(spacing: 0) {
                cameraHeader
                    .padding(.horizontal, Theme.Spacing.lg)
                    .padding(.top, Theme.Spacing.sm)

                Spacer()

                captureButton
                    .padding(.bottom, 14)

                Button { showTextInput = true } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "keyboard")
                            .font(.system(size: 12))
                        Text("type a problem")
                            .font(.system(size: 14, weight: .medium))
                    }
                    .foregroundStyle(.white.opacity(0.7))
                }
                .padding(.bottom, recentProblems.isEmpty ? 40 : 20)

                if !recentProblems.isEmpty {
                    recentSection
                        .padding(.bottom, Theme.Spacing.sm)
                }
            }
        }
    }

    // MARK: - Crop Screen

    private func cropScreen(_ image: UIImage) -> some View {
        ZStack {
            Color.black.ignoresSafeArea()

            GeometryReader { geo in
                ZStack {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()

                    CropZoneOverlay(cropRect: $cropRect, containerSize: geo.size)
                }
                .onAppear {
                    if !cropInitialized {
                        let w = geo.size.width * 0.8
                        let h = geo.size.height * 0.25
                        let x = (geo.size.width - w) / 2
                        let y = (geo.size.height - h) / 2
                        cropRect = CGRect(x: x, y: y, width: w, height: h)
                        cropInitialized = true
                    }
                }
            }
            .ignoresSafeArea()

            // Bottom bar
            VStack {
                Spacer()

                HStack {
                    Button { retake() } label: {
                        Text("Retake")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(.white)
                    }

                    Spacer()

                    Button { solveWithCrop(image) } label: {
                        HStack(spacing: 6) {
                            Text("Solve")
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
        .statusBarHidden(true)
    }

    // MARK: - Camera Header

    private var cameraHeader: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("solvr.")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(.white)

                Text("point. snap. learn.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
            }

            Spacer()

            HStack(spacing: 10) {
                Button {
                    cameraManager.toggleTorch()
                    Haptics.light()
                } label: {
                    Image(systemName: cameraManager.torchOn ? "bolt.fill" : "bolt.slash.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(cameraManager.torchOn ? .yellow : .white.opacity(0.85))
                        .frame(width: 34, height: 34)
                        .background(.ultraThinMaterial)
                        .clipShape(Circle())
                }

                PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                    Image(systemName: "photo.on.rectangle")
                        .font(.system(size: 15))
                        .foregroundStyle(.white.opacity(0.85))
                        .frame(width: 34, height: 34)
                        .background(.ultraThinMaterial)
                        .clipShape(Circle())
                }

                Button(action: onHistory) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 15))
                        .foregroundStyle(.white.opacity(0.85))
                        .frame(width: 34, height: 34)
                        .background(.ultraThinMaterial)
                        .clipShape(Circle())
                }

                Button(action: onSettings) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 15))
                        .foregroundStyle(.white.opacity(0.85))
                        .frame(width: 34, height: 34)
                        .background(.ultraThinMaterial)
                        .clipShape(Circle())
                }
            }
        }
    }

    // MARK: - Capture Button

    private var captureButton: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(pulseOpacity), lineWidth: 2)
                .frame(width: 82, height: 82)
                .scaleEffect(pulseScale)
                .onAppear {
                    withAnimation(
                        .easeOut(duration: 2.0)
                        .repeatForever(autoreverses: false)
                    ) {
                        pulseScale = 1.5
                        pulseOpacity = 0
                    }
                }

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
        }
    }

    // MARK: - Text Input Sheet

    private var textInputSheet: some View {
        NavigationStack {
            VStack(spacing: Theme.Spacing.lg) {
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    Text("Enter your math problem")
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)

                    TextEditor(text: $textProblem)
                        .font(.system(size: 16))
                        .frame(minHeight: 100, maxHeight: 200)
                        .padding(12)
                        .background(Theme.Colors.secondaryBackground)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radii.md, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.Radii.md, style: .continuous)
                                .stroke(Theme.Colors.separator, lineWidth: 0.5)
                        )
                }
                .padding(.horizontal, Theme.Spacing.lg)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Theme.Spacing.sm) {
                        ForEach(viewModel.topics, id: \.self) { topic in
                            Button {
                                viewModel.selectTopic(topic)
                                textProblem = viewModel.problemText
                            } label: {
                                Text(topic)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(Theme.Colors.accent)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 8)
                                    .background(Theme.Colors.accentSubtle)
                                    .clipShape(Capsule())
                            }
                        }
                    }
                    .padding(.horizontal, Theme.Spacing.lg)
                }

                Button {
                    let problem = textProblem.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !problem.isEmpty else { return }
                    showTextInput = false
                    textProblem = ""
                    onSolve(problem)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                        Text("Solve")
                            .font(.system(size: 16, weight: .bold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        textProblem.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            ? Theme.Colors.accent.opacity(0.4)
                            : Theme.Colors.accent
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .disabled(textProblem.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .padding(.horizontal, Theme.Spacing.lg)

                Spacer()
            }
            .padding(.top, Theme.Spacing.lg)
            .navigationTitle("Type a Problem")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { showTextInput = false }
                        .foregroundStyle(Theme.Colors.accent)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Recent Section

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Recent")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                Spacer()
                Button(action: onHistory) {
                    Text("See all")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
            .padding(.horizontal, Theme.Spacing.lg)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(recentProblems.prefix(6)) { problem in
                        recentChip(problem)
                    }
                }
                .padding(.horizontal, Theme.Spacing.lg)
            }
        }
    }

    private func recentChip(_ problem: Problem) -> some View {
        Button {
            Haptics.light()
            if let onLoadFromHistory {
                onLoadFromHistory(problem)
            } else {
                onSolve(problem.text)
            }
        } label: {
            HStack(spacing: 8) {
                if let imageData = problem.sourceImageData,
                   let uiImage = UIImage(data: imageData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 32, height: 32)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                } else {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(.white.opacity(0.15))
                        .frame(width: 32, height: 32)
                        .overlay(
                            Image(systemName: "function")
                                .font(.system(size: 14))
                                .foregroundStyle(.white.opacity(0.5))
                        )
                }

                Text(problem.text)
                    .font(.system(size: 13))
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial)
            .clipShape(Capsule())
        }
    }

    // MARK: - Permission Denied

    private var permissionDeniedOverlay: some View {
        VStack(spacing: 16) {
            Image(systemName: "camera.fill")
                .font(.system(size: 36))
                .foregroundStyle(.white.opacity(0.5))

            Text("Camera Access Required")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)

            Text("Allow camera access in Settings to scan problems")
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)

            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            } label: {
                Text("Open Settings")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(Theme.Colors.accent)
                    .clipShape(Capsule())
            }
        }
        .padding(40)
    }

    // MARK: - Actions

    private func capture() {
        guard let frame = cameraManager.captureCurrentFrame() else { return }
        Haptics.medium()
        cameraManager.stop()
        capturedImage = frame
        cropInitialized = false
    }

    private func retake() {
        capturedImage = nil
        cropInitialized = false
        cameraManager.start()
    }

    private func solveWithCrop(_ fullImage: UIImage) {
        Haptics.medium()
        let cropped = cropImage(fullImage)
        capturedImage = nil
        cropInitialized = false
        onSolveFromImage?(cropped)
    }

    // MARK: - Image Cropping

    private func cropImage(_ image: UIImage) -> UIImage {
        guard let cgImage = image.cgImage else { return image }

        let imageW = CGFloat(cgImage.width)
        let imageH = CGFloat(cgImage.height)
        let containerW = UIScreen.main.bounds.width
        let containerH = UIScreen.main.bounds.height

        let imageAspect = imageW / imageH
        let containerAspect = containerW / containerH

        let displayW: CGFloat
        let displayH: CGFloat
        let offsetX: CGFloat
        let offsetY: CGFloat

        if imageAspect > containerAspect {
            displayH = containerH
            displayW = containerH * imageAspect
            offsetX = (displayW - containerW) / 2
            offsetY = 0
        } else {
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
}

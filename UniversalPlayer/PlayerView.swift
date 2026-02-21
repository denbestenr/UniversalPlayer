import SwiftUI
@preconcurrency import MobileVLCKit

struct PlayerView: View {
    @ObservedObject var viewModel: PlayerViewModel
    @State private var showControls = true
    @State private var hideControlsTask: Task<Void, Never>?

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // VLC Video view
                VLCVideoView(viewModel: viewModel)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        toggleControls()
                    }

                // Controls overlay
                if showControls {
                    controlsOverlay
                        .transition(.opacity)
                }

                // Loading indicator
                if case .loading = viewModel.playbackState {
                    ProgressView()
                        .scaleEffect(2)
                        .tint(.white)
                }

                // Error message
                if case .error(let message) = viewModel.playbackState {
                    errorView(message: message)
                }
            }
        }
        .ignoresSafeArea()
        .onAppear {
            scheduleHideControls()
        }
    }

    // MARK: - Controls Overlay

    private var controlsOverlay: some View {
        VStack {
            // Top bar met bestandsnaam
            HStack {
                if let url = viewModel.currentMediaURL {
                    Text(url.lastPathComponent)
                        .font(.headline)
                        .foregroundColor(.white)
                        .lineLimit(1)
                }
                Spacer()
            }
            .padding()
            .background(
                LinearGradient(
                    colors: [.black.opacity(0.7), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )

            Spacer()

            // Center play button
            Button(action: {
                viewModel.togglePlayPause()
                scheduleHideControls()
            }) {
                Image(systemName: viewModel.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 80))
                    .foregroundColor(.white)
                    .shadow(radius: 10)
            }

            Spacer()

            // Bottom controls
            VStack(spacing: 12) {
                // Seek slider
                SeekSlider(
                    value: Binding(
                        get: { viewModel.progress },
                        set: { viewModel.seek(to: $0) }
                    )
                )

                // Time labels
                HStack {
                    Text(viewModel.currentTimeFormatted)
                        .font(.caption)
                        .foregroundColor(.white)

                    Spacer()

                    Text(viewModel.durationFormatted)
                        .font(.caption)
                        .foregroundColor(.white)
                }
            }
            .padding()
            .background(
                LinearGradient(
                    colors: [.clear, .black.opacity(0.7)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
    }

    // MARK: - Error View

    private func errorView(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 50))
                .foregroundColor(.red)

            Text("Afspelen mislukt")
                .font(.headline)
                .foregroundColor(.white)

            Text(message)
                .font(.caption)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
        }
        .padding()
    }

    // MARK: - Helper Methods

    private func toggleControls() {
        withAnimation(.easeInOut(duration: 0.2)) {
            showControls.toggle()
        }
        if showControls {
            scheduleHideControls()
        }
    }

    private func scheduleHideControls() {
        hideControlsTask?.cancel()
        hideControlsTask = Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if !Task.isCancelled {
                await MainActor.run {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showControls = false
                    }
                }
            }
        }
    }
}

// MARK: - VLC Video View

struct VLCVideoView: UIViewRepresentable {
    @ObservedObject var viewModel: PlayerViewModel

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .black
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        viewModel.setDrawable(uiView)
    }
}

// MARK: - Seek Slider

struct SeekSlider: View {
    @Binding var value: Double
    @State private var isDragging = false
    @State private var dragValue: Double = 0

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Track background
                Rectangle()
                    .fill(Color.white.opacity(0.3))
                    .frame(height: 4)
                    .cornerRadius(2)

                // Progress
                Rectangle()
                    .fill(Color.white)
                    .frame(width: max(0, geometry.size.width * (isDragging ? dragValue : value)), height: 4)
                    .cornerRadius(2)

                // Thumb
                Circle()
                    .fill(Color.white)
                    .frame(width: 16, height: 16)
                    .offset(x: max(0, geometry.size.width * (isDragging ? dragValue : value) - 8))
                    .shadow(radius: 2)
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        isDragging = true
                        dragValue = max(0, min(1, gesture.location.x / geometry.size.width))
                    }
                    .onEnded { _ in
                        value = dragValue
                        isDragging = false
                    }
            )
        }
        .frame(height: 20)
    }
}

// MARK: - Fullscreen Player View

struct FullscreenPlayerView: View {
    @ObservedObject var viewModel: PlayerViewModel
    @ObservedObject var youtubeService = YouTubeService.shared
    @ObservedObject var uploadManager = BackgroundUploadManager.shared
    let onClose: () -> Void

    @State private var showControls = true
    @State private var hideControlsTask: Task<Void, Never>?
    @State private var showUploadDialog = false
    @State private var uploadTitle = ""

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Zwarte achtergrond
                Color.black
                    .ignoresSafeArea()

                // VLC Video view
                VLCVideoView(viewModel: viewModel)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .ignoresSafeArea()

                // Tap area voor controls toggle
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        toggleControls()
                    }

                // Controls overlay
                if showControls {
                    controlsOverlay
                        .transition(.opacity)
                }

                // Loading indicator
                if case .loading = viewModel.playbackState {
                    ProgressView()
                        .scaleEffect(3)
                        .tint(.white)
                }

                // Error message
                if case .error(let message) = viewModel.playbackState {
                    errorView(message: message)
                }
            }
        }
        .ignoresSafeArea()
        .statusBarHidden(true)
        .onAppear {
            scheduleHideControls()
        }
        .alert("Zet op YouTube", isPresented: $showUploadDialog) {
            TextField("Titel", text: $uploadTitle)
            Button("Uploaden") {
                startBackgroundUpload()
            }
            Button("Annuleren", role: .cancel) {}
        } message: {
            Text("Geef de video een naam:")
        }
    }

    private func startBackgroundUpload() {
        guard let url = viewModel.currentMediaURL else { return }
        // Altijd uploaden als "unlisted" (verborgen)
        uploadManager.startUpload(url: url, title: uploadTitle, privacy: "unlisted")
        // Sluit de video view en ga terug naar hoofdscherm
        onClose()
    }

    private var controlsOverlay: some View {
        ZStack {
            // Donkere overlay voor betere zichtbaarheid
            Color.black.opacity(0.4)
                .ignoresSafeArea()

            VStack {
                // Top bar met sluiten knop
                HStack {
                    // Bestandsnaam
                    if let url = viewModel.currentMediaURL {
                        Text(url.lastPathComponent)
                            .font(.title3)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .lineLimit(1)
                            .padding(.leading, 20)
                    }

                    Spacer()

                    // Grote sluit knop
                    Button(action: onClose) {
                        ZStack {
                            Circle()
                                .fill(Color.red)
                                .frame(width: 70, height: 70)
                            Image(systemName: "xmark")
                                .font(.system(size: 30, weight: .bold))
                                .foregroundColor(.white)
                        }
                        .shadow(radius: 8)
                    }
                    .padding(20)
                }

                Spacer()

                // Grote play/pause knop in het midden
                Button(action: {
                    viewModel.togglePlayPause()
                    scheduleHideControls()
                }) {
                    ZStack {
                        Circle()
                            .fill(Color.white.opacity(0.9))
                            .frame(width: 120, height: 120)
                        Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 50, weight: .bold))
                            .foregroundColor(.black)
                            .offset(x: viewModel.isPlaying ? 0 : 5) // Visuele correctie voor play icon
                    }
                    .shadow(radius: 10)
                }

                Spacer()

                // Bottom bar met tijdlijn en upload
                VStack(spacing: 16) {
                    // Seek slider
                    SeekSlider(
                        value: Binding(
                            get: { viewModel.progress },
                            set: { viewModel.seek(to: $0) }
                        )
                    )
                    .frame(height: 30)

                    // Time labels en upload knop
                    HStack {
                        Text(viewModel.currentTimeFormatted)
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.white)

                        Spacer()

                        // Grote "Zet op YouTube" knop
                        Button(action: {
                            if let url = viewModel.currentMediaURL {
                                uploadTitle = url.deletingPathExtension().lastPathComponent
                            }
                            showUploadDialog = true
                        }) {
                            HStack(spacing: 12) {
                                Image(systemName: "play.rectangle.fill")
                                    .font(.system(size: 28))
                                Text("Zet op YouTube")
                                    .font(.system(size: 24, weight: .bold))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 30)
                            .padding(.vertical, 18)
                            .background(Color.blue)
                            .cornerRadius(35)
                            .shadow(radius: 5)
                        }
                        .disabled(uploadManager.isUploading || !youtubeService.isAuthenticated)

                        // YouTube link button (shows after successful upload)
                        if let videoId = uploadManager.uploadedVideoId {
                            Button(action: {
                                if let url = URL(string: "https://youtube.com/watch?v=\(videoId)") {
                                    UIApplication.shared.open(url)
                                }
                            }) {
                                HStack(spacing: 12) {
                                    Image(systemName: "arrow.up.right.square")
                                        .font(.system(size: 28))
                                    Text("Bekijk")
                                        .font(.system(size: 24, weight: .bold))
                                }
                                .foregroundColor(.white)
                                .padding(.horizontal, 30)
                                .padding(.vertical, 18)
                                .background(Color.red)
                                .cornerRadius(35)
                                .shadow(radius: 5)
                            }
                        }

                        Spacer()

                        Text(viewModel.durationFormatted)
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                    }
                }
                .padding(.horizontal, 30)
                .padding(.bottom, 40)
            }
        }
    }

    private func errorView(message: String) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 60))
                .foregroundColor(.red)

            Text("Afspelen mislukt")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.white)

            Text(message)
                .font(.body)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button(action: onClose) {
                Text("Sluiten")
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding(.horizontal, 40)
                    .padding(.vertical, 15)
                    .background(Color.red)
                    .cornerRadius(10)
            }
        }
        .padding()
    }

    private func toggleControls() {
        withAnimation(.easeInOut(duration: 0.3)) {
            showControls.toggle()
        }
        if showControls {
            scheduleHideControls()
        }
    }

    private func scheduleHideControls() {
        hideControlsTask?.cancel()
        hideControlsTask = Task {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            if !Task.isCancelled {
                await MainActor.run {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        showControls = false
                    }
                }
            }
        }
    }
}

#Preview {
    PlayerView(viewModel: PlayerViewModel())
}

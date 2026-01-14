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

#Preview {
    PlayerView(viewModel: PlayerViewModel())
}

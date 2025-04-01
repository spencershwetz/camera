import SwiftUI
import CoreData
import CoreMedia
import UIKit
import AVFoundation

struct CameraView: View {
    // Add a unique ID for logging
    private let viewInstanceId = UUID()

    @StateObject private var viewModel = CameraViewModel()
    @StateObject private var lutManager = LUTManager()
    @StateObject private var orientationViewModel = DeviceOrientationViewModel()
    @State private var isShowingSettings = false
    @State private var isShowingDocumentPicker = false
    @State private var showLUTPreview = true
    @State private var isShowingVideoLibrary = false
    @State private var statusBarHidden = true
    @State private var isDebugEnabled = false

    init() {
        // Log creation with unique ID
        print("🟣 CameraView.init() - Instance ID: \(viewInstanceId)")
        setupOrientationNotifications()
    }

    private func setupOrientationNotifications() {
        // Register for app state changes... (Keep existing)
        NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { _ in
            print("DEBUG: App became active - re-enforcing camera orientation")
        }
    }

    var body: some View {
        // Log body evaluation
        let _ = print("🔵 CameraView.body - Instance ID: \(viewInstanceId), ViewModel ID: \(viewModel.instanceId)")
        ZStack {
            // Background...
            Color.black.edgesIgnoringSafeArea(.all)

            // REVERT: Place cameraPreview directly in ZStack without VStack/frame
            cameraPreview()
                .edgesIgnoringSafeArea(.all) // Let the preview itself handle safe area for now

            // Overlays... (Keep existing FunctionButtonsView)
            FunctionButtonsView()
                .zIndex(100)
                .allowsHitTesting(true)
                .ignoresSafeArea()

            // Zoom Slider VStack (Keep existing)
            VStack {
                 Spacer()
                     .frame(height: UIScreen.main.bounds.height * 0.65) // Keep adjustment

                 if !viewModel.availableLenses.isEmpty {
                     ZoomSliderView(viewModel: viewModel, availableLenses: viewModel.availableLenses)
                         .padding(.bottom, 20)
                 }

                 Spacer()
             }
             .zIndex(99)


            // Bottom Controls VStack (Keep existing)
            VStack {
                Spacer()
                ZStack {
                    recordButton
                        .frame(width: 75, height: 75)

                    HStack {
                        videoLibraryButton
                            .frame(width: 60, height: 60)
                            .fullScreenCover(isPresented: $isShowingVideoLibrary, onDismiss: {
                                print("DEBUG: [LibraryButton] Dismissed - Setting isVideoLibraryPresented = false")
                                // **Crucial:** Reset the flag *after* dismissing
                                AppDelegate.isVideoLibraryPresented = false

                                // Force orientation back to portrait
                                DispatchQueue.main.async { // Ensure UI updates on main thread
                                    if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                                        print("DEBUG: Forcing portrait after video library dismissal")
                                        let geometryPreferences = UIWindowScene.GeometryPreferences.iOS(interfaceOrientations: .portrait)
                                        windowScene.requestGeometryUpdate(geometryPreferences) { error in
                                            if error != nil {
                                                print("DEBUG: Portrait reset error: \(error.localizedDescription)")
                                            } else {
                                                print("DEBUG: Portrait reset successful")
                                            }
                                            // Force update orientation on root controller AFTER the geometry update attempt
                                            windowScene.windows.forEach { window in
                                                window.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
                                            }
                                        }
                                    }
                                }
                            }) {
                                // Wrap VideoLibraryView in OrientationFixView to allow landscape
                                OrientationFixView(allowsLandscapeMode: true) {
                                    VideoLibraryView()
                                }
                            }
                        Spacer()
                        settingsButton
                            .frame(width: 60, height: 60)
                    }
                    .padding(.horizontal, 67.5)
                }
                .padding(.bottom, 30)
            }
            .ignoresSafeArea()
            .zIndex(101)

        }
        // Apply OrientationFixView as a background... (Keep existing)
        .background( // This ensures the CameraView itself respects portrait-only
            OrientationFixView(allowsLandscapeMode: false) {
                EmptyView()
            }
        )
        // Keep other existing modifiers (.onAppear, .onChange, etc.)...
         .onAppear {
             print("🟢 CameraView.onAppear - Instance ID: \(viewInstanceId)")
             startSession()
         }
         .onDisappear {
             print("🔴 CameraView.onDisappear - Instance ID: \(viewInstanceId)")
             stopSession()
         }
         .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
             stopSession()
         }
         .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
             startSession()
         }
         .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in
             // Orientation is handled within CustomPreviewView now
         }
         .onChange(of: lutManager.currentLUTFilter) { oldValue, newValue in
             if newValue != nil {
                 print("DEBUG: LUT filter updated to: \(lutManager.currentLUTName)")
                 showLUTPreview = true // This state variable might be redundant now
             } else {
                 print("DEBUG: LUT filter removed")
                 showLUTPreview = false // This state variable might be redundant now
             }
         }
         .alert(item: $viewModel.error) { error in
             Alert(
                 title: Text("Error"),
                 message: Text(error.description),
                 dismissButton: .default(Text("OK"))
             )
         }
         .sheet(isPresented: $isShowingSettings) {
             // Ensure flashlight is turned off when settings sheet is dismissed
             let settings = SettingsModel()
             if settings.isFlashlightEnabled {
                 // Find the flashlight manager instance if needed, or handle via viewModel
             }
         } content: {
              SettingsView(
                  lutManager: lutManager,
                  viewModel: viewModel,
                  isDebugEnabled: $isDebugEnabled
              )
         }
         .sheet(isPresented: $isShowingDocumentPicker) {
             DocumentPicker(types: LUTManager.supportedTypes) { url in
                 DispatchQueue.main.async {
                     handleLUTImport(url: url)
                     isShowingDocumentPicker = false // Ensure picker is dismissed
                 }
             }
         }
         .statusBar(hidden: statusBarHidden)
         .preferredColorScheme(.dark) // Ensure dark mode
         .ignoresSafeArea(.all) // Try ignoring safe area at the top level
    }

    // cameraPreview() function definition remains the same
    private func cameraPreview() -> AnyView {
         AnyView(
             Group {
                 if viewModel.isSessionRunning {
                     CameraPreviewView(
                         session: viewModel.session,
                         lutManager: lutManager,
                         viewModel: viewModel
                     )
                     .overlay(alignment: .topLeading) {
                         if isDebugEnabled {
                             debugOverlay
                                 .padding(.top, 50) // Adjust padding if needed relative to preview frame
                                 .padding(.leading, 10)
                         }
                     }
                     // Keep preview ignoring its own safe area
                     .edgesIgnoringSafeArea(.all)
                 } else {
                     // Loading state... (Keep existing)
                     VStack {
                         Text("Starting camera...")
                             .font(.headline)
                             .foregroundColor(.white)

                         if viewModel.status == .failed, let error = viewModel.error {
                             Text("Error: \(error.description)")
                                 .font(.subheadline)
                                 .foregroundColor(.red)
                                 .padding()
                         } else if viewModel.status == .unauthorized {
                              Text("Camera access denied. Please enable in Settings.")
                                   .font(.subheadline)
                                   .foregroundColor(.orange)
                                   .padding()
                               Button("Open Settings") {
                                   if let url = URL(string: UIApplication.openSettingsURLString) {
                                        UIApplication.shared.open(url)
                                   }
                               }
                          }
                      }
                      .frame(maxWidth: .infinity, maxHeight: .infinity)
                      .background(Color.black)
                 }
             }
             // Group no longer needs safe area ignore here
         )
     }

    // Keep existing debugOverlay, buttons, styles, methods...
    private var debugOverlay: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Res: \(viewModel.selectedResolution.rawValue)")
            Text("FPS: \(String(format: "%.2f", viewModel.selectedFrameRate))")
            Text("Codec: \(viewModel.selectedCodec.rawValue)")
            Text("Color: \(viewModel.isAppleLogEnabled ? "Log" : "Rec.709")")
            Text("Lens: \(viewModel.currentLens.rawValue)x (\(String(format: "%.1f", viewModel.currentZoomFactor))x)")
            Text("ISO: \(String(format: "%.0f", viewModel.iso))")
            // Text("Shtr: \(viewModel.shutterSpeed.timescale)/\(viewModel.shutterSpeed.value)")
            Text("WB: \(String(format: "%.0fK", viewModel.whiteBalance))")
            Text("Rec: \(viewModel.isRecording ? "ON" : "OFF")")
            Text("Proc: \(viewModel.isProcessingRecording ? "YES" : "NO")")

        }
        .font(.system(size: 10, weight: .medium, design: .monospaced))
        .foregroundColor(.white)
        .padding(6)
        .background(Color.black.opacity(0.5))
        .cornerRadius(6)
    }

    private var videoLibraryButton: some View {
        RotatingView(orientationViewModel: orientationViewModel) {
            Button(action: {
                print("DEBUG: [LibraryButton] Tapped - Setting isVideoLibraryPresented = true")
                // **Crucial:** Set the flag *before* presenting
                AppDelegate.isVideoLibraryPresented = true
                isShowingVideoLibrary = true
            }) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.black.opacity(0.6))
                        .frame(width: 60, height: 60)

                    if let thumbnailImage = viewModel.lastRecordedVideoThumbnail {
                        Image(uiImage: thumbnailImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 54, height: 54)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    } else {
                        Image(systemName: "film")
                            .font(.system(size: 24))
                            .foregroundColor(.white)
                    }
                }
            }
            .buttonStyle(PlainButtonStyle())
        }
        .frame(width: 60, height: 60)
    }

    private var settingsButton: some View {
        RotatingView(orientationViewModel: orientationViewModel) {
            Button(action: {
                isShowingSettings = true
            }) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.black.opacity(0.6))
                        .frame(width: 60, height: 60)

                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 24))
                        .foregroundColor(.white)
                }
            }
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 3.0)
                    .onEnded { _ in
                        withAnimation {
                            isDebugEnabled.toggle()
                        }
                    }
            )
        }
    }

    private var recordButton: some View {
        Button(action: {
            // Debounce rapid taps if processing
             guard !viewModel.isProcessingRecording else {
                 print("Record button disabled: Processing recording.")
                 return
             }

            withAnimation(.easeInOut(duration: 0.3)) {
                _ = Task { @MainActor in
                    if viewModel.isRecording {
                         print("Stopping recording...")
                        await viewModel.stopRecording()
                    } else {
                         print("Starting recording...")
                        await viewModel.startRecording()
                    }
                }
            }
        }) {
            ZStack {
                Circle()
                    .strokeBorder(Color.white, lineWidth: 4)
                    .frame(width: 75, height: 75)

                Group {
                    if viewModel.isRecording {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.red)
                            .frame(width: 30, height: 30)
                    } else {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 54, height: 54)
                    }
                }
                .animation(.easeInOut(duration: 0.3), value: viewModel.isRecording)
            }
            .opacity(viewModel.isProcessingRecording ? 0.5 : 1.0)
        }
        .buttonStyle(ScaleButtonStyle())
        .disabled(viewModel.isProcessingRecording) // Disable during processing
    }

    private struct ScaleButtonStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
                .animation(.easeInOut(duration: 0.2), value: configuration.isPressed)
        }
    }

    private func handleLUTImport(url: URL) {
        let fileSize = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        print("LUT file size: \(fileSize) bytes")

        lutManager.importLUT(from: url) { success in
            if success {
                print("DEBUG: LUT import successful, enabling preview")

                // **Important:** Update the viewModel's lutManager reference
                // This ensures the preview and recording service use the new LUT
                self.viewModel.lutManager = self.lutManager
                self.showLUTPreview = true
                print("DEBUG: LUT filter set in viewModel")

            } else {
                print("DEBUG: LUT import failed")
            }
        }
    }

    private func startSession() {
        // Check permissions first
        let cameraAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
        let micAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .audio)

        guard cameraAuthorizationStatus == .authorized && micAuthorizationStatus == .authorized else {
            print("Permissions not granted. Camera: \(cameraAuthorizationStatus.rawValue), Mic: \(micAuthorizationStatus.rawValue)")
            // Update status to reflect lack of permissions if not already handled by setup service
            if viewModel.status != .unauthorized {
                 viewModel.status = .unauthorized
            }
            // Optionally prompt user to go to settings
            return
        }


        if !viewModel.session.isRunning {
            DispatchQueue.global(qos: .userInitiated).async {
                self.viewModel.session.startRunning()
                DispatchQueue.main.async {
                    self.viewModel.isSessionRunning = self.viewModel.session.isRunning
                    // Update status based on session running state ONLY if not unauthorized
                    if self.viewModel.status != .unauthorized {
                         self.viewModel.status = self.viewModel.session.isRunning ? .running : .failed
                    }
                    self.viewModel.error = self.viewModel.session.isRunning ? nil : CameraError.sessionFailedToStart
                    print("DEBUG: Camera session running: \(self.viewModel.isSessionRunning)")
                }
            }
        } else {
             print("DEBUG: Camera session already running.")
             // Ensure state reflects reality
             DispatchQueue.main.async {
                 self.viewModel.isSessionRunning = true
                 if self.viewModel.status != .unauthorized {
                     self.viewModel.status = .running
                 }
             }
        }

        // **Important:** Ensure viewModel has the latest lutManager reference on appear
        viewModel.lutManager = lutManager
        showLUTPreview = true
    }

    private func stopSession() {
        if viewModel.session.isRunning {
            DispatchQueue.global(qos: .userInitiated).async {
                self.viewModel.session.stopRunning()
                DispatchQueue.main.async {
                    self.viewModel.isSessionRunning = false
                     // Only update status if not unauthorized
                     if self.viewModel.status != .unauthorized {
                         self.viewModel.status = .unknown // Or another appropriate state
                     }
                     print("DEBUG: Camera session stopped.")
                }
            }
        }
    }
}

#Preview("Camera View") {
    CameraView()
        .preferredColorScheme(.dark)
        .environment(\.colorScheme, .dark)
}

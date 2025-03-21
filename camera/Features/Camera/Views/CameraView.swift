import SwiftUI
import CoreData
import CoreMedia
import UIKit
import AVFoundation

// Custom struct for padding values
struct PaddingValues {
    let top: CGFloat
    let leading: CGFloat
    let bottom: CGFloat
    let trailing: CGFloat
}

/// A container view that enforces portrait layout dimensions regardless of device orientation
struct PortraitFixedContainer<Content: View>: View {
    var content: Content
    
    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
    
    var body: some View {
        GeometryReader { geometry in
            // Create a fixed portrait container with the original width and proportional height
            let portraitFrame = calculatePortraitFrame(from: geometry.size)
            let isLandscape = geometry.size.width > geometry.size.height
            
            ZStack {
                // Black background to fill any gaps
                Color.black
                    .ignoresSafeArea()
                
                // Content is centered in a fixed portrait frame
                content
                    .frame(width: portraitFrame.width, height: portraitFrame.height)
                    .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                    .onAppear {
                        print("🖼️ PORTRAIT CONTAINER - Initial frame: width=\(portraitFrame.width), height=\(portraitFrame.height)")
                        print("🖼️ PORTRAIT CONTAINER - Window: width=\(geometry.size.width), height=\(geometry.size.height), isLandscape=\(isLandscape)")
                    }
                    .onChange(of: isLandscape) { oldValue, newValue in
                        print("🔄 ORIENTATION CHANGE - isLandscape: \(oldValue) → \(newValue)")
                        print("🖼️ PORTRAIT CONTAINER - New dimensions: width=\(portraitFrame.width), height=\(portraitFrame.height)")
                    }
            }
            .onAppear {
                print("🖼️ PORTRAIT CONTAINER - Created fixed portrait frame: \(portraitFrame.width)x\(portraitFrame.height)")
            }
            .onChange(of: geometry.size) { oldValue, newValue in
                let newPortraitFrame = calculatePortraitFrame(from: newValue)
                let oldIsLandscape = oldValue.width > oldValue.height
                let newIsLandscape = newValue.width > newValue.height
                
                print("🖼️ PORTRAIT CONTAINER - Window size changed: \(oldValue) → \(newValue)")
                print("🖼️ PORTRAIT CONTAINER - New portrait frame: \(newPortraitFrame.width)x\(newPortraitFrame.height)")
                print("🖼️ PORTRAIT CONTAINER - Orientation: \(oldIsLandscape ? "landscape" : "portrait") → \(newIsLandscape ? "landscape" : "portrait")")
                
                // Additional logging to confirm orientation locking
                let interfaceOrientation = UIApplication.shared.connectedScenes.first(where: { $0 is UIWindowScene }).flatMap({ $0 as? UIWindowScene })?.interfaceOrientation
                print("🖼️ PORTRAIT CONTAINER - Interface orientation: \(interfaceOrientation?.rawValue ?? 0), maintaining portrait layout")
            }
        }
    }
    
    /// Calculate a portrait frame (taller than wide) regardless of device orientation
    private func calculatePortraitFrame(from size: CGSize) -> CGSize {
        // Determine if we're in landscape mode
        let isLandscape = size.width > size.height
        
        if isLandscape {
            print("🔄 CONTAINER DIMENSIONS - Device in landscape, maintaining portrait layout")
        }
        
        // For a portrait layout, the width should always be the smaller dimension
        // and the height should be larger (9:16 aspect ratio)
        var portraitWidth: CGFloat
        var portraitHeight: CGFloat
        
        if isLandscape {
            // In landscape, we need to use the height as our width reference
            // to maintain a portrait-oriented frame
            portraitWidth = size.height  // Use the device height as our width
            portraitHeight = portraitWidth * (16/9)  // Maintain 9:16 aspect ratio
            
            // If this would be too tall, scale it down
            if portraitHeight > size.width {
                let scale = size.width / portraitHeight
                portraitWidth *= scale
                portraitHeight = size.width
            }
        } else {
            // In portrait, simply use device width and maintain aspect ratio
            portraitWidth = size.width
            portraitHeight = portraitWidth * (16/9)
            
            // If this would be too tall, scale it down
            if portraitHeight > size.height {
                let scale = size.height / portraitHeight
                portraitWidth *= scale
                portraitHeight = size.height
            }
        }
        
        return CGSize(width: portraitWidth, height: portraitHeight)
    }
}

struct CameraView: View {
    @StateObject private var viewModel = CameraViewModel()
    @State private var orientation = UIDevice.current.orientation
    @StateObject private var lutManager = LUTManager()
    @State private var isShowingSettings = false
    @State private var isShowingDocumentPicker = false
    @State private var uiOrientation = UIDeviceOrientation.portrait
    @State private var showLUTPreview = true
    @State private var rotationAnimationDuration: Double = 0.3
    @State private var isRotating = false
    
    // Initialize with proper handling of StateObjects
    init() {
        // We CANNOT access @StateObject properties here as they won't be initialized yet
        // Only setup notifications that don't depend on StateObjects
        setupOrientationNotifications()
    }
    
    private func setupOrientationNotifications() {
        // Register for app state changes to re-enforce orientation when app becomes active
        NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { _ in
            print("DEBUG: App became active - re-enforcing camera orientation")
            // We CANNOT reference viewModel directly here - it causes the error
            // Instead, we'll handle this in onAppear or through a dedicated @State property
        }
    }
    
    var body: some View {
        // Wrap content in the PortraitFixedContainer to maintain portrait layout
        PortraitFixedContainer {
            ZStack {
                // Black background for the entire screen
                Color.black.ignoresSafeArea()
                
                GeometryReader { outerGeometry in
                    if viewModel.isSessionRunning {
                        // Main camera content view with all components
                        CameraContentView(
                            viewModel: viewModel,
                            lutManager: lutManager,
                            orientation: uiOrientation,
                            isRotating: isRotating,
                            animationDuration: rotationAnimationDuration
                        )
                    } else {
                        // Show loading or error state
                        VStack {
                            Text("Starting camera...")
                                .font(.headline)
                                .foregroundColor(.white)
                            
                            if viewModel.status == .failed, let error = viewModel.error {
                                Text("Error: \(error.description)")
                                    .font(.subheadline)
                                    .foregroundColor(.red)
                                    .padding()
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.black)
                    }
                }
            }
        }
        .ignoresSafeArea()
        .onAppear {
            // Start the camera session when the view appears
            if !viewModel.session.isRunning {
                DispatchQueue.global(qos: .userInitiated).async {
                    viewModel.session.startRunning()
                    DispatchQueue.main.async {
                        viewModel.isSessionRunning = viewModel.session.isRunning
                        viewModel.status = viewModel.session.isRunning ? .running : .failed
                        viewModel.error = viewModel.session.isRunning ? nil : CameraError.sessionFailedToStart
                        print("DEBUG: Camera session running: \(viewModel.isSessionRunning)")
                    }
                }
            }
            
            // Lock camera orientation
            viewModel.updateInterfaceOrientation(lockCamera: true)
            
            // Setup notification for when app becomes active
            NotificationCenter.default.addObserver(
                forName: UIApplication.didBecomeActiveNotification,
                object: nil,
                queue: .main
            ) { _ in
                print("DEBUG: App became active - re-enforcing camera orientation")
                viewModel.updateInterfaceOrientation(lockCamera: true)
            }
            
            // Share the lutManager between views
            viewModel.lutManager = lutManager
            
            // Enable LUT preview by default
            showLUTPreview = true
            
            // Enable device orientation notifications
            UIDevice.current.beginGeneratingDeviceOrientationNotifications()
            
            // Print that we're enforcing portrait orientation for the UI
            print("🔒 CAMERA VIEW - Enforcing portrait orientation for UI and camera preview")
        }
        .onDisappear {
            // Remove notification observer when the view disappears
            NotificationCenter.default.removeObserver(self, name: UIApplication.didBecomeActiveNotification, object: nil)
            
            // Stop the camera session when the view disappears
            if viewModel.session.isRunning {
                DispatchQueue.global(qos: .userInitiated).async {
                    viewModel.session.stopRunning()
                    DispatchQueue.main.async {
                        viewModel.isSessionRunning = false
                    }
                }
            }
            
            // Disable device orientation notifications
            UIDevice.current.endGeneratingDeviceOrientationNotifications()
        }
        .onChange(of: UIDevice.current.orientation) { oldValue, newValue in
            if newValue.isValidInterfaceOrientation {
                print("🔒 CAMERA VIEW - Device orientation changed to \(newValue.rawValue), but keeping UI in portrait")
                
                // Still update camera and allow system UI to rotate
                viewModel.updateInterfaceOrientation(lockCamera: true)
                
                // But we're not changing uiOrientation - keeping it portrait
                // This keeps all our UI elements in portrait orientation
            }
        }
        .onChange(of: lutManager.currentLUTFilter) { oldValue, newValue in
            // When LUT changes, update preview indicator
            if newValue != nil {
                print("DEBUG: LUT filter updated to: \(lutManager.currentLUTName)")
                // Automatically turn on preview when a new LUT is loaded
                showLUTPreview = true
            } else {
                print("DEBUG: LUT filter removed")
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
            SettingsView(lutManager: lutManager)
        }
        .sheet(isPresented: $isShowingDocumentPicker) {
            DocumentPicker(types: LUTManager.supportedTypes) { url in
                DispatchQueue.main.async {
                    handleLUTImport(url: url)
                    isShowingDocumentPicker = false
                }
            }
        }
    }
    
    private func handleLUTImport(url: URL) {
        // Import LUT file
        let fileSize = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        print("LUT file size: \(fileSize) bytes")
        
        lutManager.importLUT(from: url) { success in
            if success {
                print("DEBUG: LUT import successful, enabling preview")
                
                // Enable the LUT in the viewModel for real-time preview
                if let lutFilter = self.lutManager.currentLUTFilter {
                    self.viewModel.lutManager.currentLUTFilter = lutFilter
                    self.showLUTPreview = true
                    print("DEBUG: LUT filter set in viewModel for preview")
                }
            } else {
                print("DEBUG: LUT import failed")
            }
        }
    }
    
    private func isLandscapeOrientation(_ orientation: UIDeviceOrientation) -> Bool {
        return orientation == .landscapeLeft || orientation == .landscapeRight
    }
    
    private func rotationAngle(for orientation: UIDeviceOrientation) -> Angle {
        switch orientation {
        case .portrait:
            return .degrees(0)
        case .portraitUpsideDown:
            return .degrees(180)
        case .landscapeLeft:
            return .degrees(90)
        case .landscapeRight:
            return .degrees(-90)
        default:
            return .degrees(0)
        }
    }
    
    // Computed properties to simplify code
    private var isLandscape: Bool {
        // Always return false to keep UI in portrait orientation
        return false
    }
    
    // Rotation angle for UI components - always portrait (0°)
    private var uiRotationAngle: Angle {
        // Always return 0° (portrait) regardless of device orientation
        return .degrees(0)
    }
}

// Break out the camera content into a separate view to reduce complexity
struct CameraContentView: View {
    let viewModel: CameraViewModel
    let lutManager: LUTManager
    let orientation: UIDeviceOrientation
    let isRotating: Bool
    let animationDuration: Double
    
    // Computed properties to simplify code - always portrait mode
    private var isLandscape: Bool {
        // Always return false to keep UI in portrait orientation
        return false
    }
    
    // Rotation angle for UI components - always portrait (0°)
    private var uiRotationAngle: Angle {
        // Always return 0° (portrait) regardless of device orientation
        return .degrees(0)
    }
    
    var body: some View {
        GeometryReader { outerGeometry in
            ZStack {
                // CAMERA PREVIEW
                cameraPreviewView(geometry: outerGeometry)
                
                // BOTTOM CONTROLS
                bottomControlsView(geometry: outerGeometry)
            }
            .opacity(isRotating ? 0.99 : 1.0)
            .onAppear {
                printOrientationInfo()
                print("📏 FRAME SIZE - Initial: width=\(outerGeometry.size.width), height=\(outerGeometry.size.height)")
            }
            .onChange(of: orientation) { oldValue, newValue in
                printOrientationInfo()
                print("📏 FRAME SIZE - After orientation change: width=\(outerGeometry.size.width), height=\(outerGeometry.size.height)")
                print("📏 SAFE AREA - Top: \(outerGeometry.safeAreaInsets.top), Bottom: \(outerGeometry.safeAreaInsets.bottom), Leading: \(outerGeometry.safeAreaInsets.leading), Trailing: \(outerGeometry.safeAreaInsets.trailing)")
            }
            .onChange(of: outerGeometry.size) { oldSize, newSize in
                print("📏 GEOMETRY CHANGED - Old: \(oldSize.width)x\(oldSize.height), New: \(newSize.width)x\(newSize.height)")
                if oldSize.width != newSize.width || oldSize.height != newSize.height {
                    print("⚠️ LAYOUT ISSUE - Size changed, likely due to device rotation")
                }
            }
        }
    }
    
    private func printOrientationInfo() {
        print("🔒 CAMERA CONTENT VIEW - Device Orientation: \(orientation.rawValue) (\(describeDeviceOrientation(orientation)))")
        print("🔒 UI ROTATION - Locked to portrait (0°), isLandscape: \(isLandscape)")
        
        // Get interface orientation
        let interfaceOrientation: UIInterfaceOrientation
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            interfaceOrientation = windowScene.interfaceOrientation
            print("🔍 INTERFACE ORIENTATION - \(interfaceOrientation.rawValue) (\(describeInterfaceOrientation(interfaceOrientation)))")
        }
    }
    
    private func describeDeviceOrientation(_ orientation: UIDeviceOrientation) -> String {
        switch orientation {
        case .portrait: return "Portrait"
        case .portraitUpsideDown: return "Portrait Upside Down"
        case .landscapeLeft: return "Landscape Left (home button right)"
        case .landscapeRight: return "Landscape Right (home button left)" 
        case .faceUp: return "Face Up"
        case .faceDown: return "Face Down"
        case .unknown: return "Unknown"
        @unknown default: return "Unknown New Case"
        }
    }
    
    private func describeInterfaceOrientation(_ orientation: UIInterfaceOrientation) -> String {
        switch orientation {
        case .portrait: return "Portrait"
        case .portraitUpsideDown: return "Portrait Upside Down"
        case .landscapeLeft: return "Landscape Left (home button left)"
        case .landscapeRight: return "Landscape Right (home button right)"
        case .unknown: return "Unknown"
        @unknown default: return "Unknown New Case"
        }
    }
    
    // Camera preview component
    private func cameraPreviewView(geometry: GeometryProxy) -> some View {
        // Calculate dimensions for portrait orientation regardless of device orientation
        let isLandscape = geometry.size.width > geometry.size.height
        
        // Calculate the width and height to maintain a portrait 9:16 aspect ratio
        var previewWidth: CGFloat
        var previewHeight: CGFloat
        
        if isLandscape {
            // In landscape, use height as reference and calculate width to maintain 9:16 ratio
            previewHeight = geometry.size.height * 0.8 // Use 80% of the height
            previewWidth = previewHeight * (9.0/16.0)  // 9:16 ratio in portrait means 9/16 ratio for width/height
        } else {
            // In portrait, use width as reference
            previewWidth = geometry.size.width
            previewHeight = previewWidth * (16.0/9.0)  // 9:16 aspect ratio
            
            // If this would be too tall, scale it down
            if previewHeight > geometry.size.height * 0.8 {
                let scale = (geometry.size.height * 0.8) / previewHeight
                previewWidth *= scale
                previewHeight = geometry.size.height * 0.8
            }
        }
        
        // Log the dimensions to verify they're consistent
        print("📸 CAMERA PREVIEW - Using portrait dimensions: \(previewWidth) x \(previewHeight)")
        
        return ZStack {
            // Camera preview layer
            FixedOrientationCameraPreview(viewModel: viewModel, session: viewModel.session)
                .cornerRadius(20)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(Color.white.opacity(0.3), lineWidth: 1)
                )
                .frame(width: previewWidth, height: previewHeight)
            
            // Camera overlay with top status bar and grid lines
            CameraViewfinderOverlay(
                viewModel: viewModel,
                orientation: orientation
            )
                .frame(width: previewWidth, height: previewHeight)
        }
        // No need for scale effect as we're controlling the size directly
        // Use calculated dimensions that maintain portrait aspect ratio
        .frame(width: previewWidth, height: previewHeight)
        // Center the preview in the available space
        .position(
            x: geometry.size.width / 2,
            y: geometry.size.height / 2
        )
    }
    
    // Bottom controls component
    private func bottomControlsView(geometry: GeometryProxy) -> some View {
        // Get interface orientation to help with positioning
        let isLandscape = geometry.size.width > geometry.size.height
        
        // Calculate control dimensions based on available space
        // For portrait orientation controls, we use a consistent width regardless of device orientation
        var controlWidth: CGFloat
        var controlHeight: CGFloat
        
        if isLandscape {
            // In landscape, match the width of our portrait-oriented preview
            let previewHeight = geometry.size.height * 0.8
            let previewWidth = previewHeight * (9.0/16.0)
            
            controlWidth = previewWidth
            controlHeight = geometry.size.height * 0.15 // Smaller height in landscape
        } else {
            // In portrait, use the full width
            controlWidth = geometry.size.width
            controlHeight = geometry.size.height * 0.25
        }
        
        // Log the dimensions to verify they're consistent
        print("🎛️ BOTTOM CONTROLS - Size: \(controlWidth) x \(controlHeight), isLandscape: \(isLandscape)")
        
        return ZStack {
            CameraBottomControlsView(
                viewModel: viewModel,
                orientation: orientation
            )
        }
        // Frame with calculated dimensions
        .frame(width: controlWidth, height: controlHeight)
        // Position the controls at appropriate location based on orientation
        .position(
            x: geometry.size.width / 2,
            // In portrait mode, position controls near the bottom
            // In landscape mode, we position them below the centered camera preview
            y: geometry.size.height * (isLandscape ? 0.65 : 0.85)
        )
    }
} 

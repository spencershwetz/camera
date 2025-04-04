import SwiftUI
import AVFoundation
import CoreImage

struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession
    @ObservedObject var lutManager: LUTManager
    let viewModel: CameraViewModel
    
    func makeUIView(context: Context) -> RotationLockedContainer {
        print("DEBUG: Creating CameraPreviewView")
        // Create a rotation-locked container to hold our preview
        let container = RotationLockedContainer(frame: UIScreen.main.bounds)
        
        // Store reference to this container in the view model for LUT processing
        viewModel.owningView = container
        
        // Create a custom preview view that will handle LUT processing
        let preview = CustomPreviewView(frame: UIScreen.main.bounds, 
                                       session: session, 
                                       lutManager: lutManager,
                                       viewModel: viewModel)
        preview.backgroundColor = .black
        preview.tag = 100 // Tag for identification
        
        // Apply rounded corners to the preview
        preview.layer.cornerRadius = 20
        preview.layer.masksToBounds = true
        
        // Add the preview to our container
        container.addSubview(preview)
        
        // Pin the preview to the container with auto layout - using 80% of the screen size
        // and positioning it more towards the top
        preview.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            // Center horizontally
            preview.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            // Position away from the top to avoid status bar and cutoff
            // Increased top offset to match manual frame calculations
            preview.topAnchor.constraint(equalTo: container.topAnchor, constant: container.bounds.height * 0.18),
            // Width is 80% of container width
            preview.widthAnchor.constraint(equalTo: container.widthAnchor, multiplier: 0.8),
            // Set height based on width using 3:4 aspect ratio (width:height)
            // This means height should be 4/3 of the width
            // Slightly adjust height multiplier to account for top inset
            preview.heightAnchor.constraint(equalTo: preview.widthAnchor, multiplier: 4.0/3.0)
        ])
        
        return container
    }
    
    func updateUIView(_ uiView: RotationLockedContainer, context: Context) {
        // Verify session is running
        if !session.isRunning {
            print("DEBUG: Camera session NOT running during update! Starting...")
            DispatchQueue.global(qos: .userInitiated).async {
                self.session.startRunning()
                DispatchQueue.main.async {
                    print("DEBUG: Camera session started in updateUIView: \(self.session.isRunning)")
                }
            }
        }
        
        // Re-enforce the fixed frame and rotation settings
        uiView.frame = UIScreen.main.bounds
        
        // Find and update the preview view
        if let preview = uiView.viewWithTag(100) as? CustomPreviewView {
            // Update LUT if needed - just pass the reference, don't modify
            preview.updateLUT(lutManager.currentLUTFilter)
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }
    
    class Coordinator: NSObject {
        let parent: CameraPreviewView
        
        init(parent: CameraPreviewView) {
            self.parent = parent
            super.init()
        }
    }
    
    // MARK: - Custom Views
    
    // A container view that actively resists rotation changes
    class RotationLockedContainer: UIView {
        // Add a property to track animation state
        private var isAnimating = false
        
        override init(frame: CGRect) {
            super.init(frame: frame)
            print("DEBUG: RotationLockedContainer init with frame: \(frame)")
            setupView()
        }
        
        required init?(coder: NSCoder) {
            super.init(coder: coder)
            setupView()
        }
        
        private func setupView() {
            // Basics
            autoresizingMask = [.flexibleWidth, .flexibleHeight]
            backgroundColor = .black
            clipsToBounds = true
            
            // Register for orientation changes
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(orientationDidChange),
                name: UIDevice.orientationDidChangeNotification,
                object: nil
            )
            
            // Use modern approach to detect size changes - observe view bounds
            NotificationCenter.default.addObserver(
                self, 
                selector: #selector(interfaceOrientationDidChange),
                name: UIWindow.didBecomeVisibleNotification, 
                object: nil
            )
            
            // Register for trait changes in iOS 17+
            if #available(iOS 17.0, *) {
                registerForTraitChanges([UITraitHorizontalSizeClass.self, UITraitVerticalSizeClass.self]) { [weak self] (_: RotationLockedContainer, _: UITraitCollection) in
                    // Use animation to prevent abrupt changes
                    UIView.animate(withDuration: 0.3) {
                        self?.enforceBounds()
                    }
                }
            }
            
            print("DEBUG: RotationLockedContainer initialized")
        }
        
        @objc private func orientationDidChange() {
            print("DEBUG: Container detected device orientation change")
            // Use animation to prevent abrupt changes
            UIView.animate(withDuration: 0.3) {
                self.enforceBounds()
            }
        }
        
        @objc private func interfaceOrientationDidChange() {
            print("DEBUG: Container detected interface orientation change")
            // Use animation to prevent abrupt changes
            UIView.animate(withDuration: 0.3) {
                self.enforceBounds()
            }
        }
        
        // Using availability attribute to silence the warning
        @available(iOS, obsoleted: 17.0, message: "Use registerForTraitChanges instead")
        override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
            // Don't call super.traitCollectionDidChange on iOS 17+ to avoid the warning
            if #available(iOS 17.0, *) {
                // No-op, we're using registerForTraitChanges in setupView
            } else {
                super.traitCollectionDidChange(previousTraitCollection)
                // Use animation to prevent abrupt changes
                UIView.animate(withDuration: 0.3) {
                    self.enforceBounds()
                }
            }
        }
        
        private func enforceBounds() {
            // Set flag to indicate animation in progress
            isAnimating = true
            
            print("DEBUG: enforceBounds - Before: frame=\(frame), bounds=\(bounds)")
            
            // Always maintain full screen bounds regardless of rotation
            frame = UIScreen.main.bounds
            
            print("DEBUG: enforceBounds - After: frame=\(frame), bounds=\(bounds)")
            print("DEBUG: enforceBounds - Safe area insets: \(safeAreaInsets)")
            
            // Re-enforce rotation settings for all subviews
            for case let preview as CustomPreviewView in subviews {
                print("DEBUG: enforceBounds - CustomPreviewView before: \(preview.frame)")
                preview.frame = bounds
                print("DEBUG: enforceBounds - CustomPreviewView after: \(preview.frame)")
                preview.updateFrameSize()
            }
            
            // Reset animation flag after a short delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self.isAnimating = false
            }
        }
        
        // Override these methods to prevent rotation from affecting our view
        override func layoutSubviews() {
            super.layoutSubviews()
            // Only enforce bounds if not already animating to prevent conflicts
            if !isAnimating {
                enforceBounds()
            }
        }
        
        override func didMoveToSuperview() {
            super.didMoveToSuperview()
            enforceBounds()
        }
        
        override func didMoveToWindow() {
            super.didMoveToWindow()
            enforceBounds()
        }
        
        deinit {
            NotificationCenter.default.removeObserver(self)
        }
    }
    
    // Custom preview view that handles LUT processing
    class CustomPreviewView: UIView, AVCaptureVideoDataOutputSampleBufferDelegate {
        private let previewLayer = AVCaptureVideoPreviewLayer()
        private var dataOutput: AVCaptureVideoDataOutput?
        private let session: AVCaptureSession
        private var lutManager: LUTManager
        private var viewModel: CameraViewModel
        private var ciContext = CIContext(options: [.useSoftwareRenderer: false])
        private let processingQueue = DispatchQueue(label: "com.camera.lutprocessing", qos: .userInitiated)
        private var currentLUTFilter: CIFilter?
        
        init(frame: CGRect, session: AVCaptureSession, lutManager: LUTManager, viewModel: CameraViewModel) {
            self.session = session
            self.lutManager = lutManager
            self.viewModel = viewModel
            super.init(frame: frame)
            setupView()
        }
        
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
        
        private func setupView() {
            // Set background color for the view itself
            backgroundColor = .black
            clipsToBounds = true
            layer.cornerRadius = 20
            
            // Configure preview layer
            previewLayer.session = session
            previewLayer.videoGravity = .resizeAspect
            
            // Calculate inset that creates a small margin around the preview
            let inset: CGFloat = 6.0
            // Use a larger top inset to fix the cutoff issue
            let topInset: CGFloat = 16.0
            
            // Create frame with custom insets
            let frameWithInsets = CGRect(
                x: bounds.origin.x + inset,
                y: bounds.origin.y + topInset, // Use larger top inset
                width: bounds.width - (inset * 2),
                height: bounds.height - (inset * 2 + topInset) // Adjust height for top inset
            )
            
            previewLayer.frame = frameWithInsets
            // Ensure the preview layer respects the view's rounded corners
            previewLayer.cornerRadius = 20
            previewLayer.masksToBounds = true
            
            layer.addSublayer(previewLayer)
            
            // Set initial orientation
            if previewLayer.connection?.isVideoRotationAngleSupported(90) == true {
                previewLayer.connection?.videoRotationAngle = 90
            }
            
            print("DEBUG: CustomPreviewView set up with AVCaptureVideoPreviewLayer")
            
            // Set up data output if LUT filter is available
            if let filter = lutManager.currentLUTFilter {
                setupDataOutput()
                currentLUTFilter = filter
            }
        }
        
        func updateFrameSize() {
            // Use animation to prevent abrupt changes
            CATransaction.begin()
            CATransaction.setAnimationDuration(0.3)
            
            // Calculate inset that creates a small margin around the preview
            let inset: CGFloat = 6.0
            // Use a larger top inset to fix the cutoff issue
            let topInset: CGFloat = 16.0
            
            // Create frame with custom insets
            let frameWithInsets = CGRect(
                x: bounds.origin.x + inset,
                y: bounds.origin.y + topInset, // Use larger top inset
                width: bounds.width - (inset * 2),
                height: bounds.height - (inset * 2 + topInset) // Adjust height for top inset
            )
            
            previewLayer.frame = frameWithInsets
            
            // Ensure the corner radius is maintained
            previewLayer.cornerRadius = 20
            
            // Also update connection orientation
            if previewLayer.connection?.isVideoRotationAngleSupported(90) == true {
                previewLayer.connection?.videoRotationAngle = 90
            }
            
            // Also update any LUT overlay layer
            if let overlay = previewLayer.sublayers?.first(where: { $0.name == "LUTOverlayLayer" }) {
                overlay.frame = previewLayer.bounds
                overlay.cornerRadius = 20
            }
            
            CATransaction.commit()
        }
        
        func updateLUT(_ filter: CIFilter?) {
            // Skip if same filter (reference equality)
            if (filter === currentLUTFilter) {
                return
            }
            
            // If filter state changed (nil vs non-nil), update processing
            if (filter != nil) != (currentLUTFilter != nil) {
                if filter != nil {
                    // New filter added when none existed
                    setupDataOutput()
                } else {
                    // Filter removed - first clean up any existing overlay
                    DispatchQueue.main.async { [weak self] in
                        guard let self = self else { return }
                        
                        // Remove any existing LUT overlay layer before removing the data output
                        CATransaction.begin()
                        CATransaction.setDisableActions(true)
                        
                        if let overlay = self.previewLayer.sublayers?.first(where: { $0.name == "LUTOverlayLayer" }) {
                            overlay.removeFromSuperlayer()
                            print("DEBUG: Removed LUT overlay layer during filter update")
                        }
                        
                        CATransaction.commit()
                        
                        // Now remove the data output on the session queue to prevent freezing
                        DispatchQueue.global(qos: .userInitiated).async {
                            self.removeDataOutput()
                        }
                    }
                }
            }
            
            // Update our local reference only - don't modify published properties
            currentLUTFilter = filter
            
            // DON'T update viewModel.lutManager here - this is called during view updates
            // and would trigger the SwiftUI warning
            
            if filter != nil {
                print("DEBUG: CustomPreviewView updated with LUT filter")
            } else {
                print("DEBUG: CustomPreviewView cleared LUT filter")
            }
        }
        
        private func setupDataOutput() {
            // Remove any existing outputs
            if let existingOutput = dataOutput {
                session.removeOutput(existingOutput)
            }
            
            session.beginConfiguration()
            
            // Create new video data output
            let output = AVCaptureVideoDataOutput()
            output.setSampleBufferDelegate(self, queue: processingQueue)
            output.alwaysDiscardsLateVideoFrames = true
            
            // Set video settings for compatibility with CoreImage
            let settings: [String: Any] = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ]
            output.videoSettings = settings
            
            if session.canAddOutput(output) {
                session.addOutput(output)
                dataOutput = output
                
                // Ensure proper orientation
                if let connection = output.connection(with: .video),
                   connection.isVideoRotationAngleSupported(90) {
                    connection.videoRotationAngle = 90
                }
                
                print("DEBUG: Added video data output for LUT processing")
            }
            
            session.commitConfiguration()
        }
        
        private func removeDataOutput() {
            if let output = dataOutput {
                session.beginConfiguration()
                session.removeOutput(output)
                session.commitConfiguration()
                dataOutput = nil
                
                // Clear any existing LUT overlay to prevent freezing
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    
                    CATransaction.begin()
                    CATransaction.setDisableActions(true)
                    
                    // Remove the LUT overlay layer if it exists
                    if let overlay = self.previewLayer.sublayers?.first(where: { $0.name == "LUTOverlayLayer" }) {
                        overlay.removeFromSuperlayer()
                        print("DEBUG: Removed LUT overlay layer")
                    }
                    
                    CATransaction.commit()
                }
                
                print("DEBUG: Removed video data output for LUT processing")
            }
        }
        
        // MARK: - AVCaptureVideoDataOutputSampleBufferDelegate
        
        func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
            guard let currentLUTFilter = currentLUTFilter,
                  let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
                return
            }
            
            // Create CIImage from the pixel buffer
            let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
            
            // Apply LUT filter
            currentLUTFilter.setValue(ciImage, forKey: kCIInputImageKey)
            
            guard let outputImage = currentLUTFilter.outputImage,
                  let cgImage = ciContext.createCGImage(outputImage, from: outputImage.extent) else {
                return
            }
            
            // Create an overlay image
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                
                CATransaction.begin()
                CATransaction.setAnimationDuration(0.3)
                
                // Update existing overlay or create a new one
                if let overlay = self.previewLayer.sublayers?.first(where: { $0.name == "LUTOverlayLayer" }) {
                    overlay.contents = cgImage
                    overlay.frame = self.previewLayer.bounds
                    overlay.cornerRadius = 20
                } else {
                    let overlayLayer = CALayer()
                    overlayLayer.name = "LUTOverlayLayer"
                    overlayLayer.frame = self.previewLayer.bounds
                    overlayLayer.contentsGravity = .resizeAspect
                    overlayLayer.contents = cgImage
                    overlayLayer.cornerRadius = 20
                    overlayLayer.masksToBounds = true
                    self.previewLayer.addSublayer(overlayLayer)
                    print("DEBUG: Added LUT overlay layer")
                }
                
                CATransaction.commit()
            }
        }
        
        override func layoutSubviews() {
            super.layoutSubviews()
            
            // The Auto Layout system has updated our frame
            // Ensure our preview layer is properly positioned within it
            updateFrameSize()
        }
    }
}

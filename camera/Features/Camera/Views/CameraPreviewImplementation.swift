// File: camera/Features/Camera/CameraPreviewImplementation.swift

import SwiftUI
import AVFoundation

/// A SwiftUI view that presents a live camera preview using an AVCaptureVideoPreviewLayer.
/// This implementation locks the preview to a fixed portrait orientation
/// so that the preview does not rotate even if the device rotates.
struct CameraPreview: UIViewRepresentable {
    private let source: PreviewSource

    init(source: PreviewSource) {
        self.source = source
    }

    func makeUIView(context: Context) -> PreviewView {
        // Lock the orientation to portrait
        CameraOrientationLock.lockToPortrait()
        let preview = PreviewView()
        source.connect(to: preview)
        return preview
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        // No updates required.
    }
    
    static func dismantleUIView(_ uiView: PreviewView, coordinator: ()) {
        // Maintain portrait orientation when view is dismantled
        CameraOrientationLock.lockToPortrait()
    }

    /// A UIView whose backing layer is AVCaptureVideoPreviewLayer.
    /// It sets the session and forces a fixed rotation.
    class PreviewView: UIView, PreviewTarget {
        override class var layerClass: AnyClass {
            AVCaptureVideoPreviewLayer.self
        }
        
        var previewLayer: AVCaptureVideoPreviewLayer {
            layer as! AVCaptureVideoPreviewLayer
        }
        
        init() {
            super.init(frame: .zero)
            backgroundColor = .black
            // Do not register for orientation notifications to keep a fixed preview.
        }
        
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
        
        func setSession(_ session: AVCaptureSession) {
            previewLayer.session = session
            previewLayer.videoGravity = .resizeAspectFill
            
            if let connection = previewLayer.connection {
                // Force a fixed rotation to portrait (90 degrees)
                if connection.isVideoRotationAngleSupported(90) {
                    connection.videoRotationAngle = 90
                    print("DEBUG: Set videoRotationAngle to 90 (portrait fixed)")
                } else {
                    print("DEBUG: videoRotationAngle 90 not supported")
                }
                print("DEBUG: Current videoRotationAngle: \(connection.videoRotationAngle)")
            } else {
                print("DEBUG: No connection available on previewLayer")
            }
        }
    }
}

/// A protocol to allow connecting an AVCaptureSession to a preview view.
@preconcurrency
protocol PreviewSource: Sendable {
    func connect(to target: PreviewTarget)
}

/// A protocol that defines a preview target which can accept an AVCaptureSession.
protocol PreviewTarget {
    func setSession(_ session: AVCaptureSession)
}

/// The default implementation for connecting a session.
struct DefaultPreviewSource: PreviewSource {
    private let session: AVCaptureSession
    
    init(session: AVCaptureSession) {
        self.session = session
    }
    
    func connect(to target: PreviewTarget) {
        target.setSession(session)
    }
    
    func makeUIView() -> UIView {
        let view = UIView()
        let previewLayer = AVCaptureVideoPreviewLayer()
        
        // Configure preview layer
        previewLayer.session = session
        previewLayer.videoGravity = .resizeAspectFill
        
        // Force portrait orientation
        if let connection = previewLayer.connection, connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90
            print("DEBUG: DefaultPreviewSource set rotation to 90°")
        }
        
        // Add preview layer to view
        previewLayer.frame = view.bounds
        view.layer.addSublayer(previewLayer)
        
        return view
    }
    
    func updateUIView(_ uiView: UIView) {
        guard let previewLayer = uiView.layer.sublayers?.first as? AVCaptureVideoPreviewLayer else {
            return
        }
        
        // Force portrait orientation
        if let connection = previewLayer.connection, connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90
        }
        
        // Update frame to match view
        previewLayer.frame = uiView.bounds
    }
}

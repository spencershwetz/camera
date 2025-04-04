import UIKit

/// Utility class to lock the device orientation for camera operations
final class CameraOrientationLock {
    
    private static var isLocked = false
    private static var lastLockTime: TimeInterval = 0
    private static var activeTransitionTimer: Timer?
    
    /// Lock the device orientation to portrait - this is the only orientation we support
    static func lockToPortrait() {
        isLocked = true
        lastLockTime = CACurrentMediaTime()
        
        // Cancel any existing transition timer
        activeTransitionTimer?.invalidate()
        
        // Force the orientation to portrait
        if #available(iOS 16.0, *) {
            // Use the correct approach for iOS 16+
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                // Request geometry update to lock to portrait
                windowScene.requestGeometryUpdate(.iOS(interfaceOrientations: .portrait))
                
                // Update all root view controllers in all windows
                for window in windowScene.windows {
                    window.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
                }
            }
            
            // Update orientation for all scenes and windows
            for scene in UIApplication.shared.connectedScenes {
                if let windowScene = scene as? UIWindowScene {
                    for window in windowScene.windows {
                        window.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
                    }
                }
            }
        } else {
            // Fallback for older iOS versions
            // Direct orientation setting (for pre-iOS 16 only)
            UIDevice.current.setValue(UIDeviceOrientation.portrait.rawValue, forKey: "orientation")
            UIViewController.attemptRotationToDeviceOrientation()
        }
        
        // Schedule a sequence of re-locks to handle system auto-rotation attempts
        // This helps ensure consistent behavior during portrait-to-landscape transitions
        scheduleReorientationSequence()
        
        print("🔒 Camera preview locked to portrait orientation (90°)")
    }
    
    /// Schedule a sequence of orientation reapplications to handle transition edge cases
    private static func scheduleReorientationSequence() {
        // Cancel any existing timer
        activeTransitionTimer?.invalidate()
        
        // Create a repeating timer that will check and reapply orientation lock as needed
        activeTransitionTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { timer in
            // Get the current device orientation
            let currentOrientation = UIDevice.current.orientation
            
            // If device is in landscape but our interface should be portrait, force a stronger update
            if currentOrientation.isLandscape {
                if #available(iOS 16.0, *) {
                    // Force all windows to update
                    for scene in UIApplication.shared.connectedScenes {
                        if let windowScene = scene as? UIWindowScene {
                            // Apply the geometry update more aggressively during landscape detection
                            windowScene.requestGeometryUpdate(.iOS(interfaceOrientations: .portrait))
                            
                            for window in windowScene.windows {
                                // Force update the view controller orientation
                                window.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
                                
                                // Also notify any child view controllers that might need updating
                                notifyChildViewControllersOfOrientationChange(window.rootViewController)
                            }
                        }
                    }
                    
                    // Post a notification to inform custom views that they may need to update
                    NotificationCenter.default.post(name: .orientationLockEnforced, object: nil)
                }
            }
            
            // Stop the timer after 2 seconds (20 checks at 0.1s interval)
            // This prevents unnecessary CPU usage while still covering the transition period
            if CACurrentMediaTime() - lastLockTime > 2.0 {
                timer.invalidate()
            }
        }
    }
    
    /// Notify all child view controllers to update their orientations
    private static func notifyChildViewControllersOfOrientationChange(_ viewController: UIViewController?) {
        guard let viewController = viewController else { return }
        
        // Update this view controller
        viewController.setNeedsUpdateOfSupportedInterfaceOrientations()
        
        // Update presented view controller if any
        if let presented = viewController.presentedViewController {
            notifyChildViewControllersOfOrientationChange(presented)
        }
        
        // Update children
        for child in viewController.children {
            notifyChildViewControllersOfOrientationChange(child)
        }
    }
    
    /// Force immediate application of the portrait orientation lock
    static func forceOrientationUpdate() {
        if #available(iOS 16.0, *) {
            // Use the proper iOS 16+ approach
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                // Request geometry update with portrait orientation
                windowScene.requestGeometryUpdate(.iOS(interfaceOrientations: .portrait))
                
                // Update all windows in the scene
                for window in windowScene.windows {
                    window.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
                    
                    // Notify child view controllers
                    notifyChildViewControllersOfOrientationChange(window.rootViewController)
                }
            }
            
            // Update all scenes and windows
            for scene in UIApplication.shared.connectedScenes {
                if let windowScene = scene as? UIWindowScene {
                    for window in windowScene.windows {
                        window.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
                    }
                }
            }
            
            // Post notification for custom views
            NotificationCenter.default.post(name: .orientationLockEnforced, object: nil)
        } else {
            // Fallback for older iOS versions
            UIDevice.current.setValue(UIDeviceOrientation.portrait.rawValue, forKey: "orientation")
            UIViewController.attemptRotationToDeviceOrientation()
        }
        
        print("🔄 Forced orientation update to portrait")
    }
    
    /// Handle device orientation change - call this from orientation change handlers
    static func handleDeviceOrientationChange(_ newOrientation: UIDeviceOrientation) {
        print("🔄 Device orientation changed: \(newOrientation) (value: \(newOrientation.rawValue))")
        
        // If the device is in landscape, enforce portrait lock
        if newOrientation.isLandscape {
            // Refresh the lock to ensure it's maintained during landscape transition
            lockToPortrait()
        }
    }
}

/// Extension to be used in SceneDelegate or App to enforce orientation lock
extension UIWindowScene {
    static var orientationLockObserver: NSObjectProtocol? = nil
    
    /// Setup orientation lock support in your SceneDelegate or SwiftUI App
    static func setupOrientationLockSupport() {
        if orientationLockObserver == nil {
            orientationLockObserver = NotificationCenter.default.addObserver(
                forName: UIDevice.orientationDidChangeNotification,
                object: nil,
                queue: .main
            ) { _ in
                // Handle device orientation change
                let newOrientation = UIDevice.current.orientation
                CameraOrientationLock.handleDeviceOrientationChange(newOrientation)
                
                if #available(iOS 16.0, *) {
                    // For iOS 16+, iterate through all scenes and call setNeedsUpdateOfSupportedInterfaceOrientations
                    for scene in UIApplication.shared.connectedScenes {
                        if let windowScene = scene as? UIWindowScene {
                            for window in windowScene.windows {
                                window.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
                            }
                        }
                    }
                } else {
                    // Fallback for older iOS versions
                    UIViewController.attemptRotationToDeviceOrientation()
                }
            }
        }
    }
}

// Define a notification name for custom views to listen for orientation lock enforcement
extension Notification.Name {
    static let orientationLockEnforced = Notification.Name("orientationLockEnforced")
} 
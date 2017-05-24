// Copyright (c) 2017 Philip M. Hubbard
//
// Permission is hereby granted, free of charge, to any person obtaining a copy of this software and
// associated documentation files (the "Software"), to deal in the Software without restriction,
// including without limitation the rights to use, copy, modify, merge, publish, distribute,
// sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all copies or
// substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT
// NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
// NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM,
// DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
//
// http://opensource.org/licenses/MIT

import UIKit
import GLKit
import AVFoundation

// The view controller for the OpenGL view, with code to handle some gestures and buttons.

class ViewController: GLKViewController, UIGestureRecognizerDelegate {
    
    var videoHandler: VideoHandler!
    var renderer: Renderer!
    
    // The pinch gesture changes the overall height scale for the lumincance height field created
    // by the vertex shader.
    
    var pinchGestureRecognizer: UIPinchGestureRecognizer!
    var heightScaleBegan: GLfloat = 0
    
    // Double-tap resets to the default image and height scale.
    
    var doubleTapGestureRecognizer: UITapGestureRecognizer!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        guard let view = self.view as? GLKView else {
            return;
        }
        
        view.drawableDepthFormat = GLKViewDrawableDepthFormat.format24
        
        preferredFramesPerSecond = 60
        
        renderer = Renderer(view: view)
        videoHandler = VideoHandler(renderer: renderer)
        
        pinchGestureRecognizer = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(gestureRecognizer:)))
        view.addGestureRecognizer(pinchGestureRecognizer)
        
        doubleTapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(gestureRecognizer:)))
        doubleTapGestureRecognizer.numberOfTapsRequired = 2
        view.addGestureRecognizer(doubleTapGestureRecognizer)
    }
    
    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {

        // The following idiom seems to be the best way to respond to a change in the device
        // orientation (portrait, landscape), so the camera can be put into the matching
        // orientation.
        
        super.viewWillTransition(to: size, with: coordinator)

        coordinator.animate(alongsideTransition: nil) { _ in
            let deviceOrientation = UIDevice.current.orientation
            switch deviceOrientation {
            case .landscapeLeft:
                self.videoHandler.cameraOrientation = AVCaptureVideoOrientation.landscapeRight
            case .landscapeRight:
                self.videoHandler.cameraOrientation = AVCaptureVideoOrientation.landscapeLeft
            case .portrait:
                self.videoHandler.cameraOrientation = AVCaptureVideoOrientation.portrait
            default:
                break
            }
        }
    }
    
    // The standard GLKViewController function for rendering a frame.
    
    override func glkView(_ view: GLKView, drawIn rect: CGRect) {
        guard view == self.view else {
            fatalError("ViewController.glkView(): unexpected GLKView")
        }
        
        renderer.render(rect: rect, timeSinceLastDraw: timeSinceLastDraw, framesPerSecond: framesPerSecond)
    }
    
    func handlePinch(gestureRecognizer: UIPinchGestureRecognizer) {
        if gestureRecognizer.state == .began {
            heightScaleBegan = renderer.heightScale
        } else if gestureRecognizer.state == .changed {
            let change = GLfloat(1 - gestureRecognizer.scale)
            let sensitivity = GLfloat(1.0)
            var scale = heightScaleBegan + change * sensitivity
            scale = max(scale, LuminanceWarpingVertexShaderPNT.HeightScaleMin)
            scale = min(scale, LuminanceWarpingVertexShaderPNT.HeightScaleMax)
            renderer.heightScale = scale
        }
    }
    
    func handleDoubleTap(gestureRecognizer: UITapGestureRecognizer) {
        if gestureRecognizer.state == .ended {
            renderer.reset()
        }
    }
    
    // The button to flip the camera (between back and front) is defined in the storyboard.
    
    @IBAction func handleFlipButton(_ sender: UIBarButtonItem) {
        sender.isEnabled = false
        
        renderer.detour()
        videoHandler.toggleCameraPosition()
        
        // Fade on a label informing the user of which camera is being used.
        
        let nowFront = videoHandler.cameraPosition == AVCaptureDevicePosition.front
        whichCameraLabel.text = nowFront ? "Using front camera" : "Using back camera"
        UIView.animate(withDuration: 1, animations: {
            self.whichCameraLabel.alpha = 1.0
        }, completion: { _ in
            
            // After the label has been displayed for 2 seconds, fade it off again.
            
            UIView.animate(withDuration: 1, delay: 2, animations: {
                self.whichCameraLabel.alpha = 0.0
                sender.isEnabled = true
            })
        })
    }
    
    // The button to change the lighting model is defined in the storyboard.
    
    @IBAction func handleLightingButton(_ sender: UIBarButtonItem) {
        renderer.toggleShaderProgram()
    }
    
    // The label to indicate which camera is being used is defined in the storyboard.
    
    @IBOutlet weak var whichCameraLabel: UILabel!
}

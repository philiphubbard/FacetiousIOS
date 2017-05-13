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

import AVFoundation
import SCamera
import CoreMedia
import SUtility

// A class to get images from the video camera, run the face detector, and turn the result into a
// texture for the renderer.

class VideoHandler: VideoDelegate {
    init?(renderer: Renderer) {
        self.renderer = renderer
        
        let options: [String : Any] = [CIDetectorTracking: true, CIDetectorAccuracy: CIDetectorAccuracyHigh]

        guard let detector =  CIDetector(ofType: CIDetectorTypeFace, context: nil, options: options) else {
            print("CIDetector init failed")
            return nil
        }
        self.detector = detector
        
        // The face detector cannot run at 60 Hz, so it runs asynchronously in its own queue,
        // allowing the renderer to continue to animate with the most recently detected face texture
        // at the desired frame rate.
        
        detectorQueue = DispatchQueue(label: "com.philiphubbard.facetious.videoHandler.detector")
        
        // This queue synchronizes access to the "detecting" property.
        
        detectingQueue = DispatchQueue(label: "com.philiphubbard.facetious.videoHandler.detecting")

        let capacity = 4
        xAvg = RunningAverage<CGFloat>(capacity: capacity)
        yAvg = RunningAverage<CGFloat>(capacity: capacity)
        widthAvg = RunningAverage<CGFloat>(capacity: capacity)
        heightAvg = RunningAverage<CGFloat>(capacity: capacity)
        
        camera = Video(delegate: self)
        camera.start()
    }
    
    // Allows the view controller know which camera (front, back) is in use.
    
    var cameraPosition: AVCaptureDevicePosition {
        get {
            return camera.position
        }
    }
    
    // Allows the view controller button to switch between the front and back cameras.

    func toggleCameraPosition() {
        let newPosition = camera.position == AVCaptureDevicePosition.front ? AVCaptureDevicePosition.back : AVCaptureDevicePosition.front
        camera.position = newPosition
    }
    
    // Allows the view controller to control the camera orientation (portrait, landscape).
    
    var cameraOrientation: AVCaptureVideoOrientation {
        get {
            return camera.orientation
        }
        set(newValue) {
            camera.orientation = newValue
        }
    }
    
    // The delegate function called when a new frame is received.
    
    func captureOutput(sampleBuffer: CMSampleBuffer!) {
        
        // Check whether the face detector is processing a previous frame.
        
        var runDetector = false
        detectingQueue.sync {
            if !self.detecting {
                self.detecting = true
                runDetector = true
            }
        }
        
        // If not, then run the face detector on this frame, in its own queue.
        
        if runDetector {
            detectorQueue.async {
                guard let cgImage = Video.cgImage(fromSampleBuffer: sampleBuffer) else {
                    print("VideoHandler.captureOutput could not create CGImage")
                    return
                }
                self.detectFace(inCgImage: cgImage)
                self.detectingQueue.sync {
                    self.detecting = false
                }
            }
        }
        
    }
    
    // The delegate function called when a frame is dropped.
    
    func droppedFrame(sampleBuffer: CMSampleBuffer!) {
        
        // Just ingore this case and go on to the next frame.
        
    }
    
    private func makeCIImage(fromCgImage cgImage: CGImage) -> CIImage {
        return CIImage(cgImage: cgImage)
    }
    
    // Run the face detector on the input CGImage.
    
    private func detectFace(inCgImage cgImage: CGImage) {
        let ciImage = makeCIImage(fromCgImage: cgImage)
        
        let results = detector.features(in: ciImage)
        
        // If we are not tracking a face, then use the face with the largest area (if there is more
        // than one face present).
        
        var chosenFace: CIFaceFeature?
        var maxArea: CGFloat = 0
        
        for result in results {
            if let face = result as? CIFaceFeature {
                if let id = detectedTrackingId {
                    if face.hasTrackingID && face.trackingID == id {
                        
                        // If we are tracking a face from a previous frame, use it again.
                        
                        chosenFace = face
                        break
                    }
                }
                let rect = face.bounds
                let area = rect.size.width * rect.size.height
                if area > maxArea {
                    
                    // Otherwise, use the face with the largest area.
                    
                    maxArea = area
                    chosenFace = face
                }
            }
        }
        
        if let face = chosenFace {
            let origin = face.bounds.origin
            let size = face.bounds.size
            
            // The face detector can be jittery.  So use a running average of the position and size
            // over the last few frames.
            
            xAvg.add(value: origin.x)
            yAvg.add(value: origin.y)
            widthAvg.add(value: size.width)
            heightAvg.add(value: size.height)
            
            let x = xAvg.value()
            let y = yAvg.value()
            let width = widthAvg.value()
            let height = heightAvg.value()
            
            if face.hasTrackingID {
                detectedTrackingId = face.trackingID
            }
            
            let rect = CGRect(x: x, y: ciImage.extent.height - y - height, width: width, height: height)
            if let faceImage = cgImage.cropping(to: rect) {
                
                // Give the detected face image to the renderer.
                
                renderer.setCGImage(faceImage)
            }
        }
        else {
            detectedTrackingId = nil
        }
    }
    
    // Properties.
    
    private let renderer: Renderer
    
    private var camera: Video!
    
    private let detector: CIDetector
    private let detectorQueue: DispatchQueue

    private var detecting = false
    private let detectingQueue: DispatchQueue
    
    private var detectedTrackingId: Int32? = nil
    
    private let xAvg: RunningAverage<CGFloat>
    private let yAvg: RunningAverage<CGFloat>
    private let widthAvg: RunningAverage<CGFloat>
    private let heightAvg: RunningAverage<CGFloat>
}

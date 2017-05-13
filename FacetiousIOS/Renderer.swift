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

import GLKit
import OpenGLES
import SUtility
import SGL

// A class to initialize the rendering and render each frame.

class Renderer {
    init?(view: GLKView) {
        view.context = EAGLContext(api: EAGLRenderingAPI.openGLES3)
        EAGLContext.setCurrent(view.context)
        sharegroup = view.context.sharegroup
        
        guard initProgram() else {
            return nil
        }
        guard initTexture() else {
            return nil
        }
        guard initGeometry() else {
            return nil
        }
        initAnimation()
        
        // Use a default image until the camera and face tracker have found a face image.
        
        if let imagePath = Bundle.main.path(forResource: "defaultImage", ofType: "png") {
            warpingTexture.setAsync(filename: imagePath)
        }
    }

    // Used by VideoHandler.
    
    func setCGImage(_ image: CGImage) {
        self.warpingTexture.setAsync(cgImage: image)
    }
    
    // Render the current frame.
    
    func render(rect: CGRect, timeSinceLastDraw: TimeInterval, framesPerSecond: Int) {
        glClear(GLbitfield(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT))
        
        let aspect = Float(rect.width) / Float(rect.height)

        // For portrait mode, we want the field of view in the vertical direction to be pi / 4 
        // radians (45 degrees).
        
        var fovyRadians = Float.pi / 4
        if rect.width > rect.height {
            
            // So in landscape mode, scale this field of view down.
            
            fovyRadians = fovyRadians / aspect
        }
        
        // Build the projection matrix.
        
        let near: Float = 0.4
        let far: Float = 8.0
        let project = GLKMatrix4MakePerspective(fovyRadians, aspect, near, far)
        
        // Build the matrices for the animated rotation.
        
        animation.evaluate()
        if animation.finished() {
            initAnimation()
        }
        
        let rotX = GLKMatrix4MakeXRotation(xAngleRadians)
        let rotY = GLKMatrix4MakeYRotation(yAngleRadians)
        let rot = GLKMatrix4Multiply(rotY, rotX)
        
        // Build the model-view-projection matrix, and corresponsponding normal matrix, for the
        // warped-face surface.
        
        let warpingModel = rot
        
        let z: Float = -2.6
        let view = GLKMatrix4MakeTranslation(0, 0, z)
        
        let warpingModelView = GLKMatrix4Multiply(view, warpingModel)
        
        var invertible: Bool = true
        let warpingNormal = GLKMatrix3InvertAndTranspose(GLKMatrix4GetMatrix3(warpingModelView), &invertible)
        guard invertible else {
            print("render(): model-view matrix is not invertible")
            return
        }
        
        let warpingModelViewProj = GLKMatrix4Multiply(project, warpingModelView)

        // Pass the matrices to the variables connected to the warped-face vertex shader.
        
        warpingSurface.variables.modelViewProjMat.value = warpingModelViewProj
        warpingSurface.variables.normalMat.value = warpingNormal

        // For the "standard" (not warped) surface, the model matrix has an additional rotation to
        // put it on the other side of the warped-face surface.
        
        let standardRotX = GLKMatrix4MakeXRotation(GLfloat.pi)
        let standardRot = GLKMatrix4Multiply(rot, standardRotX)
        
        let standardModel = standardRot
        
        let standardModelView = GLKMatrix4Multiply(view, standardModel)
        
        invertible = true
        let standardNormal = GLKMatrix3InvertAndTranspose(GLKMatrix4GetMatrix3(standardModelView), &invertible)
        guard invertible else {
            print("render(): model-view matrix is not invertible")
            return
        }
        
        let standardModelViewProj = GLKMatrix4Multiply(project, standardModelView)
        
        // Pass the matrices to the "standard" vertex shader.
        
        standardSurface.variables.modelViewProjMat.value = standardModelViewProj
        standardSurface.variables.normalMat.value = standardNormal
        
        // Update the face-image texture if a new one has been loaded asynchronously, and bind
        // both textures.
        
        warpingTexture.swap()
        warpingTexture.bind()
        
        standardTexture.bind()
        
        // Use the appropriate shader program to draw the surfaces.
        
        if usePhongProgram {
            warpingPhongProgram.draw()
            standardPhongProgram.draw()
        } else {
            warpingSphericalHarmonicsProgram.draw()
            standardSphericalHarmonicsProgram.draw()
        }
    }
    
    // Access to the overall height scale, used by the gesture recognizer in the view controller.
    
    var heightScale: GLfloat {
        get {
            let shader = usePhongProgram ? warpingVertexShaderA! : warpingVertexShaderB!
            return shader.variablesWarping.heightScale.value
        }
        set(newValue) {
            let shader = usePhongProgram ? warpingVertexShaderA! : warpingVertexShaderB!
            shader.variablesWarping.heightScale.value = newValue
        }
    }
    
    // Create a "detour" animation to show the surfaces flipping around when changing between the
    // front and back cameras.
    
    func detour() {
        if let newAnimation = animation.detour(endMagnitude: 2 * Float.pi, duration: 1.0) {
            animation = newAnimation
        } else {
            let setX = { val in self.xAngleRadians = val }
            let segments = [Animation.Segment(val0: 0, val1: 2 * Float.pi, duration: 1, onEvaluate: setX)]
            animation = Animation(segments: segments, repeating: false)
        }
    }
    
    // Control over the shader program, used by the button in the view controller.
    
    func toggleShaderProgram() {
        if usePhongProgram {
            warpingPhongProgram.removeAllDrawables()
            standardPhongProgram.removeAllDrawables()
            guard warpingSphericalHarmonicsProgram.addDrawable(warpingSurface) else {
                print("Cannot add warping surface to spherical harmonics shader program")
                return
            }
            guard standardSphericalHarmonicsProgram.addDrawable(standardSurface) else {
                print("Cannot add standard surface to spherical harmonics shader program")
                return
            }
        } else {
            warpingSphericalHarmonicsProgram.removeAllDrawables()
            standardSphericalHarmonicsProgram.removeAllDrawables()
            guard warpingPhongProgram.addDrawable(warpingSurface) else {
                print("Cannot add warping surface to Phong shader program")
                return
            }
            guard standardPhongProgram.addDrawable(standardSurface) else {
                print("Cannot add standard surface to Phong shader program")
                return
            }
        }
        usePhongProgram = !usePhongProgram
    }
    
    // Reset to the default image and height scale, used by the gesture recognizer in the view
    // controller.
    
    func reset() {
        if let imagePath = Bundle.main.path(forResource: "defaultImage", ofType: "png") {
            warpingTexture.setAsync(filename: imagePath)
        }
        heightScale = LuminanceWarpingVertexShaderPNT.HeightScaleDefault
    }
    
    // Internal initalization routines.
    
    private func initProgram() -> Bool {
        glEnable(GLenum(GL_DEPTH_TEST));
        
        glEnable(GLenum(GL_CULL_FACE));
        glCullFace(GLenum(GL_BACK));
        
        glClearColor(0.4, 0.4, 0.5, 1.0)
        
        guard
            let wvsA = LuminanceWarpingVertexShaderPNT(),
            let svsA = BasicVertexShaderPNT(),
            let pfs1 = PhongOneDirectionalFragmentShaderPNT(),
            let pfs2 = PhongOneDirectionalFragmentShaderPNT(),
            let wpp = ShaderProgram<LuminanceWarpingVertexShaderPNT, PhongOneDirectionalFragmentShaderPNT, FlattishSquarePNT>(vertexShader: wvsA, fragmentShader: pfs1),
            let spp = ShaderProgram<BasicVertexShaderPNT, PhongOneDirectionalFragmentShaderPNT, FlattishSquarePNT>(vertexShader: svsA, fragmentShader: pfs2) else {
            return false
        }
        warpingVertexShaderA = wvsA
        standardVertexShaderA = svsA
        phongFragmentShader1 = pfs1
        phongFragmentShader2 = pfs2
        warpingPhongProgram = wpp
        standardPhongProgram = spp
 
        guard
            let wvsB = LuminanceWarpingVertexShaderPNT(),
            let svsB = BasicVertexShaderPNT(),
            let shfs1 = SphericalHarmonicsFragmentShaderPNT(),
            let shfs2 = SphericalHarmonicsFragmentShaderPNT(),
            let wshp = ShaderProgram<LuminanceWarpingVertexShaderPNT, SphericalHarmonicsFragmentShaderPNT, FlattishSquarePNT>(vertexShader: wvsB, fragmentShader: shfs1),
            let sshp = ShaderProgram<BasicVertexShaderPNT, SphericalHarmonicsFragmentShaderPNT, FlattishSquarePNT>(vertexShader: svsB, fragmentShader: shfs2) else {
                return false
        }
        warpingVertexShaderB = wvsB
        standardVertexShaderB = svsB
        sphericalHarmonicsFragmentShader1 = shfs1
        sphericalHarmonicsFragmentShader2 = shfs2
        warpingSphericalHarmonicsProgram = wshp
        standardSphericalHarmonicsProgram = sshp
        
        return true
    }
    
    private func initTexture() -> Bool {
        
        // Let the warped surface be black until the default image is loaded.
        
        let warpingData: [GLubyte] = [0, 0, 0, 255]

        warpingTexture = Texture(sharegroup: sharegroup, unit: GL_TEXTURE0)
        guard warpingTexture.set(data: warpingData, width: 1, height: 1, format: GL_RGBA) else {
            return false
        }
        
        // The "standard" surface behind the warped surface will remain white.

        let standardData: [GLubyte] = [255, 255, 255, 255]
        
        standardTexture = Texture(sharegroup: sharegroup, unit: GL_TEXTURE0)
        guard standardTexture.set(data: standardData, width: 1, height: 1, format: GL_RGBA) else {
            return false
        }

        return true
    }
    
    private func initGeometry() -> Bool {
        warpingSurface = FlattishSquarePNT(numVerticesX: 128, numVerticesY: 128, maxZ: 0, texture: warpingTexture)
        guard warpingSphericalHarmonicsProgram.addDrawable(warpingSurface) else {
            return false
        }
        
        // There is a small "bulge" in the surface behind the warped image, to make it more 
        // interesting.
        
        standardSurface = FlattishSquarePNT(numVerticesX: 128, numVerticesY: 128, maxZ: 0.5, texture: standardTexture)
        guard standardSphericalHarmonicsProgram.addDrawable(standardSurface) else {
            return false
        }

        return true
    }
    
    private func initAnimation() {
        let maxAngle = Float.pi / 4.0
        let halfDur: TimeInterval = 5
        let setX = { (val: Float) in
            self.xAngleRadians = val
            self.yAngleRadians = 0
        }
        let setY = { (val: Float) in
            self.xAngleRadians = 0
            self.yAngleRadians = val
        }
        
        // The animation turns left and right and back to the center, then nods up and down and
        // back to the center.
        
        let segments = [
            Animation.Segment(val0:         0, val1:  maxAngle, duration:     halfDur, onEvaluate: setX),
            Animation.Segment(val0:  maxAngle, val1: -maxAngle, duration: 2 * halfDur, onEvaluate: setX),
            Animation.Segment(val0: -maxAngle, val1:         0, duration:     halfDur, onEvaluate: setX),
            Animation.Segment(val0:         0, val1:  maxAngle, duration:     halfDur, onEvaluate: setY),
            Animation.Segment(val0:  maxAngle, val1: -maxAngle, duration: 2 * halfDur, onEvaluate: setY),
            Animation.Segment(val0: -maxAngle, val1:         0, duration:     halfDur, onEvaluate: setY)
        ]
        animation = Animation(segments: segments, t0: CACurrentMediaTime() + 1)
    }
    
    // Properties.
    
    private let sharegroup: EAGLSharegroup
        
    private var warpingVertexShaderA: LuminanceWarpingVertexShaderPNT!
    private var standardVertexShaderA: BasicVertexShaderPNT!

    private var phongFragmentShader1: PhongOneDirectionalFragmentShaderPNT!
    private var phongFragmentShader2: PhongOneDirectionalFragmentShaderPNT!
    
    private var warpingPhongProgram: ShaderProgram<LuminanceWarpingVertexShaderPNT, PhongOneDirectionalFragmentShaderPNT, FlattishSquarePNT>!
    private var standardPhongProgram: ShaderProgram<BasicVertexShaderPNT, PhongOneDirectionalFragmentShaderPNT, FlattishSquarePNT>!
    
    private var usePhongProgram: Bool = false
    
    private var warpingVertexShaderB: LuminanceWarpingVertexShaderPNT!
    private var standardVertexShaderB: BasicVertexShaderPNT!
    
    private var sphericalHarmonicsFragmentShader1: SphericalHarmonicsFragmentShaderPNT!
    private var sphericalHarmonicsFragmentShader2: SphericalHarmonicsFragmentShaderPNT!
    
    private var warpingSphericalHarmonicsProgram: ShaderProgram<LuminanceWarpingVertexShaderPNT, SphericalHarmonicsFragmentShaderPNT, FlattishSquarePNT>!
    private var standardSphericalHarmonicsProgram: ShaderProgram<BasicVertexShaderPNT, SphericalHarmonicsFragmentShaderPNT, FlattishSquarePNT>!
    
    private var warpingTexture: Texture!
    private var standardTexture: Texture!
    
    private var warpingSurface: FlattishSquarePNT!
    private var standardSurface: FlattishSquarePNT!
    
    private var animation: Animation!
    
    private var xAngleRadians: Float = 0.0
    private var yAngleRadians: Float = 0.0
}

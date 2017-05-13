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

import OpenGLES
import SGL

// A vertex shader, with associated Variables subclass, that takes a texture and warps the
// vertices into a height field (with normals), using the luminances from the texture as the 
// heights.

// The Variables subclass.

public class VariablesLuminanceWarping: Variables {
    
    // An overall scaling factor for the heights in the height field, to allow the user to 
    // drag the heights up and down.
    
    public let heightScale: Uniform1f

    public func connect(other: Variables, shaderProgram: GLuint) -> Bool {
        guard let otherWarping = other as? VariablesLuminanceWarping else {
            return false
        }
        guard heightScale.connect(other: otherWarping.heightScale, shaderProgram: shaderProgram) else {
                return false
        }
        return true
    }
    
    public func draw() {
        heightScale.draw()
    }
    
    fileprivate init(heightScaleName: String) {
        heightScale = Uniform1f(name: heightScaleName)
    }
}

// The vertex shader.

public class LuminanceWarpingVertexShaderPNT: VertexShading {
    public var id: GLuint {
        get {
            return shadingCore.id
        }
    }
    public let variables: VariablesPNT
    public let variablesWarping: VariablesLuminanceWarping
    
    // Limits of the overall scaling factoring for heights.
    
    public static let HeightScaleMin: GLfloat = 0.0
    public static let HeightScaleMax: GLfloat = 0.75
    public static let HeightScaleDefault: GLfloat = 0.5
    
    public init?() {
        guard let core = ShadingCore(shaderType: GLenum(GL_VERTEX_SHADER), shaderStr: vertexShaderStr) else {
            return nil
        }
        shadingCore = core
        variables = VariablesPNT.initForShading(positionName: "in_position", normalName: "in_normal", textureName: "in_texCoord", modelViewProjMatName: "modelViewProjMatrix", normalMatName: "normalMatrix")
        variablesWarping = VariablesLuminanceWarping(heightScaleName: "heightScale")

        variablesWarping.heightScale.value = LuminanceWarpingVertexShaderPNT.HeightScaleDefault
    }
    
    public func postLink(shaderProgram: GLuint) -> Bool {
        
        // Connect the warping variables to themselves to establish the OpenGL uniforms.
        
        return variablesWarping.connect(other: variablesWarping, shaderProgram: shaderProgram)
    }
    
    public func preDraw() {
        
        // Save the current texture wrapping settings so they can be changed and then restored
        // after drawing.
        
        glGetTexParameteriv(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_WRAP_S), &defaultTextureWrapS);
        glGetTexParameteriv(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_WRAP_T), &defaultTextureWrapT);
        
        // Gives a cleaner looking edge to the surface with the height field.
        
        glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_WRAP_S), GL_CLAMP_TO_EDGE);
        glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_WRAP_T), GL_CLAMP_TO_EDGE);
        
        variablesWarping.draw()
    }
    
    public func postDraw() {
        glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_WRAP_S), defaultTextureWrapS);
        glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_WRAP_T), defaultTextureWrapT);
    }
    
    private let shadingCore: ShadingCore
    private let vertexShaderStr = "#version 300 es\n" +
        "uniform mat4 modelViewProjMatrix;\n" +
        "uniform mat3 normalMatrix;\n" +
        "// The texture to use when computing the luminance-based height.\n" +
        "uniform sampler2D tex;\n" +
        "// An overall scaling factor for the luminance-based height.\n" +
        "uniform float heightScale;\n" +
        "in vec4 in_position;\n" +
        "in vec3 in_normal;\n" +
        "in vec2 in_texCoord;\n" +
        "out vec2 vs_texCoord;\n" +
        "out vec3 vs_normal;\n" +
        "#define luminance(t) 0.2126 * t.r + 0.7152 * t.g + 0.0722 * t.b\n" +
        "// Macros to allow averaging of texels in a 4 x 4 region.  The lower frequency of the \n" +
        "// averaged texels makes a nicer, less chaotic looking height field. \n" +
        "#define to(iv) textureOffset(tex, in_texCoord, iv)\n" +
        "#define iv2(x, y) ivec2(x, y)\n" +
        "#define texAvg(iv) (to(iv) + to(iv + iv2(0,1)) + to(iv + iv2(0,2)) + to(iv + iv2(0,3)) +" +
        "                    to(iv + iv2(1,0)) + to(iv + iv2(1,1)) + to(iv + iv2(1,2)) + to(iv + iv2(1,3)) +" +
        "                    to(iv + iv2(2,0)) + to(iv + iv2(2,1)) + to(iv + iv2(2,2)) + to(iv + iv2(2,3)) +" +
        "                    to(iv + iv2(3,0)) + to(iv + iv2(3,1)) + to(iv + iv2(3,2)) + to(iv + iv2(3,3))) / 16.0\n" +
        "void main()\n" +
        "{\n" +
        "    vec4 t = texAvg(ivec2(0, 0));\n" +
        "    // Compute height, h, as the luminance from the texture at this vertex.\n" +
        "    float h = luminance(t);\n" +
        "    // For the normal, compute the heights using the adjacent texels.\n" +
        "    vec4 tdx = texAvg(ivec2(4, 0));\n" +
        "    float hdx = luminance(tdx);\n" +
        "    vec4 tdy = texAvg(ivec2(0, 4));\n" +
        "    float hdy = luminance(tdy);\n" +
        "    // Compute a weight, w, that drops to 0 at the edges of the surface.\n" +
        "    float w = min(in_texCoord.s / 0.1, 1.0);\n" +
        "    w *= min((1.0 - in_texCoord.s) / 0.1, 1.0);\n" +
        "    w *= min(in_texCoord.t / 0.1, 1.0);\n" +
        "    w *= min((1.0 - in_texCoord.t) / 0.1, 1.0);\n" +
        "    // Include an overall scaling for the height.\n" +
        "    w *= heightScale;\n" +
        "    h *= w;\n" +
        "    hdx *= w;\n" +
        "    hdy *= w;\n" +
        "    vec4 v = in_position;\n" +
        "    v.z += h;\n" +
        "    gl_Position = modelViewProjMatrix * v;\n" +
        "    vs_texCoord = in_texCoord;\n" +
        "    // We cannot know exactly how far the adjacent pixels are in X and Y, so use an\n" +
        "    // approximation of the texel width and height based on texel density.\n" +
        "    ivec2 textureWidth = textureSize(tex, 0);\n" +
        "    float texelWidthS = 1.0 / float(textureWidth.s);\n" +
        "    float texelWidthT = 1.0 / float(textureWidth.t);\n" +
        "    vec3 dx = vec3(texelWidthS, 0, hdx - h);\n" +
        "    vec3 dy = vec3(0, texelWidthT, hdy - h);\n" +
        "    vec3 n = cross(dx, dy);\n" +
        "    // VariablesPNT expects in_normal to be used, even though\n" +
        "    // this shader is unusual in that it does not need it.\n" +
        "    vs_normal = in_normal;\n" +
        "    vs_normal = normalize(normalMatrix * n);\n" +
        "}\n";

    
    private var defaultTextureWrapS: GLint = GL_REPEAT
    private var defaultTextureWrapT: GLint = GL_REPEAT
}


import Foundation
import MetalKit
import ARKit
import simd

public class HitTestResult {
    var node: Node

    var localCoordinates: SIMD3<Float>

    var worldCoordinates: SIMD3<Float>
    
    public init(node: Node, localCoordinates: SIMD3<Float>) {
        self.node = node
        self.localCoordinates = localCoordinates
        self.worldCoordinates = localCoordinates
    }
}

fileprivate struct InstanceUniforms {
    var modelMatrix = matrix_identity_float4x4
    var normalMatrix = matrix_identity_float3x3
}

fileprivate struct FrameUniforms {
    var viewMatrix = matrix_identity_float4x4
    var viewProjectionMatrix = matrix_identity_float4x4
}

public class SceneRenderer {
    public let device: MTLDevice
    
    private let commandQueue: MTLCommandQueue
    private let bufferAllocator: BufferAllocator
    private let shaderManager: ShaderManager
    private let textureCache: CVMetalTextureCache
    
    private let quadDepthStencilState: MTLDepthStencilState
    private let sceneDepthStencilState: MTLDepthStencilState
    private let textureLoader: MTKTextureLoader

    public var scene: Scene?
    public var pointOfView: Node?
    public var interfaceOrientation: UIInterfaceOrientation = .portrait
    public var currentFrame: ARFrame?
    public var drawableSize = CGSize(width: 1, height: 1)
    
    private var commandBuffer: MTLCommandBuffer!
    private var renderCommandEncoder: MTLRenderCommandEncoder!
    private var instanceUniformBuffer: MTLBuffer!
    private var instanceUniformBufferOffset: Int = 0

    public init(device: MTLDevice) {
        self.device = device
        
        commandQueue = device.makeCommandQueue()!
        bufferAllocator = BufferAllocator(device: device)
        shaderManager = ShaderManager(device: device)
        
        var textureCache: CVMetalTextureCache? = nil
        CVMetalTextureCacheCreate(nil, nil, device, nil, &textureCache)
        self.textureCache = textureCache!
        
        textureLoader = MTKTextureLoader(device: device)
        sceneDepthStencilState = SceneRenderer.makeDepthStencilState(device: device, depthReadEnabled: true, depthWriteEnabled: true)
        quadDepthStencilState = SceneRenderer.makeDepthStencilState(device: device, depthReadEnabled: false, depthWriteEnabled: false)
    }

    public func beginFrame() {
        commandBuffer = commandQueue.makeCommandBuffer()
        
        instanceUniformBuffer = bufferAllocator.dequeueReusableBuffer(length: 64 * 256)

        instanceUniformBufferOffset = 0
    }
    
    public func endFrame() {
        let uniformBuffer: MTLBuffer = instanceUniformBuffer
        
       commandBuffer.addScheduledHandler { _ in
            self.bufferAllocator.enqueueReusableBuffer(uniformBuffer)
        }

        commandBuffer.commit()
    }
    
    public func visibleNodes(in scene: Scene, from pointOfView: Node) -> [Node] {
        var nodes = [Node]()
        var queue = [scene.rootNode]
        while queue.count > 0 {
            let node = queue.removeFirst()
            if node.geometry != nil {
                nodes.append(node)
            }
            queue.append(contentsOf: node.childNodes)
        }
        return nodes
    }
    
    private static func makeDepthStencilState(device: MTLDevice, depthReadEnabled: Bool, depthWriteEnabled: Bool) -> MTLDepthStencilState {
        let descriptor = MTLDepthStencilDescriptor()
        descriptor.isDepthWriteEnabled = depthWriteEnabled
        descriptor.depthCompareFunction = depthReadEnabled ? .less : .always
        return device.makeDepthStencilState(descriptor: descriptor)!
    }
    
    private func drawVideoQuad(_ frame: ARFrame, viewportSize: CGSize, pass: MTLRenderPassDescriptor) {
        let pixelBuffer = frame.capturedImage

        var lumaTexture: CVMetalTexture? = nil
        let lumaWidth = CVPixelBufferGetWidthOfPlane(pixelBuffer, 0)
        let lumaHeight = CVPixelBufferGetHeightOfPlane(pixelBuffer, 0)
        CVMetalTextureCacheCreateTextureFromImage(nil, textureCache, pixelBuffer, nil, .r8Unorm, lumaWidth, lumaHeight, 0, &lumaTexture)

        var chromaTexture: CVMetalTexture? = nil
        let chromaWidth = CVPixelBufferGetWidthOfPlane(pixelBuffer, 1)
        let chromaHeight = CVPixelBufferGetHeightOfPlane(pixelBuffer, 1)
        CVMetalTextureCacheCreateTextureFromImage(nil, textureCache, pixelBuffer, nil, .rg8Unorm, chromaWidth, chromaHeight, 1, &chromaTexture)

        if let luma = lumaTexture, let chroma = chromaTexture {
            let renderPipelineState = shaderManager.pipelineStateForFullscreenQuad(pass: pass)
            renderCommandEncoder.setRenderPipelineState(renderPipelineState)

            renderCommandEncoder.setFragmentTexture(CVMetalTextureGetTexture(luma), index: 0)
            renderCommandEncoder.setFragmentTexture(CVMetalTextureGetTexture(chroma), index: 1)
            
            let vertices: [Float] = [
              // x   y  s  t
                -1, -1, 0, 1, // bottom left
                -1,  1, 0, 0, // top left
                 1, -1, 1, 1, // bottom right
                 1,  1, 1, 0, // top right
            ]
            
            renderCommandEncoder.setVertexBytes(vertices, length: MemoryLayout<Float>.size * 16, index: 0)
            
            let transform = frame.displayTransform(for: interfaceOrientation, viewportSize: viewportSize)
            var transformMatrix = float3x3(affineTransform: transform).inverse
            
            renderCommandEncoder.setVertexBytes(&transformMatrix, length: MemoryLayout.size(ofValue: transformMatrix), index: 1)
            
            renderCommandEncoder.setDepthStencilState(quadDepthStencilState)

            renderCommandEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        }
    }
    
    private func textureForImage(_ cgImage: CGImage) -> MTLTexture? {
        let options: [MTKTextureLoader.Option : Any] = [ .generateMipmaps : true ]
        do {
            return try textureLoader.newTexture(cgImage: cgImage, options: options)
        } catch {
            print("Error loading texture from CGImage: \(error)")
            return nil
        }
    }
    
    private func textureForSolidColor(_ color: CGColor) -> MTLTexture? {
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        let bitmapInfo = UInt32(CGImageAlphaInfo.premultipliedLast.rawValue)
        let context = CGContext(data: nil,
                                width: 1,
                                height: 1,
                                bitsPerComponent: 8,
                                bytesPerRow: 4,
                                space: colorSpace,
                                bitmapInfo: bitmapInfo)
        context?.setFillColor(color)
        context?.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: 1, height: 1, mipmapped: false)
        let texture = device.makeTexture(descriptor: descriptor)!
        if let imageData = context?.makeImage()?.dataProvider?.data, let bytes = CFDataGetBytePtr(imageData) {
            texture.replace(region: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0, withBytes: bytes, bytesPerRow: 4)
        }
        return texture
    }
    
    private func textureForFloat(_ value: Float) -> MTLTexture? {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: 1, height: 1, mipmapped: false)
        let texture = device.makeTexture(descriptor: descriptor)!
        let byte = UInt8(value * 255)
        let componentBytes = [ byte, byte, byte, byte ]
        texture.replace(region: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0, withBytes: componentBytes, bytesPerRow: 4)
        return texture
    }

    private func textureForMaterialProperty(_ property: MaterialProperty) -> MTLTexture? {
        if property.contents == nil { return nil }
        
        if property.cachedTexture != nil { return property.cachedTexture }
        
        if let textureContents = property.contents as? MTLTexture {
            property.cachedTexture = textureContents
        } else if let imageName = property.contents as? String {
            if let image = UIImage(named: imageName)?.cgImage {
                property.cachedTexture = textureForImage(image)
            }
        } else if let uiColor = property.contents as? UIColor {
            property.cachedTexture = textureForSolidColor(uiColor.cgColor)
        } else if (CFGetTypeID(property.contents as CFTypeRef) == CGColor.typeID) {
            let colorContents = property.contents as! CGColor
            property.cachedTexture = textureForSolidColor(colorContents)
        } else if let floatContents = property.contents as? Float {
            property.cachedTexture = textureForFloat(floatContents)
        } else {
            fatalError("Couldn't understand type of material property contents \(String(describing: property.contents))")
        }
        
        if property.cachedTexture == nil {
            property.cachedTexture = textureForFloat(0.0)
        }
        
        return property.cachedTexture
    }

    private func drawNode(_ node: Node, viewMatrix: float4x4, pass: MTLRenderPassDescriptor) {
        guard let geometry = node.geometry else { return }
        
        let renderPipelineState = shaderManager.pipelineState(for: geometry, pass: pass)
        
        renderCommandEncoder.setRenderPipelineState(renderPipelineState)
        
        for (index, buffer) in geometry.buffers.enumerated() {
            renderCommandEncoder.setVertexBuffer(buffer, offset: 0, index: index)
        }

        var instanceUniforms = InstanceUniforms()
        instanceUniforms.modelMatrix = node.worldTransform.matrix
        instanceUniforms.normalMatrix = (viewMatrix.upperLeft * instanceUniforms.modelMatrix.upperLeft).transpose.inverse

        let uniformPtr = instanceUniformBuffer.contents().advanced(by: instanceUniformBufferOffset).assumingMemoryBound(to: InstanceUniforms.self)
        uniformPtr.pointee = instanceUniforms
        renderCommandEncoder.setVertexBuffer(instanceUniformBuffer, offset: instanceUniformBufferOffset, index: Material.BufferIndex.instanceUniforms)
        instanceUniformBufferOffset += 256

        renderCommandEncoder.setDepthStencilState(sceneDepthStencilState)

        for element in geometry.elements {
            let material = element.material
            
            renderCommandEncoder.setTriangleFillMode(material.fillMode == .solid ? .fill : .lines)
            
            renderCommandEncoder.setFragmentTexture(textureForMaterialProperty(material.diffuse), index: Material.TextureIndex.diffuse)
            renderCommandEncoder.setFragmentTexture(textureForMaterialProperty(material.normal), index: Material.TextureIndex.normal)
            renderCommandEncoder.setFragmentTexture(textureForMaterialProperty(material.emissive), index: Material.TextureIndex.emissive)
//            renderCommandEncoder.setFragmentTexture(textureForMaterialProperty(material.metalness), index: Material.TextureIndex.metalness)
//            renderCommandEncoder.setFragmentTexture(textureForMaterialProperty(material.roughness), index: Material.TextureIndex.roughness)
//            renderCommandEncoder.setFragmentTexture(textureForMaterialProperty(material.occlusion), index: Material.TextureIndex.occlusion)

            renderCommandEncoder.drawIndexedPrimitives(type: element.primitiveType, indexCount: element.indexCount,
                                                       indexType: element.indexType, indexBuffer: element.indexBuffer,
                                                       indexBufferOffset: element.indexBufferOffset)
        }
    }

    public func draw(in view: MTKView, completion: (() -> Void)?) {
        beginFrame()

        guard let scene = scene, let pointOfView = pointOfView, let camera = pointOfView.camera else { return }

        if let frameCamera = currentFrame?.camera {
            let cameraTransform = frameCamera.viewMatrix(for: interfaceOrientation)
            pointOfView.transform = Transform(from: cameraTransform)
            pointOfView.camera?.projectionTransform = frameCamera.projectionMatrix(for: interfaceOrientation,
                                                                                   viewportSize: view.bounds.size,
                                                                                   zNear: 0.01, zFar: 100)
        }

        guard let pass = view.currentRenderPassDescriptor else { return }
        renderCommandEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass)!
            
        if let frame = currentFrame {
            drawVideoQuad(frame, viewportSize: view.bounds.size, pass: pass)
        }
        
        let viewMatrix = pointOfView.worldTransform.matrix
        let projectionMatrix = camera.projectionTransform
        
        var frameUniforms = FrameUniforms()
        frameUniforms.viewMatrix = viewMatrix
        frameUniforms.viewProjectionMatrix = projectionMatrix * viewMatrix
        renderCommandEncoder.setVertexBytes(&frameUniforms, length: MemoryLayout.size(ofValue: frameUniforms), index: Material.BufferIndex.frameUniforms)

        let nodes = visibleNodes(in: scene, from: pointOfView)
        for node in nodes {
            drawNode(node, viewMatrix: viewMatrix, pass: pass)
        }

        renderCommandEncoder.endEncoding()

        guard let drawable = view.currentDrawable else { return }
        commandBuffer.present(drawable)

        endFrame()
    }
    
    public func hitTest(_ point: SIMD2<Float>) -> [HitTestResult] {
        return []
    }
    
    public func isNode(_ node: Node, insideFrustumOf pointOfView: Node) -> Bool {
        return true
    }
    
    public func nodesInsideFrustum(of pointOfView: Node) -> [Node] {
        return []
    }
    
    public func projectPoint(_ point: SIMD3<Float>) -> SIMD3<Float> {
        guard let frameCamera = currentFrame?.camera else { return point }
        let viewMatrix: matrix_float4x4 = frameCamera.viewMatrix(for: interfaceOrientation)
        let projectionMatrix: matrix_float4x4 = frameCamera.projectionMatrix(for: interfaceOrientation,
                                                                             viewportSize: drawableSize, zNear: 0.01, zFar: 100)
        let viewProjectionMatrix = projectionMatrix * viewMatrix
        return (viewProjectionMatrix * SIMD4<Float>(point, 1)).xyz
    }
    
    public func unprojectPoint(_ point: SIMD3<Float>) -> SIMD3<Float> {
        return SIMD3<Float>(repeating: 0)
    }
}

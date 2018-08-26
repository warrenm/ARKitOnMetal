
import Foundation
import Metal
import simd

public class Sphere : Geometry {
    struct Vertex {
        var position: packed_float3
        var normal: packed_float3
        var texCoords: packed_float2
    }
    
    public init(radius: Float, segments: Int, bufferAllocator: BufferAllocator) {
        let vertexCount = segments * segments
        let indexCount = segments * (segments + 1) * 6

        let vertexBuffer = bufferAllocator.makeBuffer(length: MemoryLayout<Vertex>.stride * vertexCount)
        let indexBuffer = bufferAllocator.makeBuffer(length: MemoryLayout<UInt32>.stride * indexCount)
        
        let vertices = vertexBuffer.contents().assumingMemoryBound(to: Vertex.self)
        let indices = indexBuffer.contents().assumingMemoryBound(to: UInt32.self)
        
        let deltaPhi = .pi / Float(segments)
        let deltaTheta = 2 * .pi / Float(segments)
        var phi = Float.pi / 2
        var i = 0
        for _ in 0...segments
        {
            var theta: Float = 0
            for slice in 0...segments
            {
                let x = cos(theta) * cos(phi)
                let y = sin(phi)
                let z = sin(theta) * cos(phi)

                vertices[i].position = packed_float3(radius * x, radius * y, radius * z)
                vertices[i].normal = packed_float3(x, y, z)
                vertices[i].texCoords = packed_float2(1 - Float(slice) / Float(segments), 1 - (sin(phi) + 1) * 0.5)

                i += 1
                
                theta += deltaTheta
            }
            
            phi += deltaPhi
        }
        
        i = 0
        for stack in 0...segments
        {
            for slice in 0..<segments
            {
                let i0 = UInt32(slice + stack * segments)
                let i1 = i0 + 1
                let i2 = i0 + UInt32(segments)
                let i3 = i2 + 1
                
                indices[i] = i0; i += 1
                indices[i] = i2; i += 1
                indices[i] = i3; i += 1
                indices[i] = i0; i += 1
                indices[i] = i3; i += 1
                indices[i] = i1; i += 1
            }
        }
        
        let descriptor = MTLVertexDescriptor()
        let bufferIndex = 0
        descriptor.attributes[Material.AttributeIndex.position].bufferIndex = bufferIndex
        descriptor.attributes[Material.AttributeIndex.position].format = .float3
        descriptor.attributes[Material.AttributeIndex.position].offset = 0

        descriptor.attributes[Material.AttributeIndex.normal].bufferIndex = bufferIndex
        descriptor.attributes[Material.AttributeIndex.normal].format = .float3
        descriptor.attributes[Material.AttributeIndex.normal].offset = MemoryLayout<Float>.stride * 3

        descriptor.attributes[Material.AttributeIndex.texCoords].bufferIndex = bufferIndex
        descriptor.attributes[Material.AttributeIndex.texCoords].format = .float2
        descriptor.attributes[Material.AttributeIndex.texCoords].offset = MemoryLayout<Float>.stride * 6

        descriptor.layouts[bufferIndex].stepFunction = .perVertex
        descriptor.layouts[bufferIndex].stepRate = 1
        descriptor.layouts[bufferIndex].stride = MemoryLayout<Vertex>.stride

        let indexSource = GeometryElement(indexBuffer: indexBuffer, primitiveType: .triangle, indexCount: indexCount, indexType: .uint32)

        super.init(buffers: [vertexBuffer], elements: [indexSource], vertexDescriptor: descriptor)
    }
}

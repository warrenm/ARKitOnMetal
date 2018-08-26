
import Foundation
import ARKit
import simd

public class PointCloud : Geometry {

    public init(pointCloud: ARPointCloud, bufferAllocator: BufferAllocator) {
        let vertexCount = pointCloud.points.count
        let indexCount = vertexCount

        let vertexBuffer = bufferAllocator.makeBuffer(length: MemoryLayout<float4>.stride * vertexCount)
        let vertices = vertexBuffer.contents().assumingMemoryBound(to: float4.self)
        
        let indexBuffer = bufferAllocator.makeBuffer(length: MemoryLayout<UInt32>.stride * indexCount)
        let indices = indexBuffer.contents().assumingMemoryBound(to: UInt32.self)

        for (index, position) in pointCloud.points.enumerated() {
            vertices[index] = float4(position.x, position.y, position.z, 1)
            indices[index] = UInt32(index)
        }

        let element = GeometryElement(indexBuffer: indexBuffer,
                                      primitiveType: .point,
                                      indexCount: indexCount,
                                      indexType: .uint32)
        
        let descriptor = MTLVertexDescriptor()
        let bufferIndex = 0
        descriptor.attributes[Material.AttributeIndex.position].bufferIndex = bufferIndex
        descriptor.attributes[Material.AttributeIndex.position].format = .float3
        descriptor.attributes[Material.AttributeIndex.position].offset = 0
        
//        descriptor.attributes[Material.AttributeIndex.normal].bufferIndex = bufferIndex
//        descriptor.attributes[Material.AttributeIndex.normal].format = .float3
//        descriptor.attributes[Material.AttributeIndex.normal].offset = MemoryLayout<Float>.stride * 3
        
//        descriptor.attributes[Material.AttributeIndex.texCoords].bufferIndex = bufferIndex
//        descriptor.attributes[Material.AttributeIndex.texCoords].format = .float2
//        descriptor.attributes[Material.AttributeIndex.texCoords].offset = MemoryLayout<Float>.stride * 6
        
        descriptor.layouts[bufferIndex].stepFunction = .perVertex
        descriptor.layouts[bufferIndex].stepRate = 1
        descriptor.layouts[bufferIndex].stride = MemoryLayout<float4>.stride

        super.init(buffers: [vertexBuffer], elements: [element], vertexDescriptor: descriptor)
    }
}

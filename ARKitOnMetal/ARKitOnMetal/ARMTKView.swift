
import Foundation
import MetalKit
import ARKit

public class ARMTKView : MTKView, ARSessionDelegate {

    public struct DebugOptions: OptionSet {
        static let showFeaturePoints = DebugOptions(rawValue: 1)
        static let showWorldAxes = DebugOptions(rawValue: 2)

        public let rawValue: Int

        public init(rawValue: Int) {
            self.rawValue = rawValue
        }
    }

    public var rendererDelegate: ARMTKViewDelegate?
    public var session: ARSession
    public var scene = Scene()
    public var automaticallyUpdatesLighting = true
    public var debugOptions: DebugOptions = [.showFeaturePoints, .showWorldAxes]

    private let worldAxisNode = Node()
    private let pointCloudNode = Node()

    private var renderer: SceneRenderer
    private let bufferAllocator: BufferAllocator
    private var anchorsForNodes: [UUID : ARAnchor] = [:]
    private var nodesForAnchors: [UUID: Node] = [:]
    
    override public var drawableSize: CGSize {
        didSet {
            renderer.drawableSize = drawableSize
        }
    }

    public override required init(frame frameRect: CGRect, device: MTLDevice?) {
        let device = device ?? MTLCreateSystemDefaultDevice()!
        bufferAllocator = BufferAllocator(device: device)
        renderer = SceneRenderer(device: device)
        session = ARSession()
        
        super.init(frame: frameRect, device: device)
        
        session.delegate = self
        configureDefaultScene()
    }

    public required init(coder: NSCoder) {
        fatalError("ARMTKView does not support coding")
    }
    
    private func configureDefaultScene() {
        let cameraNode = Node()
        cameraNode.camera = Camera()

        scene.rootNode.addChildNode(worldAxisNode)
        scene.rootNode.addChildNode(pointCloudNode)

        renderer.scene = scene
        renderer.pointOfView = cameraNode
    }

    public func anchor(forNode node: Node) -> ARAnchor? {
        return anchorsForNodes[node.identifier]
    }
    
    public func node(forAnchor anchor: ARAnchor) -> Node? {
        return nodesForAnchors[anchor.identifier]
    }
    
    public func hitTest(_ point: CGPoint, types: ARHitTestResult.ResultType) -> [ARHitTestResult] {
        if let frame = session.currentFrame {
            let unitPoint = CGPoint(x: point.x / bounds.width, y: point.y / bounds.height)
            let transform = frame.displayTransform(for: renderer.interfaceOrientation, viewportSize: bounds.size)
            let frameUnitPoint = unitPoint.applying(transform.inverted())
            return frame.hitTest(frameUnitPoint, types:types)
        }
        return []
    }
    
    public override func draw(_ rect: CGRect) {
        renderer.draw(in: self, completion: {
        })
    }
    
    public func session(_ session: ARSession, didUpdate frame: ARFrame) {
        if #available(iOS 13.0, *) {
            guard case renderer.interfaceOrientation = UIApplication.shared.windows.first?.windowScene?.interfaceOrientation else {
                return
            }
        } else {
            renderer.interfaceOrientation = UIApplication.shared.statusBarOrientation
        }
        
        renderer.currentFrame = frame

        /*
        // Not currently supported. Need an alternative material shader that doesn't require normals and tex coords
        if debugOptions.contains(.showFeaturePoints) {
            if let featurePoints = frame.rawFeaturePoints {
                pointCloudNode.geometry = PointCloud(pointCloud: featurePoints, bufferAllocator: bufferAllocator)
            }
        }
         */
    }
    
    public func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
        for anchor in anchors {
            let node = rendererDelegate?.renderer(renderer, nodeForAnchor: anchor) ?? Node()
            anchorsForNodes[node.identifier] = anchor
            nodesForAnchors[anchor.identifier] = node
            node.transform = Transform(from: anchor.transform)
            scene.rootNode.addChildNode(node)
            rendererDelegate?.renderer(renderer, didAddNode: node, forAnchor: anchor)
        }
    }
    
    public func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        for anchor in anchors {
            if let node = node(forAnchor: anchor) {
                rendererDelegate?.renderer(renderer, willUpdateNode: node, forAnchor: anchor)
                node.transform = Transform(from: anchor.transform)
                rendererDelegate?.renderer(renderer, didUpdateNode: node, forAnchor: anchor)
            }
        }
    }
    
    public func session(_ session: ARSession, didRemove anchors: [ARAnchor]) {
        for anchor in anchors {
            if let node = node(forAnchor: anchor) {
                node.removeFromParentNode()
                anchorsForNodes[node.identifier] = nil
                nodesForAnchors[anchor.identifier] = nil
                rendererDelegate?.renderer(renderer, didRemoveNode: node, forAnchor: anchor)
            }
        }
    }

    public func session(_ session: ARSession, didFailWithError error: Error) {
        rendererDelegate?.session?(session, didFailWithError: error)
    }
    
    public func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
        rendererDelegate?.session?(session, cameraDidChangeTrackingState: camera)
    }
    
    public func sessionWasInterrupted(_ session: ARSession) {
        rendererDelegate?.sessionWasInterrupted?(session)
    }
    
    public func sessionInterruptionEnded(_ session: ARSession) {
        rendererDelegate?.sessionInterruptionEnded?(session)
    }
}

public protocol ARMTKViewDelegate: ARSessionObserver {
    /// Implement this to provide a custom node for the given anchor. If this method is
    /// not implemented, a node will be created automatically. If this method returns nil,
    /// the anchor will be ignored.
    func renderer(_: SceneRenderer, nodeForAnchor: ARAnchor) -> Node?
    
    /// Notifies the delegate that a node was added for an anchor
    func renderer(_: SceneRenderer, didAddNode: Node, forAnchor: ARAnchor)
    
    /// Notifies the delegate that the renderer will update the node corresponding to an anchor
    func renderer(_: SceneRenderer, willUpdateNode: Node, forAnchor: ARAnchor)
    
    /// Notifies the delegate that the renderer did update the node corresponding to an anchor
    func renderer(_: SceneRenderer, didUpdateNode: Node, forAnchor: ARAnchor)
    
    /// Notifies the delegate that the renderer did remove the node corresponding to an anchor
    func renderer(_: SceneRenderer, didRemoveNode: Node, forAnchor: ARAnchor)
}

public extension ARMTKViewDelegate {
    func renderer(_: SceneRenderer, nodeForAnchor anchor: ARAnchor) -> Node? {
        let node = Node()
        node.transform = Transform(from: anchor.transform)
        return node
    }

    func renderer(_: SceneRenderer, didAddNode: Node, forAnchor: ARAnchor) {}

    func renderer(_: SceneRenderer, willUpdateNode: Node, forAnchor: ARAnchor) {}

    func renderer(_: SceneRenderer, didUpdateNode: Node, forAnchor: ARAnchor) {}

    func renderer(_: SceneRenderer, didRemoveNode: Node, forAnchor: ARAnchor) {}
}

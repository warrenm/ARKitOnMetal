
import UIKit
import ARKit
import MetalKit

class ViewController: UIViewController, ARMTKViewDelegate {
    
    var device: MTLDevice!
    var bufferAllocator: BufferAllocator!
    var arView: ARMTKView!
    var trackingStatusLabel: UILabel!
    var tapRecognizer: UITapGestureRecognizer!
    var modelGeometry: Geometry?

    override func viewDidLoad() {
        super.viewDidLoad()
        
        if let defaultDevice = MTLCreateSystemDefaultDevice() {
            device = defaultDevice
        } else {
            fatalError("Metal is not supported on this target.")
        }
        
        bufferAllocator = BufferAllocator(device: device)

        arView = ARMTKView(frame: view.bounds, device: device)
        arView.colorPixelFormat = .bgra8Unorm
        arView.depthStencilPixelFormat = .depth32Float
        arView.rendererDelegate = self

        arView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(arView)
        
        tapRecognizer = UITapGestureRecognizer(target: self, action: #selector(tapGestureDidRecognize))
        arView.addGestureRecognizer(tapRecognizer)
        
        let assetURL = Bundle.main.url(forResource: "animated_humanoid_robot", withExtension: "obj")!
        modelGeometry = Geometry(url: assetURL, bufferAllocator: bufferAllocator)
    }
    
    override func viewDidAppear(_ animated: Bool) {
        let sessionConfiguration = ARWorldTrackingConfiguration()
        sessionConfiguration.planeDetection = .horizontal
        arView.session.run(sessionConfiguration, options: [.resetTracking])
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        arView.session.pause()
    }
    
    func renderer(_: SceneRenderer, didAddNode node: Node, forAnchor anchor: ARAnchor) {
        if let planeAnchor = anchor as? ARPlaneAnchor {
            node.geometry = Plane(center: planeAnchor.center, width: planeAnchor.extent.x, depth: planeAnchor.extent.z, segments: 20, bufferAllocator: bufferAllocator)
            
            let material = node.geometry?.elements.first?.material
            material?.diffuse.contents = UIColor.white
            material?.fillMode = .wireframe
        } else {
            let geometryNode = Node(geometry: modelGeometry)
            geometryNode.transform.scale = SIMD3<Float>(repeating: 0.04)
            node.addChildNode(geometryNode)
        }
    }
    
    func renderer(_: SceneRenderer, didUpdateNode node: Node, forAnchor anchor: ARAnchor) {
        if let planeAnchor = anchor as? ARPlaneAnchor {
            node.geometry = Plane(center: planeAnchor.center, width: planeAnchor.extent.x, depth: planeAnchor.extent.z, segments: 20, bufferAllocator: bufferAllocator)
            
            let material = node.geometry?.elements.first?.material
            material?.diffuse.contents = UIColor.white
            material?.fillMode = .wireframe
        }
    }

    func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
        if trackingStatusLabel == nil {
            trackingStatusLabel = UILabel()
            trackingStatusLabel.translatesAutoresizingMaskIntoConstraints = false
            trackingStatusLabel.textAlignment = .center
            trackingStatusLabel.backgroundColor = UIColor(white: 0.0, alpha: 0.2)
            trackingStatusLabel.textColor = UIColor.white
            trackingStatusLabel.font = UIFont.boldSystemFont(ofSize: 16)
            trackingStatusLabel.numberOfLines = 2
            view.addSubview(trackingStatusLabel)
            view.addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "|-(20)-[label]-(20)-|", options: [], metrics: nil,
                                                               views: ["label" : trackingStatusLabel!]))
            view.addConstraint(NSLayoutConstraint(item: trackingStatusLabel!, attribute: .top, relatedBy: .equal,
                                                  toItem: view.safeAreaLayoutGuide, attribute: .top, multiplier: 1, constant: 20))
        }
        
        trackingStatusLabel.isHidden = false
        
        switch camera.trackingState {
        case .normal:
            trackingStatusLabel.isHidden = true
        case .notAvailable:
            trackingStatusLabel.text = "Tracking is not available"
        case .limited(let reason):
            switch reason {
            case .initializing:
                trackingStatusLabel.text = "Tracking is limited:\nInitializing"
            case .excessiveMotion:
                trackingStatusLabel.text = "Tracking is limited:\nExcessive motion"
            case .insufficientFeatures:
                trackingStatusLabel.text = "Tracking is limited:\nInsufficient features"
            case .relocalizing:
                trackingStatusLabel.text = "Tracking is limited:\nRelocalizing..."
            @unknown default:
                fatalError()
            }
        }
    }
    
    @objc func tapGestureDidRecognize(_ sender: UIGestureRecognizer) {
        let session = arView.session
//        if let currentFrame = session.currentFrame {
            if let firstHit = arView.hitTest(sender.location(in: arView), types: [.estimatedHorizontalPlane]).first {
//            let position = float3(0, 0, -0.5) // 50 centimeters in front of camera
//            let translation = float4x4(translationBy: position)
//            let transform = currentFrame.camera.transform * translation
                let anchor = ARAnchor(transform: firstHit.worldTransform)
                session.add(anchor: anchor)
            }
//        }
    }
}

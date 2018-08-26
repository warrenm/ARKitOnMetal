
import UIKit
import ARKit

class SphereAnchor : ARAnchor {
    override init(transform: simd_float4x4) {
        super.init(transform: transform)
    }
    
    required init(anchor: ARAnchor) {
        super.init(anchor: anchor)
    }
    
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }
}

class ARSceneRendererDelegate : NSObject, ARSCNViewDelegate {
    // MARK: ARSessionObserver

    func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
        switch camera.trackingState {
        case .limited(let reason):
            switch reason {
            case .relocalizing:
                print("Tracking state changed to relocalizing")
            case .initializing:
                print("Tracking state changed to initializing")
            case .excessiveMotion:
                print("Tracking state changed to excessive motion")
            case .insufficientFeatures:
                print("Tracking state changed to insufficient features")
            }
        case .notAvailable:
            print("Tracking is not available in this configuration")
        case .normal:
            print("Tracking state changed to normal")
        }
    }

    // MARK: ARSCNViewDelegate

    func renderer(_ renderer: SCNSceneRenderer, didAdd node: SCNNode, for anchor: ARAnchor) {
        if let planeAnchor = anchor as? ARPlaneAnchor {
            let anchorGeometry = planeAnchor.geometry
            let scnGeometry = ARSCNPlaneGeometry(device: renderer.device!)!
            scnGeometry.materials.first?.colorBufferWriteMask = []
            node.renderingOrder = 0 // Render before other geometry that might be occluded
            scnGeometry.materials.first?.diffuse.contents = "uv_grid.png"
            scnGeometry.update(from: anchorGeometry)
            node.geometry = scnGeometry
        }
        if anchor is SphereAnchor {
            node.renderingOrder = 1 // Render after any occluding planes
            let scnGeometry = SCNSphere(radius: 0.125)
            scnGeometry.materials.first?.diffuse.contents = "uv_grid.png"
            node.geometry = scnGeometry
        }
    }

    func renderer(_ renderer: SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor) {
        if let planeAnchor = anchor as? ARPlaneAnchor {
            if let scnGeometry = node.geometry as? ARSCNPlaneGeometry {
                scnGeometry.update(from: planeAnchor.geometry)
            }
        }
    }
}

class ViewController: UIViewController {
    
    var session: ARSession!
    var arView: ARSCNView!
    var rendererDelegate: ARSceneRendererDelegate!

    override func viewDidLoad() {
        super.viewDidLoad()
        
        session = arView.session

        rendererDelegate = ARSceneRendererDelegate()
        
        arView = ARSCNView(frame: self.view.bounds, options: [:])
        arView.session = session
        arView.delegate = rendererDelegate

        //arView.debugOptions = [.showFeaturePoints]
        
        let tapRecognizer = UITapGestureRecognizer(target: self, action: #selector(tapGestureRecognized))
        arView.addGestureRecognizer(tapRecognizer)

        self.view.addSubview(arView)
        arView.translatesAutoresizingMaskIntoConstraints = false
        self.view.addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "|[arView]|",
                                                                options: [], metrics: nil, views: ["arView" : arView]))
        self.view.addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "V:|[arView]|",
                                                                options: [], metrics: nil, views: ["arView" : arView]))
        
        
        
        let sessionOptions: ARSession.RunOptions = [ .resetTracking, .removeExistingAnchors]
        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = [.horizontal]
        session.run(configuration, options: sessionOptions)
    }
    
    @objc
    func tapGestureRecognized(_ recognizer: UIGestureRecognizer) {
        guard let frame = session.currentFrame else { return }
        let cameraTransform = frame.camera.transform
        var modelTransform = matrix_identity_float4x4
        modelTransform[3][2] = -0.5 // Set the z component of the fourth column, i.e. the translation
        let sphereAnchor = SphereAnchor(transform: cameraTransform * modelTransform)
        session.add(anchor: sphereAnchor)
    }
    
}



import QuartzCore
import simd

//public extension float4 {
//    var xyz: SIMD3<Float> {
//        return SIMD3<Float>(x, y, z)
//    }
//
//    init(_ v: SIMD3<Float>, _ w: Float) {
//        self.init(v.x, v.y, v.z, w)
//    }
//}

// https://stackoverflow.com/questions/59915812/how-to-translate-float3-to-simd3float-xcode-11-swift-5-giving-depreciation-wa

extension SIMD4 {
    var xyz: SIMD3<Scalar> {
        SIMD3(x, y, z)
    }
    
    init(_ v: SIMD3<Scalar>, _ w: Scalar) {
        self.init(v.x, v.y, v.z, w)
    }
}

public struct packed_float3 {
    var x, y, z: Float
    
    init(_ x: Float, _ y: Float, _ z: Float) {
        self.x = x
        self.y = y
        self.z = z
    }
    
    init(_ v: SIMD3<Float>) {
        self.x = v.x
        self.y = v.y
        self.z = v.z
    }
}

public extension float3x3 {
    init(affineTransform m: CGAffineTransform) {
        self.init(SIMD3<Float>(Float( m.a), Float( m.b), 0),
                  SIMD3<Float>(Float( m.c), Float( m.d), 0),
                  SIMD3<Float>(Float(m.tx), Float(m.ty), 1))
    }
}

public extension float4x4 {
    init(translationBy t: SIMD3<Float>) {
        self.init(SIMD4<Float>(1, 0, 0, 0),
                  SIMD4<Float>(0, 1, 0, 0),
                  SIMD4<Float>(0, 0, 1, 0),
                  SIMD4<Float>(t.x, t.y, t.z, 1))
    }
    
    init(rotationFrom q: simd_quatf) {
        let (x, y, z) = (q.imag.x, q.imag.y, q.imag.z)
        let w = q.real
        self.init(SIMD4<Float>( 1 - 2*y*y - 2*z*z,     2*x*y + 2*z*w,     2*x*z - 2*y*w, 0),
                  SIMD4<Float>(     2*x*y - 2*z*w, 1 - 2*x*x - 2*z*z,     2*y*z + 2*x*w, 0),
                  SIMD4<Float>(     2*x*z + 2*y*w,     2*y*z - 2*x*w, 1 - 2*x*x - 2*y*y, 0),
                  SIMD4<Float>(                 0,                 0,                 0, 1))
    }
    
    init(rotationFromEulerAngles v: SIMD3<Float>) {
        let sx = sin(v.x)
        let cx = cos(v.x)
        let sy = sin(v.y)
        let cy = cos(v.y)
        let sz = sin(v.z)
        let cz = cos(v.z)
        let columns = [ SIMD4<Float>(           cy*cz,             cy*sz,   -sy, 0),
                        SIMD4<Float>(cz*sx*sy - cx*sz,  cx*cz + sx*sy*sz, cy*sx, 0),
                        SIMD4<Float>(cx*cz*sy + sx*sz, -cz*sx + cx*sy*sz, cx*cy, 0),
                        SIMD4<Float>(               0,                 0,     0, 1) ]
        self.init(columns)
    }

    init(scaleBy s: SIMD3<Float>) {
        self.init([SIMD4<Float>(s.x, 0, 0, 0), SIMD4<Float>(0, s.y, 0, 0), SIMD4<Float>(0, 0, s.z, 0), SIMD4<Float>(0, 0, 0, 1)])
    }
    
    var upperLeft: float3x3 {
        return float3x3(self[0].xyz, self[1].xyz, self[2].xyz)
    }

//    public init(perspectiveProjectionFOV fov: Float, near: Float, far: Float) {
//        let s = 1 / tanf(fov * 0.5)
//        let q = -far / (far - near)
//
//        let columns = [ float4(s, 0, 0, 0),
//                        float4(0, s, 0, 0),
//                        float4(0, 0, q, -1),
//                        float4(0, 0, q * near, 0) ]
//        self.init(columns)
//    }
}

public extension float3x3 {
    func decomposeToEulerAngles() -> SIMD3<Float> {
        let rotX = atan2( self[1][2], self[2][2])
        let rotY = atan2(-self[0][2], hypot(self[1][2], self[2][2]))
        let rotZ = atan2( self[0][1], self[0][0])
        return SIMD3<Float>(rotX, rotY, rotZ)
    }
}

import ARKit
import Vision
import UIKit

enum ScanFailure: LocalizedError {
    case noObject, sparseDepth, differentObject, tooFar
    var errorDescription: String? {
        switch self {
        case .noObject: return "No clear object at that spot. Tap the middle of an opaque object with some space around it."
        case .sparseDepth: return "Not enough reliable depth. Move closer, keep the object in view, and try again."
        case .differentObject: return "That selection doesn’t overlap the original object. Tap the same stationary object, or start a new scan."
        case .tooFar: return "Move within 0.2–3 meters of the object and try again."
        }
    }
}

struct ScanCloud {
    var points: [SIMD3<Float>]
    var yaw: Float
    var cameraPosition: SIMD3<Float>
}

/// Runs on a serial background queue. RGB, pose and depth always come from the same ARFrame.
enum DepthScanner {
    static func scan(frame: ARFrame, normalizedImagePoint tap: CGPoint) throws -> ScanCloud {
        guard let depth = frame.sceneDepth else { throw ScanFailure.sparseDepth }
        // ARKit buffers use the sensor's landscape orientation. Keeping Vision at .up
        // lets mask pixels, intrinsics and depth share the exact same coordinate system.
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cvPixelBuffer: frame.capturedImage, orientation: .up)
        try handler.perform([request])
        guard let observation = request.results?.first else { throw ScanFailure.noObject }
        let instances = observation.instanceMask
        guard CVPixelBufferGetPixelFormatType(instances) == kCVPixelFormatType_OneComponent8 else { throw ScanFailure.noObject }
        CVPixelBufferLockBaseAddress(instances, .readOnly)
        let mw = CVPixelBufferGetWidth(instances), mh = CVPixelBufferGetHeight(instances)
        let mx = min(mw - 1, max(0, Int(tap.x * Double(mw))))
        let my = min(mh - 1, max(0, Int(tap.y * Double(mh))))
        let instanceRow = CVPixelBufferGetBaseAddress(instances)!.advanced(by: my * CVPixelBufferGetBytesPerRow(instances))
        let selected = Int(instanceRow.assumingMemoryBound(to: UInt8.self)[mx])
        CVPixelBufferUnlockBaseAddress(instances, .readOnly)
        guard selected != 0 else { throw ScanFailure.noObject }
        let mask = try observation.generateScaledMaskForImage(forInstances: IndexSet(integer: selected), from: handler)
        let map = depth.depthMap
        guard let confidence = depth.confidenceMap else { throw ScanFailure.sparseDepth }
        guard CVPixelBufferGetPixelFormatType(mask) == kCVPixelFormatType_OneComponent32Float,
              CVPixelBufferGetPixelFormatType(map) == kCVPixelFormatType_DepthFloat32,
              CVPixelBufferGetWidth(confidence) == CVPixelBufferGetWidth(map),
              CVPixelBufferGetHeight(confidence) == CVPixelBufferGetHeight(map) else { throw ScanFailure.sparseDepth }
        for buffer in [mask, map, confidence] { CVPixelBufferLockBaseAddress(buffer, .readOnly) }
        defer { for buffer in [mask, map, confidence] { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) } }
        let width = CVPixelBufferGetWidth(map), height = CVPixelBufferGetHeight(map)
        let maskWidth = CVPixelBufferGetWidth(mask), maskHeight = CVPixelBufferGetHeight(mask)
        let k = frame.camera.intrinsics
        let imageSize = frame.camera.imageResolution
        let sx = Float(imageSize.width) / Float(width), sy = Float(imageSize.height) / Float(height)
        let fx = k[0][0] / sx, fy = k[1][1] / sy, cx = k[2][0] / sx, cy = k[2][1] / sy
        let transform = frame.camera.transform
        var points: [SIMD3<Float>] = []
        var distances: [Float] = []
        for y in stride(from: 1, to: height - 1, by: 2) {
            let depthRow = CVPixelBufferGetBaseAddress(map)!.advanced(by: y * CVPixelBufferGetBytesPerRow(map)).assumingMemoryBound(to: Float.self)
            let confidenceRow = CVPixelBufferGetBaseAddress(confidence)!.advanced(by: y * CVPixelBufferGetBytesPerRow(confidence)).assumingMemoryBound(to: UInt8.self)
            for x in stride(from: 1, to: width - 1, by: 2) {
                guard confidenceRow[x] >= UInt8(ARConfidenceLevel.medium.rawValue) else { continue }
                let u = min(maskWidth - 1, Int((Float(x) + 0.5) / Float(width) * Float(maskWidth)))
                let v = min(maskHeight - 1, Int((Float(y) + 0.5) / Float(height) * Float(maskHeight)))
                // Erode by one depth pixel to avoid mixed foreground/background edge samples.
                let marginX = max(1, maskWidth / width), marginY = max(1, maskHeight / height)
                guard [(u,v), (u-marginX,v), (u+marginX,v), (u,v-marginY), (u,v+marginY)].allSatisfy({ px, py in
                    guard px >= 0, py >= 0, px < maskWidth, py < maskHeight else { return false }
                    let row = CVPixelBufferGetBaseAddress(mask)!.advanced(by: py * CVPixelBufferGetBytesPerRow(mask)).assumingMemoryBound(to: Float.self)
                    return row[px] > 0.85
                }) else { continue }
                let d = depthRow[x]
                guard d.isFinite, d > 0.2, d < 3 else { continue }
                let camera = SIMD4((Float(x) - cx) * d / fx, -(Float(y) - cy) * d / fy, -d, 1)
                let world = transform * camera
                points.append(SIMD3(world.x, world.y, world.z))
                distances.append(d)
            }
        }
        guard points.count >= 40 else { throw ScanFailure.sparseDepth }
        // Reject remote background leakage while preserving the object's visible depth range.
        let sorted = distances.sorted(), median = sorted[sorted.count / 2]
        points = zip(points, distances).filter { abs($0.1 - median) < max(0.15, median * 0.35) }.map(\.0)
        guard points.count >= 40 else { throw ScanFailure.sparseDepth }
        // Use the initial camera's horizontal right vector as width, fixed for later views.
        let right = transform.columns.0
        let yaw = atan2(-right.z, right.x)
        let translation = transform.columns.3
        return ScanCloud(points: points, yaw: yaw, cameraPosition: SIMD3(translation.x, translation.y, translation.z))
    }
}

import SwiftUI
import ARKit
import AVFoundation
import SceneKit

@MainActor
final class ScanSession: NSObject, ObservableObject, @preconcurrency ARSessionDelegate {
    @Published var box: MeasuredBox?
    @Published var busy = false
    @Published var message = "Move your phone slowly to find surfaces."
    @Published var problem: String?
    @Published var demo = false
    @Published var available = ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth)
    @Published var denied = false
    @Published var ready = false
    @Published var addingView = false
    @Published var unit: MeasureUnit = .centimeters { didSet { renderBox() } }
    weak var view: ARSCNView?
    private let worker = DispatchQueue(label: "com.form.segmentation", qos: .userInitiated)
    private var points: [SIMD3<Float>] = []
    private var scanGeneration = UUID()
    private var cameraPositions: [SIMD3<Float>] = []
    private var overlay = SCNNode()
    private var active = false

    func attach(_ view: ARSCNView) {
        self.view = view
        view.session.delegate = self
        view.session.delegateQueue = .main
        view.scene = SCNScene()
        view.automaticallyUpdatesLighting = true
        view.scene.rootNode.addChildNode(overlay)
        start()
    }

    func start() {
        guard !demo, available, !active else { return }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: denied = false; run()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] allowed in
                Task { @MainActor in
                    guard let self else { return }
                    if allowed { self.start() } else { self.denied = true }
                }
            }
        default: denied = true
        }
    }

    private func run() {
        guard view != nil else { return }
        let configuration = ARWorldTrackingConfiguration()
        configuration.frameSemantics = [.sceneDepth]
        configuration.planeDetection = [.horizontal, .vertical]
        configuration.environmentTexturing = .automatic
        view?.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
        active = true
        reset()
    }

    func pause() {
        view?.session.pause()
        active = false
        ready = false
        scanGeneration = UUID()
        busy = false
    }

    func showDemo() {
        pause()
        demo = true
        box = .demo
        message = "Example dimensions · no camera data"
    }

    func leaveDemo() {
        demo = false
        reset()
        start()
    }

    func reset() {
        scanGeneration = UUID()
        box = nil
        points = []
        cameraPositions = []
        busy = false
        addingView = false
        problem = nil
        overlay.childNodes.forEach { $0.removeFromParentNode() }
        message = demo ? "Tap the example object to try a scan." : "Tap the middle of the object to measure."
    }

    func addView() {
        guard !busy else { return }
        addingView = true
        message = "Move to another angle, then tap the same object."
    }

    func select(at point: CGPoint) {
        if demo {
            box = .demo
            if addingView { box?.views = 3 }
            addingView = false
            return
        }
        guard ready, !busy, box == nil || addingView,
              let view, let frame = view.session.currentFrame else { return }
        guard case .normal = frame.camera.trackingState else { return }
        let normalized = CGPoint(x: point.x / view.bounds.width, y: point.y / view.bounds.height)
        let imagePoint = normalized.applying(frame.displayTransform(for: .portrait, viewportSize: view.bounds.size).inverted())
        guard imagePoint.x >= 0, imagePoint.x <= 1, imagePoint.y >= 0, imagePoint.y <= 1 else { return }
        busy = true
        message = "Isolating the object and reading depth…"
        let generation = scanGeneration
        worker.async {
            let result = Result { try DepthScanner.scan(frame: frame, normalizedImagePoint: imagePoint) }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.scanGeneration == generation else { return }
                self.busy = false
                switch result {
                case .success(let cloud):
                    do { try self.accept(cloud) }
                    catch { self.problem = error.localizedDescription; self.message = "Try selecting the object again." }
                case .failure(let error):
                    self.problem = error.localizedDescription
                    self.message = "Try selecting the object again."
                }
            }
        }
    }

    private func accept(_ cloud: ScanCloud) throws {
        let yaw = box?.yaw ?? cloud.yaw
        guard let candidate = MeasuredBox.fit(points: cloud.points, yaw: yaw, views: 1) else { throw ScanFailure.sparseDepth }
        if let existing = box {
            // Require spatial overlap; do not fuse a second, unrelated object.
            let nearby = cloud.points.filter {
                let p = MeasuredBox.rotate($0 - existing.center, yaw: -yaw)
                let allowance = existing.size / 2 + SIMD3<Float>(repeating: 0.08)
                return abs(p.x) <= allowance.x && abs(p.y) <= allowance.y && abs(p.z) <= allowance.z
            }
            guard Float(nearby.count) / Float(cloud.points.count) > 0.25,
                  simd_distance(existing.center, candidate.center) < max(0.15, simd_length(existing.size) * 0.65)
            else { throw ScanFailure.differentObject }
            guard cameraPositions.allSatisfy({ simd_distance($0, cloud.cameraPosition) > 0.08 }) else {
                message = "Move at least a little farther around the object, then tap again."
                return
            }
        }
        // Cap memory across a long sequence of scans.
        let combined = points + cloud.points
        let bounded = combined.count > 30000 ? stride(from: 0, to: combined.count, by: 2).map { combined[$0] } : combined
        guard let fitted = MeasuredBox.fit(points: bounded, yaw: yaw, views: cameraPositions.count + 1) else { throw ScanFailure.sparseDepth }
        points = bounded
        cameraPositions.append(cloud.cameraPosition)
        box = fitted
        addingView = false
        message = "Visible surfaces measured. Add angles to capture hidden sides."
        renderBox()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    func adjust(size: SIMD3<Float>, yaw: Float) {
        guard var updated = box else { return }
        if !points.isEmpty, abs(updated.yaw - yaw) > 0.001,
           let fit = MeasuredBox.fit(points: points, yaw: yaw, views: updated.views) {
            updated = fit
        } else { updated.size = size }
        updated.yaw = yaw
        updated.edited = true
        box = updated
        renderBox()
    }

    func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
        switch camera.trackingState {
        case .normal: ready = true
        case .notAvailable: ready = false; message = "Tracking is unavailable."
        case .limited(let reason):
            ready = false
            switch reason {
            case .excessiveMotion: message = "Slow down to keep measurements in place."
            case .insufficientFeatures: message = "Aim at a textured, well-lit area."
            default: message = "Move your phone slowly to find surfaces."
            }
        }
    }

    func sessionWasInterrupted(_ session: ARSession) {
        ready = false
        scanGeneration = UUID()
        busy = false
        message = "Camera paused. Return to resume."
    }
    func sessionInterruptionEnded(_ session: ARSession) { active = false; start() }
    func session(_ session: ARSession, didFailWithError error: Error) {
        pause()
        problem = "Camera session stopped: \(error.localizedDescription). Tap New to restart."
    }

    func restart() { reset(); if !active { start() } }

    private func renderBox() {
        overlay.childNodes.forEach { $0.removeFromParentNode() }
        guard let box, !demo else { return }
        let half = box.size / 2
        let corners: [SIMD3<Float>] = (0..<8).map { i in
            box.world(SIMD3(i & 1 == 0 ? -half.x : half.x,
                            i & 2 == 0 ? -half.y : half.y,
                            i & 4 == 0 ? -half.z : half.z))
        }
        for i in 0..<8 {
            for bit in [1, 2, 4] where i & bit == 0 {
                let a = corners[i], b = corners[i | bit], delta = b - a
                let cylinder = SCNCylinder(radius: 0.0012, height: CGFloat(simd_length(delta)))
                cylinder.firstMaterial?.diffuse.contents = UIColor(red: 0.80, green: 0.98, blue: 0.40, alpha: 1)
                cylinder.firstMaterial?.lightingModel = .constant
                let node = SCNNode(geometry: cylinder)
                node.simdPosition = (a + b) / 2
                node.simdOrientation = simd_quatf(from: SIMD3(0, 1, 0), to: simd_normalize(delta))
                overlay.addChildNode(node)
            }
        }
        let labels: [(String, Float, SIMD3<Float>)] = [
            ("W", box.size.x, SIMD3(0, -half.y - 0.035, half.z)),
            ("H", box.size.y, SIMD3(half.x + 0.04, 0, half.z)),
            ("D", box.size.z, SIMD3(-half.x - 0.04, -half.y, 0))
        ]
        for (axis, length, position) in labels {
            let text = SCNText(string: "\(axis)  \(unit.format(length)) \(unit.rawValue)", extrusionDepth: 0)
            text.font = UIFont.monospacedSystemFont(ofSize: 12, weight: .semibold)
            text.flatness = 0.3
            text.firstMaterial?.diffuse.contents = UIColor.white
            text.firstMaterial?.lightingModel = .constant
            text.firstMaterial?.readsFromDepthBuffer = false
            let label = SCNNode(geometry: text)
            let bounds = text.boundingBox
            label.pivot = SCNMatrix4MakeTranslation((bounds.max.x + bounds.min.x) / 2, (bounds.max.y + bounds.min.y) / 2, 0)
            label.simdScale = SIMD3(repeating: 0.002)
            label.simdPosition = box.world(position)
            label.constraints = [SCNBillboardConstraint()]
            label.renderingOrder = 100
            overlay.addChildNode(label)
        }
    }
}

struct CameraView: UIViewRepresentable {
    let session: ScanSession
    func makeUIView(context: Context) -> ARSCNView {
        let view = ARSCNView(frame: .zero)
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tap(_:)))
        view.addGestureRecognizer(tap)
        session.attach(view)
        return view
    }
    func updateUIView(_ uiView: ARSCNView, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(session) }
    static func dismantleUIView(_ uiView: ARSCNView, coordinator: Coordinator) { uiView.session.pause() }
    @MainActor final class Coordinator: NSObject {
        let session: ScanSession
        init(_ session: ScanSession) { self.session = session }
        @objc func tap(_ sender: UITapGestureRecognizer) { session.select(at: sender.location(in: sender.view)) }
    }
}

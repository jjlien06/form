import SwiftUI
import simd

enum MeasureUnit: String, CaseIterable, Identifiable {
    case centimeters = "cm", inches = "in"
    var id: String { rawValue }
    func format(_ meters: Float) -> String {
        String(format: "%.1f", meters * (self == .centimeters ? 100 : 39.3701))
    }
}

/// A gravity-aligned box. Its horizontal axes remain fixed across added views.
struct MeasuredBox {
    var center: SIMD3<Float>
    var size: SIMD3<Float>
    var yaw: Float
    var views: Int
    var samples: Int
    var edited = false

    func world(_ local: SIMD3<Float>) -> SIMD3<Float> {
        center + Self.rotate(local, yaw: yaw)
    }

    static func rotate(_ p: SIMD3<Float>, yaw: Float) -> SIMD3<Float> {
        SIMD3(cos(yaw) * p.x + sin(yaw) * p.z, p.y, -sin(yaw) * p.x + cos(yaw) * p.z)
    }

    static func fit(points: [SIMD3<Float>], yaw: Float, views: Int) -> MeasuredBox? {
        let clean = points.filter { $0.x.isFinite && $0.y.isFinite && $0.z.isFinite }
        guard clean.count >= 40 else { return nil }
        let local = clean.map { rotate($0, yaw: -yaw) }
        // Trim isolated depth outliers, without claiming millimeter precision.
        func extent(_ axis: Int) -> (Float, Float) {
            let sorted = local.map { $0[axis] }.sorted()
            let trim = Int(Float(sorted.count) * 0.015)
            return (sorted[trim], sorted[sorted.count - 1 - trim])
        }
        let x = extent(0), y = extent(1), z = extent(2)
        let minimum = SIMD3(x.0, y.0, z.0), maximum = SIMD3(x.1, y.1, z.1)
        let size = maximum - minimum
        guard size.x > 0.005, size.y > 0.005, size.z > 0.005 else { return nil }
        return MeasuredBox(center: rotate((minimum + maximum) / 2, yaw: yaw),
                           size: size, yaw: yaw, views: views, samples: clean.count)
    }

    static let demo = MeasuredBox(center: .zero, size: SIMD3(0.324, 0.218, 0.246), yaw: 0, views: 2, samples: 1832)
}

struct SavedMeasurement: Identifiable, Codable {
    var id = UUID()
    var date = Date()
    var name: String
    var width: Float
    var height: Float
    var depth: Float
    var views: Int
    var edited: Bool
    var demo: Bool
}

@MainActor
final class MeasurementLibrary: ObservableObject {
    @Published private(set) var items: [SavedMeasurement] = []
    @Published var error: String?
    private let url: URL

    init(url: URL? = nil) {
        self.url = url ?? URL.documentsDirectory.appending(path: "measurements.json")
        do {
            if FileManager.default.fileExists(atPath: self.url.path) {
                items = try JSONDecoder().decode([SavedMeasurement].self, from: Data(contentsOf: self.url))
            }
        } catch { self.error = "Your saved measurements couldn’t be opened. \(error.localizedDescription)" }
    }

    @discardableResult
    func save(_ box: MeasuredBox, name: String, demo: Bool) -> Bool {
        let item = SavedMeasurement(name: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled object" : name,
                                    width: box.size.x, height: box.size.y, depth: box.size.z,
                                    views: box.views, edited: box.edited, demo: demo)
        return write([item] + items)
    }

    func delete(_ offsets: IndexSet) {
        var next = items
        next.remove(atOffsets: offsets)
        _ = write(next)
    }

    private func write(_ next: [SavedMeasurement]) -> Bool {
        do {
            let data = try JSONEncoder().encode(next)
            try data.write(to: url, options: .atomic)
            items = next
            return true
        } catch {
            self.error = "Couldn’t save your changes. \(error.localizedDescription)"
            return false
        }
    }
}

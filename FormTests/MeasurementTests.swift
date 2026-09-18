import XCTest
@testable import Form

final class MeasurementTests: XCTestCase {
    private func cube(yaw: Float = 0, center: SIMD3<Float> = .zero) -> [SIMD3<Float>] {
        var points: [SIMD3<Float>] = []
        for x in 0...10 {
            for y in 0...10 {
                for z in 0...10 {
                    let local = SIMD3(Float(x) / 10 * 0.4 - 0.2, Float(y) / 10 * 0.2 - 0.1, Float(z) / 10 * 0.3 - 0.15)
                    points.append(MeasuredBox.rotate(local, yaw: yaw) + center)
                }
            }
        }
        return points
    }

    func testRotatedTranslatedObjectPreservesDimensions() throws {
        let yaw: Float = 0.7, center = SIMD3<Float>(1.3, -0.2, -1.7)
        let box = try XCTUnwrap(MeasuredBox.fit(points: cube(yaw: yaw, center: center), yaw: yaw, views: 2))
        XCTAssertEqual(box.size.x, 0.4, accuracy: 0.0001)
        XCTAssertEqual(box.size.y, 0.2, accuracy: 0.0001)
        XCTAssertEqual(box.size.z, 0.3, accuracy: 0.0001)
        XCTAssertEqual(box.center.x, center.x, accuracy: 0.0001)
        XCTAssertEqual(box.center.z, center.z, accuracy: 0.0001)
    }

    func testSparseAndNonfiniteCloudsCannotProduceMeasurements() {
        XCTAssertNil(MeasuredBox.fit(points: Array(repeating: .zero, count: 39), yaw: 0, views: 1))
        XCTAssertNil(MeasuredBox.fit(points: Array(repeating: SIMD3(.nan, 1, 1), count: 100), yaw: 0, views: 1))
    }

    func testIsolatedDepthOutliersAreRejected() throws {
        let points = cube() + [SIMD3<Float>(20, 20, 20), SIMD3<Float>(-20, -20, -20)]
        let box = try XCTUnwrap(MeasuredBox.fit(points: points, yaw: 0, views: 1))
        XCTAssertEqual(box.size.x, 0.4, accuracy: 0.0001)
        XCTAssertEqual(box.size.y, 0.2, accuracy: 0.0001)
        XCTAssertEqual(box.size.z, 0.3, accuracy: 0.0001)
    }

    func testUnitConversion() {
        XCTAssertEqual(MeasureUnit.centimeters.format(0.324), "32.4")
        XCTAssertEqual(MeasureUnit.inches.format(0.254), "10.0")
    }

    @MainActor
    func testLibraryPersistsAndDeletesDemoProvenance() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = MeasurementLibrary(url: url)
        XCTAssertTrue(store.save(.demo, name: "Example", demo: true))
        let restored = MeasurementLibrary(url: url)
        XCTAssertEqual(restored.items.count, 1)
        XCTAssertTrue(try XCTUnwrap(restored.items.first).demo)
        XCTAssertEqual(restored.items.first?.width, 0.324)
        restored.delete(IndexSet(integer: 0))
        XCTAssertTrue(MeasurementLibrary(url: url).items.isEmpty)
    }
}

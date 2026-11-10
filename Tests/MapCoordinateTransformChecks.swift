import CoreLocation
import Foundation

@main
struct MapCoordinateTransformChecks {
    static func main() {
        var checks = 0

        func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
            checks += 1
            guard condition() else { fatalError(message) }
        }

        func expectClose(
            _ actual: CLLocationCoordinate2D,
            _ expected: CLLocationCoordinate2D,
            tolerance: Double = 1e-9,
            _ message: String
        ) {
            expect(abs(actual.latitude - expected.latitude) <= tolerance, "\(message): latitude")
            expect(abs(actual.longitude - expected.longitude) <= tolerance, "\(message): longitude")
        }

        // Bitwise comparison also verifies passthrough of NaN, infinity and -0.
        func expectUnchanged(_ actual: CLLocationCoordinate2D, _ input: CLLocationCoordinate2D, _ message: String) {
            expect(actual.latitude.bitPattern == input.latitude.bitPattern, "\(message): latitude changed")
            expect(actual.longitude.bitPattern == input.longitude.bitPattern, "\(message): longitude changed")
        }

        let beijing = CLLocationCoordinate2D(latitude: 39.908823, longitude: 116.397470)
        // Published reference values used in Locus PRs #19/#20.
        let beijingGCJ = CLLocationCoordinate2D(latitude: 39.910226498, longitude: 116.403713582)
        expectClose(MapCoordinateTransform.wgs84ToGcj02(beijing), beijingGCJ, "Beijing forward reference")
        expectClose(MapCoordinateTransform.gcj02ToWgs84(beijingGCJ), beijing, "Beijing inverse reference")

        let cities = [
            beijing,
            CLLocationCoordinate2D(latitude: 31.2304, longitude: 121.4737),
            CLLocationCoordinate2D(latitude: 23.1291, longitude: 113.2644)
        ]
        for (index, point) in cities.enumerated() {
            let gcj = MapCoordinateTransform.wgs84ToGcj02(point)
            let restored = MapCoordinateTransform.gcj02ToWgs84(gcj)
            expectClose(restored, point, "City \(index) roundtrip")
            expectClose(MapCoordinateTransform.wgs84ToGcj02(restored), gcj, tolerance: 1e-10, "City \(index) inverse residual")
            expectClose(MapCoordinateTransform.convertForSystem(gcj, correctionEnabled: true), point, "City \(index) enabled correction")
            expectUnchanged(MapCoordinateTransform.convertForSystem(gcj, correctionEnabled: false), gcj, "City \(index) disabled correction")
            expectUnchanged(MapCoordinateTransform.convertForSystem(gcj), gcj, "City \(index) default is off")
        }

        // These overseas examples lie outside the coarse numerical rectangle.
        // The helper does not claim that the rectangle identifies any country's border.
        let overseas = [
            CLLocationCoordinate2D(latitude: 51.5074, longitude: -0.1278),
            CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060),
            CLLocationCoordinate2D(latitude: 35.6762, longitude: 139.6503),
            CLLocationCoordinate2D(latitude: -33.8688, longitude: 151.2093)
        ]
        for point in overseas {
            expectUnchanged(MapCoordinateTransform.wgs84ToGcj02(point), point, "Overseas forward passthrough")
            expectUnchanged(MapCoordinateTransform.gcj02ToWgs84(point), point, "Overseas inverse passthrough")
            expectUnchanged(MapCoordinateTransform.convertForSystem(point, correctionEnabled: true), point, "Overseas enabled passthrough")
        }

        let invalidAndOutside = [
            CLLocationCoordinate2D(latitude: .nan, longitude: 113),
            CLLocationCoordinate2D(latitude: 23, longitude: .nan),
            CLLocationCoordinate2D(latitude: .infinity, longitude: 113),
            CLLocationCoordinate2D(latitude: 23, longitude: -.infinity),
            CLLocationCoordinate2D(latitude: 90.0001, longitude: 113),
            CLLocationCoordinate2D(latitude: 23, longitude: 180.0001),
            CLLocationCoordinate2D(latitude: -90.0001, longitude: -180.0001),
            CLLocationCoordinate2D(latitude: 90, longitude: 180),
            CLLocationCoordinate2D(latitude: -90, longitude: -180),
            CLLocationCoordinate2D(latitude: -0.0, longitude: 0),
            CLLocationCoordinate2D(latitude: (0.8293).nextDown, longitude: 113),
            CLLocationCoordinate2D(latitude: (55.8271).nextUp, longitude: 113),
            CLLocationCoordinate2D(latitude: 23, longitude: (72.004).nextDown),
            CLLocationCoordinate2D(latitude: 23, longitude: (137.8347).nextUp)
        ]
        for point in invalidAndOutside {
            expectUnchanged(MapCoordinateTransform.wgs84ToGcj02(point), point, "Invalid/outside forward passthrough")
            expectUnchanged(MapCoordinateTransform.gcj02ToWgs84(point), point, "Invalid/outside inverse passthrough")
            expectUnchanged(MapCoordinateTransform.convertForSystem(point, correctionEnabled: true), point, "Invalid/outside enabled passthrough")
            expectUnchanged(MapCoordinateTransform.convertForSystem(point), point, "Invalid/outside default passthrough")
        }

        // Exercise the numerical guard's inclusive edges and the x = 0 term.
        let nearEdges = [
            CLLocationCoordinate2D(latitude: 0.8293, longitude: 72.004),
            CLLocationCoordinate2D(latitude: 55.8271, longitude: 137.8347),
            CLLocationCoordinate2D(latitude: 35, longitude: 105)
        ]
        for point in nearEdges {
            let restored = MapCoordinateTransform.gcj02ToWgs84(point)
            expect(CLLocationCoordinate2DIsValid(restored), "Edge inverse must remain valid")
            expect(restored.latitude.isFinite && restored.longitude.isFinite, "Edge inverse must remain finite")
        }

        expect(MapCoordinateTransform.defaultsKey == "locus.gcj02CorrectionEnabled", "Settings key must remain stable")
        print("MapCoordinateTransform checks passed (\(checks) assertions)")
    }
}

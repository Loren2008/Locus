import CoreLocation
import Foundation

/// Explicit coordinate interpretation at the system-location output boundary.
/// Pins, routes and saved places keep their original coordinates.
enum MapCoordinateTransform {
    static let defaultsKey = "locus.gcj02CorrectionEnabled"

    /// The caller must opt in after confirming that its input uses GCJ-02.
    /// No device region, language or location is inspected here.
    static func convertForSystem(
        _ coordinate: CLLocationCoordinate2D,
        correctionEnabled: Bool = false
    ) -> CLLocationCoordinate2D {
        guard correctionEnabled else { return coordinate }
        return gcj02ToWgs84(coordinate)
    }

    static func wgs84ToGcj02(_ coordinate: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        guard isWithinApproximateTransformBounds(coordinate) else { return coordinate }
        return forwardModel(coordinate)
    }

    static func gcj02ToWgs84(_ coordinate: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        guard isWithinApproximateTransformBounds(coordinate) else { return coordinate }

        var estimate = coordinate
        for _ in 0..<30 {
            // Do not reapply the coarse bounds to intermediate estimates: a
            // solution near an edge can lie just outside that numerical guard.
            let projected = forwardModel(estimate)
            let latitudeError = projected.latitude - coordinate.latitude
            let longitudeError = projected.longitude - coordinate.longitude
            if max(abs(latitudeError), abs(longitudeError)) <= 1e-10 {
                return estimate
            }
            estimate.latitude -= latitudeError
            estimate.longitude -= longitudeError
        }
        return estimate
    }

    /// A coarse numerical coverage rectangle used by the common approximation.
    /// This is NOT a national border and includes some neighboring regions.
    /// Being inside it never enables correction; that is an explicit caller choice.
    private static func isWithinApproximateTransformBounds(_ coordinate: CLLocationCoordinate2D) -> Bool {
        coordinate.latitude.isFinite && coordinate.longitude.isFinite
            && CLLocationCoordinate2DIsValid(coordinate)
            && (0.8293...55.8271).contains(coordinate.latitude)
            && (72.004...137.8347).contains(coordinate.longitude)
    }

    // Forward approximation also used by the published Locus PRs #19 and #20.
    private static func forwardModel(_ coordinate: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        let x = coordinate.longitude - 105
        let y = coordinate.latitude - 35
        let pi = Double.pi
        let common = (20 * sin(6 * x * pi) + 20 * sin(2 * x * pi)) * 2 / 3

        var latitude = -100 + 2 * x + 3 * y + 0.2 * y * y + 0.1 * x * y + 0.2 * sqrt(abs(x))
        latitude += common
        latitude += (20 * sin(y * pi) + 40 * sin(y / 3 * pi)) * 2 / 3
        latitude += (160 * sin(y / 12 * pi) + 320 * sin(y * pi / 30)) * 2 / 3

        var longitude = 300 + x + 2 * y + 0.1 * x * x + 0.1 * x * y + 0.1 * sqrt(abs(x))
        longitude += common
        longitude += (20 * sin(x * pi) + 40 * sin(x / 3 * pi)) * 2 / 3
        longitude += (150 * sin(x / 12 * pi) + 300 * sin(x / 30 * pi)) * 2 / 3

        let radians = coordinate.latitude / 180 * pi
        let eccentricity = 0.00669342162296594323
        let magic = 1 - eccentricity * pow(sin(radians), 2)
        let root = sqrt(magic)
        let axis = 6378245.0
        latitude = latitude * 180 / ((axis * (1 - eccentricity)) / (magic * root) * pi)
        longitude = longitude * 180 / (axis / root * cos(radians) * pi)
        return CLLocationCoordinate2D(
            latitude: coordinate.latitude + latitude,
            longitude: coordinate.longitude + longitude
        )
    }
}

import SwiftUI
import MapKit

struct RestaurantCard: View {
    let restaurant: Restaurant

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(restaurant.name)
                    .font(.headline)
                    .foregroundStyle(.white)
                Spacer()
                Text(distanceText)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.7))
            }
            if let address = restaurant.address {
                Label(address, systemImage: "mappin.and.ellipse")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(2)
            }
            if let phone = restaurant.phone {
                Label(phone, systemImage: "phone")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.7))
            }
            Button(action: openDirections) {
                Label("Directions", systemImage: "arrow.triangle.turn.up.right.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .glassCard(cornerRadius: 16)
    }

    /// Locale-aware road distance ("350 m" / "0.9 mi" depending on region).
    private var distanceText: String {
        Measurement(value: restaurant.distanceMeters, unit: UnitLength.meters)
            .formatted(.measurement(width: .abbreviated, usage: .road))
    }

    /// Google Maps first, Apple Maps as the fallback (F8) — both when Google
    /// Maps isn't installed and when its open unexpectedly fails.
    private func openDirections() {
        let googleMaps = DirectionsPlanner.googleMapsURL(latitude: restaurant.latitude,
                                                         longitude: restaurant.longitude)
        if UIApplication.shared.canOpenURL(googleMaps) {
            UIApplication.shared.open(googleMaps, options: [:]) { opened in
                if !opened { openAppleMaps() }
            }
        } else {
            openAppleMaps()
        }
    }

    private func openAppleMaps() {
        let coordinate = CLLocationCoordinate2D(latitude: restaurant.latitude, longitude: restaurant.longitude)
        let item = MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
        item.name = restaurant.name
        item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving])
    }
}

#Preview {
    RestaurantCard(restaurant: Restaurant(
        id: UUID(), name: "Haidilao Hot Pot", distanceMeters: 850,
        address: "40 Boylston St, Boston, MA", phone: "(617) 555-0123",
        latitude: 42.352, longitude: -71.064
    ))
    .padding()
}

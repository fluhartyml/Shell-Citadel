//
//  LocationStamp.swift
//  Shell Citadel
//
//  TWO FEATURES, NOT ONE. Michael, 2026-08-28 07:29:
//  "since you suggested i want a map pin snapshot in the plus to drop a location pin and i
//   would like an undisclosed gps location stamp imbeded in every message sent from human
//   to claude in citadel"
//
//    A · THE PIN DROP   — explicit, in the `+` menu. PRECISE. Map snapshot into the
//                          thread AND his photo album.
//    B · THE SILENT STAMP — every human→Claude message carries a coordinate. COARSE.
//                          Coordinate only, no image, not drawn in his bubble.
//
//  His ruling on accuracy, 2026-08-29 22:42:
//  "Course for regular chat precice for the pin drop picture of the map"
//
//  ── WHY REDUCED-BY-DEFAULT, AND WHY THAT IS HIS DESIGN AND NOT A WORKAROUND ─────
//  iOS has a sanctioned mechanism for exactly this split. The app asks for reduced
//  accuracy as its normal state and calls `requestTemporaryFullAccuracyAuthorization`
//  only when he taps the pin. Three things get better at once: the radio is not spun
//  for full precision on every line he types, the purpose key is user-visible text
//  explaining why precision is needed at that moment, and reduced-by-default is the
//  pattern Apple documents and expects.
//
//  ⚠️ PRECISE LOCATION IS *HIS* SWITCH, NOT THE APP'S. `accuracyAuthorization` reflects
//  the Precise Location toggle in Settings. If he leaves it ON, the temporary request is
//  unnecessary and is skipped. If he turns it OFF, the pin drop asks — once, with a
//  reason — and iOS returns to reduced afterwards on its own. Both paths are handled
//  because assuming either one is how this breaks on his phone rather than in testing.
//
//  ── WHY ROUNDING AND NOT CLGeocoder ────────────────────────────────────────────
//  A reverse-geocoded place name reads beautifully — "Surfside Beach, TX" — and requires
//  a network call. This app's founding property is that everything works with NO INTERNET
//  AT ALL, on the LAN. Rounding is offline, instant and free.
//
//      0.1°   ≈ 11 km    which town
//      0.01°  ≈ 1.1 km   which neighbourhood   ← this one, his choice
//      0.001° ≈ 110 m    which building
//
//  Rounded AT THE SOURCE, not stored precise and merely displayed rounded — that is what
//  he asked for and it keeps the data matching the intent.
//
//  ── ⚠️ THE ONE RULE THAT MUST NOT BE BROKEN HERE ───────────────────────────────
//  Location lives in the DATA MODEL. It is NEVER written into photo EXIF. iOS's own
//  camera setting stays the single authority on that. `PHAssetChangeRequest.location`
//  is therefore deliberately NOT set below, and must never be added.
//  A map snapshot DEPICTS a place, which is not the same thing as stamping one into
//  metadata.  → feedback_photo_location_privacy
//
//  ── ⚠️ THIS IS NOT A SAFETY SYSTEM AND MUST NEVER BE DESCRIBED AS ONE ──────────
//  It gained a reason on 2026-08-29 — he re-asked for it hours after a 35-minute
//  tachycardia he rode out alone — and a coordinate riding along means Claude knows
//  where he is at the moment typing is hardest. That is CONTEXT FOR A MESSAGE.
//  His pendant is the dispatch path, with his address already on file at a staffed
//  monitoring centre.  → project_he_has_a_monitored_panic_necklace
//

import CoreLocation
import MapKit
import Photos
import UIKit

@MainActor
final class LocationStamp: NSObject, CLLocationManagerDelegate {

    static let shared = LocationStamp()

    /// Must match the key inside `NSLocationTemporaryUsageDescriptionDictionary` in
    /// Info.plist. A mismatch does not crash and does not warn — the request simply
    /// returns denied, which is the silent-failure shape this project keeps getting
    /// bitten by, so the string lives in exactly one place.
    static let pinDropPurposeKey = "PinDrop"

    private let manager = CLLocationManager()

    /// Continuations for one-shot fixes. An array rather than a single optional because
    /// two requests can overlap — he taps the pin while a refresh is in flight — and
    /// dropping one would hang that caller forever.
    private var pending: [CheckedContinuation<CLLocation, Error>] = []

    /// The last fix we were given. `manager.location` is also consulted, but this
    /// survives the manager clearing its own cache between one-shot requests.
    ///
    /// Deliberately NOT `@Published` and this type is deliberately NOT an
    /// `ObservableObject`: nothing in the UI redraws when a fix arrives. The stamp is
    /// read at the moment a message is sent and the pin drop awaits its own fix, so an
    /// observable wrapper here would pull in Combine and publish changes no view is
    /// watching.
    private(set) var lastFix: CLLocation?

    enum Failure: LocalizedError {
        case denied
        case noFix
        case snapshotFailed
        case photosDenied

        var errorDescription: String? {
            switch self {
            case .denied:         return "Location is off for Shell Citadel. Settings › Privacy › Location Services."
            case .noFix:          return "No location fix yet. Try again in a moment."
            case .snapshotFailed: return "The map picture could not be rendered."
            case .photosDenied:   return "Shell Citadel is not allowed to add to your photo library."
            }
        }
    }

    private override init() {
        super.init()
        manager.delegate = self
        // The NORMAL state of this app. Precision is borrowed for one pin drop and
        // handed straight back.
        manager.desiredAccuracy = kCLLocationAccuracyReduced
    }

    // MARK: - B · the silent stamp

    /// Ask once, at launch, and only if he has never been asked. Never re-prompts:
    /// a permission dialog that reappears is how an app gets denied permanently.
    func requestAuthorizationIfNeeded() {
        guard manager.authorizationStatus == .notDetermined else { return }
        manager.requestWhenInUseAuthorization()
    }

    /// A single low-power fix to keep `lastFix` warm. Called when the app comes to the
    /// foreground, NOT on a timer and NOT per message — `startUpdatingLocation` would
    /// hold the radio open for the life of the session, and battery is already a stated
    /// constraint of his.
    func refresh() {
        guard isAuthorized else { return }
        manager.requestLocation()
    }

    /// `28.96,-95.28` — rounded at the source to 2 decimal places, ~1.1 km.
    /// Returns nil rather than a stale-but-plausible number when there is no fix at all;
    /// "nothing" is honest and "0,0" is the Gulf of Guinea.
    func coarseStamp() -> String? {
        guard let fix = lastFix ?? manager.location else { return nil }
        let c = fix.coordinate
        return String(format: "%.2f,%.2f", c.latitude, c.longitude)
    }

    /// What actually rides along on a human→Claude message. Not drawn in his bubble.
    /// Deliberately bracketed and named so that a human reading the raw thread months
    /// later can tell what it is without asking.
    func messageSuffix() -> String {
        guard let stamp = coarseStamp() else { return "" }
        return "\n[gps \(stamp)]"
    }

    private var isAuthorized: Bool {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways: return true
        default: return false
        }
    }

    // MARK: - A · the pin drop

    /// A fresh, precise fix — borrowing full accuracy for this one tap if he has Precise
    /// Location switched off.
    func preciseFix() async throws -> CLLocation {
        guard isAuthorized else { throw Failure.denied }

        if manager.accuracyAuthorization == .reducedAccuracy {
            // The completion-handler form, wrapped. An error here is NOT fatal: he may
            // decline precision and still want a pin. We fall through to whatever
            // accuracy we are allowed rather than refusing to drop one at all.
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                manager.requestTemporaryFullAccuracyAuthorization(
                    withPurposeKey: Self.pinDropPurposeKey
                ) { _ in cont.resume() }
            }
        }

        // Raised only for this request, and put back below, so the reduced-by-default
        // promise in the file header stays true.
        manager.desiredAccuracy = kCLLocationAccuracyBest
        defer { manager.desiredAccuracy = kCLLocationAccuracyReduced }

        return try await withCheckedThrowingContinuation { cont in
            pending.append(cont)
            manager.requestLocation()
        }
    }

    /// A small map with a pin on it. Rendered without ever presenting a map view.
    ///
    /// 600×400 at ~400 m across: wide enough to show which street, small enough that it
    /// is a few tens of KB over cellular. The same reasoning as `PhotoSend.longEdge` —
    /// this has to be READABLE, not archival.
    static func snapshot(at coordinate: CLLocationCoordinate2D) async throws -> UIImage {
        let options = MKMapSnapshotter.Options()
        options.region = MKCoordinateRegion(center: coordinate,
                                            latitudinalMeters: 400,
                                            longitudinalMeters: 400)
        options.size = CGSize(width: 600, height: 400)
        options.pointOfInterestFilter = .includingAll

        let snapshot = try await MKMapSnapshotter(options: options).start()

        // The snapshotter draws the map but not the pin — the pin is ours to composite,
        // at the point the snapshot says the coordinate landed on.
        let renderer = UIGraphicsImageRenderer(size: options.size)
        return renderer.image { context in
            snapshot.image.draw(at: .zero)

            let point = snapshot.point(for: coordinate)
            guard options.size.width > point.x, point.x > 0,
                  options.size.height > point.y, point.y > 0 else { return }

            let radius: CGFloat = 9
            let dot = CGRect(x: point.x - radius, y: point.y - radius,
                             width: radius * 2, height: radius * 2)
            context.cgContext.setFillColor(UIColor.systemRed.cgColor)
            context.cgContext.setStrokeColor(UIColor.white.cgColor)
            context.cgContext.setLineWidth(3)
            context.cgContext.fillEllipse(in: dot)
            context.cgContext.strokeEllipse(in: dot)
        }
    }

    /// Add-only. The app never needs to READ his library, and add-only is both the
    /// correct level and the lighter ask at App Store review.
    ///
    /// ⚠️ `PHAssetChangeRequest.location` is NOT set, on purpose. See the header.
    static func saveToPhotoLibrary(_ image: UIImage) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { throw Failure.photosDenied }

        try await PHPhotoLibrary.shared().performChanges {
            _ = PHAssetChangeRequest.creationRequestForAsset(from: image)
        }
    }

    /// `2026-08-30-0715-22-pin.jpg` — the same sortable shape as `PhotoSend.filename()`,
    /// with `-pin` so a folder of them can be told apart from photographs at a glance.
    static func filename(_ date: Date = Date()) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd-HHmm-ss"
        f.locale = Locale(identifier: "en_US_POSIX")
        return "\(f.string(from: date))-pin.jpg"
    }

    // MARK: - CLLocationManagerDelegate

    nonisolated func locationManager(_ manager: CLLocationManager,
                                     didUpdateLocations locations: [CLLocation]) {
        guard let newest = locations.last else { return }
        Task { @MainActor in
            self.lastFix = newest
            let waiting = self.pending
            self.pending.removeAll()
            for cont in waiting { cont.resume(returning: newest) }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager,
                                     didFailWithError error: Error) {
        Task { @MainActor in
            let waiting = self.pending
            self.pending.removeAll()
            // A failed one-shot with a usable cached fix is not worth failing over —
            // a five-minute-old position is the difference between "he is at the house"
            // and nothing at all.
            for cont in waiting {
                if let fallback = self.lastFix {
                    cont.resume(returning: fallback)
                } else {
                    cont.resume(throwing: Failure.noFix)
                }
            }
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            // Newly granted: take one fix so the very first message he sends already
            // carries a stamp rather than the second one.
            if self.isAuthorized { manager.requestLocation() }
        }
    }
}

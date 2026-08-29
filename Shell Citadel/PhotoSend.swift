//
//  PhotoSend.swift
//  Shell Citadel
//
//  The camera button.  Michael, 2026-08-27:
//  "For this app i will need a camera plus button above the keyboard like in imessages"
//
//  WHAT IT IS FOR.  He works in a wheelchair in a rack room. A serial number on the back
//  of a server, a cable that goes somewhere unexpected, an error on a screen he cannot
//  copy and paste from — all of those are one photograph and twenty minutes of typing.
//
//  ── CONTAINMENT ────────────────────────────────────────────────────────────────
//  Michael, 2026-08-27: "that way the pictures and videos stay within shell citadel
//  and dont leave its sandbox."
//
//  He was not describing where to file things. He was describing a BOUNDARY, and the
//  reason is that these photographs are of medical documents, of the inside of his
//  house, of his equipment. So:
//
//    • The camera writes into this app and NOWHERE ELSE. There is no
//      UIImageWriteToSavedPhotosAlbum here and there must never be one. The moment an
//      image lands in the photo library it is synced to iCloud and it has left.
//    • Nothing is kept. The bytes exist in memory, go up the wire, and are dropped.
//      This file has no cache and no directory of its own.
//    • On the Mac the honest limit applies: for Claude to look at a picture it has to
//      be on the Mac's disk. What we control is that it goes to one known folder,
//      outside the apartment repo, under his own TopSecret-by-default rule.
//
//  ── WHY IT IS COMPRESSED ───────────────────────────────────────────────────────
//  A modern iPhone photograph is 3-6 MB. Over cellular, on a connection that is also
//  carrying the conversation, that is a long stall with no progress bar. A serial
//  number needs to be READABLE, not archival — 2000px on the long edge at quality 0.7
//  lands around 400 KB and every character is still sharp.
//

import SwiftUI
import UIKit

enum PhotoSend {

    /// Target for the long edge. Chosen so that small print — a service tag, a MAC
    /// address on a sticker — survives, while the file stays small enough to send from
    /// a rack room on one bar.
    static let longEdge: CGFloat = 2000
    static let quality: CGFloat = 0.7

    /// Downscale and JPEG-encode. Returns nil only if the image cannot be encoded at
    /// all, which in practice means it was empty.
    static func prepare(_ image: UIImage) -> Data? {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return nil }

        let longest = max(size.width, size.height)
        let scale = longest > longEdge ? longEdge / longest : 1
        let target = CGSize(width: size.width * scale, height: size.height * scale)

        // `UIGraphicsImageRenderer` respects the image's orientation, which matters
        // here more than usual: a photograph of a label held sideways that arrives
        // rotated is a photograph Claude reads the wrong way up.
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1          // target is already in pixels, not points
        let rendered = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        return rendered.jpegData(compressionQuality: quality)
    }

    /// `2026-08-27-0914-32.jpg` — sortable, readable, and unique enough for a folder
    /// that a human opens by hand. Deliberately not a UUID: he will be looking at these
    /// filenames in a message, and a UUID tells him nothing about when it was taken.
    static func filename(_ date: Date = Date()) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd-HHmm-ss"
        f.locale = Locale(identifier: "en_US_POSIX")
        return "\(f.string(from: date)).jpg"
    }
}

// MARK: - Camera

/// A camera that hands the image back in memory.
///
/// `UIImagePickerController` rather than SwiftUI's `PhotosPicker` for this half,
/// because PhotosPicker cannot open the camera — it is a library browser. The camera
/// genuinely still needs the UIKit controller.
struct CameraCapture: UIViewControllerRepresentable {
    var onCaptured: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        // Guarded because the simulator has no camera, and an unguarded .camera source
        // crashes rather than degrades.
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        private let parent: CameraCapture
        init(_ parent: CameraCapture) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            // .originalImage, never .editedImage — nothing here offers editing, and
            // asking for the edited one returns nil when there was no edit.
            if let image = info[.originalImage] as? UIImage {
                parent.onCaptured(image)
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

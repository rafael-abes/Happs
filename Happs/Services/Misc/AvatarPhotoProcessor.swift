//
//  AvatarPhotoProcessor.swift
//  Happs
//
//  Created by Rafa Abes on 11/2/26.
//


// CODE OVERVIEW
// A pure image helper (caseless enum, no state) used by the profile photo editor. process(_:)
// takes the raw bytes from PhotosPicker and returns a 256 px square JPEG under 40 KB, or nil if
// the data is not an image or cannot be made small enough. Cropping and compression are done
// here, before upload, so the stored profile photo stays small and cheap to load everywhere.
//
import UIKit

nonisolated enum AvatarPhotoProcessor {
    /// Width and height in pixels of the final square avatar.
    static let side: CGFloat = 256
    /// Upper size limit for the JPEG, in bytes.
    static let maxBytes = 40_000

    /// Decodes, square-crops and compresses a photo. Returns nil if it is not a valid image or
    /// still exceeds maxBytes at the lowest quality tried.
    static func process(_ data: Data) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let square = croppedSquare(image)
        // Start at good quality and step down by 0.1 until the size fits, so quality is only lost when needed.
        var quality: CGFloat = 0.8
        while quality >= 0.3 {
            if let jpeg = square.jpegData(compressionQuality: quality), jpeg.count <= maxBytes {
                return jpeg
            }
            quality -= 0.1
        }
        return nil
    }

    /// Scales the image so its shorter side is exactly `side`, then centres it in a square canvas (centre crop).
    static func croppedSquare(_ image: UIImage) -> UIImage {
        let shortest = min(image.size.width, image.size.height)
        guard shortest > 0 else { return image }
        let format = UIGraphicsImageRendererFormat()
        // Scale 1 means 1 point = 1 pixel; otherwise the renderer would use the screen scale and make a bigger image.
        format.scale = 1
        // No alpha channel is needed for a JPEG and it renders faster.
        format.opaque = true
        let scale = side / shortest
        let drawSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        // Negative offset on the longer axis pushes the overflow outside the canvas, which crops it evenly.
        let origin = CGPoint(x: (side - drawSize.width) / 2, y: (side - drawSize.height) / 2)
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { _ in
            image.draw(in: CGRect(origin: origin, size: drawSize))
        }
    }
}

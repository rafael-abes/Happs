//
//  ImageProcessor.swift
//  Happs
//
//  Created by Rafa Abes on 10/27/26.
//
// CODE OVERVIEW
// Pure image helper (caseless enum) used before uploading recap photos to Supabase storage.
// prepare(_:) makes two versions from one picked photo: a 1600 px JPEG for attendees and a 16 px
// JPEG that is shown blurred to people who did not attend. Doing this on the device keeps uploads
// small, which matters for the free storage allowance. Types are nonisolated and Sendable so the
// work can run off the main thread (assumed reason).
//
import UIKit

/// The two JPEG versions produced for one uploaded photo.
nonisolated struct PreparedImage: Sendable {
    /// About 1600 px on the long side, JPEG 0.7, usually 200 to 400 KB.
    let full: Data
    /// 16 px on the long side. Shown blurred to people who did not attend.
    let preview: Data
}

/// Shrinks photos before upload so the free 1 GB of storage goes a long way.
nonisolated enum ImageProcessor {
    /// Returns both versions, or nil if the data is not a decodable image or encoding fails.
    static func prepare(_ data: Data) -> PreparedImage? {
        guard let image = UIImage(data: data),
              let full = resized(image, maxDimension: 1600).jpegData(compressionQuality: 0.7),
              let preview = resized(image, maxDimension: 16).jpegData(compressionQuality: 0.4)
        else { return nil }
        return PreparedImage(full: full, preview: preview)
    }

    /// Scales so the longest side is at most maxDimension, keeping the aspect ratio. Never enlarges.
    static func resized(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let longest = max(image.size.width, image.size.height)
        guard longest > 0 else { return image }
        // min with 1 stops small images being scaled up.
        let scale = min(1, maxDimension / longest)
        let size = CGSize(
            // max(1, ...) prevents a zero sized canvas for extreme aspect ratios.
            width: max(1, (image.size.width * scale).rounded()),
            height: max(1, (image.size.height * scale).rounded())
        )
        let format = UIGraphicsImageRendererFormat()
        // 1 point = 1 pixel, so the size above is the real pixel size.
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    /// Small solid image for the Supabase self-test.
    static func sampleJPEG() -> Data {
        let size = CGSize(width: 40, height: 40)
        let image = UIGraphicsImageRenderer(size: size).image { context in
            UIColor.systemGreen.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
        return image.jpegData(compressionQuality: 0.7) ?? Data()
    }
}


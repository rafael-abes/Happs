//
//  ImageProcessor.swift
//  Happs
//
//  Created by Rafa Abes on 10/27/26.
//
import UIKit

nonisolated struct PreparedImage: Sendable {
    /// About 1600 px on the long side, JPEG 0.7, usually 200 to 400 KB.
    let full: Data
    /// 16 px on the long side. Shown blurred to people who did not attend.
    let preview: Data
}

/// Shrinks photos before upload so the free 1 GB of storage goes a long way.
nonisolated enum ImageProcessor {
    static func prepare(_ data: Data) -> PreparedImage? {
        guard let image = UIImage(data: data),
              let full = resized(image, maxDimension: 1600).jpegData(compressionQuality: 0.7),
              let preview = resized(image, maxDimension: 16).jpegData(compressionQuality: 0.4)
        else { return nil }
        return PreparedImage(full: full, preview: preview)
    }

    static func resized(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let longest = max(image.size.width, image.size.height)
        guard longest > 0 else { return image }
        let scale = min(1, maxDimension / longest)
        let size = CGSize(
            width: max(1, (image.size.width * scale).rounded()),
            height: max(1, (image.size.height * scale).rounded())
        )
        let format = UIGraphicsImageRendererFormat()
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


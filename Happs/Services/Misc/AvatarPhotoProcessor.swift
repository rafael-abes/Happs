//
//  AvatarPhotoProcessor.swift
//  Happs
//
//  Created by Rafa Abes on 11/2/26.
//


import UIKit

nonisolated enum AvatarPhotoProcessor {
    static let side: CGFloat = 256
    static let maxBytes = 40_000

    static func process(_ data: Data) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let square = croppedSquare(image)
        var quality: CGFloat = 0.8
        while quality >= 0.3 {
            if let jpeg = square.jpegData(compressionQuality: quality), jpeg.count <= maxBytes {
                return jpeg
            }
            quality -= 0.1
        }
        return nil
    }

    static func croppedSquare(_ image: UIImage) -> UIImage {
        let shortest = min(image.size.width, image.size.height)
        guard shortest > 0 else { return image }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let scale = side / shortest
        let drawSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let origin = CGPoint(x: (side - drawSize.width) / 2, y: (side - drawSize.height) / 2)
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { _ in
            image.draw(in: CGRect(origin: origin, size: drawSize))
        }
    }
}

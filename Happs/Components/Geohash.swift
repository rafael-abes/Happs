//
//  Geohash.swift
//  Happs
//
//  Created by Rafa Abes on 10/19/26.
//
import Foundation

enum Geohash {
    private static let alphabet = Array("0123456789bcdefghjkmnpqrstuvwxyz")
    
    static func encode(latitude: Double, longitude: Double, precision: Int = 9) -> String {
        var latRange: (low: Double, high: Double) = (-90, 90)
        var lonRange: (low: Double, high: Double) = (-180, 180)
        var result = ""
        var isLongitudeBit = true
        var bitCount = 0
        var index = 0
        
        while result.count < precision {
            if isLongitudeBit {
                let mid = (lonRange.low + lonRange.high) / 2
                if longitude >= mid {
                    index = index * 2 + 1
                    lonRange.low = mid
                } else {
                    index *= 2
                    lonRange.high = mid
                }
            } else {
                let mid = (latRange.low + latRange.high) / 2
                if latitude >= mid {
                    index = index * 2 + 1
                    latRange.low = mid
                } else {
                    index *= 2
                    latRange.high = mid
                }
            }
            isLongitudeBit.toggle()
            bitCount += 1
            if bitCount == 5 {
                result.append(alphabet[index])
                bitCount = 0
                index = 0
            }
        }
        return result
    }
}

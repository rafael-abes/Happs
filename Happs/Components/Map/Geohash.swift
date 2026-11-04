//
//  Geohash.swift
//  Happs
//
//  Created by Rafa Abes on 10/19/26.
//
// CODE OVERVIEW
// A small hand-written geohash encoder: it turns a latitude and longitude into a short string
// (for example 9 characters) that identifies a grid cell. TicketmasterService calls it to build
// the `geoPoint` query parameter for the Ticketmaster Discovery API search. Writing it here
// avoids adding a library for one function. It is a pure function with no state.
import Foundation

/// Namespace for geohash encoding. Geohash is a standard scheme: it repeatedly halves the longitude and
/// latitude ranges, interleaves those bits, and writes each group of 5 bits as one base-32 character.
enum Geohash {
    /// The geohash base-32 alphabet. It deliberately leaves out the letters a, i, l and o.
    private static let alphabet = Array("0123456789bcdefghjkmnpqrstuvwxyz")
    
    /// Encodes a coordinate as a geohash.
    /// - Parameters:
    ///   - latitude: Degrees, -90 to 90.
    ///   - longitude: Degrees, -180 to 180.
    ///   - precision: Number of characters. More characters means a smaller cell; 9 is roughly a few metres across.
    /// - Returns: The geohash string.
    static func encode(latitude: Double, longitude: Double, precision: Int = 9) -> String {
        // Each range starts as the whole world and is halved once per bit.
        var latRange: (low: Double, high: Double) = (-90, 90)
        var lonRange: (low: Double, high: Double) = (-180, 180)
        var result = ""
        // Bits alternate starting with longitude. This is part of the geohash definition.
        var isLongitudeBit = true
        // bitCount counts bits collected towards the current character; index accumulates their value.
        var bitCount = 0
        var index = 0
        
        // Stop once enough characters have been produced.
        while result.count < precision {
            if isLongitudeBit {
                // Bit is 1 if the point is in the upper half of the range (keep that half), 0 for the lower half.
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
            // Every 5 bits form an index 0 to 31 into the alphabet. Then reset for the next character.
            if bitCount == 5 {
                result.append(alphabet[index])
                bitCount = 0
                index = 0
            }
        }
        return result
    }
}

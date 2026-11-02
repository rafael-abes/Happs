//
//  Color+Happs.swift
//  Happs
//
//  Created by Rafa Abes on 10/10/26.
//
import SwiftUI
import UIKit

extension Color {
    /// Original brand green. Decorative use only. See the documentation above.
    static let happsGreen = Color(red: 0.38, green: 0.68, blue: 0.31)

    /// Green for text and small icons. Adapts to dark mode and Increased Contrast.
    static let happsGreenText = Color(uiColor: HappsPalette.greenText)

    /// Green behind white text or white icons. Adapts to Increased Contrast.
    static let happsGreenFill = Color(uiColor: HappsPalette.greenFill)

    /// Red behind white text or white icons, such as unread badges.
    static let happsRedFill = Color(uiColor: HappsPalette.redFill)
}

/// The raw UIColors, so the unit tests can resolve them in any appearance.
enum HappsPalette {
    static let greenText = UIColor { traits in
        let high = traits.accessibilityContrast == .high
        if traits.userInterfaceStyle == .dark {
            return high
                ? UIColor(red: 0.55, green: 0.82, blue: 0.47, alpha: 1)
                : UIColor(red: 0.38, green: 0.68, blue: 0.31, alpha: 1)
        }
        return high
            ? UIColor(red: 0.10, green: 0.36, blue: 0.10, alpha: 1)
            : UIColor(red: 0.16, green: 0.45, blue: 0.16, alpha: 1)
    }

    static let greenFill = UIColor { traits in
        traits.accessibilityContrast == .high
            ? UIColor(red: 0.10, green: 0.36, blue: 0.10, alpha: 1)
            : UIColor(red: 0.16, green: 0.45, blue: 0.16, alpha: 1)
    }

    static let redFill = UIColor { traits in
        traits.accessibilityContrast == .high
            ? UIColor(red: 0.62, green: 0.05, blue: 0.05, alpha: 1)
            : UIColor(red: 0.75, green: 0.08, blue: 0.08, alpha: 1)
    }
}

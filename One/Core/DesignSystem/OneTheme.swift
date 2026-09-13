import SwiftUI

enum OneTheme {
    static let canvas = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(red: 0.08, green: 0.09, blue: 0.11, alpha: 1) : UIColor(red: 0.985, green: 0.985, blue: 0.99, alpha: 1)
    })
    static let surface = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(red: 0.14, green: 0.15, blue: 0.18, alpha: 1) : UIColor.white
    })
    static let controlFill = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(red: 0.18, green: 0.19, blue: 0.22, alpha: 1) : UIColor(red: 0.95, green: 0.95, blue: 0.96, alpha: 1)
    })
    static let inverseSurface = Color(uiColor: UIColor { traits in
        // Inverse surfaces are intentionally dark in both appearances so camera and
        // assistant cards retain a stable, high-contrast identity.
        traits.userInterfaceStyle == .dark ? UIColor(red: 0.04, green: 0.05, blue: 0.07, alpha: 1) : UIColor(red: 0.09, green: 0.10, blue: 0.12, alpha: 1)
    })
    static let ink = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor.white : UIColor(red: 0.082, green: 0.090, blue: 0.110, alpha: 1)
    })
    static let secondaryInk = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(white: 0.78, alpha: 1) : UIColor(red: 0.30, green: 0.32, blue: 0.36, alpha: 1)
    })
    static let accentBlue = Color(red: 0.09, green: 0.41, blue: 0.91)
    static let accentCyan = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(red: 0.35, green: 0.88, blue: 0.92, alpha: 1) : UIColor(red: 0.02, green: 0.48, blue: 0.56, alpha: 1)
    })
    static let cyan = accentCyan
    static let mint = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(red: 0.44, green: 0.94, blue: 0.68, alpha: 1) : UIColor(red: 0.07, green: 0.45, blue: 0.25, alpha: 1)
    })
    static let amber = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(red: 1.0, green: 0.76, blue: 0.30, alpha: 1) : UIColor(red: 0.62, green: 0.32, blue: 0.02, alpha: 1)
    })
}

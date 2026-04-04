import SwiftUI

struct ManagementTheme {
    let colorScheme: ColorScheme

    var gradientColors: [Color] {
        switch colorScheme {
        case .dark:
            [
                Color(red: 0.10, green: 0.11, blue: 0.12),
                Color(red: 0.12, green: 0.13, blue: 0.14),
            ]
        default:
            [
                Color(red: 0.96, green: 0.97, blue: 0.99),
                Color(red: 0.91, green: 0.94, blue: 0.98),
            ]
        }
    }

    var cardBackground: Color {
        switch colorScheme {
        case .dark:
            Color.white.opacity(0.05)
        default:
            Color.white.opacity(0.88)
        }
    }

    var cardBorder: Color {
        switch colorScheme {
        case .dark:
            Color.white.opacity(0.08)
        default:
            Color.black.opacity(0.08)
        }
    }

    var mutedSurface: Color {
        switch colorScheme {
        case .dark:
            Color.white.opacity(0.03)
        default:
            Color.black.opacity(0.035)
        }
    }

    var inputBackground: Color {
        switch colorScheme {
        case .dark:
            Color.white.opacity(0.05)
        default:
            Color.white.opacity(0.96)
        }
    }

    var inputBorder: Color {
        switch colorScheme {
        case .dark:
            Color.white.opacity(0.08)
        default:
            Color.black.opacity(0.10)
        }
    }

    var secondaryText: Color {
        switch colorScheme {
        case .dark:
            Color.white.opacity(0.68)
        default:
            Color.black.opacity(0.62)
        }
    }

    var shadowColor: Color {
        switch colorScheme {
        case .dark:
            Color.black.opacity(0.18)
        default:
            Color.black.opacity(0.10)
        }
    }
}

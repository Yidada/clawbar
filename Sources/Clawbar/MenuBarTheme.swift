import SwiftUI

struct MenuBarTheme {
    let colorScheme: ColorScheme

    var chromeBackground: LinearGradient {
        switch colorScheme {
        case .dark:
            LinearGradient(
                colors: [
                    Color(red: 0.10, green: 0.12, blue: 0.15),
                    Color(red: 0.07, green: 0.08, blue: 0.10),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        default:
            LinearGradient(
                colors: [
                    Color(red: 0.96, green: 0.97, blue: 0.99),
                    Color(red: 0.93, green: 0.95, blue: 0.98),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    var panelBackground: Color {
        switch colorScheme {
        case .dark:
            Color(red: 0.11, green: 0.12, blue: 0.14)
        default:
            Color.white.opacity(0.94)
        }
    }

    var panelBorder: Color {
        switch colorScheme {
        case .dark:
            Color.white.opacity(0.10)
        default:
            Color.black.opacity(0.10)
        }
    }

    var rowBackground: Color {
        switch colorScheme {
        case .dark:
            Color.white.opacity(0.04)
        default:
            Color.black.opacity(0.035)
        }
    }

    var divider: Color {
        switch colorScheme {
        case .dark:
            Color.white.opacity(0.08)
        default:
            Color.black.opacity(0.09)
        }
    }

    var primaryText: Color {
        switch colorScheme {
        case .dark:
            Color.white.opacity(0.96)
        default:
            Color.black.opacity(0.88)
        }
    }

    var secondaryText: Color {
        switch colorScheme {
        case .dark:
            Color.white.opacity(0.68)
        default:
            Color.black.opacity(0.58)
        }
    }

    var tertiaryText: Color {
        switch colorScheme {
        case .dark:
            Color.white.opacity(0.50)
        default:
            Color.black.opacity(0.45)
        }
    }

    var accent: Color {
        Color(red: 0.42, green: 0.79, blue: 0.90)
    }

    var actionIcon: Color {
        switch colorScheme {
        case .dark:
            accent.opacity(0.92)
        default:
            Color(red: 0.18, green: 0.53, blue: 0.66)
        }
    }

    var shadowColor: Color {
        switch colorScheme {
        case .dark:
            Color.black.opacity(0.32)
        default:
            Color.black.opacity(0.12)
        }
    }

    func pillForeground(for level: OpenClawHealthLevel) -> Color {
        switch level {
        case .healthy:
            accent
        case .warning:
            Color.orange
        case .critical:
            Color.red.opacity(0.88)
        case .unknown:
            tertiaryText
        }
    }

    func pillBackground(for level: OpenClawHealthLevel) -> Color {
        pillForeground(for: level).opacity(colorScheme == .dark ? 0.14 : 0.10)
    }
}

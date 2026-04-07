enum ClawbarDebugOptions {
    static var isDevelopmentBuild: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
    }

    static func shouldShowDebugUI(globalDebugEnabled: Bool) -> Bool {
        isDevelopmentBuild || globalDebugEnabled
    }
}

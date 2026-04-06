import Foundation

enum ApplicationManagementSection: String, CaseIterable, Identifiable {
    case provider
    case gateway
    case channels

    var id: String { rawValue }
}

@MainActor
final class ApplicationManagementRouter: ObservableObject {
    static let shared = ApplicationManagementRouter()

    @Published var selectedSection: ApplicationManagementSection = .provider

    func show(_ section: ApplicationManagementSection) {
        selectedSection = section
    }
}

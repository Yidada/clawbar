import Foundation

enum FeishuRegistrationClientError: LocalizedError {
    case invalidResponse
    case unsupportedAuthMethod
    case malformedPayload

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "飞书注册接口返回了不可识别的响应。"
        case .unsupportedAuthMethod:
            return "当前环境不支持 client_secret 注册。"
        case .malformedPayload:
            return "飞书注册接口返回的数据不完整。"
        }
    }
}

struct FeishuRegistrationInitResponse: Decodable, Equatable, Sendable {
    let supportedAuthMethods: [String]

    enum CodingKeys: String, CodingKey {
        case supportedAuthMethods = "supported_auth_methods"
    }
}

struct FeishuRegistrationBeginResponse: Decodable, Equatable, Sendable {
    let deviceCode: String
    let verificationURL: String
    let expiresIn: Int?
    let interval: Int?

    enum CodingKeys: String, CodingKey {
        case deviceCode = "device_code"
        case verificationURL = "verification_uri_complete"
        case expiresIn = "expire_in"
        case interval
    }
}

struct FeishuRegistrationUserInfo: Decodable, Equatable, Sendable {
    let openID: String?
    let tenantBrand: FeishuTenantBrand?

    enum CodingKeys: String, CodingKey {
        case openID = "open_id"
        case tenantBrand = "tenant_brand"
    }
}

struct FeishuRegistrationPollResponse: Decodable, Equatable, Sendable {
    let clientID: String?
    let clientSecret: String?
    let error: String?
    let errorDescription: String?
    let userInfo: FeishuRegistrationUserInfo?

    enum CodingKeys: String, CodingKey {
        case clientID = "client_id"
        case clientSecret = "client_secret"
        case error
        case errorDescription = "error_description"
        case userInfo = "user_info"
    }
}

struct FeishuRegistrationClient: Sendable {
    typealias Transport = @Sendable (_ request: URLRequest) async throws -> (Data, HTTPURLResponse)

    let transport: Transport

    init(transport: @escaping Transport) {
        self.transport = transport
    }

    func initialize() async throws -> FeishuRegistrationInitResponse {
        let request = makeRequest(
            brand: .feishu,
            action: "init",
            parameters: [:]
        )
        let (data, _) = try await transport(request)
        let response = try decode(FeishuRegistrationInitResponse.self, from: data)
        guard response.supportedAuthMethods.contains("client_secret") else {
            throw FeishuRegistrationClientError.unsupportedAuthMethod
        }
        return response
    }

    func begin(brand: FeishuTenantBrand) async throws -> FeishuRegistrationBeginResponse {
        let request = makeRequest(
            brand: brand,
            action: "begin",
            parameters: [
                "archetype": "PersonalAgent",
                "auth_method": "client_secret",
                "request_user_info": "open_id",
            ]
        )
        let (data, _) = try await transport(request)
        let response = try decode(FeishuRegistrationBeginResponse.self, from: data)
        guard trimmedNonEmpty(response.deviceCode) != nil,
              trimmedNonEmpty(response.verificationURL) != nil else {
            throw FeishuRegistrationClientError.malformedPayload
        }
        return response
    }

    func poll(deviceCode: String, brand: FeishuTenantBrand) async throws -> FeishuRegistrationPollResponse {
        let request = makeRequest(
            brand: brand,
            action: "poll",
            parameters: ["device_code": deviceCode]
        )
        let (data, _) = try await transport(request)
        return try decode(FeishuRegistrationPollResponse.self, from: data)
    }

    static let live = FeishuRegistrationClient { request in
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw FeishuRegistrationClientError.invalidResponse
        }
        return (data, httpResponse)
    }

    private func makeRequest(
        brand: FeishuTenantBrand,
        action: String,
        parameters: [String: String]
    ) -> URLRequest {
        var request = URLRequest(url: brand.registrationBaseURL.appending(path: "/oauth/v1/app/registration"))
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        var components = URLComponents()
        components.queryItems = ([URLQueryItem(name: "action", value: action)] + parameters
            .map { URLQueryItem(name: $0.key, value: $0.value) })
            .sorted(by: { $0.name < $1.name })
        request.httpBody = components.percentEncodedQuery?.data(using: .utf8)
        return request
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw FeishuRegistrationClientError.invalidResponse
        }
    }
}

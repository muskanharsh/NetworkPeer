import Foundation

public actor NetworkPeerAPI {
    private let baseURL: URL
    private let urlSession: URLSession
    private let sessionStore: SessionStoring
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder
    private let maximumEvidenceBytes: Int64
    private var refreshFlight: RefreshFlight?

    private struct RefreshFlight {
        let id: UUID
        let session: StoredSession
        let task: Task<StoredSession, Error>
    }

    public init(
        baseURL: URL,
        sessionStore: SessionStoring,
        urlSession: URLSession = .shared,
        maximumEvidenceBytes: Int64 = EvidenceUploadLimits.defaultMaximumFileSizeBytes,
    ) throws {
        guard baseURL.scheme == "https" || baseURL.host == "localhost" || baseURL.host == "127.0.0.1" else {
            throw NetworkPeerAPIError.invalidConfiguration("NetworkPeer API must use HTTPS outside local development.")
        }
        guard EvidenceUploadLimits.isValid(maximumEvidenceBytes) else {
            throw NetworkPeerAPIError.invalidConfiguration("NETWORKPEER_MAX_EVIDENCE_BYTES must be greater than zero.")
        }
        self.baseURL = baseURL.absoluteString.hasSuffix("/") ? baseURL : baseURL.appendingPathComponent("")
        self.sessionStore = sessionStore
        self.urlSession = urlSession
        self.maximumEvidenceBytes = maximumEvidenceBytes
        decoder = JSONDecoder()
        encoder = JSONEncoder()
    }

    public func session() -> StoredSession? {
        sessionStore.read()
    }

    public func requestOTP(email: String, role: UserRole) async throws -> OTPRequestResult {
        try validateEmail(email)
        return try await request(path: "auth/email-otp/request", method: "POST", body: try encode(OTPRequestBody(email: email, role: role)), requiresAuthentication: false)
    }

    @discardableResult
    public func verifyOTP(email: String, code: String, challengeId: String) async throws -> StoredSession {
        try validateEmail(email)
        guard !code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw NetworkPeerAPIError.validation("Enter the verification code.")
        }
        let pair: TokenPair = try await request(
            path: "auth/email-otp/verify",
            method: "POST",
            body: try encode(OTPVerifyBody(email: email, otp: code, challengeId: challengeId)),
            requiresAuthentication: false,
        )
        let session = StoredSession(pair: pair)
        try sessionStore.save(session)
        return session
    }

    public func logout() async {
        guard let session = sessionStore.read() else { return }
        defer { _ = try? sessionStore.clear(ifMatches: session) }
        guard let body = try? encode(RefreshTokenBody(refreshToken: session.refreshToken)) else { return }
        // A refresh token can revoke its own family. Do not refresh an expired
        // access token merely to log out, because that can rotate the only
        // locally held refresh token before revocation is attempted.
        _ = try? await request(
            path: "auth/logout",
            method: "POST",
            body: body,
            requiresAuthentication: false,
            retryAfterRefresh: false,
        ) as LogoutResult
    }

    public func clientJobs(status: JobStatus? = nil, page: Int = 1, perPage: Int = 20) async throws -> ClientJobPage {
        guard page > 0, perPage > 0 else {
            throw NetworkPeerAPIError.validation("Page and page size must be positive.")
        }
        var query = [URLQueryItem(name: "page", value: String(page)), URLQueryItem(name: "per_page", value: String(perPage))]
        if let status { query.append(URLQueryItem(name: "status", value: status.rawValue)) }
        return try await request(path: "client/jobs", query: query)
    }

    public func clientJob(id: String) async throws -> ClientJobDetail {
        try await request(path: "client/jobs/\(id)")
    }

    public func clientEvidence(jobID: String) async throws -> ClientEvidenceReviewResponse {
        try validateIdentifier(jobID, message: "A job ID is required to review evidence.")
        return try await request(path: "client/jobs/\(jobID)/evidence")
    }

    public func createClientJob(_ body: CreateJobRequest) async throws -> Job {
        try CreateJobValidator.validate(body)
        return try await request(path: "client/jobs", method: "POST", body: try encode(body))
    }

    public func fundClientJob(id: String, idempotencyKey: String) async throws -> FundingResult {
        try validateIdempotencyKey(idempotencyKey)
        return try await request(path: "client/jobs/\(id)/fund", method: "POST", body: try encode(IdempotencyBody(idempotencyKey: idempotencyKey)))
    }

    public func approveClientJob(id: String, idempotencyKey: String) async throws -> ApprovalResult {
        try validateIdempotencyKey(idempotencyKey)
        return try await request(path: "client/jobs/\(id)/approve", method: "POST", body: try encode(IdempotencyBody(idempotencyKey: idempotencyKey)))
    }

    public func cancelClientJob(id: String, cancellationReason: String? = nil) async throws -> ClientJobCancelResult {
        try validateIdentifier(id, message: "A job ID is required to cancel a job.")
        let reason = cancellationReason?.trimmingCharacters(in: .whitespacesAndNewlines)
        return try await request(
            path: "client/jobs/\(id)/cancel",
            method: "POST",
            body: try encode(CancelClientJobBody(cancellationReason: reason?.isEmpty == true ? nil : reason)),
        )
    }

    public func completeClientJob(id: String) async throws -> ClientJobResolutionResult {
        try validateIdentifier(id, message: "A job ID is required to complete a job.")
        return try await request(path: "client/jobs/\(id)/complete", method: "POST")
    }

    public func disputeClientJob(id: String) async throws -> ClientJobResolutionResult {
        try validateIdentifier(id, message: "A job ID is required to dispute a job.")
        return try await request(path: "client/jobs/\(id)/dispute", method: "POST")
    }

    public func clientWallet() async throws -> WalletResponse {
        try await request(path: "client/wallet")
    }

    public func updateWorkerLocation(latitude: Double, longitude: Double) async throws {
        guard Point(longitude: longitude, latitude: latitude).isValid else {
            throw NetworkPeerAPIError.validation("Worker location coordinates are invalid.")
        }
        let _: WorkerLocationResult = try await request(
            path: "worker/location",
            method: "POST",
            body: try encode(WorkerLocationBody(latitude: latitude, longitude: longitude)),
        )
    }

    public func nearbyWorkerJobs(radiusKilometres: Int? = nil, page: Int = 1, perPage: Int = 20) async throws -> NearbyJobsPage {
        guard page > 0, perPage > 0 else {
            throw NetworkPeerAPIError.validation("Page and page size must be positive.")
        }
        if let radiusKilometres, radiusKilometres <= 0 {
            throw NetworkPeerAPIError.validation("Search radius must be greater than zero.")
        }
        var query = [URLQueryItem(name: "page", value: String(page)), URLQueryItem(name: "per_page", value: String(perPage))]
        if let radiusKilometres { query.append(URLQueryItem(name: "radius_km", value: String(radiusKilometres))) }
        return try await request(path: "worker/jobs/nearby", query: query)
    }

    public func workerJob(id: String) async throws -> WorkerJobDetail {
        try await request(path: "worker/jobs/\(id)")
    }

    public func acceptWorkerJob(id: String) async throws -> WorkerJobDetail {
        try await request(path: "worker/jobs/\(id)/accept", method: "POST")
    }

    public func workerWallet() async throws -> WalletResponse {
        try await request(path: "worker/wallet")
    }

    public func advanceWork(jobID: String, status: JobStatus) async throws -> WorkStatusResult {
        guard !jobID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw NetworkPeerAPIError.validation("A job ID is required to update work status.")
        }
        guard [.enRoute, .atLocation, .inProgress].contains(status) else {
            throw NetworkPeerAPIError.invalidConfiguration("Only worker progression states can be sent to /work/status.")
        }
        return try await request(path: "work/status", method: "POST", body: try encode(WorkStatusBody(jobID: jobID, status: status)))
    }

    public func reserveEvidence(_ body: ReserveEvidenceRequest) async throws -> EvidenceReservation {
        try EvidenceReservationValidator.validate(body, maximumFileSizeBytes: maximumEvidenceBytes)
        return try await request(path: "work/upload-url", method: "POST", body: try encode(body))
    }

    public func confirmEvidence(mediaID: String) async throws -> EvidenceSummary {
        guard !mediaID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw NetworkPeerAPIError.validation("An evidence ID is required for confirmation.")
        }
        return try await request(path: "work/evidence", method: "POST", body: try encode(ConfirmEvidenceBody(mediaID: mediaID)))
    }

    public func submitWork(jobID: String) async throws -> SubmitWorkResult {
        guard !jobID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw NetworkPeerAPIError.validation("A job ID is required to submit work.")
        }
        return try await request(path: "work/submit", method: "POST", body: try encode(SubmitWorkBody(jobID: jobID)))
    }

    public func sync(cursor: String = "0", limit: Int = 100) async throws -> SyncPage {
        guard limit > 0 else {
            throw NetworkPeerAPIError.validation("Sync cursor and limit are invalid.")
        }
        try validateCursor(cursor)
        return try await request(path: "sync", query: [URLQueryItem(name: "cursor", value: cursor), URLQueryItem(name: "limit", value: String(limit))])
    }

    public func workerSync(cursor: String = "0", limit: Int = 100) async throws -> WorkerSyncPage {
        guard limit > 0 else {
            throw NetworkPeerAPIError.validation("Sync cursor and limit are invalid.")
        }
        try validateCursor(cursor)
        return try await request(path: "worker/sync", query: [URLQueryItem(name: "cursor", value: cursor), URLQueryItem(name: "limit", value: String(limit))])
    }

    public func notifications(beforeCursor: String? = nil, limit: Int = 50) async throws -> NotificationPage {
        guard limit > 0 else {
            throw NetworkPeerAPIError.validation("Notification page size must be positive.")
        }
        var query = [URLQueryItem(name: "limit", value: String(limit))]
        if let beforeCursor {
            try validateCursor(beforeCursor)
            query.append(URLQueryItem(name: "before_cursor", value: beforeCursor))
        }
        return try await request(path: "notifications", query: query)
    }

    public func markNotificationRead(id: String) async throws -> NetworkPeerNotification {
        try validateIdentifier(id, message: "A notification ID is required to mark it read.")
        return try await request(path: "notifications/\(id)/read", method: "POST")
    }

    public func markAllNotificationsRead() async throws -> MarkAllNotificationsReadResult {
        try await request(path: "notifications/read-all", method: "POST")
    }

    public func registerDevice(token: String) async throws -> DeviceRegistration {
        guard !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw NetworkPeerAPIError.validation("A device token is required for notifications.")
        }
        return try await request(path: "notifications/devices", method: "POST", body: try encode(RegisterDeviceBody(token: token, platform: "IOS")))
    }

    public func unregisterDevice(token: String, retryAfterRefresh: Bool = true) async throws {
        guard !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw NetworkPeerAPIError.validation("A device token is required for notifications.")
        }
        try await requestDiscardingResponse(
            path: "notifications/devices",
            method: "DELETE",
            body: try encode(UnregisterDeviceBody(token: token)),
            retryAfterRefresh: retryAfterRefresh,
        )
    }

    private func validateIdempotencyKey(_ key: String) throws {
        guard !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw NetworkPeerAPIError.validation("A stable idempotency key is required to safely retry this action.")
        }
    }

    private func validateIdentifier(_ value: String, message: String) throws {
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw NetworkPeerAPIError.validation(message)
        }
    }

    private func validateCursor(_ cursor: String) throws {
        guard !cursor.isEmpty, cursor.unicodeScalars.allSatisfy({ (48 ... 57).contains($0.value) }) else {
            throw NetworkPeerAPIError.validation("Sync cursor is invalid.")
        }
    }

    private func validateEmail(_ email: String) throws {
        let value = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = value.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2,
              !parts[0].isEmpty,
              parts[1].contains("."),
              !parts[1].hasPrefix("."),
              !parts[1].hasSuffix("."),
              !value.contains(" ") else {
            throw NetworkPeerAPIError.validation("Enter a valid email address, for example name@example.com.")
        }
    }

    private func refresh(after unauthorizedSession: StoredSession?) async throws {
        guard let unauthorizedSession else {
            throw NetworkPeerAPIError.server(code: "UNAUTHENTICATED", message: "Sign in again to continue.", statusCode: 401)
        }
        while true {
            // A successful refresh or sign-in already replaced the credentials that sent the 401.
            guard sessionStore.read() == unauthorizedSession else { return }
            if let refreshFlight {
                do {
                    try await waitForRefresh(refreshFlight)
                } catch where refreshFlight.session == unauthorizedSession {
                    throw error
                } catch {
                    // A different session's failed refresh cannot invalidate this session.
                }
                continue
            }

            let id = UUID()
            let task = Task<StoredSession, Error> { [weak self] in
                guard let self else { throw CancellationError() }
                return try await self.performRefresh(using: unauthorizedSession)
            }
            let flight = RefreshFlight(id: id, session: unauthorizedSession, task: task)
            refreshFlight = flight
            try await waitForRefresh(flight)
            return
        }
    }

    private func waitForRefresh(_ flight: RefreshFlight) async throws {
        defer {
            if refreshFlight?.id == flight.id {
                refreshFlight = nil
            }
        }
        _ = try await flight.task.value
    }

    private func performRefresh(using existing: StoredSession) async throws -> StoredSession {
        do {
            let pair: TokenPair = try await request(
                path: "auth/refresh",
                method: "POST",
                body: try encode(RefreshTokenBody(refreshToken: existing.refreshToken)),
                requiresAuthentication: false,
                retryAfterRefresh: false,
            )
            let refreshed = StoredSession(pair: pair)
            if try sessionStore.replace(refreshed, ifMatches: existing) {
                return refreshed
            }
            guard let current = sessionStore.read() else {
                throw NetworkPeerAPIError.server(code: "UNAUTHENTICATED", message: "Sign in again to continue.", statusCode: 401)
            }
            return current
        } catch {
            // A one-time refresh token may be invalidated by a newer sign-in. Never clear that session.
            _ = try? sessionStore.clear(ifMatches: existing)
            throw error
        }
    }

    private func request<Payload: Codable & Sendable>(
        path: String,
        method: String = "GET",
        body: Data? = nil,
        query: [URLQueryItem] = [],
        requiresAuthentication: Bool = true,
        retryAfterRefresh: Bool = true,
    ) async throws -> Payload {
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        components?.queryItems = query.isEmpty ? nil : query
        guard let url = components?.url else { throw NetworkPeerAPIError.invalidConfiguration("Invalid NetworkPeer API URL.") }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = method
        urlRequest.httpBody = body
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        if body != nil { urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        let authorizationSession = requiresAuthentication ? sessionStore.read() : nil
        if let session = authorizationSession {
            urlRequest.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await urlSession.data(for: urlRequest)
        } catch {
            throw NetworkPeerAPIError.transport("Cannot reach NetworkPeer. Check your connection and try again.")
        }
        guard let http = response as? HTTPURLResponse else { throw NetworkPeerAPIError.invalidResponse }
        let envelope = try? decoder.decode(APIEnvelope<Payload>.self, from: data)

        if http.statusCode == 401, requiresAuthentication, retryAfterRefresh {
            try await refresh(after: authorizationSession)
            return try await request(
                path: path,
                method: method,
                body: body,
                query: query,
                requiresAuthentication: requiresAuthentication,
                retryAfterRefresh: false,
            )
        }

        guard (200 ..< 300).contains(http.statusCode), let envelope, envelope.success, let payload = envelope.data else {
            let error = envelope?.error
            throw NetworkPeerAPIError.server(
                code: error?.code ?? "REQUEST_FAILED",
                message: error?.message ?? "The request could not be completed.",
                statusCode: http.statusCode,
            )
        }
        return payload
    }

    private func requestDiscardingResponse(
        path: String,
        method: String = "GET",
        body: Data? = nil,
        query: [URLQueryItem] = [],
        requiresAuthentication: Bool = true,
        retryAfterRefresh: Bool = true,
    ) async throws {
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        components?.queryItems = query.isEmpty ? nil : query
        guard let url = components?.url else { throw NetworkPeerAPIError.invalidConfiguration("Invalid NetworkPeer API URL.") }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = method
        urlRequest.httpBody = body
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        if body != nil { urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        let authorizationSession = requiresAuthentication ? sessionStore.read() : nil
        if let session = authorizationSession {
            urlRequest.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await urlSession.data(for: urlRequest)
        } catch {
            throw NetworkPeerAPIError.transport("Cannot reach NetworkPeer. Check your connection and try again.")
        }
        guard let http = response as? HTTPURLResponse else { throw NetworkPeerAPIError.invalidResponse }
        let envelope = try? decoder.decode(APIEnvelope<JSONValue>.self, from: data)

        if http.statusCode == 401, requiresAuthentication, retryAfterRefresh {
            try await refresh(after: authorizationSession)
            return try await requestDiscardingResponse(
                path: path,
                method: method,
                body: body,
                query: query,
                requiresAuthentication: requiresAuthentication,
                retryAfterRefresh: false,
            )
        }

        guard (200 ..< 300).contains(http.statusCode) else {
            let error = envelope?.error
            throw NetworkPeerAPIError.server(
                code: error?.code ?? "REQUEST_FAILED",
                message: error?.message ?? "The request could not be completed.",
                statusCode: http.statusCode,
            )
        }
        guard data.isEmpty || envelope?.success == true else { throw NetworkPeerAPIError.invalidResponse }
    }

    private func encode<Body: Encodable>(_ body: Body) throws -> Data {
        do {
            return try encoder.encode(body)
        } catch {
            throw NetworkPeerAPIError.invalidConfiguration("NetworkPeer could not encode a request payload.")
        }
    }
}

public struct CreateJobRequest: Codable, Sendable {
    public let title: String
    public let description: String
    public let category: String
    public let budgetCents: Int64
    public let currency: String
    public let location: Point
    public let address: String?
    public let scheduledAt: String?
    public let metadata: [String: JSONValue]?
    public let publicTitle: String?
    public let publicDescription: String?
    public let idempotencyKey: String
    public let subtasks: [CreateSubtaskRequest]

    enum CodingKeys: String, CodingKey {
        case title, description, category, currency, location, address, metadata, subtasks
        case budgetCents = "budget_cents"
        case scheduledAt = "scheduled_at"
        case publicTitle = "public_title"
        case publicDescription = "public_description"
        case idempotencyKey = "idempotency_key"
    }

    public init(
        title: String,
        description: String,
        category: String,
        budgetCents: Int64,
        currency: String = "USD",
        location: Point,
        address: String? = nil,
        scheduledAt: String? = nil,
        metadata: [String: JSONValue]? = nil,
        publicTitle: String? = nil,
        publicDescription: String? = nil,
        idempotencyKey: String,
        subtasks: [CreateSubtaskRequest] = [],
    ) {
        self.title = title
        self.description = description
        self.category = category
        self.budgetCents = budgetCents
        self.currency = currency
        self.location = location
        self.address = address
        self.scheduledAt = scheduledAt
        self.metadata = metadata
        self.publicTitle = publicTitle
        self.publicDescription = publicDescription
        self.idempotencyKey = idempotencyKey
        self.subtasks = subtasks
    }
}

public struct CreateSubtaskRequest: Codable, Sendable {
    public let title: String
    public let description: String?
    public let isRequired: Bool

    enum CodingKeys: String, CodingKey {
        case title, description
        case isRequired = "is_required"
    }

    public init(title: String, description: String? = nil, isRequired: Bool) {
        self.title = title
        self.description = description
        self.isRequired = isRequired
    }
}

public struct ReserveEvidenceRequest: Encodable, Sendable {
    public let jobID: String
    public let subtaskID: String
    public let mediaType: MediaType
    public let mimeType: String
    public let fileSizeBytes: Int64
    public let capturedAt: String
    public let checksumSHA256: String
    public let idempotencyKey: String
    public let location: Point?

    enum CodingKeys: String, CodingKey {
        case mediaType = "media_type"
        case mimeType = "mime_type"
        case location
        case jobID = "job_id"
        case subtaskID = "subtask_id"
        case fileSizeBytes = "file_size_bytes"
        case capturedAt = "captured_at"
        case checksumSHA256 = "checksum_sha256"
        case idempotencyKey = "idempotency_key"
    }

    public init(
        jobID: String,
        subtaskID: String,
        mediaType: MediaType,
        mimeType: String,
        fileSizeBytes: Int64,
        capturedAt: String,
        checksumSHA256: String,
        idempotencyKey: String,
        location: Point? = nil,
    ) {
        self.jobID = jobID
        self.subtaskID = subtaskID
        self.mediaType = mediaType
        self.mimeType = mimeType
        self.fileSizeBytes = fileSizeBytes
        self.capturedAt = capturedAt
        self.checksumSHA256 = checksumSHA256
        self.idempotencyKey = idempotencyKey
        self.location = location
    }
}

public enum CreateJobValidator {
    public static func validate(_ request: CreateJobRequest) throws {
        guard !request.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw NetworkPeerAPIError.validation("Enter a job title.")
        }
        guard !request.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw NetworkPeerAPIError.validation("Enter a job description.")
        }
        guard !request.category.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw NetworkPeerAPIError.validation("Choose a job category.")
        }
        guard request.budgetCents > 0 else {
            throw NetworkPeerAPIError.validation("Budget must be greater than zero.")
        }
        let currency = request.currency.trimmingCharacters(in: .whitespacesAndNewlines)
        guard currency.count == 3, currency.unicodeScalars.allSatisfy({ (65 ... 90).contains($0.value) || (97 ... 122).contains($0.value) }) else {
            throw NetworkPeerAPIError.validation("Use a three-letter currency code.")
        }
        guard request.location.isValid else {
            throw NetworkPeerAPIError.validation("Choose a valid job location.")
        }
        guard !request.idempotencyKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw NetworkPeerAPIError.validation("A stable idempotency key is required to create a job.")
        }
        if let scheduledAt = request.scheduledAt, ISO8601DateFormatter().date(from: scheduledAt) == nil {
            throw NetworkPeerAPIError.validation("Scheduled time must be an ISO-8601 timestamp.")
        }
        for subtask in request.subtasks {
            guard !subtask.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw NetworkPeerAPIError.validation("Each checklist item needs a title.")
            }
        }
    }
}

public enum EvidenceReservationValidator {
    public static func validate(
        _ request: ReserveEvidenceRequest,
        maximumFileSizeBytes: Int64 = EvidenceUploadLimits.defaultMaximumFileSizeBytes,
    ) throws {
        guard EvidenceUploadLimits.isValid(maximumFileSizeBytes) else {
            throw NetworkPeerAPIError.invalidConfiguration("Evidence upload limit must be greater than zero.")
        }
        guard !request.jobID.isEmpty, !request.subtaskID.isEmpty else {
            throw NetworkPeerAPIError.validation("Evidence must be attached to the selected job checklist item.")
        }
        guard request.fileSizeBytes > 0, request.fileSizeBytes <= maximumFileSizeBytes else {
            throw NetworkPeerAPIError.validation("Evidence files must be between 1 byte and the configured platform limit.")
        }
        guard !request.mimeType.isEmpty,
              ISO8601DateFormatter().date(from: request.capturedAt) != nil else {
            throw NetworkPeerAPIError.validation("Evidence metadata is incomplete.")
        }
        let allowedMIMETypes: Set<String>
        switch request.mediaType {
        case .image: allowedMIMETypes = ["image/jpeg", "image/png", "image/webp"]
        case .video: allowedMIMETypes = ["video/mp4", "video/quicktime", "video/webm"]
        case .audio: allowedMIMETypes = ["audio/mpeg", "audio/mp4", "audio/wav", "audio/webm"]
        case .document: allowedMIMETypes = ["application/pdf"]
        }
        guard allowedMIMETypes.contains(request.mimeType) else {
            throw NetworkPeerAPIError.validation("The evidence MIME type is not allowed for this media type.")
        }
        guard request.checksumSHA256.count == 64,
              request.checksumSHA256 == request.checksumSHA256.lowercased(),
              request.checksumSHA256.unicodeScalars.allSatisfy({ CharacterSet(charactersIn: "0123456789abcdef").contains($0) }) else {
            throw NetworkPeerAPIError.validation("Evidence checksum is invalid.")
        }
        guard !request.idempotencyKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw NetworkPeerAPIError.validation("A stable idempotency key is required to retry evidence safely.")
        }
        if let location = request.location, !location.isValid {
            throw NetworkPeerAPIError.validation("Evidence location is invalid.")
        }
    }
}

public struct DeviceRegistration: Codable, Sendable {
    public let id: String
    public let platform: String
    public let active: Bool
}

private struct OTPRequestBody: Encodable {
    let email: String
    let role: UserRole
    enum CodingKeys: String, CodingKey {
        case email
        case role
    }
}

private struct OTPVerifyBody: Encodable {
    let email: String
    let otp: String
    let challengeId: String
    let transport = "native"
    enum CodingKeys: String, CodingKey {
        case email
        case otp
        case challengeId = "challenge_id"
        case transport
    }
}

private struct RefreshTokenBody: Encodable {
    let refreshToken: String
    enum CodingKeys: String, CodingKey { case refreshToken = "refresh_token" }
}

private struct LogoutResult: Codable, Sendable { let loggedOut: Bool; enum CodingKeys: String, CodingKey { case loggedOut = "logged_out" } }
private struct IdempotencyBody: Encodable { let idempotencyKey: String; enum CodingKeys: String, CodingKey { case idempotencyKey = "idempotency_key" } }
private struct CancelClientJobBody: Encodable { let cancellationReason: String?; enum CodingKeys: String, CodingKey { case cancellationReason = "cancellation_reason" } }
private struct WorkerLocationBody: Encodable { let latitude: Double; let longitude: Double }
private struct WorkerLocationResult: Codable, Sendable { let updatedAt: String; enum CodingKeys: String, CodingKey { case updatedAt = "updated_at" } }
private struct WorkStatusBody: Encodable { let jobID: String; let status: JobStatus; enum CodingKeys: String, CodingKey { case jobID = "job_id"; case status } }
private struct ConfirmEvidenceBody: Encodable { let mediaID: String; enum CodingKeys: String, CodingKey { case mediaID = "media_id" } }
private struct SubmitWorkBody: Encodable { let jobID: String; enum CodingKeys: String, CodingKey { case jobID = "job_id" } }
private struct RegisterDeviceBody: Encodable { let token: String; let platform: String }
private struct UnregisterDeviceBody: Encodable { let token: String }

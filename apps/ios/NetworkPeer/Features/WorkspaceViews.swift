import Foundation
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct LoginView: View {
    @EnvironmentObject private var model: AppModel
    @State private var email = ""
    @State private var verificationCode = ""
    @State private var role = UserRole.client
    @State private var codeRequested = false
    @State private var challengeId = ""
    @State private var message: String?
    @State private var error: String?
    @State private var isWorking = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Spacer(minLength: 28)
                BrandHeader()
                VStack(alignment: .leading, spacing: 8) {
                    Text("Work that moves with you.")
                        .font(.largeTitle.weight(.bold))
                        .foregroundStyle(NetworkPeerTheme.slate)
                    Text("Sign in securely to manage jobs, protected evidence, wallet activity, and updates.")
                        .foregroundStyle(NetworkPeerTheme.muted)
                }
                NetworkPeerCard {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Secure sign in")
                            .font(.title3.weight(.semibold))
                        Text("Use the same phone number and role as the web application.")
                            .font(.subheadline)
                            .foregroundStyle(NetworkPeerTheme.muted)
                        TextField("name@example.com", text: $email)
                            .keyboardType(.emailAddress)
                            .textContentType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled(true)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityIdentifier("login.email")
                        Picker("I am using NetworkPeer as", selection: $role) {
                            Text("Client").tag(UserRole.client)
                            Text("Worker").tag(UserRole.worker)
                        }
                        .pickerStyle(.segmented)
                        .accessibilityIdentifier("login.role")
                        if codeRequested {
                            SecureField("Verification code", text: $verificationCode)
                                .keyboardType(.numberPad)
                                .textContentType(.oneTimeCode)
                                .textFieldStyle(.roundedBorder)
                                .accessibilityIdentifier("login.code")
                        }
                        if let message { NoticeCard(message: message, color: NetworkPeerTheme.teal) }
                        if let error { NoticeCard(message: error, color: NetworkPeerTheme.danger) }
                        Button {
                            Task { await authenticate() }
                        } label: {
                            HStack {
                                Spacer()
                                if isWorking { ProgressView().tint(.white) }
                                Text(codeRequested ? "Verify and continue" : "Send verification code")
                                Spacer()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(NetworkPeerTheme.indigo)
                        .disabled(email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (codeRequested && verificationCode.isEmpty) || isWorking)
                        .accessibilityIdentifier("login.submit")
                    }
                }
                Text("NetworkPeer stores session tokens in Keychain and never stores AWS credentials, database access, or payment secret keys on your iPhone.")
                    .font(.footnote)
                    .foregroundStyle(NetworkPeerTheme.muted)
            }
            .padding(24)
        }
    }

    private func authenticate() async {
        guard let api = model.api else { return }
        isWorking = true
        error = nil
        defer { isWorking = false }
        do {
            if codeRequested {
                let session = try await api.verifyOTP(
                    email: email.trimmingCharacters(in: .whitespacesAndNewlines),
                    code: verificationCode,
                    challengeId: challengeId,
                )
                model.signedIn(session)
            } else {
                let result = try await api.requestOTP(
                    email: email.trimmingCharacters(in: .whitespacesAndNewlines),
                    role: role,
                )
                codeRequested = true
                challengeId = result.challengeId
                // Do not surface a development OTP echoed by a backend response.
                message = "A verification code was sent to your email address."
            }
        } catch {
            self.error = error.localizedDescription
        }
    }
}

private enum ClientRoute: Hashable {
    case job(String)
}

private enum ClientLifecycleAction: String, Identifiable, Equatable {
    case complete
    case dispute

    var id: String { rawValue }

    var title: String {
        switch self {
        case .complete: "Mark job complete"
        case .dispute: "Open dispute"
        }
    }
}

struct ClientWorkspaceView: View {
    @EnvironmentObject private var model: AppModel
    @State private var jobs: [Job] = []
    @State private var balances: [WalletBalance] = []
    @State private var error: String?
    @State private var loading = true
    @State private var isLoadingMore = false
    @State private var nextPage: Int?
    @State private var path = NavigationPath()
    @State private var isCreatingJob = false
    @State private var isShowingInbox = false
    @State private var isShowingWallet = false

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Client workspace")
                        .font(.largeTitle.weight(.bold))
                        .accessibilityAddTraits(.isHeader)
                    Text("Funding, status, and wallet figures are confirmed by the NetworkPeer API.")
                        .foregroundStyle(NetworkPeerTheme.muted)
                    WalletCard(balances: balances, role: .client)
                    NotificationPermissionCard()
                    HStack {
                        Text("Your jobs")
                            .font(.title2.weight(.bold))
                        Spacer()
                        Button {
                            Task { await load() }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .disabled(loading)
                        .accessibilityLabel("Refresh jobs")
                    }
                    if loading {
                        ProgressView("Loading your jobs")
                            .frame(maxWidth: .infinity)
                    }
                    if let error { NoticeCard(message: error, color: NetworkPeerTheme.danger) }
                    if let syncError = model.syncError {
                        NoticeCard(message: "Updates may be delayed: \(syncError)", color: NetworkPeerTheme.warning)
                    }
                    if !loading && error == nil && jobs.isEmpty {
                        EmptyState(title: "No jobs yet", message: "Create a job with its address, location, and evidence checklist from this workspace.")
                    }
                    ForEach(jobs) { job in
                        NavigationLink(value: ClientRoute.job(job.id)) {
                            ClientJobRow(job: job)
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Open \(job.title)")
                    }
                    if let nextPage {
                        Button(isLoadingMore ? "Loading more jobs" : "Load more jobs") {
                            Task { await loadMore(page: nextPage) }
                        }
                        .buttonStyle(.bordered)
                        .disabled(isLoadingMore || loading)
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(16)
            }
            .navigationDestination(for: ClientRoute.self) { route in
                switch route {
                case let .job(id): ClientJobDetailView(jobID: id)
                }
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) { BrandHeader(compact: true) }
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button {
                        isShowingInbox = true
                    } label: {
                        Image(systemName: "bell")
                    }
                    .accessibilityLabel("Open inbox")
                    Button {
                        isShowingWallet = true
                    } label: {
                        Image(systemName: "wallet.pass")
                    }
                    .accessibilityLabel("Open wallet")
                    Button {
                        isCreatingJob = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Create job")
                    Button("Sign out") { Task { await model.signOut() } }
                }
            }
            .sheet(isPresented: $isCreatingJob) {
                CreateJobView { job in
                    jobs.insert(job, at: 0)
                    Task { await load() }
                }
                .environmentObject(model)
            }
            .sheet(isPresented: $isShowingInbox) {
                InboxView()
                    .environmentObject(model)
            }
            .sheet(isPresented: $isShowingWallet) {
                WalletDetailView(title: "Client wallet", balances: balances) {
                    await loadWallet()
                }
            }
            .task {
                await load()
                consume(model.deepLinks.destination)
            }
            .onChange(of: model.deepLinks.destination) { _, destination in
                consume(destination)
            }
            .onChange(of: model.syncGeneration) { _, _ in
                if let cachedJobs = model.cached(ClientJobPage.self, name: "client.jobs") {
                    jobs = cachedJobs.items
                    nextPage = cachedJobs.total > cachedJobs.page * cachedJobs.perPage ? cachedJobs.page + 1 : nil
                }
                if let cachedWallet = model.cached(WalletResponse.self, name: "client.wallet") {
                    balances = cachedWallet.balances
                }
            }
        }
    }

    private func load() async {
        if let cachedJobs = model.cached(ClientJobPage.self, name: "client.jobs") {
            jobs = cachedJobs.items
            nextPage = cachedJobs.total > cachedJobs.page * cachedJobs.perPage ? cachedJobs.page + 1 : nil
            loading = false
        }
        if let cachedWallet = model.cached(WalletResponse.self, name: "client.wallet") {
            balances = cachedWallet.balances
        }
        guard let api = model.api else { return }
        loading = jobs.isEmpty
        error = nil
        defer { loading = false }
        do {
            async let loadedJobs = api.clientJobs()
            async let loadedWallet = api.clientWallet()
            let jobPage = try await loadedJobs
            let wallet = try await loadedWallet
            jobs = jobPage.items
            nextPage = jobPage.total > jobPage.page * jobPage.perPage ? jobPage.page + 1 : nil
            balances = wallet.balances
            model.cache(jobPage, name: "client.jobs")
            model.cache(wallet, name: "client.wallet")
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func loadMore(page: Int) async {
        guard let api = model.api else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let result = try await api.clientJobs(page: page)
            let existing = Set(jobs.map(\.id))
            jobs.append(contentsOf: result.items.filter { !existing.contains($0.id) })
            nextPage = result.total > result.page * result.perPage ? result.page + 1 : nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func loadWallet() async {
        guard let api = model.api else { return }
        do {
            let wallet = try await api.clientWallet()
            balances = wallet.balances
            model.cache(wallet, name: "client.wallet")
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func consume(_ destination: DeepLinkDestination?) {
        guard let destination else { return }
        switch destination {
        case let .job(id):
            path.append(ClientRoute.job(id))
        case .inbox:
            isShowingInbox = true
        }
        model.deepLinks.clear()
    }
}

struct ClientJobDetailView: View {
    @EnvironmentObject private var model: AppModel
    let jobID: String

    @State private var detail: ClientJobDetail?
    @State private var error: String?
    @State private var actionMessage: String?
    @State private var loading = true
    @State private var isWorking = false
    @State private var fundingKey = UUID().uuidString
    @State private var approvalKey = UUID().uuidString
    @State private var cancellationReason = ""
    @State private var isShowingCancellation = false
    @State private var resolutionAction: ClientLifecycleAction?
    @State private var isShowingResolutionConfirmation = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if loading { ProgressView("Loading job").frame(maxWidth: .infinity) }
                if let error { NoticeCard(message: error, color: NetworkPeerTheme.danger) }
                if let detail {
                    NetworkPeerCard {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(alignment: .top) {
                                Text(detail.job.title).font(.title2.weight(.bold))
                                Spacer()
                                StatusPill(status: detail.job.status)
                            }
                            Text(detail.job.description).foregroundStyle(NetworkPeerTheme.muted)
                            Text(currency(detail.job.budgetCents, detail.job.currency)).font(.title.weight(.bold))
                            Label("Escrow: \(detail.job.escrowStatus.rawValue)", systemImage: "lock.shield")
                                .font(.footnote.weight(.medium))
                                .foregroundStyle(NetworkPeerTheme.indigo)
                        }
                    }

                    NetworkPeerCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Service location").font(.title3.weight(.bold))
                            Text(detail.job.address ?? "No full address was provided.")
                            if detail.job.location.isValid {
                                Text("Coordinates: \(detail.job.location.coordinates[1], specifier: "%.5f"), \(detail.job.location.coordinates[0], specifier: "%.5f")")
                                    .font(.footnote)
                                    .foregroundStyle(NetworkPeerTheme.muted)
                            }
                            if let scheduledAt = detail.job.scheduledAt {
                                Text("Scheduled: \(scheduledAt)")
                                    .font(.footnote)
                                    .foregroundStyle(NetworkPeerTheme.muted)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Evidence checklist").font(.title3.weight(.bold))
                        ForEach(detail.subtasks) { subtask in
                            Label(
                                subtask.isRequired ? "Required: \(subtask.title)" : "Optional: \(subtask.title)",
                                systemImage: subtask.isRequired ? "checkmark.seal" : "circle",
                            )
                            .font(.subheadline)
                        }
                    }

                    if supportsEvidenceReview(detail.job.status) {
                        NavigationLink {
                            ClientEvidenceReviewView(jobID: detail.job.id, subtasks: detail.subtasks)
                        } label: {
                            Label("Review submitted evidence", systemImage: "doc.viewfinder")
                        }
                        .buttonStyle(.bordered)
                        .frame(maxWidth: .infinity)
                        .accessibilityHint("Opens read-only evidence verified by NetworkPeer")
                    }

                    if detail.job.status == .funding, let message = model.paymentCoordinator.configurationMessage {
                        NoticeCard(message: message, color: NetworkPeerTheme.warning)
                    }

                    lifecycleActions(for: detail.job)
                    if let actionMessage { NoticeCard(message: actionMessage, color: NetworkPeerTheme.teal) }
                }
            }
            .padding(16)
        }
        .navigationTitle("Job detail")
        .task { await load() }
        .onChange(of: model.syncGeneration) { _, _ in
            Task { await load() }
        }
        .alert("Cancel unfunded job", isPresented: $isShowingCancellation) {
            TextField("Reason (optional)", text: $cancellationReason)
            Button("Cancel job", role: .destructive) {
                Task { await cancel() }
            }
            Button("Keep job", role: .cancel) {}
        } message: {
            Text("Only an unfunded FUNDING job can be cancelled through this workflow.")
        }
        .confirmationDialog(
            resolutionAction?.title ?? "Confirm action",
            isPresented: $isShowingResolutionConfirmation,
            titleVisibility: .visible,
        ) {
            if let action = resolutionAction {
                Button(action.title, role: .destructive) {
                    Task { await resolve(action) }
                }
            }
        } message: {
            switch resolutionAction {
            case .complete:
                Text("This marks an APPROVED job as complete.")
            case .dispute:
                Text("This opens a dispute and freezes the server-controlled lifecycle until resolution.")
            case nil:
                EmptyView()
            }
        }
    }

    @ViewBuilder
    private func lifecycleActions(for job: Job) -> some View {
        if job.status == .funding {
            Button(isWorking ? "Preparing funding" : "Prepare escrow funding") {
                Task { await prepareFunding() }
            }
            .buttonStyle(.borderedProminent)
            .tint(NetworkPeerTheme.indigo)
            .disabled(isWorking)
            .frame(maxWidth: .infinity)
            .accessibilityHint("Starts the server-authoritative funding operation")
        }
        if job.status == .submitted {
            Button(isWorking ? "Approving work" : "Approve and release payout") {
                Task { await approve() }
            }
            .buttonStyle(.borderedProminent)
            .tint(NetworkPeerTheme.indigo)
            .disabled(isWorking)
            .frame(maxWidth: .infinity)
        }
        if job.status == .funding, job.escrowStatus == .unfunded {
            Button("Cancel unfunded job", role: .destructive) {
                cancellationReason = ""
                isShowingCancellation = true
            }
            .buttonStyle(.bordered)
            .disabled(isWorking)
            .frame(maxWidth: .infinity)
        }
        if job.status == .approved {
            Button("Mark job complete") {
                resolutionAction = .complete
                isShowingResolutionConfirmation = true
            }
            .buttonStyle(.borderedProminent)
            .tint(NetworkPeerTheme.success)
            .disabled(isWorking)
            .frame(maxWidth: .infinity)
        }
        if [.assigned, .enRoute, .atLocation, .inProgress, .submitted, .approved].contains(job.status) {
            Button("Open dispute", role: .destructive) {
                resolutionAction = .dispute
                isShowingResolutionConfirmation = true
            }
            .buttonStyle(.bordered)
            .disabled(isWorking)
            .frame(maxWidth: .infinity)
        }
    }

    private func load() async {
        if let cached = model.cached(ClientJobDetail.self, name: "client.job.\(jobID)") {
            detail = cached
            loading = false
        }
        guard let api = model.api else { return }
        loading = detail == nil
        error = nil
        defer { loading = false }
        do {
            let loaded = try await api.clientJob(id: jobID)
            detail = loaded
            model.cache(loaded, name: "client.job.\(jobID)")
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func prepareFunding() async {
        guard let api = model.api else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            let funding = try await api.fundClientJob(id: jobID, idempotencyKey: fundingKey)
            if let clientSecret = funding.clientSecret {
                switch await model.paymentCoordinator.present(clientSecret: clientSecret) {
                case .completed:
                    actionMessage = "Payment was submitted. Funding becomes available only after NetworkPeer confirms the provider result."
                case .cancelled:
                    actionMessage = "Payment was cancelled. You can resume the same funding operation when ready."
                case let .failed(message), let .unavailable(message):
                    actionMessage = message
                }
            } else {
                actionMessage = "Funding operation \(funding.status.rawValue.lowercased()) was prepared. Wait for the server-confirmed provider update before workers can discover this job."
            }
            await load()
        } catch {
            actionMessage = error.localizedDescription
        }
    }

    private func approve() async {
        guard let api = model.api else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            let approval = try await api.approveClientJob(id: jobID, idempotencyKey: approvalKey)
            approvalKey = UUID().uuidString
            actionMessage = "Work approved. Payout \(approval.payoutStatus.rawValue.lowercased()) is reconciled independently by the payment provider."
            await load()
        } catch {
            actionMessage = error.localizedDescription
        }
    }

    private func cancel() async {
        guard let api = model.api else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            let result = try await api.cancelClientJob(id: jobID, cancellationReason: cancellationReason)
            actionMessage = result.cancelled ? "Job cancelled." : "Cancellation was not completed."
            await load()
        } catch {
            actionMessage = error.localizedDescription
        }
    }

    private func resolve(_ action: ClientLifecycleAction) async {
        guard let api = model.api else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            let result: ClientJobResolutionResult
            switch action {
            case .complete:
                result = try await api.completeClientJob(id: jobID)
                actionMessage = "Job marked complete."
            case .dispute:
                result = try await api.disputeClientJob(id: jobID)
                actionMessage = "Dispute opened. NetworkPeer will reconcile the server-controlled lifecycle."
            }
            guard result.action == (action == .complete ? .complete : .dispute) else {
                throw NetworkPeerAPIError.invalidResponse
            }
            await load()
        } catch {
            actionMessage = error.localizedDescription
        }
    }

    private func supportsEvidenceReview(_ status: JobStatus) -> Bool {
        [.inProgress, .submitted, .approved, .completed, .disputed].contains(status)
    }
}

private enum WorkerRoute: Hashable {
    case preview(String)
    case task(String)
}

struct WorkerWorkspaceView: View {
    @EnvironmentObject private var model: AppModel
    @StateObject private var location = DeviceLocationManager()
    @State private var jobs: [WorkerJobSummary] = []
    @State private var assignedJobs: [WorkerJobDetail] = []
    @State private var balances: [WalletBalance] = []
    @State private var error: String?
    @State private var isSearching = false
    @State private var isLoadingMore = false
    @State private var radiusKilometres = 20
    @State private var nextPage: Int?
    @State private var hasSearched = false
    @State private var path = NavigationPath()
    @State private var isShowingInbox = false
    @State private var isShowingWallet = false

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Nearby work")
                        .font(.largeTitle.weight(.bold))
                        .accessibilityAddTraits(.isHeader)
                    Text("Exact addresses, coordinates, and client identity stay private until the server assigns the job to you.")
                        .foregroundStyle(NetworkPeerTheme.muted)
                    WalletCard(balances: balances, role: .worker)
                    NotificationPermissionCard()
                    if !assignedJobs.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Active assignments").font(.title2.weight(.bold))
                            ForEach(assignedJobs) { job in
                                NavigationLink(value: WorkerRoute.task(job.id)) {
                                    WorkerAssignedJobRow(job: job)
                                }
                                .buttonStyle(.plain)
                                .accessibilityHint("Open assigned task")
                            }
                        }
                    }
                    NetworkPeerCard {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 12) {
                                Image(systemName: "location.fill").foregroundStyle(NetworkPeerTheme.indigo)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("Location-protected discovery").font(.headline)
                                    Text("Your current location is updated before each new search.")
                                        .font(.footnote)
                                        .foregroundStyle(NetworkPeerTheme.muted)
                                }
                            }
                            Picker("Search radius", selection: $radiusKilometres) {
                                Text("1 km").tag(1)
                                Text("5 km").tag(5)
                                Text("20 km").tag(20)
                                Text("50 km").tag(50)
                            }
                            .pickerStyle(.segmented)
                            .accessibilityLabel("Search radius")
                            Button(isSearching ? "Searching" : "Search nearby work") {
                                Task { await search() }
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(NetworkPeerTheme.indigo)
                            .disabled(isSearching || isLoadingMore)
                            .frame(maxWidth: .infinity)
                        }
                    }
                    if let error {
                        NoticeCard(message: error, color: NetworkPeerTheme.danger)
                        if error.localizedCaseInsensitiveContains("location") {
                            Button("Open Location Settings") { location.openSettings() }
                            .buttonStyle(.bordered)
                        }
                    }
                    if let syncError = model.syncError {
                        NoticeCard(message: "Updates may be delayed: \(syncError)", color: NetworkPeerTheme.warning)
                    }
                    if jobs.isEmpty && !isSearching && hasSearched && error == nil {
                        EmptyState(title: "No matching work", message: "Try another approved radius or refresh your current location.")
                    }
                    if jobs.isEmpty && !isSearching && !hasSearched && error == nil {
                        EmptyState(title: "Ready when you are", message: "Update your location to see funded jobs within your approved worker radius.")
                    }
                    ForEach(jobs) { job in
                        NavigationLink(value: WorkerRoute.preview(job.id)) {
                            WorkerJobRow(job: job)
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Review privacy-safe job details before accepting")
                    }
                    if let nextPage {
                        Button(isLoadingMore ? "Loading more" : "Load more nearby work") {
                            Task { await loadMore(page: nextPage) }
                        }
                        .buttonStyle(.bordered)
                        .disabled(isLoadingMore || isSearching)
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(16)
            }
            .navigationDestination(for: WorkerRoute.self) { route in
                switch route {
                case let .preview(id):
                    WorkerJobPreviewView(jobID: id) { acceptedID in
                        path.append(WorkerRoute.task(acceptedID))
                    }
                case let .task(id):
                    WorkerTaskView(jobID: id)
                }
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) { BrandHeader(compact: true) }
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button {
                        isShowingInbox = true
                    } label: {
                        Image(systemName: "bell")
                    }
                    .accessibilityLabel("Open inbox")
                    Button {
                        isShowingWallet = true
                    } label: {
                        Image(systemName: "wallet.pass")
                    }
                    .accessibilityLabel("Open wallet")
                    Button("Sign out") { Task { await model.signOut() } }
                }
            }
            .sheet(isPresented: $isShowingInbox) {
                InboxView().environmentObject(model)
            }
            .sheet(isPresented: $isShowingWallet) {
                WalletDetailView(title: "Worker wallet", balances: balances) {
                    await loadWallet()
                }
            }
            .task {
                await loadWallet()
                loadAssignedJobs()
                consume(model.deepLinks.destination)
            }
            .onChange(of: model.deepLinks.destination) { _, destination in
                consume(destination)
            }
            .onChange(of: model.syncGeneration) { _, _ in
                if let cached = model.cached(WalletResponse.self, name: "worker.wallet") {
                    balances = cached.balances
                }
                loadAssignedJobs()
            }
        }
    }

    private func search() async {
        guard let api = model.api else { return }
        isSearching = true
        error = nil
        defer { isSearching = false }
        do {
            let coordinate = try await location.requestCurrentCoordinate()
            try await api.updateWorkerLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            let page = try await api.nearbyWorkerJobs(radiusKilometres: radiusKilometres)
            jobs = page.items
            nextPage = page.hasMore ? page.nextPage : nil
            hasSearched = true
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func loadMore(page: Int) async {
        guard let api = model.api else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let result = try await api.nearbyWorkerJobs(radiusKilometres: radiusKilometres, page: page)
            let existing = Set(jobs.map(\.id))
            jobs.append(contentsOf: result.items.filter { !existing.contains($0.id) })
            nextPage = result.hasMore ? result.nextPage : nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func loadWallet() async {
        if let cached = model.cached(WalletResponse.self, name: "worker.wallet") {
            balances = cached.balances
        }
        guard let api = model.api else { return }
        do {
            let wallet = try await api.workerWallet()
            balances = wallet.balances
            model.cache(wallet, name: "worker.wallet")
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func loadAssignedJobs() {
        assignedJobs = model.cached([WorkerJobDetail].self, name: "worker.assigned.jobs") ?? []
    }

    private func consume(_ destination: DeepLinkDestination?) {
        guard let destination else { return }
        switch destination {
        case let .job(id):
            path.append(WorkerRoute.task(id))
        case .inbox:
            isShowingInbox = true
        }
        model.deepLinks.clear()
    }
}

struct WorkerJobPreviewView: View {
    @EnvironmentObject private var model: AppModel
    let jobID: String
    let onAccepted: (String) -> Void

    @State private var detail: WorkerJobDetail?
    @State private var error: String?
    @State private var loading = true
    @State private var isAccepting = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if loading { ProgressView("Loading job preview").frame(maxWidth: .infinity) }
                if let error { NoticeCard(message: error, color: NetworkPeerTheme.danger) }
                if let detail {
                    NetworkPeerCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(detail.title).font(.title2.weight(.bold))
                            Text(detail.description).foregroundStyle(NetworkPeerTheme.muted)
                            Text(currency(detail.budgetCents, detail.currency)).font(.title.weight(.bold))
                            Label("\(detail.category) \u{00B7} priority \(detail.priority)", systemImage: "briefcase")
                                .font(.footnote)
                                .foregroundStyle(NetworkPeerTheme.muted)
                        }
                    }
                    NetworkPeerCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Before acceptance").font(.title3.weight(.bold))
                            Text("The API projection intentionally omits client identity, address, and precise location until the server atomically assigns this job to you.")
                                .font(.subheadline)
                                .foregroundStyle(NetworkPeerTheme.muted)
                            Text("Checklist items: \(detail.subtasks.count)")
                                .font(.footnote.weight(.medium))
                        }
                    }
                    if detail.isAssignedToRequester {
                        NavigationLink("Open assigned task") {
                            WorkerTaskView(jobID: detail.id)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(NetworkPeerTheme.indigo)
                        .frame(maxWidth: .infinity)
                    } else {
                        Button(isAccepting ? "Accepting securely" : "Accept securely") {
                            Task { await accept() }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(NetworkPeerTheme.indigo)
                        .disabled(isAccepting)
                        .frame(maxWidth: .infinity)
                        .accessibilityHint("The server chooses at most one eligible worker")
                    }
                }
            }
            .padding(16)
        }
        .navigationTitle("Job preview")
        .task { await load() }
    }

    private func load() async {
        guard let api = model.api else { return }
        loading = true
        error = nil
        defer { loading = false }
        do {
            detail = try await api.workerJob(id: jobID)
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func accept() async {
        guard let api = model.api else { return }
        isAccepting = true
        defer { isAccepting = false }
        do {
            let accepted = try await api.acceptWorkerJob(id: jobID)
            guard accepted.isAssignedToRequester else {
                throw NetworkPeerAPIError.invalidResponse
            }
            onAccepted(accepted.id)
        } catch {
            self.error = error.localizedDescription
        }
    }
}

private struct EvidenceSelection: Equatable {
    let jobID: String
    let subtaskID: String
}

struct WorkerTaskView: View {
    @EnvironmentObject private var model: AppModel
    let jobID: String

    @State private var job: WorkerJobDetail?
    @State private var evidence: [String: EvidenceSummary] = [:]
    @State private var pendingEvidence: [PendingEvidence] = []
    @State private var error: String?
    @State private var loading = true
    @State private var isUpdating = false
    @State private var selectedEvidence: EvidenceSelection?
    @State private var isImporting = false
    @State private var isShowingCamera = false
    @State private var isShowingPhotoPicker = false

    private var nextStatus: JobStatus? {
        guard job?.isAssignedToRequester == true else { return nil }
        switch job?.status {
        case .assigned: .enRoute
        case .enRoute: .atLocation
        case .atLocation: .inProgress
        default: nil
        }
    }

    private var readyToSubmit: Bool {
        guard let job, job.isAssignedToRequester, job.status == .inProgress else { return false }
        return job.subtasks.filter(\.isRequired).allSatisfy { isConfirmed(evidence[$0.id]) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if loading { ProgressView("Loading assigned task").frame(maxWidth: .infinity) }
                if let error { NoticeCard(message: error, color: NetworkPeerTheme.danger) }
                if let job {
                    NetworkPeerCard {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(alignment: .top) {
                                Text(job.title).font(.title2.weight(.bold))
                                Spacer()
                                StatusPill(status: job.status)
                            }
                            Text(job.isAssignedToRequester ? (job.address ?? "Assigned location is available after acceptance.") : "Assignment is required before protected location details are shown.")
                                .foregroundStyle(NetworkPeerTheme.muted)
                            HStack(spacing: 8) {
                                Label("Server validated", systemImage: "checkmark.shield")
                                Label("SHA-256 evidence", systemImage: "checkmark.seal")
                            }
                            .font(.caption.weight(.medium))
                            .foregroundStyle(NetworkPeerTheme.teal)
                        }
                    }
                    if let nextStatus {
                        Button(isUpdating ? "Updating status" : "Mark \(readableStatus(nextStatus))") {
                            Task { await advance(nextStatus) }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(NetworkPeerTheme.indigo)
                        .disabled(isUpdating)
                        .frame(maxWidth: .infinity)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Evidence checklist").font(.title2.weight(.bold))
                        Text("Every file is copied into app storage, hashed, reserved through the API, posted to its short-lived opaque policy, and then confirmed by the API.")
                            .foregroundStyle(NetworkPeerTheme.muted)
                    }
                    ForEach(job.subtasks) { subtask in
                        evidenceCard(subtask, job: job)
                    }
                    if !pendingEvidence.isEmpty {
                        NetworkPeerCard {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Pending evidence").font(.headline)
                                Text("\(pendingEvidence.count) file\(pendingEvidence.count == 1 ? "" : "s") will keep the original metadata and idempotency key when retried.")
                                    .font(.footnote)
                                    .foregroundStyle(NetworkPeerTheme.muted)
                                ForEach(pendingEvidence) { pending in
                                    Text("Checklist item \(pending.subtaskID.prefix(8)) \u{00B7} attempt \(pending.retryCount + 1)")
                                        .font(.caption)
                                    if let lastError = pending.lastError {
                                        Text(lastError).font(.caption).foregroundStyle(NetworkPeerTheme.danger)
                                    }
                                }
                                Button(isUpdating ? "Retrying" : "Retry pending evidence") {
                                    Task { await retryPending() }
                                }
                                .buttonStyle(.bordered)
                                .disabled(isUpdating)
                            }
                        }
                    }
                    Button(isUpdating ? "Submitting work" : "Submit evidence for review") {
                        Task { await submit() }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(NetworkPeerTheme.indigo)
                    .disabled(!readyToSubmit || isUpdating)
                    .frame(maxWidth: .infinity)
                    .accessibilityHint("Requires all required evidence to be confirmed by the API")
                }
            }
            .padding(16)
        }
        .navigationTitle("Live task")
        .task { await load() }
        .onChange(of: model.syncGeneration) { _, _ in
            Task { await load() }
        }
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.image, .movie, .audio, .pdf],
        ) { result in
            Task { await receiveImportedEvidence(result) }
        }
        .sheet(isPresented: $isShowingCamera) {
            CameraEvidencePicker { result in
                Task { await receiveEvidence(result) }
            }
        }
        .sheet(isPresented: $isShowingPhotoPicker) {
            PhotoEvidencePicker { result in
                Task { await receiveEvidence(result) }
            }
        }
    }

    @ViewBuilder
    private func evidenceCard(_ subtask: JobSubtask, job: WorkerJobDetail) -> some View {
        let confirmed = isConfirmed(evidence[subtask.id])
        let pending = pendingEvidence.contains { $0.subtaskID == subtask.id }
        NetworkPeerCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(subtask.title).font(.headline)
                    Spacer()
                    Text(subtask.isRequired ? "Required" : "Optional")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(subtask.isRequired ? NetworkPeerTheme.indigo : NetworkPeerTheme.muted)
                }
                if let description = subtask.description {
                    Text(description).font(.subheadline).foregroundStyle(NetworkPeerTheme.muted)
                }
                if confirmed {
                    Label("Evidence confirmed", systemImage: "checkmark.seal.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(NetworkPeerTheme.success)
                } else if pending {
                    Label("Upload queued for retry", systemImage: "arrow.clockwise")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(NetworkPeerTheme.warning)
                } else if job.isAssignedToRequester && job.status == .inProgress {
                    Menu {
                        Button {
                            capture(subtask)
                        } label: {
                            Label("Capture photo or video", systemImage: "camera")
                        }
                        Button {
                            selectPhoto(for: subtask)
                        } label: {
                            Label("Choose photo", systemImage: "photo")
                        }
                        Button {
                            selectFile(for: subtask)
                        } label: {
                            Label("Browse files", systemImage: "folder")
                        }
                    } label: {
                        Label("Add evidence", systemImage: "plus.circle")
                    }
                    .buttonStyle(.bordered)
                    .disabled(isUpdating)
                    .accessibilityHint("Attaches evidence to \(subtask.title)")
                } else {
                    Text("Evidence can be added once work is in progress.")
                        .font(.caption)
                        .foregroundStyle(NetworkPeerTheme.muted)
                }
            }
        }
    }

    private func load() async {
        evidence = model.confirmedEvidence(jobID: jobID)
        pendingEvidence = model.pendingEvidence(jobID: jobID)
        guard let api = model.api else { return }
        loading = true
        error = nil
        defer { loading = false }
        do {
            job = try await api.workerJob(id: jobID)
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func advance(_ target: JobStatus) async {
        guard let api = model.api else { return }
        isUpdating = true
        defer { isUpdating = false }
        do {
            _ = try await api.advanceWork(jobID: jobID, status: target)
            await load()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func capture(_ subtask: JobSubtask) {
        beginEvidence(for: subtask)
        Task {
            guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
                error = EvidenceCaptureError.cameraUnavailable.localizedDescription
                selectedEvidence = nil
                return
            }
            guard await requestCameraPermission() else {
                error = EvidenceCaptureError.cameraPermissionDenied.localizedDescription
                selectedEvidence = nil
                return
            }
            isShowingCamera = true
        }
    }

    private func selectPhoto(for subtask: JobSubtask) {
        beginEvidence(for: subtask)
        isShowingPhotoPicker = true
    }

    private func selectFile(for subtask: JobSubtask) {
        beginEvidence(for: subtask)
        isImporting = true
    }

    private func beginEvidence(for subtask: JobSubtask) {
        error = nil
        selectedEvidence = EvidenceSelection(jobID: jobID, subtaskID: subtask.id)
    }

    private func receiveImportedEvidence(_ result: Result<URL, Error>) async {
        switch result {
        case let .success(url):
            let hasScope = url.startAccessingSecurityScopedResource()
            defer {
                if hasScope { url.stopAccessingSecurityScopedResource() }
            }
            await uploadSelected(url)
        case let .failure(error):
            if !(error is CancellationError) {
                self.error = error.localizedDescription
            }
            selectedEvidence = nil
        }
    }

    private func receiveEvidence(_ result: Result<URL, Error>) async {
        isShowingCamera = false
        isShowingPhotoPicker = false
        switch result {
        case let .success(url):
            await uploadSelected(url)
            try? FileManager.default.removeItem(at: url)
        case let .failure(error):
            if !(error is CancellationError) {
                self.error = error.localizedDescription
            }
            selectedEvidence = nil
        }
    }

    private func uploadSelected(_ url: URL) async {
        guard let selection = selectedEvidence,
              selection.jobID == jobID,
              let job,
              job.isAssignedToRequester,
              job.subtasks.contains(where: { $0.id == selection.subtaskID }),
              job.status == .inProgress else {
            selectedEvidence = nil
            return
        }
        isUpdating = true
        defer {
            isUpdating = false
            selectedEvidence = nil
        }
        do {
            let uploaded = try await model.enqueueAndUploadEvidence(
                jobID: selection.jobID,
                subtaskID: selection.subtaskID,
                sourceURL: url,
            )
            evidence[selection.subtaskID] = uploaded
            pendingEvidence = model.pendingEvidence(jobID: jobID)
        } catch {
            self.error = error.localizedDescription
            pendingEvidence = model.pendingEvidence(jobID: jobID)
        }
    }

    private func retryPending() async {
        isUpdating = true
        defer { isUpdating = false }
        _ = await model.retryPendingEvidence(jobID: jobID)
        evidence = model.confirmedEvidence(jobID: jobID)
        pendingEvidence = model.pendingEvidence(jobID: jobID)
        if let failure = pendingEvidence.compactMap(\.lastError).last {
            error = failure
        }
    }

    private func submit() async {
        guard let api = model.api else { return }
        isUpdating = true
        defer { isUpdating = false }
        do {
            _ = try await api.submitWork(jobID: jobID)
            await load()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func readableStatus(_ status: JobStatus) -> String {
        status.rawValue.replacingOccurrences(of: "_", with: " ").lowercased()
    }

    private func isConfirmed(_ summary: EvidenceSummary?) -> Bool {
        guard let summary else { return false }
        return summary.status == .uploaded || summary.status == .verified
    }
}

struct WalletCard: View {
    let balances: [WalletBalance]
    let role: UserRole

    var body: some View {
        NetworkPeerCard {
            VStack(alignment: .leading, spacing: 6) {
                Text("Wallet").font(.headline)
                if balances.isEmpty {
                    Text("Server-calculated balances will appear here.").foregroundStyle(NetworkPeerTheme.muted)
                } else {
                    ForEach(balances) { balance in
                        Text(currency(Int64(balance.availableBalanceCents) ?? 0, balance.currency))
                            .font(.title.weight(.bold))
                        Text(walletSummary(balance))
                            .font(.footnote)
                            .foregroundStyle(NetworkPeerTheme.muted)
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func walletSummary(_ balance: WalletBalance) -> String {
        let escrow = currency(Int64(balance.pendingEscrowCents) ?? 0, balance.currency)
        switch role {
        case .worker:
            let earnings = currency(Int64(balance.lifetimeEarningsCents) ?? 0, balance.currency)
            return "Pending escrow \(escrow) \u{00B7} Lifetime earnings \(earnings)"
        default:
            let spend = currency(Int64(balance.lifetimeSpendCents) ?? 0, balance.currency)
            return "Pending escrow \(escrow) \u{00B7} Lifetime spend \(spend)"
        }
    }
}

private struct NotificationPermissionCard: View {
    @EnvironmentObject private var model: AppModel
    @State private var state = PushPermissionState.unknown

    var body: some View {
        if state != .authorized && state != .provisional {
            NetworkPeerCard {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Stay updated", systemImage: "bell.badge")
                        .font(.headline)
                    Text(state.description)
                        .font(.footnote)
                        .foregroundStyle(NetworkPeerTheme.muted)
                    if state == .denied {
                        Button("Open Notification Settings") {
                            guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                            UIApplication.shared.open(url)
                        }
                        .buttonStyle(.bordered)
                    } else {
                        Button("Enable notifications") {
                            Task {
                                await model.notificationPermissions.requestPermission()
                                state = model.notificationPermissions.state
                            }
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
            .task {
                await model.notificationPermissions.refresh()
                state = model.notificationPermissions.state
            }
        }
    }
}

struct WalletDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let balances: [WalletBalance]
    let reload: () async -> Void

    @State private var isRefreshing = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    WalletCard(balances: balances, role: title.contains("Worker") ? .worker : .client)
                    Text("NetworkPeer exposes server-calculated balances in the current mobile contract. Transaction history, top-ups, withdrawals, and payouts remain server-controlled.")
                        .font(.footnote)
                        .foregroundStyle(NetworkPeerTheme.muted)
                    Button(isRefreshing ? "Refreshing" : "Refresh wallet") {
                        Task {
                            isRefreshing = true
                            await reload()
                            isRefreshing = false
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(NetworkPeerTheme.indigo)
                    .disabled(isRefreshing)
                }
                .padding(16)
            }
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

struct ClientJobRow: View {
    let job: Job

    var body: some View {
        NetworkPeerCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top) {
                    Text(job.title).font(.headline)
                    Spacer()
                    StatusPill(status: job.status)
                }
                Text(job.description).foregroundStyle(NetworkPeerTheme.muted).lineLimit(2)
                Text(currency(job.budgetCents, job.currency)).font(.title3.weight(.bold))
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct WorkerJobRow: View {
    let job: WorkerJobSummary

    var body: some View {
        NetworkPeerCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    Text(job.title).font(.headline)
                    Spacer()
                    Text(job.distanceBand.replacingOccurrences(of: "_", with: " "))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(NetworkPeerTheme.indigo)
                }
                Text(job.description).foregroundStyle(NetworkPeerTheme.muted).lineLimit(2)
                Text(currency(job.budgetCents, job.currency)).font(.title3.weight(.bold))
                Label("Review details before accepting", systemImage: "eye.slash")
                    .font(.caption)
                    .foregroundStyle(NetworkPeerTheme.muted)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct WorkerAssignedJobRow: View {
    let job: WorkerJobDetail

    var body: some View {
        NetworkPeerCard {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(job.title).font(.headline)
                    Text(job.description)
                        .font(.subheadline)
                        .foregroundStyle(NetworkPeerTheme.muted)
                        .lineLimit(2)
                }
                Spacer()
                StatusPill(status: job.status)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct EmptyState: View {
    let title: String
    let message: String

    var body: some View {
        NetworkPeerCard {
            VStack(spacing: 10) {
                Image(systemName: "briefcase")
                    .font(.title2)
                    .foregroundStyle(NetworkPeerTheme.indigo)
                Text(title).font(.headline)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(NetworkPeerTheme.muted)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
        }
        .accessibilityElement(children: .combine)
    }
}

struct ConfigurationView: View {
    let error: String

    var body: some View {
        VStack(spacing: 16) {
            BrandHeader()
            NoticeCard(message: error, color: NetworkPeerTheme.danger)
            Text("Copy the matching Debug or Release local xcconfig example, then use the HTTPS API URL for that environment. Stripe and Firebase settings are optional public build-time integrations.")
                .font(.footnote)
                .foregroundStyle(NetworkPeerTheme.muted)
                .multilineTextAlignment(.center)
        }
        .padding(28)
        .accessibilityIdentifier("configuration.view")
    }
}

struct AdminBoundaryView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.shield")
                .font(.system(size: 42))
                .foregroundStyle(NetworkPeerTheme.indigo)
            Text("Admin operations stay on the protected web console.")
                .font(.title3.weight(.bold))
                .multilineTextAlignment(.center)
            Text("This native client intentionally does not mirror audited administrative controls without a dedicated API contract and access review.")
                .foregroundStyle(NetworkPeerTheme.muted)
                .multilineTextAlignment(.center)
        }
        .padding(28)
    }
}

private func currency(_ cents: Int64, _ code: String) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .currency
    formatter.currencyCode = code
    return formatter.string(from: NSNumber(value: Double(cents) / 100)) ?? "\(code) \(Double(cents) / 100)"
}

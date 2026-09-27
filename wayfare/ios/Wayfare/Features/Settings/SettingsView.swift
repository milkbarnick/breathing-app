import SwiftData
import SwiftUI

/// Settings sheet (UX spec 3.9).
struct SettingsView: View {
    @Environment(AppServices.self) private var services
    @Environment(SessionStore.self) private var session
    @Environment(SyncEngine.self) private var sync
    @Environment(NotificationPermission.self) private var permission
    @Environment(DeviceRegistrar.self) private var devices
    @Environment(NetworkMonitor.self) private var network
    @Environment(\.dismiss) private var dismiss

    @State private var confirmingSignOut = false
    @State private var isSigningOut = false
    @State private var priming: PrimingRequest?
    @State private var consentGiven = false

    var body: some View {
        NavigationStack {
            Form {
                accountSection
                notificationsSection
                syncSection
                aboutSection
                #if DEBUG
                DeveloperSection()
                #endif
                Section {
                    Button {
                        confirmingSignOut = true
                    } label: {
                        if isSigningOut {
                            ProgressView().frame(maxWidth: .infinity)
                        } else {
                            Text("Sign Out")
                                .foregroundStyle(Palette.accent)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .disabled(isSigningOut)
                }
                Section {
                    NavigationLink {
                        DeleteAccountView()
                    } label: {
                        Text("Delete Account")
                            .foregroundStyle(Palette.danger)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Palette.background)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .confirmationDialog("Sign out of Wayfare?", isPresented: $confirmingSignOut, titleVisibility: .visible) {
                Button("Sign Out", role: .destructive) { signOut() }
            } message: {
                if sync.pendingChangeCount > 0 && !network.isOnline {
                    Text("\(sync.pendingChangeCount) changes haven't synced and will be lost. Connect to the internet first to keep them.")
                }
            }
            .sheet(item: $priming) { request in
                PrimingSheet(request: request)
            }
            .task {
                await permission.refresh()
                consentGiven = UserDefaults.standard.bool(forKey: AppServices.aiConsentKey(userId: session.userId))
            }
        }
    }

    // MARK: - Account

    private var accountSection: some View {
        Section("Account") {
            HStack(spacing: Spacing.m) {
                AvatarCircle(name: session.displayName.isEmpty ? "?" : session.displayName,
                             color: Palette.accent, size: 56)
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(session.displayName.isEmpty ? "No name set" : session.displayName)
                        .font(.headline)
                    Text(emailText)
                        .font(.subheadline)
                        .foregroundStyle(Palette.textSecondary)
                }
            }
            .accessibilityElement(children: .combine)
            NavigationLink {
                EditNameView()
            } label: {
                LabeledContent("Name", value: session.displayName.isEmpty ? "Not set" : session.displayName)
            }
        }
    }

    private var emailText: String {
        guard let email = session.user?.email, !email.isEmpty else { return "Hidden by Apple" }
        return email.hasSuffix("privaterelay.appleid.com") ? "Hidden by Apple" : email
    }

    // MARK: - Notifications

    private var notificationsSection: some View {
        Section {
            if permission.isDenied {
                HStack {
                    Label("Notifications are off for Wayfare", systemImage: "bell.slash.fill")
                    Spacer()
                    Button("Open Settings") { permission.openSystemSettings() }
                        .buttonStyle(.borderless)
                }
            } else if permission.isNotDetermined {
                Button {
                    priming = PrimingRequest(
                        moment: .firstTrip,
                        title: "Get a heads-up before each plan",
                        body: "Wayfare can remind you before flights and check-ins, and send a short morning briefing on each day of your trips.")
                } label: {
                    Label("Turn On Notifications", systemImage: "bell.badge.fill")
                }
            }

            Group {
                Toggle("Morning briefing", isOn: Binding(
                    get: { devices.briefingEnabled },
                    set: { devices.setBriefingEnabled($0) }))
                if devices.briefingEnabled {
                    Picker("Briefing time", selection: Binding(
                        get: { devices.briefingHour },
                        set: { devices.setBriefingHour($0) })) {
                        ForEach(DeviceRegistrar.briefingHours, id: \.self) { hour in
                            Text(hourLabel(hour)).tag(hour)
                        }
                    }
                    .pickerStyle(.menu)
                }
                Toggle("Plan changes by others", isOn: Binding(
                    get: { devices.collabAlertsEnabled },
                    set: { devices.setCollabAlertsEnabled($0) }))
            }
            .disabled(permission.isDenied)
            .opacity(permission.isDenied ? 0.5 : 1)
        } header: {
            Text("Notifications")
        } footer: {
            Text("A summary of the day's plans each morning while you're on a trip. Plan changes by others: when someone on a shared trip adds or changes a plan. Plan reminders are set on each plan and work even offline.")
        }
        .accessibilityHint(permission.isDenied ? Text("Notifications are off in iOS Settings") : Text(""))
    }

    private func hourLabel(_ hour: Int) -> String {
        let date = Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: Date()) ?? Date()
        return TimeFormat.time(date, in: .current)
    }

    // MARK: - Sync

    private var syncSection: some View {
        Section("Sync") {
            LabeledContent("Last synced", value: TimeFormat.lastSynced(sync.lastSyncedAt))
            Button {
                Task { await sync.syncNow() }
            } label: {
                HStack {
                    Text("Sync Now")
                    Spacer()
                    if sync.isSyncing {
                        ProgressView()
                    }
                }
            }
            .disabled(sync.isSyncing)
            if sync.pendingChangeCount > 0 {
                Text(sync.pendingChangeCount == 1 ? "1 change waiting to sync" : "\(sync.pendingChangeCount) changes waiting to sync")
                    .font(.footnote)
                    .foregroundStyle(Palette.textSecondary)
            }
            if let error = sync.lastErrorMessage {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(Palette.danger)
            }
        }
    }

    // MARK: - About

    private var aboutSection: some View {
        Section("About") {
            LabeledContent("Version", value: AppConfig.appVersion)
            if let url = AppConfig.privacyPolicyURL {
                Link("Privacy Policy", destination: url)
            }
            if let url = AppConfig.termsURL {
                Link("Terms of Use", destination: url)
            }
            if let url = AppConfig.supportEmailURL {
                Link("Contact Support", destination: url)
            }
            HStack {
                LabeledContent("AI Import Consent", value: consentGiven ? "Given" : "Not given")
                if consentGiven {
                    Button("Withdraw") {
                        UserDefaults.standard.removeObject(forKey: AppServices.aiConsentKey(userId: session.userId))
                        consentGiven = false
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
    }

    // MARK: - Actions

    private func signOut() {
        isSigningOut = true
        Task {
            await session.signOut()
            isSigningOut = false
        }
    }
}

/// Edit display name (`PATCH /v1/me`, needs a connection).
struct EditNameView: View {
    @Environment(SessionStore.self) private var session
    @Environment(NetworkMonitor.self) private var network
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var isSaving = false
    @State private var errorText: String?

    private var trimmed: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        Form {
            Section {
                TextField("Your name", text: $name)
                    .textContentType(.givenName)
            } footer: {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("Shown to people you share trips with.")
                    if !network.isOnline {
                        Text("Changing your name needs a connection.")
                    }
                    if let errorText {
                        Text(errorText).foregroundStyle(Palette.danger)
                    }
                }
            }
        }
        .navigationTitle("Name")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                if isSaving {
                    ProgressView()
                } else {
                    Button("Save", action: save)
                        .fontWeight(.bold)
                        .disabled(!(1...40).contains(trimmed.count) || !network.isOnline)
                }
            }
        }
        .onAppear { name = session.displayName }
    }

    private func save() {
        isSaving = true
        errorText = nil
        Task {
            do {
                try await session.updateDisplayName(trimmed)
                dismiss()
            } catch {
                errorText = "Couldn't save your name. Try again."
            }
            isSaving = false
        }
    }
}

#if DEBUG
/// Settings → Developer (DEBUG builds only): server URL override and a health check.
struct DeveloperSection: View {
    @Environment(AppServices.self) private var services
    @Environment(SessionStore.self) private var session
    @State private var serverURL = AppConfig.apiBaseURLString
    @State private var healthResult: String?
    @State private var healthOK = false
    @State private var isTesting = false
    @State private var confirmingSwitch = false

    var body: some View {
        Section {
            TextField("Server URL", text: $serverURL)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.footnote.monospaced())
            Button {
                testConnection()
            } label: {
                HStack {
                    Text("Test Connection")
                    Spacer()
                    if isTesting { ProgressView() }
                }
            }
            if let healthResult {
                Label(healthResult, systemImage: healthOK ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(healthOK ? Palette.success : Palette.danger)
                    .font(.footnote)
            }
            Button("Apply") { confirmingSwitch = true }
                .disabled(serverURL == AppConfig.apiBaseURLString || URL(string: serverURL) == nil)
            Button("Reset to Default") {
                serverURL = AppConfig.defaultBaseURLString
                confirmingSwitch = true
            }
        } header: {
            Text("Developer")
        } footer: {
            Text("Default: \(AppConfig.defaultBaseURLString)")
        }
        .alert("Switch servers?", isPresented: $confirmingSwitch) {
            Button("Switch & Sign Out", role: .destructive) { applyServer() }
            Button("Cancel", role: .cancel) { serverURL = AppConfig.apiBaseURLString }
        } message: {
            Text("Switching servers signs you out and clears local data on this device.")
        }
    }

    private func testConnection() {
        isTesting = true
        healthResult = nil
        let url = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            do {
                let health = try await services.api.health(baseURLOverride: url)
                healthOK = health.ok
                healthResult = health.ok ? "OK · API v\(health.version)" : "Server answered but is not OK"
            } catch {
                healthOK = false
                healthResult = error.localizedDescription
            }
            isTesting = false
        }
    }

    private func applyServer() {
        let url = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            await session.signOut()
            if url == AppConfig.defaultBaseURLString {
                UserDefaults.standard.removeObject(forKey: AppConfig.debugOverrideKey)
            } else {
                UserDefaults.standard.set(url, forKey: AppConfig.debugOverrideKey)
            }
        }
    }
}
#endif

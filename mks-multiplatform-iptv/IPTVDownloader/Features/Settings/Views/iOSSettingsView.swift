//
//  iOSSettingsView.swift
//  mks-multiplatform-iptv
//
//  iOS Settings view - profile management and basic settings
//

import SwiftUI

#if os(iOS)
struct iOSSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var profilesManager: IPTVProfilesManager
    @State private var showAddEditSheet = false
    @State private var editingProfile: IPTVProfile? = nil
    @State private var showLoggingSettings = false

    var body: some View {
        NavigationStack {
            List {
                // Profile Section
                Section {
                    ForEach(profilesManager.profiles) { profile in
                        iOSProfileRow(profile: profile) {
                            editingProfile = profile
                            showAddEditSheet = true
                        }
                    }
                } header: {
                    Text("IPTV Profiles")
                }

                // Add Profile Button
                Section {
                    Button(action: {
                        editingProfile = nil
                        showAddEditSheet = true
                    }) {
                        Label("Add New Profile", systemImage: "plus")
                    }
                }

                // Active Profile Info
                if let activeProfile = profilesManager.activeProfile {
                    Section {
                        LabeledContent("Active Profile", value: activeProfile.name)
                        LabeledContent("Server", value: activeProfile.baseURL)
                        LabeledContent("User", value: "@\(activeProfile.username)")
                    } header: {
                        Text("Current Connection")
                    }
                }

                // Logging
                #if DEBUG
                Section {
                    Button(action: { showLoggingSettings = true }) {
                        Label("Logging Settings", systemImage: "doc.text.magnifyingglass")
                    }
                }
                #endif
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showAddEditSheet) {
                iOSEditProfileView(profile: $editingProfile) { profile in
                    if editingProfile != nil {
                        profilesManager.updateProfile(profile)
                    } else {
                        profilesManager.addProfile(profile)
                    }
                    showAddEditSheet = false
                }
            }
            .sheet(isPresented: $showLoggingSettings) {
                iOSLoggingSettingsView()
            }
        }
    }
}

// MARK: - Profile Row

struct iOSProfileRow: View {
    let profile: IPTVProfile
    let onEdit: () -> Void
    @EnvironmentObject private var profilesManager: IPTVProfilesManager

    var isActive: Bool {
        profilesManager.activeProfileID == profile.id
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(profile.name)
                        .font(.headline)

                    if isActive {
                        Text("ACTIVE")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor)
                            .foregroundColor(.white)
                            .cornerRadius(4)
                    }
                }

                Text(profile.baseURL)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)

                Text("@\(profile.username)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Spacer()

            if isActive {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.accentColor)
            } else {
                Button("Switch") {
                    profilesManager.selectProfile(profile.id)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onEdit()
        }
        .swipeActions(edge: .trailing) {
            Button("Edit", systemImage: "pencil") {
                onEdit()
            }
            .tint(.orange)

            if !isActive {
                Button("Delete", systemImage: "trash", role: .destructive) {
                    profilesManager.deleteProfile(profile.id)
                }
            }
        }
    }
}

// MARK: - Edit Profile View

struct iOSEditProfileView: View {
    @Binding var profile: IPTVProfile?
    @State private var name: String = ""
    @State private var baseURL: String = ""
    @State private var username: String = ""
    @State private var password: String = ""
    @State private var fileExtension: String = "mkv"
    var onSave: (IPTVProfile) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Profile Name", text: $name)
                    TextField("Server URL (http...:8080)", text: $baseURL)
                        .textContentType(.URL)
                        .autocapitalization(.none)
                    TextField("Username", text: $username)
                        .textContentType(.username)
                        .autocapitalization(.none)
                    SecureField("Password", text: $password)
                        .textContentType(.password)
                }

                Section {
                    TextField("Default Extension", text: $fileExtension)
                } footer: {
                    Text("File extension for streams without explicit extension (default: mkv)")
                }
            }
            .navigationTitle(profile == nil ? "New Profile" : "Edit Profile")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let edited = IPTVProfile(
                            id: profile?.id ?? UUID(),
                            name: name,
                            baseURL: baseURL,
                            username: username,
                            password: password,
                            fileExtension: fileExtension
                        )
                        onSave(edited)
                        dismiss()
                    }
                    .disabled(name.isEmpty || baseURL.isEmpty || username.isEmpty || password.isEmpty)
                }
            }
            .onAppear {
                if let p = profile {
                    name = p.name
                    baseURL = p.baseURL
                    username = p.username
                    password = p.password
                    fileExtension = p.fileExtension
                }
            }
        }
    }
}

// MARK: - iOS Logging Settings (simplified)

#if DEBUG
struct iOSLoggingSettingsView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("Log Directory") {
                        Text(MKSLogConfig.shared.logDirectory)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                } header: {
                    Text("Storage")
                }

                Section {
                    ForEach(MKSLogConfig.Subsystem.allCases) { subsystem in
                        iOSSubsystemLevelRow(subsystem: subsystem)
                    }
                } header: {
                    Text("Log Levels")
                } footer: {
                    Text("Changes take effect immediately for new log entries.")
                }

                Section {
                    Button(role: .destructive) {
                        MKSLogConfig.shared.clearAllLogs()
                    } label: {
                        Label("Clear All Logs", systemImage: "trash")
                    }
                }
            }
            .navigationTitle("Logging")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private struct iOSSubsystemLevelRow: View {
    let subsystem: MKSLogConfig.Subsystem
    @State private var selectedLevel: MKSLogConfig.Level

    init(subsystem: MKSLogConfig.Subsystem) {
        self.subsystem = subsystem
        self._selectedLevel = State(initialValue: MKSLogConfig.shared.level(for: subsystem))
    }

    var body: some View {
        Picker(subsystem.displayName, selection: $selectedLevel) {
            ForEach(MKSLogConfig.Level.allCases) { level in
                Text(level.displayName).tag(level)
            }
        }
        .onChange(of: selectedLevel) { _, newValue in
            MKSLogConfig.shared.setLevel(newValue, for: subsystem)
        }
    }
}
#endif
#endif

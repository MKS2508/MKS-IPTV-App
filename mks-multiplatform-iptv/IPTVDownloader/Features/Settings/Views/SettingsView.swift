import SwiftUI

#if os(macOS)
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var profilesManager: IPTVProfilesManager
    @State private var selectedTab: SettingsTab = .profiles
    
    enum SettingsTab: String, CaseIterable {
        case profiles = "Profiles"
        case cache = "Cache"
        case general = "General"
        case logging = "Logging"

        var systemImage: String {
            switch self {
            case .profiles: return "person.2.badge.key"
            case .cache: return "internaldrive"
            case .general: return "gearshape"
            case .logging: return "doc.text.magnifyingglass"
            }
        }
    }
    
    var body: some View {
        NavigationSplitView {
            // Sidebar with settings categories
            List(SettingsTab.allCases, id: \.self, selection: $selectedTab) { tab in
                Label(tab.rawValue, systemImage: tab.systemImage)
                    .tag(tab)
            }
            .navigationTitle("Settings")
            .frame(minWidth: 200)
        } detail: {
            // Detail view based on selected tab
            Group {
                switch selectedTab {
                case .profiles:
                    ProfilesSettingsView()
                case .cache:
                    CacheDebugView()
                case .general:
                    GeneralSettingsView()
                case .logging:
                    LoggingSettingsView()
                }
            }
            .frame(minWidth: 500, minHeight: 400)
        }
        .frame(width: 800, height: 600)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    dismiss()
                }
            }
        }
    }
}

struct ProfilesSettingsView: View {
    @EnvironmentObject private var profilesManager: IPTVProfilesManager
    @State private var showAddEditSheet = false
    @State private var editingProfile: IPTVProfile? = nil
    
    var body: some View {
        VStack {
            HeaderView()
            
            ProfilesList()
            
            AddProfileButton()
        }
        .navigationTitle("IPTV Profiles")
        .sheet(isPresented: $showAddEditSheet) {
            IPTVEditProfileView(profile: $editingProfile) { profile in
                if editingProfile != nil {
                    profilesManager.updateProfile(profile)
                } else {
                    profilesManager.addProfile(profile)
                }
                showAddEditSheet = false
            }
        }
    }
    
    @ViewBuilder
    private func HeaderView() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "server.rack")
                    .font(.title2)
                    .foregroundColor(.accentColor)
                Text("IPTV Server Profiles")
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
            }
            
            Text("Manage your IPTV server connections. The active profile is used for all streaming and downloads.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.leading)
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
        .padding(.horizontal)
    }
    
    @ViewBuilder
    private func ProfilesList() -> some View {
        List {
            ForEach(profilesManager.profiles) { profile in
                ProfileRow(profile: profile) {
                    editingProfile = profile
                    showAddEditSheet = true
                }
            }
        }
        .listStyle(.inset)
        .padding(.horizontal)
    }
    
    @ViewBuilder
    private func AddProfileButton() -> some View {
        Button(action: {
            editingProfile = nil
            showAddEditSheet = true
        }) {
            Label("Add New Profile", systemImage: "plus")
                .font(.headline)
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color.accentColor)
                .foregroundColor(.white)
                .cornerRadius(8)
        }
        .buttonStyle(.plain)
        .padding(.horizontal)
        .padding(.bottom)
    }
}

struct ProfileRow: View {
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
                        .foregroundColor(.primary)
                    
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
                    .font(.title3)
            } else {
                Button("Switch") {
                    profilesManager.selectProfile(profile.id)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .contextMenu {
            Button("Edit Profile") {
                onEdit()
            }
            
            if !isActive {
                Button("Set as Active") {
                    profilesManager.selectProfile(profile.id)
                }
            }
            
            Button("Delete Profile", role: .destructive) {
                profilesManager.deleteProfile(profile.id)
            }
        }
    }
}

struct GeneralSettingsView: View {
    @EnvironmentObject private var profilesManager: IPTVProfilesManager

    var body: some View {
        Form {
            Section {
                SyncStatusDetailView(manager: profilesManager)
            } header: {
                Label("iCloud Sync", systemImage: "icloud")
            }

            SyncedDevicesView()
        }
        .formStyle(.grouped)
        .navigationTitle("General")
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#if DEBUG
struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
            .environmentObject(IPTVProfilesManager.shared)
    }
}
#endif

#endif // os(macOS)
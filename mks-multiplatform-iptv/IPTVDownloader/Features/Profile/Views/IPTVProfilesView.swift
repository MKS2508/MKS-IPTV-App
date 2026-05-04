import SwiftUI
import IPTVCore

struct IPTVProfilesView: View {
    @ObservedObject var manager: IPTVProfilesManager = .shared
    @State private var showAddEditSheet = false
    @State private var editingProfile: IPTVProfile? = nil
    var isInSettingsMode: Bool = false
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                List(selection: $manager.activeProfileID) {
                    ForEach(manager.profiles) { profile in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(profile.name)
                                    .font(.headline)
                                Text(profile.baseURL)
                                    .font(.caption).foregroundColor(.secondary)
                                Text("@\(profile.username)")
                                    .font(.caption2).foregroundColor(.gray)
                            }
                            Spacer()
                            if manager.activeProfileID == profile.id {
                                Image(systemName: "checkmark.circle.fill").foregroundColor(.accentColor)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            manager.selectProfile(profile.id)
                        }
                        .contextMenu {
                            Button("Editar") { editingProfile = profile; showAddEditSheet = true }
                            Button("Eliminar", role: .destructive) { manager.deleteProfile(profile.id) }
                        }
                    }
                }
#if os(iOS)
                .listStyle(.insetGrouped)
#else
                .listStyle(.sidebar)
#endif
                .frame(maxHeight: 400)
                
                Button(action: { editingProfile = nil; showAddEditSheet = true }) {
                    Label("Nueva cuenta/servidor IPTV", systemImage: "plus")
                        .font(.title3.bold())
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Capsule().fill(Color.accentColor))
                        .foregroundColor(.white)
                        .padding(.horizontal)
                }
                .padding(.bottom, 16)
                
                // Show current active profile info when in settings mode
                if isInSettingsMode, let activeProfile = manager.activeProfile {
                    VStack(spacing: 8) {
                        Divider()
                            .padding(.horizontal)
                        
                        VStack(spacing: 4) {
                            Text("Current Active Profile")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Text(activeProfile.name)
                                .font(.headline)
                                .foregroundColor(.accentColor)
                            
                            Text(activeProfile.baseURL)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .padding(.bottom, 8)
                    }
                }
            }
            .navigationTitle(isInSettingsMode ? "IPTV Server Profiles" : "Perfiles y servidores IPTV")
        }
        .sheet(isPresented: $showAddEditSheet) {
            IPTVEditProfileView(profile: $editingProfile) { profile in
                if editingProfile != nil {
                    manager.updateProfile(profile)
                } else {
                    manager.addProfile(profile)
                }
                showAddEditSheet = false
            }
        }
    }
}

struct IPTVEditProfileView: View {
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
                TextField("Nombre del perfil", text: $name)
#if os(iOS)
                TextField("URL Base (http...:8080)", text: $baseURL).keyboardType(.URL)
#else
                TextField("URL Base (http...:8080)", text: $baseURL)
#endif
                TextField("Usuario", text: $username)
                SecureField("Contraseña", text: $password)
                TextField("Extensión predeterminada", text: $fileExtension)
            }
            .navigationTitle(profile == nil ? "Nuevo Perfil" : "Editar Perfil")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") {
                        let edited = IPTVProfile(id: profile?.id ?? UUID(), name: name, baseURL: baseURL, username: username, password: password, fileExtension: fileExtension)
                        onSave(edited)
                        dismiss()
                    }.disabled(name.isEmpty || baseURL.isEmpty || username.isEmpty || password.isEmpty)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
            }
            .onAppear {
                if let p = profile {
                    name = p.name; baseURL = p.baseURL; username = p.username; password = p.password; fileExtension = p.fileExtension
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

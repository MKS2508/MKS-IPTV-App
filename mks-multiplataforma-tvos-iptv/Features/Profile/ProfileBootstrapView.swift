//
//  ProfileBootstrapView.swift
//  mks-multiplataforma-tvos-iptv
//
//  iCloud-first profile bootstrap. On launch we try to pull an existing
//  IPTVProfile from CloudKit (synced from iPhone/Mac). If found, the user
//  picks one with a click — no manual typing on the Apple TV remote.
//  If the iCloud zone is empty / iCloud not signed in, we fall back to
//  a manual sign-in form.
//

import SwiftUI
import IPTVCore

struct ProfileBootstrapView: View {
    @EnvironmentObject private var store: ProfileStore
    @StateObject private var fetcher = iCloudProfileFetcher()

    @State private var showManualForm = false

    var body: some View {
        ZStack {
            backgroundGradient.ignoresSafeArea()

            switch fetcher.state {
            case .idle, .fetching:
                fetchingView
            case .found(let profiles):
                if showManualForm {
                    manualForm
                } else {
                    cloudProfilesPicker(profiles)
                }
            case .empty, .notSignedIn, .failed:
                manualForm
            }
        }
        .task {
            if case .idle = fetcher.state {
                await fetcher.fetch()
            }
        }
    }

    // MARK: - States

    private var fetchingView: some View {
        VStack(spacing: 32) {
            Image(systemName: "icloud.and.arrow.down")
                .font(.system(size: 120, weight: .ultraLight))
                .foregroundStyle(.white.opacity(0.85))
                .symbolEffect(.pulse)

            Text("Looking for your profile in iCloud…")
                .font(.title2.weight(.medium))
                .foregroundStyle(.white.opacity(0.85))

            ProgressView().scaleEffect(1.4)
        }
    }

    private func cloudProfilesPicker(_ profiles: [IPTVProfile]) -> some View {
        VStack(spacing: 40) {
            VStack(spacing: 12) {
                Image(systemName: "checkmark.icloud.fill")
                    .font(.system(size: 84, weight: .light))
                    .foregroundStyle(.green)
                Text("Sign in with iCloud")
                    .font(.system(size: 56, weight: .bold))
                    .foregroundStyle(.white)
                Text("Choose a profile synced from your iPhone or Mac.")
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.7))
            }

            ScrollView {
                VStack(spacing: 18) {
                    ForEach(profiles) { profile in
                        cloudProfileButton(profile)
                    }
                }
                .frame(maxWidth: 900)
                .padding(.horizontal, 60)
            }
            .frame(maxHeight: 480)

            Button("Sign in manually instead") {
                showManualForm = true
            }
            .buttonStyle(.bordered)
            .tint(.white.opacity(0.4))
            .foregroundStyle(.white.opacity(0.85))
            .padding(.top, 8)
        }
        .padding(60)
    }

    private func cloudProfileButton(_ profile: IPTVProfile) -> some View {
        Button {
            store.adopt(profile)
        } label: {
            HStack(spacing: 24) {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.white)

                VStack(alignment: .leading, spacing: 4) {
                    Text(profile.name)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.white)
                    Text(profile.baseURL)
                        .font(.callout)
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                    Text("@\(profile.username)")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.white.opacity(0.85))
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.forward.circle.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(.white.opacity(0.7))
            }
            .padding(.vertical, 24)
            .padding(.horizontal, 32)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.card)
    }

    private var manualForm: some View {
        ManualProfileForm(
            title: fetcher.state == .notSignedIn
                ? "Sign in to iCloud on the Apple TV — or enter credentials manually"
                : nil
        ) { name, baseURL, username, password in
            store.save(name: name, baseURL: baseURL, username: username, password: password)
        }
    }

    private var backgroundGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.04, green: 0.04, blue: 0.10),
                Color(red: 0.10, green: 0.04, blue: 0.20),
                Color(red: 0.04, green: 0.04, blue: 0.10)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

// MARK: - ManualProfileForm

private struct ManualProfileForm: View {
    let title: String?
    let onSave: (String, String, String, String) -> Void

    @State private var serverURL: String = ""
    @State private var username: String = ""
    @State private var password: String = ""
    @State private var name: String = "My IPTV"

    @FocusState private var focusedField: Field?

    private enum Field: Hashable { case name, server, username, password, save }

    private var canSave: Bool {
        !serverURL.trimmingCharacters(in: .whitespaces).isEmpty &&
        !username.trimmingCharacters(in: .whitespaces).isEmpty &&
        !password.isEmpty
    }

    var body: some View {
        HStack(spacing: 80) {
            heroPanel.frame(maxWidth: .infinity)
            form.frame(width: 720)
        }
        .padding(80)
        .onAppear { focusedField = .server }
    }

    private var heroPanel: some View {
        VStack(alignment: .leading, spacing: 32) {
            Image(systemName: "tv.inset.filled")
                .font(.system(size: 140, weight: .ultraLight))
                .foregroundStyle(
                    LinearGradient(colors: [.white, .white.opacity(0.5)],
                                   startPoint: .topLeading,
                                   endPoint: .bottomTrailing)
                )

            VStack(alignment: .leading, spacing: 12) {
                Text("MKS IPTV")
                    .font(.system(size: 88, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                Text("Movies. Series. Live TV.")
                    .font(.title.weight(.medium))
                    .foregroundStyle(.white.opacity(0.7))
            }

            Spacer()

            if let title {
                Text(title)
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.55))
                    .frame(maxWidth: 560, alignment: .leading)
            } else {
                Text("Sign in with your Xtream Codes credentials.")
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.55))
                    .frame(maxWidth: 560, alignment: .leading)
            }
        }
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 28) {
            Text("Manual Sign In")
                .font(.system(size: 56, weight: .bold))
                .foregroundStyle(.white)
                .padding(.bottom, 8)

            field(label: "Profile name", text: $name, field: .name)
            field(label: "Server URL", text: $serverURL, field: .server, hint: "https://example.com:8080")
            field(label: "Username", text: $username, field: .username)
            secureField(label: "Password", text: $password, field: .password)

            Button {
                guard canSave else { return }
                onSave(
                    name.isEmpty ? "My IPTV" : name,
                    serverURL.trimmingCharacters(in: .whitespaces),
                    username.trimmingCharacters(in: .whitespaces),
                    password
                )
            } label: {
                HStack {
                    Spacer()
                    Text("Continue")
                        .font(.title2.weight(.semibold))
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.title2)
                    Spacer()
                }
                .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .tint(canSave ? .accentColor : .gray)
            .disabled(!canSave)
            .focused($focusedField, equals: .save)
            .padding(.top, 16)
        }
    }

    @ViewBuilder
    private func field(label: String, text: Binding<String>, field: Field, hint: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.headline)
                .foregroundStyle(.white.opacity(0.7))
            TextField(hint ?? "", text: text)
                .textFieldStyle(.plain)
                .focused($focusedField, equals: field)
                .font(.title3)
                .padding(.vertical, 12)
                .padding(.horizontal, 16)
                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    @ViewBuilder
    private func secureField(label: String, text: Binding<String>, field: Field) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.headline)
                .foregroundStyle(.white.opacity(0.7))
            SecureField("", text: text)
                .textFieldStyle(.plain)
                .focused($focusedField, equals: field)
                .font(.title3)
                .padding(.vertical, 12)
                .padding(.horizontal, 16)
                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
        }
    }
}

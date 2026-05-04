//
//  ProfileBootstrapView.swift
//  mks-multiplataforma-tvos-iptv
//
//  First-run onboarding. Asks for Xtream Codes credentials.
//  TV-friendly form: large fields, generous spacing, clear primary CTA.
//

import SwiftUI
import IPTVCore

struct ProfileBootstrapView: View {
    @EnvironmentObject private var store: ProfileStore

    @State private var serverURL: String = ""
    @State private var username: String = ""
    @State private var password: String = ""
    @State private var name: String = "My IPTV"

    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case name, server, username, password, save
    }

    private var canSave: Bool {
        !serverURL.trimmingCharacters(in: .whitespaces).isEmpty &&
        !username.trimmingCharacters(in: .whitespaces).isEmpty &&
        !password.isEmpty
    }

    var body: some View {
        ZStack {
            backgroundGradient.ignoresSafeArea()

            HStack(spacing: 80) {
                heroPanel
                    .frame(maxWidth: .infinity)

                form
                    .frame(width: 720)
            }
            .padding(80)
        }
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

            Text("Sign in with your Xtream Codes credentials to get started.")
                .font(.title3)
                .foregroundStyle(.white.opacity(0.55))
                .frame(maxWidth: 560, alignment: .leading)
        }
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 28) {
            Text("Sign In")
                .font(.system(size: 56, weight: .bold))
                .foregroundStyle(.white)
                .padding(.bottom, 8)

            field(label: "Profile name", text: $name, field: .name)
            field(label: "Server URL", text: $serverURL, field: .server, hint: "https://example.com:8080")
            field(label: "Username", text: $username, field: .username)
            secureField(label: "Password", text: $password, field: .password)

            Button {
                guard canSave else { return }
                store.save(
                    name: name.isEmpty ? "My IPTV" : name,
                    baseURL: serverURL.trimmingCharacters(in: .whitespaces),
                    username: username.trimmingCharacters(in: .whitespaces),
                    password: password
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

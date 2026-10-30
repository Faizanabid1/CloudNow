import SwiftUI

/// Phone GFN sign-in. The verification page opens on this phone with the code pre-filled;
/// the QR code still lets another device finish sign-in.
struct PhoneLoginView: View {
    @Environment(AuthManager.self) private var authManager
    @Environment(\.openURL) private var openURL
    @State private var providers: [LoginProvider]?
    @State private var selectedProvider: LoginProvider?

    var body: some View {
        Group {
            switch authManager.loginPhase {
            case .idle:
                providerPicker
            case let .showingPIN(code, url, urlComplete):
                codeView(code: code, url: url, urlComplete: urlComplete)
            case .exchangingTokens:
                ProgressView(L10n.text("signing_in"))
            case let .failed(message):
                failedView(message)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .task {
            providers = await (try? authManager.discoverLoginProviders()) ?? []
        }
    }

    private var providerPicker: some View {
        VStack(spacing: 16) {
            Text(L10n.text("sign_in_to_geforce_now"))
                .font(.title.bold())

            if let providers {
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(providers.sorted { $0.priority < $1.priority }, id: \.idpId) { provider in
                            Button {
                                selectedProvider = provider
                                authManager.login(with: provider)
                            } label: {
                                Text(provider.displayName)
                                    .font(.headline)
                                    .frame(maxWidth: .infinity, minHeight: 36)
                            }
                            .buttonStyle(.bordered)
                            .tint(provider.isNvidiaDirect ? .green : .gray)
                        }
                    }
                    .frame(maxWidth: 360)
                }
                .frame(maxHeight: 220)
            } else {
                ProgressView()
            }

        }
    }

    private func codeView(code: String, url: String, urlComplete: String) -> some View {
        // Side by side when held sideways; stacked when the phone is upright.
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 32) {
                codeDetails(code: code, url: url, urlComplete: urlComplete)
                qrCode(urlComplete)
            }
            ScrollView {
                VStack(spacing: 20) {
                    codeDetails(code: code, url: url, urlComplete: urlComplete)
                    qrCode(urlComplete)
                }
            }
        }
    }

    private func qrCode(_ urlComplete: String) -> some View {
        QRCodeView(payload: urlComplete)
            .frame(width: 170, height: 170)
            .padding(10)
            .background(.white, in: RoundedRectangle(cornerRadius: 12))
    }

    private func codeDetails(code: String, url: String, urlComplete: String) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L10n.text("sign_in_to_geforce_now"))
                .font(.title2.bold())
            Text(code)
                .font(.system(size: 44, weight: .bold, design: .monospaced))
                .textSelection(.enabled)
            Button {
                if let destination = URL(string: urlComplete) {
                    openURL(destination)
                }
            } label: {
                Label("Sign In on This Phone", systemImage: "safari")
                    .font(.headline)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
            Text("Or scan the code, or go to \(url) on another device and enter the code above.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Button(L10n.text("cancel")) {
                authManager.cancelLogin()
            }
            .font(.footnote)
        }
        .frame(maxWidth: 340, alignment: .leading)
    }

    private func failedView(_ message: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.largeTitle)
                .foregroundStyle(.yellow)
            Text(L10n.text("sign_in_failed"))
                .font(.title2.bold())
            Text(message)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            HStack {
                Button(L10n.text("try_again")) {
                    authManager.login(with: selectedProvider)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                Button(L10n.text("cancel")) {
                    authManager.cancelLogin()
                }
                .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: 420)
    }
}

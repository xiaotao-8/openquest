import SwiftUI

/// The sign-in sheet: the same three provider buttons at every sign-in
/// entry point. Tapping one opens the provider's sign-in in the system
/// browser session (ClerkKit); nothing here is a WebView and no OAuth flow
/// is hand-written. Cancelling closes silently; other failures show one
/// plain line under the buttons.
struct SignInSheet: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            ModalHeader(title: L("登录账号")) {
                dismiss()
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(spacing: 10) {
                        ProviderButton(provider: .apple, title: L("使用 Apple 登录")) {
                            Image(systemName: "apple.logo").font(.system(size: 20))
                        }
                        .buttonStyle(.primary)
                        ProviderButton(provider: .google, title: L("使用 Google 登录")) {
                            EmptyView()
                        }
                        .buttonStyle(.secondary)
                        ProviderButton(provider: .github, title: L("使用 GitHub 登录")) {
                            EmptyView()
                        }
                        .buttonStyle(.secondary)
                    }
                    if let message = store.account.errorMessage {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(Palette.danger)
                            .transition(.opacity)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
        }
        .background(Palette.background)
        .onChange(of: store.account.isSignedIn) { _, signedIn in
            if signedIn { dismiss() }
        }
    }
}

/// One provider's full-width button: its mark and line, a spinner while a
/// sign-in runs (styled by the caller).
private struct ProviderButton<Mark: View>: View {
    @EnvironmentObject private var store: AppStore
    let provider: AccountStore.SignInProvider
    let title: String
    @ViewBuilder let mark: Mark

    var body: some View {
        Button { Task { await store.account.signIn(provider: provider) } } label: {
            ZStack {
                HStack(spacing: 10) {
                    mark
                    Text(title)
                }
                .opacity(store.account.isBusy ? 0 : 1)
                if store.account.isBusy { Spinner(size: 18) }
            }
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 28)
        }
        .disabled(store.account.isBusy)
        .animation(.easeInOut(duration: 0.2), value: store.account.isBusy)
    }
}

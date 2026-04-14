import AuthenticationServices
import SwiftUI

struct OnboardingView: View {
    /// Invoked after the user has successfully signed in with Apple. The
    /// caller is responsible for flipping the "seen onboarding" flag and
    /// advancing into the app.
    let onComplete: () -> Void

    @Environment(AuthViewModel.self) private var authViewModel
    @State private var animateRings = false

    private let ringColors: [Color] = [.orange, .green, .blue]

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // Animated rings + bell icon
                ZStack {
                    ForEach(0..<3, id: \.self) { index in
                        Circle()
                            .stroke(
                                ringColors[index % ringColors.count].opacity(0.15),
                                lineWidth: 1.5
                            )
                            .frame(
                                width: CGFloat(140 + index * 50),
                                height: CGFloat(140 + index * 50)
                            )
                            .scaleEffect(animateRings ? 1.05 : 0.95)
                            .animation(
                                .easeInOut(duration: 2.5 + Double(index) * 0.4)
                                .repeatForever(autoreverses: true),
                                value: animateRings
                            )
                    }

                    Image(systemName: "bell.badge.fill")
                        .font(.system(size: 72, weight: .light))
                        .foregroundStyle(.orange)
                        .symbolRenderingMode(.hierarchical)
                }
                .frame(height: 240)

                Text("StatShot")
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.top, 16)

                Text("Get alerts the moment your player does something.")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .padding(.top, 10)
                    .padding(.horizontal, 40)

                Spacer()

                // How it works strip
                HStack(spacing: 0) {
                    howItWorksItem(icon: "person.crop.circle", label: "Pick a\nplayer")
                    howItWorksItem(icon: "bolt.fill", label: "Pick a\nstat")
                    howItWorksItem(icon: "bell.badge.fill", label: "Get\nnotified")
                }
                .padding(.horizontal, 24)

                Spacer()

                // Native SIWA button. Tapping it fires our AuthViewModel flow;
                // SwiftUI's own `onRequest` / `onCompletion` are not used here
                // because we want the full flow (APNs registration, profile
                // load) gated through the ViewModel in one place.
                SignInWithAppleButton(.signIn) { _ in
                    // intentionally empty — we drive the flow via the tap
                    // gesture on the overlay below. Leaving the request
                    // builder empty is fine; we won't use this code path.
                } onCompletion: { _ in
                    // Same: ignored. See overlay tap handler.
                }
                .signInWithAppleButtonStyle(.white)
                .frame(height: 54)
                .cornerRadius(12)
                .padding(.horizontal, 40)
                .overlay(
                    // Intercept all taps and run our real flow. The
                    // SignInWithAppleButton gives us Apple-approved chrome
                    // (logo, localized label); we just reuse it as a button
                    // face. This keeps the SIWA completion entirely in
                    // AuthViewModel and avoids double-presenting the sheet.
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture {
                            Task {
                                await authViewModel.signInWithApple()
                                if authViewModel.isAuthenticated {
                                    onComplete()
                                }
                            }
                        }
                )
                .disabled(authViewModel.isLoading)
                .opacity(authViewModel.isLoading ? 0.6 : 1.0)

                if let errorMessage = authViewModel.errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 13))
                        .foregroundStyle(.red.opacity(0.9))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                        .padding(.top, 12)
                } else {
                    Text("We'll ask for notification permission next.")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(.white.opacity(0.4))
                        .padding(.top, 12)
                }

                Spacer().frame(height: 40)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear { animateRings = true }
    }

    private func howItWorksItem(icon: String, label: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 26, weight: .regular))
                .foregroundStyle(.white)
                .frame(height: 32)

            Text(label)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .lineSpacing(2)
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    OnboardingView(onComplete: {})
        .environment(AuthViewModel())
}

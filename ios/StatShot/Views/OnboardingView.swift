import SwiftUI

struct OnboardingView: View {
    let onComplete: () -> Void

    @State private var currentPage = 0

    // League colors for background decoration
    private let leagueColors: [Color] = [.orange, .green, .blue, .red, .mint, .purple, .teal]

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            TabView(selection: $currentPage) {
                OnboardingPage(
                    icon: "person.crop.circle.badge.plus",
                    title: "Follow Any Player",
                    subtitle: "LeBron's turnovers. Mahomes' touchdowns.\nOhtani's strikeouts. Pick any player, any stat.",
                    leagueColors: leagueColors
                )
                .tag(0)

                OnboardingPage(
                    icon: "bolt.circle.fill",
                    title: "Real-Time Alerts",
                    subtitle: "Get notified the moment it happens.\nEvery three-pointer. Every sack. Every home run.",
                    leagueColors: leagueColors,
                    alertPreview: true
                )
                .tag(1)

                OnboardingPage(
                    icon: "bell.badge.circle.fill",
                    title: "Never Miss a Moment",
                    subtitle: "29 stat types across NBA, NFL, NHL,\nMLB, college, and MLS.",
                    leagueColors: leagueColors,
                    showGetStarted: true,
                    onGetStarted: onComplete
                )
                .tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Onboarding Page

private struct OnboardingPage: View {
    let icon: String
    let title: String
    let subtitle: String
    let leagueColors: [Color]
    var alertPreview: Bool = false
    var showGetStarted: Bool = false
    var onGetStarted: (() -> Void)?

    @State private var animateRings = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Icon with animated background rings
            ZStack {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .stroke(
                            leagueColors[index % leagueColors.count].opacity(0.15),
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

                Image(systemName: icon)
                    .font(.system(size: 80, weight: .light))
                    .foregroundStyle(.orange)
                    .symbolRenderingMode(.hierarchical)
            }
            .frame(height: 260)

            // Title
            Text(title)
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .padding(.top, 24)

            // Subtitle
            Text(subtitle)
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .padding(.top, 12)
                .padding(.horizontal, 40)

            // Alert preview card (screen 2 only)
            if alertPreview {
                alertPreviewCard
                    .padding(.top, 32)
            }

            Spacer()

            // Get Started button (screen 3 only)
            if showGetStarted {
                Button(action: { onGetStarted?() }) {
                    Text("Get Started")
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .padding(.horizontal, 40)
                .padding(.bottom, 60)
            } else {
                // Spacer to keep consistent layout
                Color.clear.frame(height: 100)
            }
        }
        .onAppear { animateRings = true }
    }

    private var alertPreviewCard: some View {
        HStack(spacing: 12) {
            Text("\u{1F3C0}")
                .font(.system(size: 28))

            VStack(alignment: .leading, spacing: 4) {
                Text("THREE")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.orange)

                Text("Curry drains one from beyond the arc.")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(.white.opacity(0.9))

                Text("GSW 88, LAL 82 | Q3 4:22")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.4))
            }

            Spacer()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
        .padding(.horizontal, 32)
    }
}

#Preview {
    OnboardingView(onComplete: {})
}

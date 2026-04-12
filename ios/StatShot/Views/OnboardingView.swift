import SwiftUI

struct OnboardingView: View {
    let onComplete: () -> Void

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

                Button(action: onComplete) {
                    Text("Get Started")
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .padding(.horizontal, 40)

                Text("We'll ask for notification permission next.")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.white.opacity(0.4))
                    .padding(.top, 12)
                    .padding(.bottom, 40)
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
}

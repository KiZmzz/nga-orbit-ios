import SwiftUI

/// The system launch screen stays static as required by iOS. This matching,
/// short-lived layer adds motion after the first frame while startup work runs
/// underneath, so it never delays networking or blocks the main interface.
struct AnimatedSplashView: View {
    let finished: () -> Void
    @State private var entered = false
    @State private var breathing = false

    private let stars: [(x: CGFloat, y: CGFloat, size: CGFloat, delay: Double)] = [
        (0.12, 0.18, 2.3, 0.0), (0.78, 0.14, 1.7, 0.3), (0.88, 0.29, 2.1, 0.7),
        (0.22, 0.38, 1.5, 0.5), (0.69, 0.43, 2.5, 0.2), (0.10, 0.61, 1.8, 0.9),
        (0.84, 0.68, 1.6, 0.4), (0.28, 0.77, 2.2, 0.8), (0.72, 0.84, 1.7, 0.1)
    ]

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Image("SplashBackground")
                    .resizable()
                    .scaledToFill()
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .scaleEffect(entered ? 1.035 : 1.0)
                    .offset(y: entered ? -5 : 0)
                    .clipped()

                LinearGradient(colors: [.black.opacity(0.08), .clear, .black.opacity(0.28)],
                               startPoint: .top, endPoint: .bottom)

                ForEach(Array(stars.enumerated()), id: \.offset) { _, star in
                    Circle()
                        .fill(Color.white)
                        .frame(width: star.size, height: star.size)
                        .shadow(color: AppTheme.brand.opacity(0.9), radius: 4)
                        .opacity(breathing ? 0.25 : 0.95)
                        .position(x: proxy.size.width * star.x,
                                  y: proxy.size.height * star.y + (entered ? -4 : 4))
                        .animation(.easeInOut(duration: 1.15).repeatForever(autoreverses: true)
                            .delay(star.delay), value: breathing)
                }

                VStack(spacing: 9) {
                    Spacer().frame(height: proxy.size.height * 0.39)
                    Text("NGA Orbit")
                        .font(.system(size: 34, weight: .heavy, design: .rounded))
                        .tracking(0.8)
                    Text("聚集热爱 · 探索每一颗星")
                        .font(.subheadline.weight(.medium))
                        .tracking(1.2)
                        .foregroundStyle(.white.opacity(0.78))
                    Spacer()
                }
                .foregroundStyle(.white)
                .opacity(entered ? 1 : 0)
                .offset(y: entered ? 0 : 10)
                .shadow(color: .black.opacity(0.5), radius: 10, y: 3)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .ignoresSafeArea()
        }
        .background(Color(red: 0.02, green: 0.06, blue: 0.10))
        .onAppear {
            withAnimation(.easeOut(duration: 0.8)) { entered = true }
            breathing = true
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(2.0))
                finished()
            }
        }
        .accessibilityHidden(true)
    }
}

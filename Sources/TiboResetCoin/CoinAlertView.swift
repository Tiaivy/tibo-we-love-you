import AppKit
import SwiftUI

struct CoinAlertView: View {
    let openTweet: () -> Void
    let dismiss: () -> Void

    @State private var cardIsVisible = false
    @State private var buttonIsPressed = false
    @State private var pulseIsVisible = false

    init(
        preview: Bool = false,
        openTweet: @escaping () -> Void,
        dismiss: @escaping () -> Void
    ) {
        self.openTweet = openTweet
        self.dismiss = dismiss
        _cardIsVisible = State(initialValue: preview)
        _pulseIsVisible = State(initialValue: preview)
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            HStack(spacing: 10) {
                ResetButtonGraphic(
                    isPressed: buttonIsPressed,
                    pulseIsVisible: pulseIsVisible
                )
                .frame(width: 64, height: 64)

                VStack(alignment: .leading, spacing: 7) {
                    Text("Tibo hit reset!")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(
                            Color(red: 0.07, green: 0.075, blue: 0.085)
                        )

                    Text(
                        "ChatGPT and Codex limits have been reset. "
                            + "Back to building!"
                    )
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(
                            Color(red: 0.43, green: 0.46, blue: 0.49)
                        )
                        .lineLimit(2)

                    Button(action: openTweet) {
                        HStack(spacing: 4) {
                            Text("View Tibo’s post on X")
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 9, weight: .bold))
                        }
                        .font(.system(size: 11.5, weight: .bold))
                        .foregroundStyle(
                            Color(red: 0.73, green: 0.08, blue: 0.12)
                        )
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 1)
                }

                Spacer(minLength: 22)
            }
            .padding(.horizontal, 14)

            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(
                        Color(red: 0.48, green: 0.50, blue: 0.53)
                    )
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .padding(.top, 5)
            .padding(.trailing, 5)
        }
        .frame(width: 326, height: 118)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.white)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(
                    Color(red: 0.87, green: 0.88, blue: 0.90),
                    lineWidth: 1
                )
        }
        .padding(8)
        .scaleEffect(cardIsVisible ? 1 : 0.96)
        .opacity(cardIsVisible ? 1 : 0)
        .onAppear {
            withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) {
                cardIsVisible = true
            }
        }
        .task { await animateButton() }
    }

    private func animateButton() async {
        for _ in 0..<5 {
            guard !Task.isCancelled else { return }
            withAnimation(.easeIn(duration: 0.16)) {
                buttonIsPressed = true
            }

            try? await Task.sleep(for: .milliseconds(160))
            guard !Task.isCancelled else { return }
            withAnimation(.spring(response: 0.34, dampingFraction: 0.52)) {
                buttonIsPressed = false
            }
            withAnimation(.easeOut(duration: 0.58)) {
                pulseIsVisible = true
            }

            try? await Task.sleep(for: .milliseconds(640))
            guard !Task.isCancelled else { return }
            pulseIsVisible = false

            try? await Task.sleep(for: .milliseconds(200))
        }
    }
}

struct ResetButtonGraphic: View {
    let isPressed: Bool
    let pulseIsVisible: Bool

    var body: some View {
        GeometryReader { geometry in
            let size = min(geometry.size.width, geometry.size.height)

            ZStack {
                Ellipse()
                    .stroke(
                        Color.red.opacity(pulseIsVisible ? 0 : 0.38),
                        lineWidth: max(0.7, size * 0.018)
                    )
                    .frame(width: size * 0.58, height: size * 0.36)
                    .offset(y: -size * 0.08)
                    .scaleEffect(pulseIsVisible ? 1.46 : 0.84)

                Image(nsImage: buttonImage)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: size, height: size)
                    .offset(y: isPressed ? size * 0.025 : 0)
                    .scaleEffect(
                        y: isPressed ? 0.94 : 1,
                        anchor: .bottom
                    )
            }
            .frame(width: size, height: size)
            .frame(
                maxWidth: .infinity,
                maxHeight: .infinity,
                alignment: .center
            )
        }
        .animation(.easeInOut(duration: 0.16), value: isPressed)
        .animation(.easeOut(duration: 0.58), value: pulseIsVisible)
    }

    private var buttonImage: NSImage {
        let packagedURL = Bundle.main.executableURL?
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Resources/TiboButtonPhoto.png")

        for case let url? in [
            Bundle.main.url(
                forResource: "TiboButtonPhoto",
                withExtension: "png"
            ),
            packagedURL
        ] {
            if let image = NSImage(contentsOf: url) {
                return image
            }
        }

        if let developmentURL = Bundle.module.url(
                forResource: "TiboButtonPhoto",
                withExtension: "png"
        ),
        let image = NSImage(contentsOf: developmentURL) {
            return image
        }

        return NSImage(size: NSSize(width: 1, height: 1))
    }
}

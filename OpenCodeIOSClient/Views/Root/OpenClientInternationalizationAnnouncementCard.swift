import SwiftUI

struct OpenClientInternationalizationAnnouncementSection: View {
    let announcements: [OpenClientReleaseNotes.InternationalizationAnnouncement]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("NEW LANGUAGES")
                    .font(.caption.weight(.bold))
                    .tracking(0.8)
                    .foregroundStyle(.secondary)

                Text("OpenClient, in your language")
                    .font(.title2.bold())
            }

            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { timeline in
                let phase = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate

                LazyVStack(spacing: 12) {
                    ForEach(announcements) { announcement in
                        OpenClientInternationalizationAnnouncementCard(
                            announcement: announcement,
                            phase: phase
                        )
                    }
                }
            }

            OpenClientLocalizationContributionCard()
        }
    }
}

struct OpenClientInternationalizationAnnouncementCard: View {
    let announcement: OpenClientReleaseNotes.InternationalizationAnnouncement
    let phase: TimeInterval

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            OpenClientLocaleCloth(
                palette: announcement.palette,
                phase: phase
            )

            LinearGradient(
                colors: [.black.opacity(0.24), .black.opacity(0.20), .black.opacity(0.64)],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    Text(announcement.nativeGreeting)
                        .font(.system(.title3, design: .rounded, weight: .bold))

                    Spacer(minLength: 12)

                    Text(announcement.localeIdentifier.uppercased())
                        .font(.caption2.monospaced().weight(.bold))
                        .tracking(0.8)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                        .background(.black.opacity(0.24), in: Capsule())
                        .overlay {
                            Capsule().stroke(.white.opacity(0.32), lineWidth: 0.5)
                        }
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text(announcement.nativeName)
                        .font(.system(.title2, design: .rounded, weight: .bold))

                    Text(announcement.detail)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.88))
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let contributor = announcement.contributor {
                    Label {
                        Text("Thank you, \(contributor.name) (\(contributor.handle)), for translating OpenClient into \(announcement.nativeName).")
                            .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: "heart.fill")
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.9))
                }
            }
            .foregroundStyle(.white)
            .padding(20)
        }
        .frame(maxWidth: .infinity, minHeight: 190, alignment: .bottomLeading)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(.white.opacity(0.24), lineWidth: 0.75)
        }
        .shadow(color: clothShadowColor.opacity(0.22), radius: 18, y: 10)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var clothShadowColor: Color {
        announcement.palette.first.map { Color($0) } ?? .black
    }

    private var accessibilityLabel: Text {
        if let contributor = announcement.contributor {
            Text("New language: \(announcement.nativeName). \(announcement.detail) Thank you, \(contributor.name) (\(contributor.handle)), for the translation.")
        } else {
            Text("New language: \(announcement.nativeName). \(announcement.detail)")
        }
    }
}

private struct OpenClientLocalizationContributionCard: View {
    @State private var didCopyPrompt = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "globe.badge.plus")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 46, height: 46)
                    .background(.white.opacity(0.16), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                VStack(alignment: .leading, spacing: 5) {
                    Text("Bring your language next")
                        .font(.headline)

                    Text("Copy a ready-to-use prompt for your AI to translate OpenClient and open a pull request.")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.76))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Text("Clone OpenClient and help me translate it into [YOUR LANGUAGE]...")
                .font(.caption.monospaced())
                .foregroundStyle(.white.opacity(0.72))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(.black.opacity(0.2), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            Button {
                OpenCodeClipboard.copy(OpenClientLocalizationContribution.prompt)
                OpenCodeHaptics.impact(.crisp)
                didCopyPrompt = true
            } label: {
                Label(
                    didCopyPrompt ? LocalizedStringResource("Prompt copied") : LocalizedStringResource("Copy translation prompt"),
                    systemImage: didCopyPrompt ? "checkmark" : "doc.on.doc"
                )
                .font(.headline)
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.white)
            .foregroundStyle(.black)
            .accessibilityIdentifier("new-features.copy-translation-prompt")
        }
        .foregroundStyle(.white)
        .padding(18)
        .background {
            LinearGradient(
                colors: [
                    Color(red: 0.08, green: 0.19, blue: 0.28),
                    Color(red: 0.22, green: 0.10, blue: 0.34),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(.white.opacity(0.14), lineWidth: 0.75)
        }
        .accessibilityElement(children: .contain)
    }
}

struct OpenClientWhatsNewLanguageMark: View {
    var body: some View {
        ZStack {
            Image(systemName: "globe.americas.fill")
                .font(.system(size: 50, weight: .medium))
                .foregroundStyle(.cyan.opacity(0.9))

            Text(verbatim: "A")
                .font(.caption.bold())
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(.purple.gradient, in: Circle())
                .offset(x: -31, y: 19)

            Text(verbatim: "文")
                .font(.caption.bold())
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(.orange.gradient, in: Circle())
                .offset(x: 32, y: -18)
        }
        .frame(width: 94, height: 68)
        .accessibilityHidden(true)
    }
}

private struct OpenClientLocaleCloth: View {
    let palette: [OpenClientReleaseNotes.InternationalizationAnnouncement.PaletteColor]
    let phase: TimeInterval

    var body: some View {
        Canvas(opaque: true, colorMode: .linear, rendersAsynchronously: true) { context, size in
            let rect = CGRect(origin: .zero, size: size)
            let colors = palette.isEmpty ? [Color.blue, Color.purple] : palette.map { Color($0) }
            let horizontalSway = CGFloat(sin(phase * 0.46)) * size.width * 0.16
            let verticalSway = CGFloat(cos(phase * 0.34)) * size.height * 0.16

            context.fill(
                Path(rect),
                with: .linearGradient(
                    Gradient(colors: colors),
                    startPoint: CGPoint(
                        x: -size.width * 0.12 + horizontalSway,
                        y: size.height * 0.12 + verticalSway
                    ),
                    endPoint: CGPoint(
                        x: size.width * 1.12 + horizontalSway,
                        y: size.height * 0.88 - verticalSway
                    )
                )
            )

            drawMovingLightAndShadow(in: &context, size: size)
            drawWeave(in: &context, size: size)
        }
    }

    private func drawMovingLightAndShadow(in context: inout GraphicsContext, size: CGSize) {
        var shadowContext = context
        shadowContext.blendMode = .multiply
        shadowContext.addFilter(.blur(radius: 46))
        var highlightHaloContext = context
        highlightHaloContext.blendMode = .screen
        highlightHaloContext.addFilter(.blur(radius: 40))
        var highlightMidContext = context
        highlightMidContext.blendMode = .screen
        highlightMidContext.addFilter(.blur(radius: 22))
        var highlightContext = context
        highlightContext.blendMode = .screen
        highlightContext.addFilter(.blur(radius: 12))
        let spacing = max(210, size.width * 0.68)
        let cycle = phase.truncatingRemainder(dividingBy: 7.5) / 7.5
        let travel = CGFloat(cycle) * spacing
        let shapePhase = phase * 0.72

        for index in -2...4 {
            let origin = CGFloat(index) * spacing + travel - size.width * 0.34
            let shadow = wavePath(origin: origin + 48, phase: shapePhase, size: size)
            let highlight = wavePath(origin: origin, phase: shapePhase + 0.35, size: size)

            shadowContext.stroke(
                shadow,
                with: .color(.black.opacity(0.22)),
                lineWidth: 216
            )
            highlightHaloContext.stroke(
                highlight,
                with: .color(.white.opacity(0.055)),
                lineWidth: 64
            )
            highlightMidContext.stroke(
                highlight,
                with: .color(.white.opacity(0.12)),
                lineWidth: 28
            )
            highlightContext.stroke(
                highlight,
                with: .color(.white.opacity(0.34)),
                lineWidth: 7
            )
        }
    }

    private func wavePath(origin: CGFloat, phase: TimeInterval, size: CGSize) -> Path {
        var path = Path()

        for sample in 0...32 {
            let progress = CGFloat(sample) / 32
            let y = -size.height * 0.32 + progress * size.height * 1.64
            let bend = sin(Double(progress) * .pi * 2.15 + phase) * 25
            let x = origin + y * 0.58 + CGFloat(bend)

            if sample == 0 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }

        return path
    }

    private func drawWeave(in context: inout GraphicsContext, size: CGSize) {
        var textureContext = context
        textureContext.blendMode = .overlay

        stride(from: -size.height, through: size.width + size.height, by: 7).forEach { x in
            var lightThread = Path()
            lightThread.move(to: CGPoint(x: x, y: 0))
            lightThread.addLine(to: CGPoint(x: x + size.height * 0.28, y: size.height))
            textureContext.stroke(lightThread, with: .color(.white.opacity(0.055)), lineWidth: 0.65)

            var darkThread = Path()
            darkThread.move(to: CGPoint(x: x + 3.5, y: 0))
            darkThread.addLine(to: CGPoint(x: x - size.height * 0.22, y: size.height))
            textureContext.stroke(darkThread, with: .color(.black.opacity(0.045)), lineWidth: 0.55)
        }

        stride(from: CGFloat(2), through: size.height, by: 5).forEach { y in
            var thread = Path()
            thread.move(to: CGPoint(x: 0, y: y))
            thread.addLine(to: CGPoint(x: size.width, y: y))
            textureContext.stroke(thread, with: .color(.white.opacity(0.028)), lineWidth: 0.5)
        }
    }
}

private extension Color {
    init(_ color: OpenClientReleaseNotes.InternationalizationAnnouncement.PaletteColor) {
        self.init(red: color.red, green: color.green, blue: color.blue)
    }
}

import SwiftUI

enum DSButtonKind {
    case primary
    case secondary
    case tertiary
    case destructive
}

struct DSButton: View {
    let title: String
    var icon: String? = nil
    var kind: DSButtonKind = .primary
    var isLoading = false
    var isDisabled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.Spacing.x8) {
                if isLoading {
                    ProgressView()
                        .tint(foreground)
                } else if let icon {
                    Image(systemName: icon)
                }
                Text(title)
                    .font(DS.Typography.bodyMedium)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, DS.Spacing.x12)
            .foregroundStyle(foreground)
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                    .stroke(border, lineWidth: kind == .secondary ? 1 : 0)
            )
        }
        .disabled(isDisabled || isLoading)
        .opacity(isDisabled ? 0.55 : 1)
    }

    private var foreground: Color {
        switch kind {
        case .primary: return .white
        case .secondary: return DS.ColorToken.textPrimary
        case .tertiary: return DS.ColorToken.primary
        case .destructive: return .white
        }
    }

    private var background: Color {
        switch kind {
        case .primary: return DS.ColorToken.primary
        case .secondary: return DS.ColorToken.surface
        case .tertiary: return .clear
        case .destructive: return DS.ColorToken.error
        }
    }

    private var border: Color {
        kind == .secondary ? DS.ColorToken.border : .clear
    }
}

struct DSIconButton: View {
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(DS.ColorToken.textPrimary)
                .frame(width: 40, height: 40)
                .background(DS.ColorToken.surface)
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                        .stroke(DS.ColorToken.border, lineWidth: 1)
                )
        }
    }
}

struct DSSectionHeader: View {
    let title: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        HStack {
            Text(title)
                .font(DS.Typography.heading)
                .foregroundStyle(DS.ColorToken.textPrimary)
            Spacer()
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.ColorToken.primary)
            }
        }
    }
}

struct DSSearchBar: View {
    @Binding var text: String
    var placeholder: String

    var body: some View {
        HStack(spacing: DS.Spacing.x8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(DS.ColorToken.textTertiary)
            TextField(placeholder, text: $text)
                .textInputAutocapitalization(.never)
        }
        .padding(.horizontal, DS.Spacing.x12)
        .padding(.vertical, DS.Spacing.x12)
        .background(DS.ColorToken.surface)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                .stroke(DS.ColorToken.border, lineWidth: 1)
        )
    }
}

struct DSBadge: View {
    let text: String
    var tone: Color = DS.ColorToken.primary

    var body: some View {
        Text(text)
            .font(DS.Typography.micro)
            .foregroundStyle(tone)
            .padding(.horizontal, DS.Spacing.x8)
            .padding(.vertical, DS.Spacing.x4)
            .background(tone.opacity(0.12))
            .clipShape(Capsule())
    }
}

struct DSMeetingCard: View {
    let title: String
    let time: String
    let source: String
    let participants: Int
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.x12) {
            HStack {
                Text(title)
                    .font(DS.Typography.bodyMedium)
                    .foregroundStyle(DS.ColorToken.textPrimary)
                Spacer()
                DSBadge(text: source, tone: DS.ColorToken.aiAccent)
            }

            HStack(spacing: DS.Spacing.x12) {
                Label(time, systemImage: "clock")
                Label("\(participants) participants", systemImage: "person.2")
            }
            .font(DS.Typography.caption)
            .foregroundStyle(DS.ColorToken.textSecondary)

            if let action {
                DSButton(title: "Open", kind: .secondary, action: action)
            }
        }
        .dsCardStyle()
    }
}

struct DSAIInsightCard: View {
    let title: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.x12) {
            HStack {
                Image(systemName: "sparkles")
                    .foregroundStyle(.white)
                Text(title)
                    .font(DS.Typography.bodyMedium)
                    .foregroundStyle(.white)
            }
            Text(message)
                .font(DS.Typography.body)
                .foregroundStyle(Color.white.opacity(0.9))
        }
        .padding(DS.Spacing.x16)
        .background(
            LinearGradient(
                colors: [DS.ColorToken.primary, DS.ColorToken.aiAccent.opacity(0.85)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
        .shadow(color: DS.Shadow.floating.color, radius: DS.Shadow.floating.radius, x: 0, y: 8)
    }
}

struct DSActionItemCard: View {
    let title: String
    let owner: String
    let dueDate: String
    let priority: String
    @Binding var done: Bool

    var body: some View {
        HStack(alignment: .top, spacing: DS.Spacing.x12) {
            Button {
                done.toggle()
            } label: {
                Image(systemName: done ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(done ? DS.ColorToken.success : DS.ColorToken.textTertiary)
                    .font(.system(size: 22))
            }

            VStack(alignment: .leading, spacing: DS.Spacing.x8) {
                Text(title)
                    .font(DS.Typography.bodyMedium)
                    .foregroundStyle(DS.ColorToken.textPrimary)
                    .strikethrough(done)

                HStack(spacing: DS.Spacing.x8) {
                    DSBadge(text: priority, tone: priority == "High" ? DS.ColorToken.error : DS.ColorToken.warning)
                    Text(owner)
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.ColorToken.textSecondary)
                    Text(dueDate)
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.ColorToken.textSecondary)
                }
            }
            Spacer()
        }
        .dsCardStyle()
    }
}

struct DSEmptyState: View {
    let icon: String
    let title: String
    let message: String
    var buttonTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: DS.Spacing.x12) {
            Image(systemName: icon)
                .font(.system(size: 30))
                .foregroundStyle(DS.ColorToken.textTertiary)
            Text(title)
                .font(DS.Typography.heading)
                .foregroundStyle(DS.ColorToken.textPrimary)
            Text(message)
                .font(DS.Typography.body)
                .foregroundStyle(DS.ColorToken.textSecondary)
                .multilineTextAlignment(.center)
            if let buttonTitle, let action {
                DSButton(title: buttonTitle, kind: .secondary, action: action)
            }
        }
        .padding(DS.Spacing.x24)
        .frame(maxWidth: .infinity)
        .dsCardStyle()
    }
}

struct DSToast: View {
    let message: String
    var body: some View {
        Text(message)
            .font(DS.Typography.caption)
            .foregroundStyle(.white)
            .padding(.horizontal, DS.Spacing.x16)
            .padding(.vertical, DS.Spacing.x12)
            .background(DS.ColorToken.textPrimary)
            .clipShape(Capsule())
    }
}

struct DSLoadingSkeleton: View {
    var body: some View {
        RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
            .fill(DS.ColorToken.border.opacity(0.6))
            .frame(height: 110)
            .overlay {
                ProgressView()
            }
    }
}

struct DSAudioPlayerControls: View {
    @Binding var isPlaying: Bool

    var body: some View {
        HStack(spacing: DS.Spacing.x12) {
            DSIconButton(icon: "gobackward.10") {}
            DSButton(title: isPlaying ? "Pause" : "Play", icon: isPlaying ? "pause.fill" : "play.fill", kind: .primary) {
                isPlaying.toggle()
            }
            DSIconButton(icon: "goforward.10") {}
        }
    }
}

struct DSProgressPill: View {
    let title: String
    let value: Double

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.x8) {
            Text(title)
                .font(DS.Typography.caption)
                .foregroundStyle(DS.ColorToken.textSecondary)
            ProgressView(value: value)
                .tint(DS.ColorToken.primary)
        }
        .padding(DS.Spacing.x12)
        .background(DS.ColorToken.primarySoft)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))
    }
}

struct DSAIAssistantInputBar: View {
    @Binding var text: String
    var onSend: () -> Void

    var body: some View {
        HStack(spacing: DS.Spacing.x8) {
            TextField("Ask AI follow-up", text: $text)
                .padding(.horizontal, DS.Spacing.x12)
                .padding(.vertical, DS.Spacing.x12)
                .background(DS.ColorToken.surface)
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                        .stroke(DS.ColorToken.border, lineWidth: 1)
                )
            DSIconButton(icon: "arrow.up") {
                onSend()
            }
        }
    }
}

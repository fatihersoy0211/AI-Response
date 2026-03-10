import SwiftUI

struct OnboardingView: View {
    let onComplete: () -> Void

    @State private var step = 0
    @State private var role = "Product Leader"
    @State private var teamType = "Cross-functional"
    @State private var meetingFrequency = "Daily"

    private let steps: [(title: String, subtitle: String, icon: String)] = [
        (
            "AI-Meeting Assist",
            "Your premium meeting copilot for sharp decisions.",
            "sparkles.rectangle.stack"
        ),
        (
            "Record, Transcribe, Summarize",
            "Capture every conversation and extract reliable next steps automatically.",
            "waveform.and.mic"
        ),
        (
            "Enable Permissions",
            "Microphone, notifications, and calendar unlock real-time assistant workflows.",
            "checklist.checked"
        ),
        (
            "Personalize Workspace",
            "Tune AI output based on your role, team style, and meeting cadence.",
            "person.crop.circle.badge.checkmark"
        )
    ]

    var body: some View {
        ZStack {
            DS.ColorToken.canvas.ignoresSafeArea()

            VStack(spacing: DS.Spacing.x24) {
                Spacer()

                ZStack {
                    Circle()
                        .fill(DS.ColorToken.primarySoft)
                        .frame(width: 220, height: 220)
                    Circle()
                        .fill(DS.ColorToken.aiAccent.opacity(0.14))
                        .frame(width: 160, height: 160)
                    Image(systemName: steps[step].icon)
                        .font(.system(size: 54, weight: .medium))
                        .foregroundStyle(DS.ColorToken.primary)
                }

                VStack(spacing: DS.Spacing.x12) {
                    Text(steps[step].title)
                        .font(DS.Typography.title1)
                        .foregroundStyle(DS.ColorToken.textPrimary)
                        .multilineTextAlignment(.center)

                    Text(steps[step].subtitle)
                        .font(DS.Typography.body)
                        .foregroundStyle(DS.ColorToken.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, DS.Spacing.x24)
                }

                if step == 3 {
                    VStack(spacing: DS.Spacing.x12) {
                        onboardingPicker(title: "Role", selection: $role, values: ["Product Leader", "Founder", "Sales Manager", "Operations"])
                        onboardingPicker(title: "Team Type", selection: $teamType, values: ["Cross-functional", "Engineering", "Sales", "Executive"])
                        onboardingPicker(title: "Meeting Frequency", selection: $meetingFrequency, values: ["Daily", "Weekly", "Mixed"])
                    }
                    .padding(.horizontal, DS.Spacing.x24)
                }

                HStack(spacing: DS.Spacing.x8) {
                    ForEach(0..<steps.count, id: \.self) { index in
                        Capsule()
                            .fill(index == step ? DS.ColorToken.primary : DS.ColorToken.border)
                            .frame(width: index == step ? 22 : 8, height: 8)
                    }
                }

                Spacer()

                VStack(spacing: DS.Spacing.x12) {
                    DSButton(title: step == steps.count - 1 ? "Finish Setup" : "Continue", kind: .primary) {
                        if step == steps.count - 1 {
                            onComplete()
                        } else {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                step += 1
                            }
                        }
                    }

                    DSButton(title: "Skip", kind: .tertiary) {
                        onComplete()
                    }
                }
                .padding(.horizontal, DS.Spacing.x24)
                .padding(.bottom, DS.Spacing.x24)
            }
        }
    }

    private func onboardingPicker(title: String, selection: Binding<String>, values: [String]) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.x8) {
            Text(title)
                .font(DS.Typography.caption)
                .foregroundStyle(DS.ColorToken.textSecondary)
            Picker(title, selection: selection) {
                ForEach(values, id: \.self) { value in
                    Text(value).tag(value)
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity, alignment: .leading)
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
}

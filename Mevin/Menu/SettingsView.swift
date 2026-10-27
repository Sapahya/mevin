import SwiftUI

/// Menu → Settings (PRD V8 Change 3): session check-ins and the privacy screen.
struct SettingsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: SessionCardStyles.screenGap) {
            MevinScreenHeader(title: "Settings") { model.showList() }

            VStack(alignment: .leading, spacing: SessionCardStyles.sectionTitleGap) {
                SectionTitle("Session check-ins")
                Picker("Interval", selection: checkInBinding) {
                    Text("2 hours").tag(2)
                    Text("3 hours").tag(3)
                    Text("Off").tag(0)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                MevinSecondaryText(
                    "After long sessions, Mevin asks if you're still in a role. Unanswered check-ins end the session quietly.",
                    style: .caption
                )
            }
            .mevinRow()

            VStack(alignment: .leading, spacing: SessionCardStyles.sectionTitleGap) {
                SectionTitle("Privacy")
                MevinSecondaryText(
                    "Mevin stores profiles, Terminal commands, session focus times, and short session snapshots (app hosts, not full URLs) in Application Support.",
                    style: .caption
                )
                Button("Clear history") {
                    model.clearSessionHistory()
                }
                .buttonStyle(MevinChipButtonStyle())
                MevinSecondaryText("Clear history also removes role usage stats.", style: .caption)
            }
            .mevinRow()
        }
    }

    private var checkInBinding: Binding<Int> {
        Binding(
            get: { model.checkInIntervalHours },
            set: { model.setCheckInIntervalHours($0) }
        )
    }
}

/// Small medium-weight heading inside a row.
struct SectionTitle: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .sessionCardFont(.headerTitle)
            .foregroundStyle(SessionCardStyles.textPrimary)
    }
}

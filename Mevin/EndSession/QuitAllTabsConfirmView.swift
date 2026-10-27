import AppKit
import SwiftUI

struct QuitAllTabsConfirmView: View {
    @EnvironmentObject private var model: AppModel

    private var quitLabel: String {
        let count = model.quitChecked.count
        return count == 1 ? "Quit 1 app" : "Quit \(count) apps"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SessionCardStyles.screenGap) {
            Text("Quit all?")
                .sessionCardFont(.headerTitle)
                .foregroundStyle(SessionCardStyles.textPrimary)

            MevinSecondaryText("These apps will be asked to quit. Your active session stays as-is.", style: .caption)

            if model.quitRows.isEmpty {
                MevinSecondaryText("Nothing on screen to quit.")
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: SessionCardStyles.listGap) {
                        ForEach(model.quitRows) { row in
                            AppCheckRow(bundleId: row.bundleId, name: row.name, isOn: model.quitBinding(for: row.bundleId))
                        }
                    }
                }
                .frame(maxHeight: SessionCardStyles.listMaxHeight)

                if model.quitChecked.contains(Constants.terminalBundleID) {
                    MevinSecondaryText("Quitting Terminal stops anything running in it.", style: .caption)
                }
            }

            Button(quitLabel) {
                model.confirmQuitAllTabs()
            }
            .buttonStyle(MevinCapsuleButtonStyle(prominent: true))
            .keyboardShortcut(.defaultAction)
            .disabled(model.quitChecked.isEmpty)

            Button("Cancel") {
                model.cancelQuitAllTabs()
            }
            .buttonStyle(MevinCapsuleButtonStyle(prominent: false))
        }
    }
}

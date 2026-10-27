import AppKit
import SwiftUI

/// Start and switch: on-screen apps the next role doesn't need, all unticked
/// (PRD V10 Change 1). Ending: three buttons, no list (Change 4). V8 styling.
struct KeepOpenConfirmView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: SessionCardStyles.screenGap) {
            Text(model.keepOpenTitle)
                .sessionCardFont(.headerTitle)
                .foregroundStyle(SessionCardStyles.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            if model.keepOpenMode == .ending {
                EndRoleButtons()
            } else {
                switchContent
            }
        }
    }

    @ViewBuilder
    private var switchContent: some View {
        let role = model.keepOpenIncomingName

        MevinSecondaryText("These apps aren't part of \(role) and will quit. Tick any you want to keep open.", style: .caption)

        ScrollView {
            VStack(alignment: .leading, spacing: SessionCardStyles.listGap) {
                ForEach(model.switchRows) { row in
                    AppCheckRow(bundleId: row.bundleId, name: row.name, isOn: model.keepOpenBinding(for: row.bundleId))
                }
            }
        }
        .frame(maxHeight: SessionCardStyles.listMaxHeight)

        ForEach(model.lastTimeLines, id: \.self) { line in
            MevinSecondaryText(line, style: .caption)
        }

        Button(model.keepOpenPrimaryLabel) {
            model.confirmKeepOpenPanel()
        }
        .buttonStyle(MevinCapsuleButtonStyle(prominent: true))
        .keyboardShortcut(.defaultAction)

        Button("Cancel") {
            model.cancelKeepOpenPanel()
        }
        .buttonStyle(MevinCapsuleButtonStyle(prominent: false))
    }
}

/// "Ending [Role]": Keep running (Return), Quit [Role]'s apps, Quit all on
/// screen, Cancel (Esc, via AppModel.escapePressed). No list, no checkboxes (PRD V10 Change 4).
private struct EndRoleButtons: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Button(model.keepOpenPrimaryLabel) {
            model.endKeepRunning()
        }
        .buttonStyle(MevinCapsuleButtonStyle(prominent: true))
        .keyboardShortcut(.defaultAction)
        .disabled(model.isEnding)

        Button(model.endQuitRoleAppsLabel) {
            model.endQuitRoleApps()
        }
        .buttonStyle(MevinCapsuleButtonStyle(prominent: false))
        .disabled(model.isEnding)

        Button("Quit all on screen") {
            model.endQuitAllOnScreen()
        }
        .buttonStyle(MevinCapsuleButtonStyle(prominent: false))
        .disabled(model.isEnding)

        Button("Cancel") {
            model.cancelKeepOpenPanel()
        }
        .buttonStyle(MevinCapsuleButtonStyle(prominent: false))
        .disabled(model.isEnding)
    }
}

/// App row with icon and checkbox, on a 10 pt rounded row.
struct AppCheckRow: View {
    @EnvironmentObject private var model: AppModel
    let bundleId: String
    let name: String
    let isOn: Binding<Bool>

    var body: some View {
        Toggle(isOn: isOn) {
            HStack(spacing: SessionCardStyles.headerButtonGap) {
                if let icon = model.appIcon(bundleId: bundleId) {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: SessionCardStyles.appIconSize, height: SessionCardStyles.appIconSize)
                }
                Text(name)
                    .sessionCardFont(.body)
                    .foregroundStyle(SessionCardStyles.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
        }
        .toggleStyle(.checkbox)
        .mevinRow()
    }
}

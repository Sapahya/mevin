import AppKit
import SwiftUI

/// One global list, one promise: nothing on it is ever closed by Mevin.
///
/// It exists because only one session runs at a time, so switching from Day job
/// to Startup would otherwise close a shared app and immediately reopen it,
/// throwing away whatever state it held.
struct KeepOpenView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: SessionCardStyles.screenGap) {
            MevinScreenHeader(title: "Always open") { model.showList() }

            MevinSecondaryText("These apps are never closed when a session ends. A profile can still open them.", style: .caption)

            if model.keepOpenApps.isEmpty {
                MevinSecondaryText("Nothing here yet. Add the apps you always want running, whichever profile you’re in.")
            } else {
                ScrollView {
                    VStack(spacing: SessionCardStyles.listGap) {
                        ForEach(model.keepOpenApps) { app in
                            KeepOpenRow(app: app)
                        }
                    }
                }
                .frame(maxHeight: SessionCardStyles.listMaxHeight)
            }

            Button("Add app") {
                model.browseForKeepOpenApp()
            }
            .buttonStyle(MevinCapsuleButtonStyle(prominent: true))
        }
    }
}

private struct KeepOpenRow: View {
    @EnvironmentObject private var model: AppModel
    let app: InstalledApp

    var body: some View {
        HStack(spacing: SessionCardStyles.headerButtonGap) {
            if let icon = NSWorkspace.shared.icon(forBundleID: app.bundleId) {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: SessionCardStyles.appIconSize, height: SessionCardStyles.appIconSize)
            } else {
                Image(systemName: "app")
                    .foregroundStyle(SessionCardStyles.textPrimary.opacity(SessionCardStyles.secondaryOpacity))
            }

            Text(app.name)
                .sessionCardFont(.body)
                .foregroundStyle(SessionCardStyles.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 4)

            MevinIconButton(symbol: "trash", label: "Remove \(app.name) from Always open") {
                model.removeKeepOpen(bundleId: app.bundleId)
            }
        }
        .mevinRow()
    }
}

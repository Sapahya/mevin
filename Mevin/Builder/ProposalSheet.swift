import AppKit
import SwiftUI

struct ProposalItem: Identifiable, Equatable {
    enum Kind: Equatable {
        case app(bundleId: String, name: String)
        case tab(url: String, title: String)
    }

    enum CaptureSection: Equatable {
        case onScreen
        case otherOpen
        case tabs
    }

    var id = UUID()
    var kind: Kind
    var captureSection: CaptureSection
    var isSelected: Bool

    var label: String {
        switch kind {
        case .app(_, let name): return name
        case .tab(_, let title): return title
        }
    }

    var subtitle: String? {
        switch kind {
        case .app: return nil
        case .tab(let url, _): return ProfileItem.host(of: url) ?? url
        }
    }

    var bundleIdForIcon: String? {
        switch kind {
        case .app(let bundleId, _): return bundleId
        case .tab: return ChromeService.chromeBundleID
        }
    }
}

/// Both "Add what's open" and screenshot reading end here. Nothing is written
/// to a profile without passing through it.
struct ProposalSheet: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            MevinScreenHeader(title: "Add these?") { model.cancelProposal() }

            MevinSecondaryText(model.proposalSubtitle, style: .caption)

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    proposalSection(
                        title: "On your screen",
                        section: .onScreen
                    )
                    proposalSection(
                        title: "Other open apps",
                        section: .otherOpen
                    )
                    proposalSection(
                        title: "Tabs",
                        section: .tabs
                    )
                }
            }
            .frame(maxHeight: SessionCardStyles.listMaxHeight)

            if !model.proposalUnmatched.isEmpty {
                Text("Couldn't find these on your Mac: \(model.proposalUnmatched.joined(separator: ", "))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: SessionCardStyles.headerButtonGap) {
                Button("Cancel") { model.cancelProposal() }
                    .buttonStyle(MevinCapsuleButtonStyle(prominent: false))
                Button("Add selected") { model.confirmProposal() }
                    .buttonStyle(MevinCapsuleButtonStyle(prominent: true))
                    .disabled(!model.proposalItems.contains(where: \.isSelected))
            }
        }
    }

    @ViewBuilder
    private func proposalSection(title: String, section: ProposalItem.CaptureSection) -> some View {
        let indices = model.proposalItems.indices.filter {
            model.proposalItems[$0].captureSection == section
        }
        if !indices.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    MevinSecondaryText(title, style: .caption)
                    Spacer()
                    Button("Select all") {
                        model.selectProposalSection(section, selected: true)
                    }
                    .buttonStyle(MevinChipButtonStyle())
                    Button("Select none") {
                        model.selectProposalSection(section, selected: false)
                    }
                    .buttonStyle(MevinChipButtonStyle())
                }
                ForEach(indices, id: \.self) { index in
                    ProposalRow(item: $model.proposalItems[index])
                }
            }
        }
    }
}

private struct ProposalRow: View {
    @Binding var item: ProposalItem

    var body: some View {
        Button {
            item.isSelected.toggle()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: item.isSelected ? "checkmark.square.fill" : "square")
                    .foregroundStyle(SessionCardStyles.textPrimary.opacity(item.isSelected ? 1 : SessionCardStyles.secondaryOpacity))
                if let bundleId = item.bundleIdForIcon,
                   let icon = NSWorkspace.shared.icon(forBundleID: bundleId) {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: SessionCardStyles.appIconSize, height: SessionCardStyles.appIconSize)
                }
                VStack(alignment: .leading, spacing: 0) {
                    Text(item.label)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if let subtitle = item.subtitle {
                        Text(subtitle)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                Spacer(minLength: 4)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .mevinRow()
    }
}

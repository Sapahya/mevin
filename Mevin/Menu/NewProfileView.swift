import SwiftUI

struct NewProfileView: View {
    @EnvironmentObject private var model: AppModel
    @FocusState private var nameFocused: Bool

    private var trimmedName: String {
        model.newProfileName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canContinue: Bool {
        !trimmedName.isEmpty && !model.nameIsTaken(trimmedName, excluding: nil)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SessionCardStyles.screenGap) {
            MevinScreenHeader(title: "New profile") { model.showList() }

            TextField("Profile name", text: $model.newProfileName)
                .mevinField()
                .focused($nameFocused)
                .onSubmit(submit)
                .onChange(of: model.newProfileName) { _, _ in
                    model.newProfileError = nil
                }

            if let error = model.newProfileError {
                Text(error)
                    .sessionCardFont(.caption)
                    .foregroundStyle(SessionCardStyles.destructive)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                MevinSecondaryText("Name it after the work, not the time. Day job, Startup, Research.", style: .caption)
            }

            ColorSwatchRow(selection: $model.newProfileColor)

            Button("Continue", action: submit)
                .buttonStyle(MevinCapsuleButtonStyle(prominent: true))
                .keyboardShortcut(.defaultAction)
                .disabled(!canContinue)
        }
        .onAppear { nameFocused = true }
    }

    private func submit() {
        guard canContinue else {
            if !trimmedName.isEmpty {
                model.newProfileError = "You already have a profile with this name."
            }
            return
        }
        model.continueFromName()
    }
}

/// The six V8 colours (PRD V8 Change 4). There is no colour picker: the point
/// is that a profile is recognisable at a glance.
struct ColorSwatchRow: View {
    @Binding var selection: ProfileColor

    var body: some View {
        HStack(spacing: SessionCardStyles.swatchGap) {
            ForEach(ProfileColor.allCases) { color in
                Button {
                    selection = color
                } label: {
                    RoundedRectangle(cornerRadius: SessionCardStyles.swatchRadius)
                        .fill(color.color)
                        .frame(height: SessionCardStyles.swatchHeight)
                        .overlay {
                            if selection == color {
                                RoundedRectangle(cornerRadius: SessionCardStyles.swatchRadius)
                                    .strokeBorder(SessionCardStyles.swatchSelectedEdge, lineWidth: SessionCardStyles.swatchSelectedEdgeWidth)
                                Image(systemName: "checkmark")
                                    .font(.system(size: SessionCardStyles.pillIconSize, weight: .bold))
                                    .foregroundStyle(SessionCardStyles.textPrimary)
                            }
                        }
                }
                .buttonStyle(.plain)
                .help(color.displayName)
                .accessibilityLabel(color.displayName)
                .accessibilityAddTraits(selection == color ? .isSelected : [])
            }
        }
    }
}

import SwiftUI

struct TagsSettingsTab: View {
    @Environment(L10n.self) var l10n
    @Environment(AppSettings.self) var appSettings

    var body: some View {
        @Bindable var settings = appSettings
        Form {
            Section {
                ForEach(TagColor.allCases, id: \.self) { tag in
                    HStack(spacing: 10) {
                        Circle()
                            .fill(tag.color)
                            .frame(width: 14, height: 14)

                        TextField(
                            tag.defaultLabel,
                            text: Binding(
                                get: { settings.tagLabels[tag] ?? "" },
                                set: { newValue in
                                    let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                                    if trimmed.isEmpty || trimmed == tag.defaultLabel {
                                        settings.tagLabels[tag] = nil
                                    } else {
                                        settings.tagLabels[tag] = trimmed
                                    }
                                },
                            ),
                        )
                        .textFieldStyle(.roundedBorder)
                    }
                }
            } header: {
                Label(l10n["settings.tags.section"], systemImage: "tag")
            } footer: {
                Text(l10n["settings.tags.footer"])
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

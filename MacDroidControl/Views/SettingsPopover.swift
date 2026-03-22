#if os(macOS)
import SwiftUI

struct SettingsPopover: View {
    @EnvironmentObject var appSettings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // Header
            HStack(spacing: 8) {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text("Settings")
                    .font(.system(size: 13, weight: .semibold))
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)

            Divider()

            // MARK: Appearance
            settingsSection("Appearance") {
                // Theme picker as 3 icon buttons
                HStack(spacing: 6) {
                    ForEach(AppTheme.allCases, id: \.self) { theme in
                        themeButton(theme)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }

            Divider().padding(.leading, 16)

            // MARK: General
            settingsSection("General") {
                settingsRow(
                    icon: "power",
                    iconColor: .green,
                    title: "Launch at Login",
                    subtitle: "Start MacDroidControl when you log in"
                ) {
                    Toggle("", isOn: $appSettings.launchAtLogin)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }
            }

            Divider()

            // Version footer
            HStack {
                Spacer()
                Text("MacDroidControl · v1.0")
                    .font(.system(size: 10))
                    .foregroundStyle(.quaternary)
                Spacer()
            }
            .padding(.vertical, 10)
        }
        .frame(width: 260)
    }

    // MARK: - Theme Button

    private func themeButton(_ theme: AppTheme) -> some View {
        let selected = appSettings.theme == theme
        return Button {
            appSettings.theme = theme
        } label: {
            VStack(spacing: 5) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(selected
                              ? Color.accentColor.opacity(0.15)
                              : Color(.controlBackgroundColor))
                        .frame(width: 64, height: 44)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(
                                    selected ? Color.accentColor : Color(.separatorColor),
                                    lineWidth: selected ? 1.5 : 0.5
                                )
                        )
                    Image(systemName: theme.icon)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(selected ? Color.accentColor : Color.secondary)
                }
                Text(theme.label)
                    .font(.system(size: 10, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? Color.accentColor : Color.secondary)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private func settingsSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.tertiary)
                .textCase(.uppercase)
                .kerning(0.4)
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 4)
            content()
        }
    }

    private func settingsRow<Control: View>(
        icon: String,
        iconColor: Color,
        title: String,
        subtitle: String,
        @ViewBuilder control: () -> Control
    ) -> some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(iconColor.opacity(0.15))
                    .frame(width: 26, height: 26)
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(iconColor)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.callout)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            control()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}
#endif

import SwiftUI

struct SettingsView: View {
    @Bindable var settings: AppSettings

    var body: some View {
        Form {
            Section("Appearance") {
                Picker("Theme", selection: $settings.appearance) {
                    ForEach(Appearance.allCases) { appearance in
                        Text(appearance.label).tag(appearance)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section("Reading") {
                Picker("Body typeface", selection: $settings.face) {
                    ForEach(Theme.BodyFace.allCases) { face in
                        Text(face.label).tag(face)
                    }
                }
                .pickerStyle(.segmented)

                VStack(alignment: .leading, spacing: 4) {
                    Slider(
                        value: $settings.measure,
                        in: Double(Theme.measureRange.lowerBound)...Double(Theme.measureRange.upperBound),
                        step: 20
                    ) {
                        Text("Text width")
                    } minimumValueLabel: {
                        Text("Narrow").font(.caption2).foregroundStyle(.secondary)
                    } maximumValueLabel: {
                        Text("Wide").font(.caption2).foregroundStyle(.secondary)
                    }
                    Text("About \(Theme.charactersPerLine(measure: CGFloat(settings.measure), face: settings.face)) characters a line")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Behaviour") {
                Toggle("Always open documents in Preview", isOn: $settings.alwaysOpenInPreview)
                Text("Off means the app reopens in whichever mode you left it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
    }
}

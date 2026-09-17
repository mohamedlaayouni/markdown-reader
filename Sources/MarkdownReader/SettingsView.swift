import SwiftUI

struct SettingsView: View {
    @Bindable var settings: AppSettings
    var body: some View {
        Form {
            Section("Appearance") {
                Picker("Theme", selection: $settings.appearance) {
                    ForEach(Appearance.allCases) { Text($0.label).tag($0) }
                }.pickerStyle(.segmented)
            }
            Section("Reading") {
                HStack {
                    Text("Preset")
                    Spacer()
                    Menu("Choose…") {
                        ForEach(["Comfort", "Book", "Technical"], id: \.self) { name in
                            Button(name) { settings.preset(name) }
                        }
                    }
                }
                Picker("Body typeface", selection: $settings.face) {
                    ForEach(Theme.BodyFace.allCases) { Text($0.label).tag($0) }
                }.pickerStyle(.segmented)
                Stepper("Text size: \(Int(settings.textSize)) pt", value: $settings.textSize, in: 12...28)
                Slider(value: $settings.measure, in: 480...1040, step: 20) { Text("Text width") }
                Text("About \(Int(Double(Theme.charactersPerLine(measure: CGFloat(settings.measure), face: settings.face)) * Double(Theme.bodySize) / settings.textSize)) characters per line")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Reset Reading Defaults") { settings.preset("Comfort") }
            }
            Section("Behaviour") {
                Toggle("Always open documents in Preview", isOn: $settings.alwaysOpenInPreview)
                Text("When off, keep your last reading or editing mode.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped).frame(width: 480, height: 560)
    }
}

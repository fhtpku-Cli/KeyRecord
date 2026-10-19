import SwiftUI
import Foundation

private final class LicenseResourceAnchor: NSObject {}

enum LicenseNotices {
    static let files = ["LICENSE", "NOTICE", "Argon2-LICENSE.txt"]
    static func content(_ name: String) -> String? {
        guard files.contains(name), let url = Bundle(for: LicenseResourceAnchor.self).url(forResource: name, withExtension: nil),
              let data = try? Data(contentsOf: url), data.count <= 65536 else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

struct LicenseNoticesSection: View {
    let text: NativeText
    @State private var presented = false
    @State private var selected = "LICENSE"
    var body: some View {
        Section {
            Text("KeyRecord · Apache-2.0")
            Button(text("licenses.show")) { presented = true }.accessibilityIdentifier("licenses.show")
        } header: { Text(text("licenses.title")) }
        .sheet(isPresented: $presented) {
            VStack(alignment: .leading) {
                Picker(text("licenses.title"), selection: $selected) {
                    ForEach(LicenseNotices.files, id: \.self) { Text($0).tag($0) }
                }
                ScrollView { Text(LicenseNotices.content(selected) ?? text("licenses.unavailable"))
                    .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                    .accessibilityIdentifier("licenses.content")
                Button(text("licenses.close")) { presented = false }.keyboardShortcut(.cancelAction)
            }.padding().frame(width: 680, height: 520)
        }
    }
}

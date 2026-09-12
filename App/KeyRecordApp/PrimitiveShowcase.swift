import SwiftUI

enum NativeMotion {
    static func apply(to transaction: inout Transaction, reducedMotion: Bool) {
        if reducedMotion {
            transaction.disablesAnimations = true
            transaction.animation = nil
        }
    }
}

struct PrimitiveShowcase: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let fixture: PrimitiveFixture
    let action: () -> Void
    var body: some View {
        let text = NativeText(locale: fixture.locale)
        ScrollView {
            VStack(alignment: .leading, spacing: NativeLayout.group) {
                Text(text("harness.title")).font(.title2)
                Text(text("harness.disclaimer")).fixedSize(horizontal: false, vertical: true)
                ConsentPanel(text: text, action: action)
                CaptureStatus(state: fixture.state, text: text)
                PrimaryAction(state: fixture.state, text: text, action: action)
                Divider()
                AggregateRow(name: fixture.stress ? String(repeating: text("aggregate.sample"), count: 8)
                             : text("aggregate.sample"), text: text)
                SettingsRow(text: text, action: action)
                DestructiveConfirmation(text: text, action: action)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(NativeLayout.page)
        }
        .font(fixture.stress ? .title2 : .body)
        .foregroundStyle(.primary)
        .background(Color(nsColor: .windowBackgroundColor))
        .environment(\.locale, Locale(identifier: fixture.locale))
        .environment(\.colorScheme, fixture.dark ? .dark : .light)
        .environment(\.nativeLargeText, fixture.stress)
        .transaction { transaction in
            NativeMotion.apply(to: &transaction, reducedMotion: reduceMotion || fixture.stress)
        }
    }
}

struct PrimitiveHarness: View {
    @State private var state = PrimitiveState.unstarted
    @State private var locale = "en"
    @State private var dark = false
    var body: some View {
        let text = NativeText(locale: locale)
        VStack(spacing: NativeLayout.group) {
            HStack {
                Picker(text("harness.state"), selection: $state) {
                    ForEach(PrimitiveState.allCases, id: \.self) { Text(text($0.statusKey)).tag($0) }
                }.accessibilityIdentifier("harness.state")
                Picker(text("harness.locale"), selection: $locale) {
                    Text(text("locale.en")).tag("en")
                    Text(text("locale.zh-Hans")).tag("zh-Hans")
                }.accessibilityIdentifier("harness.locale")
                Toggle(text("harness.dark"), isOn: $dark).accessibilityIdentifier("harness.appearance")
            }.padding(.horizontal, NativeLayout.page)
            PrimitiveShowcase(fixture: PrimitiveFixture(state: state, locale: locale, dark: dark, stress: false), action: {})
        }.padding(.top, NativeLayout.group)
    }
}

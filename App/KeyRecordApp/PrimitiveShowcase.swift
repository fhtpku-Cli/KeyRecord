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
    @FocusState private var focusedAction: String?
    let fixture: PrimitiveFixture
    let action: () -> Void
    var body: some View {
        let text = NativeText(locale: fixture.locale)
        ScrollViewReader { proxy in
          ScrollView {
            VStack(alignment: .leading, spacing: NativeLayout.group) {
                Text(text("harness.title")).font(.title2).accessibilityIdentifier("harness.title")
                Text(text("harness.disclaimer")).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("harness.disclaimer")
                ConsentPanel(text: text, action: action)
                CaptureStatus(state: fixture.state, text: text)
                PrimaryAction(state: fixture.state, text: text, action: action)
                Divider()
                AggregateRow(name: fixture.empty ? "" : fixture.stress ? String(repeating: text("aggregate.sample") + " · ", count: 8)
                             : text("aggregate.sample"), text: text)
                SettingsRow(text: text, action: action)
                DestructiveConfirmation(text: text, action: action)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(NativeLayout.page)
          }
          .onChange(of: focusedAction) { _, id in
              if let id { proxy.scrollTo(id, anchor: .center) }
          }
        }
        .environment(\.primitiveFocus, PrimitiveFocusContext($focusedAction))
        .onAppear { focusedAction = PrimitiveFocus.order.first }
        .font(fixture.stress ? .title2 : .body)
        .foregroundStyle(.primary)
        .background(Color(nsColor: .windowBackgroundColor))
        .environment(\.locale, Locale(identifier: fixture.locale))
        .environment(\.colorScheme, fixture.dark ? .dark : .light)
        .environment(\.dynamicTypeSize, fixture.stress ? .accessibility5 : .large)
        .transaction { transaction in
            NativeMotion.apply(to: &transaction, reducedMotion: reduceMotion || fixture.stress)
        }
    }
}

struct PrimitiveHarness: View {
    @State private var state = PrimitiveState.unstarted
    @ObservedObject var selection: HarnessSelection
    @State private var dark = false
    #if DEBUG
    @State private var showsFlowPreview = false
    #endif
    var body: some View {
        let text = NativeText(locale: selection.locale)
        VStack(spacing: NativeLayout.group) {
            HStack {
                Picker(text("harness.state"), selection: $state) {
                    ForEach(PrimitiveState.allCases, id: \.self) { Text(text($0.statusKey)).tag($0) }
                }.accessibilityIdentifier("harness.state")
                Picker(text("harness.locale"), selection: $selection.locale) {
                    Text(text("locale.en")).tag("en")
                    Text(text("locale.zh-Hans")).tag("zh-Hans")
                }.accessibilityIdentifier("harness.locale")
                Toggle(text("harness.dark"), isOn: $dark).accessibilityIdentifier("harness.appearance")
                #if DEBUG
                Button(text("flowpreview.open")) { showsFlowPreview = true }
                    .accessibilityIdentifier("flowpreview.open")
                    .sheet(isPresented: $showsFlowPreview) { FlowPreviewGallery() }
                #endif
            }.padding(.horizontal, NativeLayout.page)
            PrimitiveShowcase(fixture: PrimitiveFixture(state: state, locale: selection.locale, dark: dark, stress: false), action: {})
        }.padding(.top, NativeLayout.group)
            .background(.background)
    }
}

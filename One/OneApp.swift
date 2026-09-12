import SwiftUI

@main
struct OneApp: App {
    @State private var store: AppStore

    init() {
        _store = State(initialValue: AppStore.configured())
    }

    var body: some Scene {
        WindowGroup {
            RootView(store: store)
                .tint(OneTheme.cyan)
                .task { await store.checkBackend() }
        }
    }
}

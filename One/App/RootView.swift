import SwiftUI

struct RootView: View {
    @Bindable var store: AppStore
    var body: some View {
        if !store.isAuthenticated { LoginView(store: store) }
        else if store.requiresOnboarding { OnboardingView(store: store) }
        else if store.role == .caregiver { CaregiverShell(store: store) }
        else { ResidentShell(store: store) }
    }
}

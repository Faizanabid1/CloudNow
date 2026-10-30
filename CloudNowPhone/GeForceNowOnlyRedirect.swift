import SwiftUI

/// GeForce Now Duo is GeForce NOW only: wherever the shared app would ask for a service, or
/// restore a saved Xbox choice, select GeForce NOW instead. The Xbox code stays compiled but
/// is never activated.
struct GeForceNowOnlyRedirect: View {
    @Environment(CloudGamingProviderCoordinator.self) private var providerCoordinator

    var body: some View {
        ProgressView()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black)
            .task {
                providerCoordinator.select(.geForceNow)
            }
    }
}

import SwiftUI

/// Height of the native navigation bar below the status bar.
let navigationBarHeight: CGFloat = 44

/// Back button, page title and AirPlay over the web view (see docs/ios-navigation.md).
struct NavigationBar: View {
    @ObservedObject var navigation: WebNavigation

    var body: some View {
        HStack(spacing: 0) {
            Button(action: navigation.goBack) {
                Image(systemName: "chevron.backward")
                    .font(.system(size: 20, weight: .semibold))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .foregroundStyle(.white)
            .opacity(navigation.showsBack ? 1 : 0)
            .disabled(!navigation.showsBack)
            .accessibilityLabel("Back")
            Spacer(minLength: 0)
            AirPlayButton()
                .frame(width: 44, height: 44)
        }
        .overlay {
            Text(navigation.title)
                .font(.headline)
                .foregroundStyle(.white)
                .lineLimit(1)
                .padding(.horizontal, 52)
        }
        .padding(.horizontal, 8)
        .frame(height: navigationBarHeight)
        .background(.ultraThinMaterial, ignoresSafeAreaEdges: .top)
        .animation(.easeInOut(duration: 0.2), value: navigation.showsBack)
    }
}

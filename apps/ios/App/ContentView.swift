import SwiftUI

struct ContentView: View {
    @StateObject private var navigation = WebNavigation()

    var body: some View {
        // The web view fills the screen and Substrait (viewport-fit=cover) pads for the safe areas
        // itself, so content scrolls under the status bar and the blurred navigation bar. The bar is
        // added to the page's safe area (see ComposeView) so Substrait's fixed header sits below it.
        ZStack(alignment: .top) {
            ComposeView()
                .ignoresSafeArea()
            NavigationBar(navigation: navigation)
        }
        .background(Color(red: 10 / 255, green: 10 / 255, blue: 10 / 255).ignoresSafeArea())
    }
}

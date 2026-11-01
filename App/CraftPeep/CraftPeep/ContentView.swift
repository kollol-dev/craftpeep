import SwiftUI
import WidgetSpec

struct ContentView: View {
    var body: some View {
        Text("Spec version \(WidgetSpecInfo.version)")
            .padding(40)
    }
}

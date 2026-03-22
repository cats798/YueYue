import SwiftUI

extension View {
    func glassBackground() -> some View {
        self.background(
            RoundedRectangle(cornerRadius: 24)
                .fill(.ultraThinMaterial)
                .shadow(radius: 5)
        )
    }
}
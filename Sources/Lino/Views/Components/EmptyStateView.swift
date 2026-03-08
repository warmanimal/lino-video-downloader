import SwiftUI

struct EmptyStateView: View {
    var title: String = "No Videos Yet"
    var subtitle: String = "Press Cmd+Shift+L or click the menu bar icon to add your first video."
    var systemImage: String = "film.stack"

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)

            Text(title)
                .font(.title2)
                .fontWeight(.medium)

            Text(subtitle)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

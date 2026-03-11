import SwiftUI

struct PlatformBadgeView: View {
    let platform: Video.Platform
    var size: CGFloat = 12

    var body: some View {
        Image(systemName: platform.systemImage)
            .font(.system(size: size))
            .foregroundStyle(platformColor)
    }

    private var platformColor: Color {
        switch platform {
        case .youtube: return .red
        case .tiktok: return .primary
        case .instagram: return .purple
        case .twitter: return .blue
        case .pinterest: return .red
        case .suno: return .mint
        case .other: return .secondary
        }
    }
}

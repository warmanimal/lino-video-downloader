import SwiftUI

struct TagChipView: View {
    let name: String
    var isRemovable = false
    var onRemove: (() -> Void)?

    var body: some View {
        HStack(spacing: 3) {
            Text(name)
                .font(.caption)
                .lineLimit(1)

            if isRemovable {
                Button {
                    onRemove?()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Color.accentColor.opacity(0.15))
        .foregroundStyle(Color.accentColor)
        .cornerRadius(12)
    }
}

import SwiftUI

struct LimitBarMark: View {
    var body: some View {
        LimitBarGaugeAsset()
    }
}

struct LimitBarGaugeAsset: View {
    var body: some View {
        if let image = NSImage.limitBarStatusIcon {
            Image(nsImage: image)
                .resizable()
                .renderingMode(.template)
                .scaledToFit()
                .foregroundStyle(.primary)
                .accessibilityLabel("Limit Bar")
        } else {
            Image(systemName: "gauge.with.dots.needle.bottom.50percent")
                .resizable()
                .scaledToFit()
                .foregroundStyle(.primary)
                .accessibilityLabel("Limit Bar")
        }
    }
}

private extension NSImage {
    static var limitBarStatusIcon: NSImage? {
        guard let url = Bundle.main.url(forResource: "StatusIcon", withExtension: "png"),
              let image = NSImage(contentsOf: url) else {
            return nil
        }
        image.isTemplate = true
        return image
    }
}

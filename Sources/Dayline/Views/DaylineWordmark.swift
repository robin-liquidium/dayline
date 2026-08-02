import SwiftUI

/// Fixed Dayline wordmark rendered from Instrument Serif vector outlines.
struct DaylineWordmark: View {
  /// Rendered wordmark height in points.
  var height: CGFloat = 22

  /// Optional plain-text label used by the installed development build header.
  var textOverride: String? = nil

  private static let image: NSImage? = {
    guard
      let url = Bundle.main.url(forResource: "DaylineWordmark", withExtension: "pdf"),
      let image = NSImage(contentsOf: url)
    else {
      return nil
    }
    image.isTemplate = true
    return image
  }()

  var body: some View {
    if let textOverride {
      Text(textOverride)
        .font(.system(size: height * 0.8, weight: .semibold, design: .rounded))
        .foregroundStyle(.primary)
        .accessibilityLabel(textOverride)
    } else if let image = Self.image {
      Image(nsImage: image)
        .resizable()
        .renderingMode(.template)
        .scaledToFit()
        .frame(height: height)
        .foregroundStyle(.primary)
        .accessibilityLabel("Dayline")
    } else {
      Text("Dayline")
    }
  }
}

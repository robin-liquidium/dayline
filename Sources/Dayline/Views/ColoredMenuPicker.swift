import AppKit
import SwiftUI

/// One item in a `ColoredMenuPicker`.
struct ColoredMenuPickerItem: Equatable {
  /// Stable selection tag.
  let tag: String

  /// Menu item title.
  let title: String

  /// Optional SF Symbol shown in the menu.
  let symbolName: String?

  /// Tint for the symbol.
  let color: Color
}

/// AppKit-backed popup picker that renders colored icons inside the menu,
/// which SwiftUI's `Picker` cannot do on macOS.
struct ColoredMenuPicker: NSViewRepresentable {
  @Binding var selection: String
  let items: [ColoredMenuPickerItem]
  var isEnabled = true

  /// Builds the underlying popup button.
  func makeNSView(context: Context) -> NSPopUpButton {
    let button = NSPopUpButton(frame: .zero, pullsDown: false)
    button.target = context.coordinator
    button.action = #selector(Coordinator.selectionChanged(_:))
    button.imagePosition = .imageLeft
    button.setContentHuggingPriority(.defaultHigh, for: .horizontal)
    let widthConstraint = button.widthAnchor.constraint(equalToConstant: 120)
    widthConstraint.isActive = true
    context.coordinator.widthConstraint = widthConstraint
    return button
  }

  /// Rebuilds the menu when items change and reflects the current selection.
  func updateNSView(_ button: NSPopUpButton, context: Context) {
    if context.coordinator.lastItems != items {
      context.coordinator.lastItems = items
      button.removeAllItems()
      for item in items {
        let menuItem = NSMenuItem(title: item.title, action: nil, keyEquivalent: "")
        menuItem.representedObject = item.tag
        if let symbolName = item.symbolName {
          menuItem.image = Self.coloredSymbolImage(symbolName, color: NSColor(item.color))
        }
        button.menu?.addItem(menuItem)
      }
    }
    button.isEnabled = isEnabled
    if button.selectedItem?.representedObject as? String != selection,
       let selectedItem = button.menu?.items.first(where: { $0.representedObject as? String == selection }) {
      button.select(selectedItem)
    }
    Self.fitWidth(to: button, constraint: context.coordinator.widthConstraint)
  }

  /// Sizes the button to the selected item using a real popup cell for exact chrome metrics.
  private static func fitWidth(to button: NSPopUpButton, constraint: NSLayoutConstraint?) {
    let probe = NSPopUpButtonCell(textCell: "", pullsDown: false)
    let menu = NSMenu()
    let item = NSMenuItem(
      title: button.selectedItem?.title ?? "",
      action: nil,
      keyEquivalent: ""
    )
    item.image = button.selectedItem?.image
    menu.addItem(item)
    probe.menu = menu
    let width = ceil(probe.cellSize.width)
    if constraint?.constant != width {
      constraint?.constant = width
    }
  }

  /// Creates the target-action coordinator bridging selection back into SwiftUI.
  func makeCoordinator() -> Coordinator {
    Coordinator(selection: $selection)
  }

  /// Renders an SF Symbol tinted with a color so menus keep it colored.
  private static func coloredSymbolImage(_ name: String, color: NSColor) -> NSImage? {
    guard let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil) else { return nil }
    let tinted = NSImage(size: symbol.size, flipped: false) { rect in
      symbol.draw(in: rect)
      color.setFill()
      rect.fill(using: .sourceAtop)
      return true
    }
    tinted.isTemplate = false
    return tinted
  }

  /// Receives popup selection callbacks.
  final class Coordinator: NSObject {
    @Binding var selection: String
    var lastItems: [ColoredMenuPickerItem] = []
    var widthConstraint: NSLayoutConstraint?

    init(selection: Binding<String>) {
      _selection = selection
    }

    @objc func selectionChanged(_ sender: NSPopUpButton) {
      guard let tag = sender.selectedItem?.representedObject as? String else { return }
      selection = tag
    }
  }
}

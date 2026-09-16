import AppKit

/// AppKit owns the glass, spacing, overflow and window-corner geometry.
@MainActor
final class IDockToolbarController: NSObject, NSToolbarDelegate {
    private let model: PhoneWindowModel
    private var communicationGroup: NSToolbarItemGroup?
    private var utilityGroup: NSToolbarItemGroup?
    private let communication: [PhoneWindowSection] = [.messages, .recents, .contacts, .recordings]
    private let utilities: [PhoneWindowSection] = [.proxy, .sim, .settings]
    private let communicationID = NSToolbarItem.Identifier("iDock.communication")
    private let utilitiesID = NSToolbarItem.Identifier("iDock.utilities")

    init(model: PhoneWindowModel) {
        self.model = model
        super.init()
    }

    func makeToolbar() -> NSToolbar {
        let toolbar = NSToolbar(identifier: "iDock.navigation.v1")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        return toolbar
    }

    func updateSelection() {
        let selected: PhoneWindowSection = model.selection == .dialer
            ? .recents : model.selection
        for (index, section) in communication.enumerated() {
            communicationGroup?.setSelected(section == selected, at: index)
        }
        for (index, section) in utilities.enumerated() {
            utilityGroup?.setSelected(section == selected, at: index)
        }
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.flexibleSpace, communicationID, .flexibleSpace, utilitiesID]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        let item: NSToolbarItemGroup
        if identifier == communicationID {
            item = NSToolbarItemGroup(itemIdentifier: identifier,
                                     titles: communication.map(\.title), selectionMode: .selectAny,
                                     labels: nil, target: self, action: #selector(selectCommunication(_:)))
            communicationGroup = item
        } else if identifier == utilitiesID {
            let images = utilities.map {
                NSImage(systemSymbolName: $0 == .proxy ? "network" : $0.systemImage,
                        accessibilityDescription: $0.title) ?? NSImage()
            }
            item = NSToolbarItemGroup(itemIdentifier: identifier, images: images,
                                     selectionMode: .selectAny, labels: utilities.map(\.title),
                                     target: self, action: #selector(selectUtility(_:)))
            utilityGroup = item
        } else { return nil }
        item.controlRepresentation = .expanded
        let sections = identifier == communicationID ? communication : utilities
        for (subitem, section) in zip(item.subitems, sections) {
            subitem.label = section.title
            subitem.toolTip = section.title
        }
        item.label = IDockBrand.name
        updateSelection()
        return item
    }

    @objc private func selectCommunication(_ sender: NSToolbarItemGroup) {
        guard communication.indices.contains(sender.selectedIndex) else { updateSelection(); return }
        model.activateFromRail(communication[sender.selectedIndex])
        updateSelection()
    }

    @objc private func selectUtility(_ sender: NSToolbarItemGroup) {
        guard utilities.indices.contains(sender.selectedIndex) else { updateSelection(); return }
        model.activateFromRail(utilities[sender.selectedIndex])
        updateSelection()
    }
}

struct StickNavigation {
    enum Mode { case menu, content }

    static func mode(roles: [String], openedWithOptions: Bool) -> Mode {
        // Text inputs can be nested in web lists/tables. Those containers alone
        // do not mean the user is navigating a menu.
        let explicitMenu = roles.contains { ["AXMenu", "AXMenuItem", "AXDialog", "AXSheet"].contains($0) }
        if explicitMenu { return .menu }
        if roles.first == "AXTextArea" { return .content }
        if openedWithOptions { return .menu }
        return .content // Sidebar lists are not popup menus.
    }
}

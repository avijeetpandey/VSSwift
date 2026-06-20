import Foundation

/// Built-in themes mirroring VSCode's defaults, available without external files.
public enum BuiltinThemes {
    public static let darkPlus: Theme = {
        func c(_ hex: String) -> VSSwiftColor { VSSwiftColor(hex: hex)! }
        let colors: [String: VSSwiftColor] = [
            "editor.background": c("#1E1E1E"),
            "editor.foreground": c("#D4D4D4"),
            "editorLineNumber.foreground": c("#858585"),
            "editorCursor.foreground": c("#AEAFAD"),
            "editor.selectionBackground": c("#264F78"),
            "activityBar.background": c("#333333"),
            "activityBar.foreground": c("#FFFFFF"),
            "sideBar.background": c("#252526"),
            "sideBar.foreground": c("#CCCCCC"),
            "statusBar.background": c("#007ACC"),
            "statusBar.foreground": c("#FFFFFF"),
            "tab.activeBackground": c("#1E1E1E"),
            "tab.inactiveBackground": c("#2D2D2D"),
            "panel.background": c("#1E1E1E"),
            "editorWidget.background": c("#252526"),
        ]
        let rules: [Theme.TokenRule] = [
            .init(scopes: ["comment"], style: TokenStyle(foreground: c("#6A9955"), fontStyle: .italic)),
            .init(scopes: ["string"], style: TokenStyle(foreground: c("#CE9178"))),
            .init(scopes: ["constant.numeric"], style: TokenStyle(foreground: c("#B5CEA8"))),
            .init(scopes: ["keyword"], style: TokenStyle(foreground: c("#569CD6"))),
            .init(scopes: ["keyword.control"], style: TokenStyle(foreground: c("#C586C0"))),
            .init(scopes: ["storage"], style: TokenStyle(foreground: c("#569CD6"))),
            .init(scopes: ["storage.type"], style: TokenStyle(foreground: c("#569CD6"))),
            .init(scopes: ["entity.name.type", "support.type"], style: TokenStyle(foreground: c("#4EC9B0"))),
            .init(scopes: ["entity.name.function", "support.function"], style: TokenStyle(foreground: c("#DCDCAA"))),
            .init(scopes: ["variable"], style: TokenStyle(foreground: c("#9CDCFE"))),
            .init(scopes: ["variable.parameter"], style: TokenStyle(foreground: c("#9CDCFE"))),
        ]
        return Theme(name: "Dark+", type: .dark, colors: colors, tokenRules: rules)
    }()

    public static let lightPlus: Theme = {
        func c(_ hex: String) -> VSSwiftColor { VSSwiftColor(hex: hex)! }
        let colors: [String: VSSwiftColor] = [
            "editor.background": c("#FFFFFF"),
            "editor.foreground": c("#000000"),
            "editorLineNumber.foreground": c("#237893"),
            "editor.selectionBackground": c("#ADD6FF"),
            "activityBar.background": c("#2C2C2C"),
            "sideBar.background": c("#F3F3F3"),
            "statusBar.background": c("#007ACC"),
            "statusBar.foreground": c("#FFFFFF"),
        ]
        let rules: [Theme.TokenRule] = [
            .init(scopes: ["comment"], style: TokenStyle(foreground: c("#008000"), fontStyle: .italic)),
            .init(scopes: ["string"], style: TokenStyle(foreground: c("#A31515"))),
            .init(scopes: ["constant.numeric"], style: TokenStyle(foreground: c("#098658"))),
            .init(scopes: ["keyword"], style: TokenStyle(foreground: c("#0000FF"))),
            .init(scopes: ["keyword.control"], style: TokenStyle(foreground: c("#AF00DB"))),
            .init(scopes: ["entity.name.type"], style: TokenStyle(foreground: c("#267F99"))),
            .init(scopes: ["entity.name.function"], style: TokenStyle(foreground: c("#795E26"))),
        ]
        return Theme(name: "Light+", type: .light, colors: colors, tokenRules: rules)
    }()
}

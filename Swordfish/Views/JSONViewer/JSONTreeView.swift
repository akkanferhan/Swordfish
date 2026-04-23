import SwiftUI
import AppKit

// MARK: - Tree view
//
// Built on `List` + `OutlineGroup` which is a SwiftUI wrapper around
// AppKit's `NSOutlineView`. Disclosure triangles, lazy expansion, keyboard
// navigation, and selection are all native and battle-tested — avoids the
// hit-testing issues that the hand-rolled tree ran into.

struct JSONTreeView: View {
    let root: Any

    var body: some View {
        List {
            OutlineGroup([JSONNode(key: nil, value: root, path: "$")],
                         children: \.children) { node in
                JSONNodeRow(node: node)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 1, leading: 0, bottom: 1, trailing: 0))
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(Theme.Surface.codeBg)
    }
}

// MARK: - Node model

struct JSONNode: Identifiable {
    let key: String?
    let value: Any
    let path: String

    var id: String { path }

    var children: [JSONNode]? {
        if let dict = value as? [String: Any], !dict.isEmpty {
            return dict.keys.sorted().map { k in
                JSONNode(key: k, value: dict[k] ?? NSNull(), path: "\(path).\(k)")
            }
        }
        if let arr = value as? [Any], !arr.isEmpty {
            return arr.enumerated().map { idx, item in
                JSONNode(key: "[\(idx)]", value: item, path: "\(path)[\(idx)]")
            }
        }
        return nil
    }
}

// MARK: - Row

private struct JSONNodeRow: View {
    let node: JSONNode

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            label
            Spacer(minLength: 0)
        }
        .font(Typography.code)
        .textSelection(.enabled)
    }

    @ViewBuilder
    private var label: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            if let key = node.key {
                Text("\"\(key)\"")
                    .foregroundStyle(Theme.Syntax.key)
                Text(": ")
                    .foregroundStyle(Theme.Syntax.punct)
            }
            valueText
        }
    }

    @ViewBuilder
    private var valueText: some View {
        if let dict = node.value as? [String: Any] {
            if dict.isEmpty {
                Text("{}").foregroundStyle(Theme.Syntax.punct)
            } else {
                summaryText(open: "{", count: dict.count, singular: "key", plural: "keys", close: "}")
            }
        } else if let arr = node.value as? [Any] {
            if arr.isEmpty {
                Text("[]").foregroundStyle(Theme.Syntax.punct)
            } else {
                summaryText(open: "[", count: arr.count, singular: "item", plural: "items", close: "]")
            }
        } else if let s = node.value as? String {
            Text("\"\(s)\"").foregroundStyle(Theme.Syntax.string)
        } else if let num = node.value as? NSNumber {
            if CFGetTypeID(num) == CFBooleanGetTypeID() {
                Text(num.boolValue ? "true" : "false").foregroundStyle(Theme.Syntax.bool)
            } else {
                Text(Self.formatNumber(num)).foregroundStyle(Theme.Syntax.number)
            }
        } else if node.value is NSNull {
            Text("null").foregroundStyle(Theme.Syntax.null)
        } else {
            Text("\(node.value)").foregroundStyle(Theme.TextColor.primary)
        }
    }

    private func summaryText(open: String, count: Int, singular: String, plural: String, close: String) -> some View {
        Text(open).foregroundColor(Theme.Syntax.punct)
            + Text(" \(count) \(count == 1 ? singular : plural) ").foregroundColor(Theme.TextColor.tertiary)
            + Text(close).foregroundColor(Theme.Syntax.punct)
    }

    private static func formatNumber(_ num: NSNumber) -> String {
        let f = NumberFormatter()
        f.maximumFractionDigits = 15
        f.usesGroupingSeparator = false
        return f.string(from: num) ?? num.stringValue
    }
}

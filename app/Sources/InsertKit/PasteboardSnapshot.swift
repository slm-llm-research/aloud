import AppKit

/// A full copy of a pasteboard's contents (every item, every type), so the user's clipboard can be
/// put back exactly after we paste through it.
public struct PasteboardSnapshot: Sendable {
    let items: [[NSPasteboard.PasteboardType: Data]]

    public static func capture(_ pb: NSPasteboard) -> PasteboardSnapshot {
        let items = (pb.pasteboardItems ?? []).map { item in
            var dict: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) { dict[type] = data }
            }
            return dict
        }
        return PasteboardSnapshot(items: items)
    }

    public func restore(to pb: NSPasteboard) {
        pb.clearContents()
        guard !items.isEmpty else { return }
        let restored = items.map { dict -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in dict { item.setData(data, forType: type) }
            return item
        }
        pb.writeObjects(restored)
    }
}

public enum TransientPasteboardType {
    /// http://nspasteboard.org: clipboard managers skip items marked transient / concealed, so our
    /// dictation never shows up in your clipboard history.
    public static let transient = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")
    public static let concealed = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")
    /// Marks the item as written by Aloud, so we only restore if it's still ours.
    public static let aloud = NSPasteboard.PasteboardType("ai.aloud.dictation")
}

extension NSPasteboard {
    /// Writes `text` as a transient item and returns the resulting change count.
    @discardableResult
    public func writeTransientText(_ text: String) -> Int {
        clearContents()
        let item = NSPasteboardItem()
        item.setString(text, forType: .string)
        item.setData(Data(), forType: TransientPasteboardType.transient)
        item.setData(Data(), forType: TransientPasteboardType.concealed)
        item.setData(Data(), forType: TransientPasteboardType.aloud)
        writeObjects([item])
        return changeCount
    }

    /// True if the pasteboard still holds the item we wrote (nobody copied something new since).
    public func stillHoldsOurItem(changeCount expected: Int) -> Bool {
        changeCount == expected && (types?.contains(TransientPasteboardType.aloud) ?? false)
    }
}

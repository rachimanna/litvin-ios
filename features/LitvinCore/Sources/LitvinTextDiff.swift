import Foundation

public enum LitvinTextDiff {
    public static func describe(before: String, after: String) -> String {
        if before == after { return "Текст не изменился." }
        let old = Array(before)
        let new = Array(after)
        var prefix = 0
        while prefix < min(old.count, new.count), old[prefix] == new[prefix] { prefix += 1 }
        var suffix = 0
        while suffix < min(old.count - prefix, new.count - prefix), old[old.count - suffix - 1] == new[new.count - suffix - 1] { suffix += 1 }
        let removed = String(old[prefix..<(old.count - suffix)])
        let added = String(new[prefix..<(new.count - suffix)])
        return "Убрано:\n\(removed.isEmpty ? "—" : removed)\n\nДобавлено:\n\(added.isEmpty ? "—" : added)"
    }
}

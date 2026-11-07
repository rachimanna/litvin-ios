/// One snapshot supplies both the pages and the selected index. If a refresh
/// removed the tapped item, still open that exact item rather than page zero.
public func litvinGiftPagerSelection<T: Equatable>(items: [T], selected: T) -> ([T], Int) {
    if let index = items.firstIndex(of: selected) { return (items, index) }
    return ([selected], 0)
}

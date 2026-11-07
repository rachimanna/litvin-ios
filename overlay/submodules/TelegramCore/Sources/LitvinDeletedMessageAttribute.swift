import Postbox

/// Ephemeral rendering marker. Never written to Telegram's Postbox.
public final class LitvinDeletedMessageAttribute: MessageAttribute {
    public init() {}
    public init(decoder: PostboxDecoder) {}
    public func encode(_ encoder: PostboxEncoder) {}
}

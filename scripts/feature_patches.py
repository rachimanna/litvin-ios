#!/usr/bin/env python3
"""Verified, idempotent integration edits against the pinned Telegram sources."""
import re
import sys
from pathlib import Path

CORE = 'submodules/TelegramCore'
UI = 'submodules/TelegramUI'
CORE_DEP = '//submodules/LitvinFeatures/LitvinCore:LitvinCore'


def replace(text, old, new, label):
    if new in text:
        return text
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f'{label}: expected one anchor, found {count}: {old[:100]!r}')
    return text.replace(old, new, 1)


def imported(text, module='LitvinCore'):
    line = f'import {module}\n'
    if line in text:
        return text
    return line + text


def dependency(text, dependency=CORE_DEP):
    if f'"{dependency}"' in text:
        return text
    return replace(text, '    deps = [\n', f'    deps = [\n        "{dependency}",\n', 'Bazel dependency')


def patch(root, path, transform):
    file = root / path
    old = file.read_text(encoding='utf-8')
    new = transform(old)
    if new != old:
        file.write_text(new, encoding='utf-8', newline='\n')
    print(f'[features] {path}')


def apply(root):
    # TelegramCore has a second deps list for its tests: target only the first.
    def core_build(t):
        if f'"{CORE_DEP}"' not in t:
            t = t.replace('    deps = [\n', f'    deps = [\n        "{CORE_DEP}",\n', 1)
        return t
    patch(root, f'{CORE}/BUILD', core_build)

    path = f'{CORE}/Sources/State/ManagedLocalInputActivities.swift'
    patch(root, path, lambda t: replace(imported(t),
        'private func requestActivity(postbox: Postbox, network: Network, accountPeerId: PeerId, peerId: PeerId, threadId: Int64?, activity: PeerInputActivity?) -> Signal<Void, NoError> {\n',
        'private func requestActivity(postbox: Postbox, network: Network, accountPeerId: PeerId, peerId: PeerId, threadId: Int64?, activity: PeerInputActivity?) -> Signal<Void, NoError> {\n    if LitvinPolicy.suppressTyping { return .complete() }\n', 'typing gate'))

    path = f'{CORE}/Sources/State/SynchronizePeerReadState.swift'
    patch(root, path, lambda t: replace(imported(t),
        'private func pushPeerReadState(network: Network, postbox: Postbox, stateManager: AccountStateManager, peerId: PeerId, readState: PeerReadState) -> Signal<PeerReadState, PeerReadStateValidationError> {\n',
        'private func pushPeerReadState(network: Network, postbox: Postbox, stateManager: AccountStateManager, peerId: PeerId, readState: PeerReadState) -> Signal<PeerReadState, PeerReadStateValidationError> {\n    if LitvinPolicy.suppressReadReceipts { return .single(readState) }\n', 'read receipt gate'))

    def presence(t):
        t = imported(t)
        t = replace(t, '    private var onlineTimer: SignalKitTimer?\n', '    private var onlineTimer: SignalKitTimer?\n    private var litvinTimer: SignalKitTimer?\n    private var litvinObserver: NSObjectProtocol?\n', 'presence fields')
        t = replace(t, '        self.network = network\n', '''        self.network = network
        self.litvinObserver = NotificationCenter.default.addObserver(forName: LitvinPolicy.changed, object: nil, queue: nil) { [weak self] _ in
            guard let self else { return }
            self.queue.async { [weak self] in
                guard let self else { return }
                self.updatePresence(self.wasOnline)
            }
        }
        let litvinTimer = SignalKitTimer(timeout: 30.0, repeat: true, completion: { [weak self] in
            guard let self else { return }
            let options = LitvinPolicy.options
            if options.ghostScheduleEnabled || options.alibiEnabled { self.updatePresence(self.wasOnline) }
        }, queue: queue)
        self.litvinTimer = litvinTimer
        litvinTimer.start()
''', 'presence schedule')
        t = replace(t, '        self.onlineTimer?.invalidate()\n    }\n', '        self.onlineTimer?.invalidate()\n        self.litvinTimer?.invalidate()\n        if let litvinObserver { NotificationCenter.default.removeObserver(litvinObserver) }\n    }\n', 'presence cleanup')
        t = replace(t, '                strongSelf.updatePresence(true)\n', '                strongSelf.updatePresence(strongSelf.wasOnline)\n', 'scheduled presence expiry')
        return replace(t, '    private func updatePresence(_ isOnline: Bool) {\n', '    private func updatePresence(_ requestedOnline: Bool) {\n        let isOnline = LitvinPolicy.onlineStatus(requested: requestedOnline)\n', 'presence policy')
    patch(root, f'{CORE}/Sources/State/ManagedAccountPresence.swift', presence)

    def ads(t):
        t = imported(t)
        t = replace(t, '        if messageId == nil {\n            self.state.set(CachedState.getCached', '        if messageId == nil && !LitvinPolicy.options.antiAds {\n            self.state.set(CachedState.getCached', 'cached ads')
        return replace(t, '    func activate() {\n', '    func activate() {\n        if LitvinPolicy.options.antiAds {\n            self.state.set(.single(State(interPostInterval: nil, messages: [])))\n            return\n        }\n', 'ads request')
    patch(root, f'{CORE}/Sources/TelegramEngine/Messages/AdMessages.swift', ads)

    def state(t):
        t = imported(t)
        t = replace(t, '            case let .AddMessages(messages, location):\n                if case .UpperHistoryBlock = location {', '            case let .AddMessages(messages, location):\n                for litvinMessage in messages { litvinCaptureStoreMessage(accountPeerId: accountPeerId, transaction: transaction, message: litvinMessage) }\n                if case .UpperHistoryBlock = location {', 'incoming archive')
        t = replace(t, '            case let .DeleteMessagesWithGlobalIds(ids):\n', '            case let .DeleteMessagesWithGlobalIds(ids):\n                LitvinArchive.forAccount(accountPeerId.toInt64()).markDeleted(peer: nil, namespace: Namespaces.Message.Cloud, ids: ids)\n', 'global deletions')
        t = replace(t, '            case let .DeleteMessages(ids):\n                _internal_deleteMessages', '''            case let .DeleteMessages(ids):
                for id in ids where id.namespace == Namespaces.Message.Cloud {
                    if let previous = transaction.getMessage(id) { litvinCaptureMessage(accountPeerId: accountPeerId, message: previous) }
                    LitvinArchive.forAccount(accountPeerId.toInt64()).markDeleted(peer: id.peerId.toInt64(), namespace: id.namespace, ids: [id.id])
                }
                _internal_deleteMessages''', 'peer deletions')
        return replace(t, '                transaction.updateMessage(id, update: { previousMessage in\n                    var updatedFlags = message.flags', '                transaction.updateMessage(id, update: { previousMessage in\n                    litvinCaptureMessage(accountPeerId: accountPeerId, message: previousMessage, beforeEdit: true)\n                    litvinCaptureStoreMessage(accountPeerId: accountPeerId, transaction: transaction, message: message)\n                    var updatedFlags = message.flags', 'edit history')
    patch(root, f'{CORE}/Sources/State/AccountStateManagementUtils.swift', state)
    patch(root, f'{CORE}/Sources/State/AccountStateManagementUtils.swift', lambda t: replace(t,
        '            case let .MergePeerPresences(statuses, explicit):\n', '''            case let .MergePeerPresences(statuses, explicit):
                if LitvinPolicy.options.contactProfile {
                    for (peerId, update) in statuses where peerId != accountPeerId {
                        switch update.status {
                        case .userStatusOnline: LitvinArchive.forAccount(accountPeerId.toInt64()).observePresence(peer: peerId.toInt64(), online: true)
                        case .userStatusOffline: LitvinArchive.forAccount(accountPeerId.toInt64()).observePresence(peer: peerId.toInt64(), online: false)
                        default: break
                        }
                    }
                }
''', 'observed presence history'))

    def consume(t):
        t = imported(t)
        return replace(t, 'func _internal_markMessageContentAsConsumedInteractively(postbox: Postbox, messageId: MessageId) -> Signal<Void, NoError> {\n', 'func _internal_markMessageContentAsConsumedInteractively(postbox: Postbox, messageId: MessageId) -> Signal<Void, NoError> {\n    if LitvinPolicy.options.infiniteSelfDestruct || LitvinPolicy.suppressReadReceipts { return .complete() }\n', 'viewed receipt')
    patch(root, f'{CORE}/Sources/TelegramEngine/Messages/MarkMessageContentAsConsumedInteractively.swift', consume)

    # Only the chat display is changed: server-side peer protection flags stay intact.
    def screenshot(t):
        t = imported(t)
        old = 'let isSecret = self.chatPresentationInterfaceState.copyProtectionEnabled || self.chatLocation.peerId?.namespace == Namespaces.Peer.SecretChat || self.chatLocation.peerId?.isVerificationCodes == true'
        return replace(t, old, 'let isSecret = (!LitvinPolicy.options.screenshotBypass && self.chatPresentationInterfaceState.copyProtectionEnabled) || self.chatLocation.peerId?.namespace == Namespaces.Peer.SecretChat || self.chatLocation.peerId?.isVerificationCodes == true', 'capture policy')
    patch(root, f'{UI}/Sources/ChatControllerNode.swift', screenshot)

    def history(t):
        t = imported(t)
        return replace(t, '                        let message = view.entries[i].message\n', '                        let message = view.entries[i].message\n                        litvinCaptureMessage(accountPeerId: context.account.peerId, message: message)\n', 'loaded history archive')
    patch(root, f'{UI}/Sources/ChatHistoryListNode.swift', history)

    def ui_build(t):
        if f'"{CORE_DEP}"' not in t:
            t = t.replace('    deps = [\n', f'    deps = [\n        "{CORE_DEP}",\n', 1)
        return t
    patch(root, f'{UI}/BUILD', ui_build)

    def ui_features_build(t):
        dep = '//submodules/LitvinFeatures/LitvinSettings:LitvinSettings'
        if f'"{dep}"' not in t:
            t = t.replace('    deps = [\n', f'    deps = [\n        "{dep}",\n', 1)
        return t
    patch(root, f'{UI}/BUILD', ui_features_build)
    patch(root, f'{UI}/Sources/ApplicationContext.swift', lambda t: replace(imported(t, 'LitvinSettings'), '        self.context = context\n', '        self.context = context\n        LitvinTools.initialize(context: context)\n', 'feature lifecycle'))

    def menus(t):
        marker = '// Litvin: message tools'
        if marker in t:
            return t
        t = imported(imported(t), 'LitvinSettings')
        old = 'let isCopyProtected = chatPresentationInterfaceState.copyProtectionEnabled || message.isCopyProtected()'
        if t.count(old) != 2:
            raise RuntimeError('copy menu anchors changed')
        t = t.replace(old, 'let isCopyProtected = !LitvinPolicy.options.forwardBypass && (chatPresentationInterfaceState.copyProtectionEnabled || message.isCopyProtected())')
        t = t.replace('!message.isCopyProtected()', '(!message.isCopyProtected() || LitvinPolicy.options.forwardBypass)')
        t = t.replace('if message.isCopyProtected() || message.containsSecretMedia {', 'if (message.isCopyProtected() && !LitvinPolicy.options.forwardBypass) || message.containsSecretMedia {')
        t = replace(t, '        func isPeerCopyProtected(_ peerId: EnginePeer.Id) -> Bool? {\n', '        func isPeerCopyProtected(_ peerId: EnginePeer.Id) -> Bool? {\n            if LitvinPolicy.options.forwardBypass { return false }\n', 'peer forward controls')
        t = replace(t, '        var actions: [ContextMenuItem] = []\n\n        if isSharedMediaPolls', '''        var actions: [ContextMenuItem] = []
        // Litvin: message tools
        if message.id.namespace == Namespaces.Message.Cloud {
            if LitvinPolicy.options.messageNotes {
                actions.append(.action(ContextMenuActionItem(text: "Litvin: личная заметка", icon: { _ in nil }, action: { _, done in
                    done(.default)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        LitvinTools.editNote(account: context.account.peerId.toInt64(), peer: message.id.peerId.toInt64(), namespace: message.id.namespace, message: message.id.id)
                    }
                })))
            }
            if LitvinPolicy.options.saveEditHistory {
                actions.append(.action(ContextMenuActionItem(text: "Litvin: история правок", icon: { _ in nil }, action: { _, done in
                    done(.default)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        LitvinTools.showMessageHistory(account: context.account.peerId.toInt64(), peer: message.id.peerId.toInt64(), namespace: message.id.namespace, message: message.id.id)
                    }
                })))
            }
        }

        if isSharedMediaPolls''', 'message tools')
        return t
    patch(root, f'{UI}/Sources/ChatInterfaceStateContextMenus.swift', menus)
    patch(root, f'{UI}/Sources/ChatInterfaceStateContextMenus.swift', lambda t: t if 'text: "Litvin: экспорт без метаданных"' in t else replace(t,
        '        // Litvin: message tools\n', '''        // Litvin: message tools
        if message.id.namespace == Namespaces.Message.Cloud && message.media.contains(where: { $0 is TelegramMediaImage || $0 is TelegramMediaFile }) {
            actions.append(.action(ContextMenuActionItem(text: "Litvin: экспорт без метаданных", icon: { _ in nil }, action: { _, done in
                done(.default)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { LitvinTools.exportCleanMedia(context: context, message: EngineMessage(message)) }
            })))
        }
''', 'media scrub entry'))
    patch(root, f'{UI}/Sources/ChatInterfaceStateContextMenus.swift', lambda t: t if 'text: "Litvin: скрыть / показать этот чат"' in t else replace(t,
        '        // Litvin: message tools\n', '''        // Litvin: message tools
        if message.id.namespace == Namespaces.Message.Cloud {
            actions.append(.action(ContextMenuActionItem(text: "Litvin: скрыть / показать этот чат", icon: { _ in nil }, action: { _, done in
                done(.default)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { LitvinTools.toggleHiddenChat(account: context.account.peerId.toInt64(), peer: message.id.peerId.toInt64()) }
            })))
        }
''', 'hide this chat entry'))
    patch(root, f'{UI}/Sources/ChatController.swift', lambda t: replace(imported(t, 'LitvinSettings'),
        '    override public func viewWillAppear(_ animated: Bool) {\n        super.viewWillAppear(animated)\n',
        '    override public func viewWillAppear(_ animated: Bool) {\n        super.viewWillAppear(animated)\n        if let peerId = self.chatLocation.peerId { LitvinTools.protectChatView(account: self.context.account.peerId.toInt64(), peer: peerId.toInt64(), view: self.view) }\n', 'hidden chat cover'))

    def gifts(t):
        t = imported(t, 'LitvinSettings')
        return replace(t, '                var actions = actions\n', '''                var actions = actions
                if case let .list(litvinItems) = actions.content {
                    var litvinItems = litvinItems
                    litvinItems.append(.action(ContextMenuActionItem(text: "Litvin: локальный подарок", icon: { _ in nil }, action: { [weak self] _, done in
                        done(.default)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            guard let self else { return }
                            LitvinTools.showFakeGift(in: self.view)
                        }
                    })))
                    actions.content = .list(litvinItems)
                }
''', 'local gift entry')
    patch(root, f'{UI}/Sources/Chat/ChatControllerOpenMessageContextMenu.swift', gifts)

    def forward(t):
        t = imported(t)
        return replace(t, '            case let .forward(sourceId, threadId, grouping, forwardAttributes, _):\n', '''            case let .forward(sourceId, threadId, grouping, forwardAttributes, _):
                if let sourceMessage = transaction.getMessage(sourceId), sourceId.namespace == Namespaces.Message.Cloud,
                   !sourceMessage.containsSecretMedia,
                   !sourceMessage.media.contains(where: { $0 is TelegramMediaAction || $0 is TelegramMediaExpiredContent }),
                   LitvinPolicy.options.forwardScrub || (LitvinPolicy.options.forwardBypass && (sourceMessage.isCopyProtected() || transaction.getPeer(sourceId.peerId)?.isCopyProtectionEnabled == true || (transaction.getPeerCachedData(peerId: sourceId.peerId) as? CachedUserData)?.flags.contains(.copyProtectionEnabled) == true || (transaction.getPeerCachedData(peerId: sourceId.peerId) as? CachedUserData)?.flags.contains(.myCopyProtectionEnabled) == true)) {
                    let copyAttributes = sourceMessage.attributes.filter { $0 is TextEntitiesMessageAttribute }
                    let reference = sourceMessage.media.first.map { AnyMediaReference.standalone(media: $0) }
                    updatedMessages.append((transformedMedia, .message(text: sourceMessage.text, attributes: copyAttributes, inlineStickers: [:], mediaReference: reference, threadId: threadId, replyToMessageId: nil, replyToStoryId: nil, localGroupingKey: forwardGroupingKey(grouping: grouping, sourceGroupingKey: sourceMessage.groupingKey, generatedKeys: &localGroupingKeyBySourceKey), correlationId: nil, bubbleUpEmojiOrStickersets: [])))
                    continue outer
                }
''', 'forward as copy')
    patch(root, f'{CORE}/Sources/PendingMessages/EnqueueMessage.swift', forward)

    def gallery(t):
        t = imported(t)
        t = replace(t, '            if let (beginTime, timeout, isOutgoing) = self.beginTimeAndTimeout {', '            if let (beginTime, timeout, isOutgoing) = self.beginTimeAndTimeout, !LitvinPolicy.options.infiniteSelfDestruct {', 'gallery timeout')
        return replace(t, '                        if self.currentNodeMessageIsViewOnce || (duration < 30.0 && !self.currentMessageIsDismissed) {', '                        if LitvinPolicy.options.infiniteSelfDestruct || self.currentNodeMessageIsViewOnce || (duration < 30.0 && !self.currentMessageIsDismissed) {', 'gallery replay')
    patch(root, 'submodules/GalleryUI/Sources/SecretMediaPreviewController.swift', gallery)
    patch(root, 'submodules/GalleryUI/BUILD', ui_build)

    def hidden_entries(t):
        t = imported(t)
        t = replace(t, '    loop: for entry in view.items {\n', '    loop: for entry in view.items {\n        if LitvinProtection.shouldHide(account: accountPeerId.toInt64(), peer: entry.renderedPeer.peerId.toInt64()) { continue }\n', 'hidden chat entries')
        return replace(t, '        for contact in contacts {\n', '        for contact in contacts {\n            if LitvinProtection.shouldHide(account: accountPeerId.toInt64(), peer: contact.peer.id.toInt64()) { continue }\n', 'hidden contacts')
    patch(root, 'submodules/ChatListUI/Sources/Node/ChatListNodeEntries.swift', hidden_entries)

    def hidden_node(t):
        t = imported(t)
        t = replace(t, 'public struct ChatListNodeState: Equatable {\n', 'public struct ChatListNodeState: Equatable {\n    var litvinRevision = 0\n', 'chat list revision')
        t = replace(t, '    public static func ==(lhs: ChatListNodeState, rhs: ChatListNodeState) -> Bool {\n', '    public static func ==(lhs: ChatListNodeState, rhs: ChatListNodeState) -> Bool {\n        if lhs.litvinRevision != rhs.litvinRevision { return false }\n', 'chat list revision comparison')
        t = replace(t, '    private let statePromise: ValuePromise<ChatListNodeState>\n', '    private let statePromise: ValuePromise<ChatListNodeState>\n    private var litvinObserver: NSObjectProtocol?\n', 'chat list observer')
        t = replace(t, '        super.init()\n        \n        if case .internal', '''        super.init()
        self.litvinObserver = NotificationCenter.default.addObserver(forName: LitvinPolicy.changed, object: nil, queue: .main) { [weak self] _ in
            self?.updateState { state in var state = state; state.litvinRevision &+= 1; return state }
        }
        
        if case .internal''', 'chat list refresh')
        return replace(t, '    deinit {\n        self.chatListDisposable.dispose()', '    deinit {\n        if let litvinObserver { NotificationCenter.default.removeObserver(litvinObserver) }\n        self.chatListDisposable.dispose()', 'chat list cleanup')
    patch(root, 'submodules/ChatListUI/Sources/Node/ChatListNode.swift', hidden_node)
    patch(root, 'submodules/ChatListUI/BUILD', ui_build)

    def message_search(t):
        t = imported(t)
        return replace(t, '            return _internal_searchMessages(account: self.account, location: location, query: query, state: state, centerId: centerId, limit: limit)\n', '''            let litvinAccount = self.account.peerId.toInt64()
            return _internal_searchMessages(account: self.account, location: location, query: query, state: state, centerId: centerId, limit: limit)
            |> map { result, state in
                let messages = result.messages.filter { !LitvinProtection.shouldHide(account: litvinAccount, peer: $0.id.peerId.toInt64()) }
                let count = messages.count == result.messages.count ? result.totalCount : max(Int32(messages.count), result.totalCount - Int32(result.messages.count - messages.count))
                let filtered = SearchMessagesResult(messages: messages, readStates: result.readStates, threadInfo: result.threadInfo, totalCount: count, completed: result.completed)
                return (filtered, state)
            }
''', 'hidden message search')
    patch(root, f'{CORE}/Sources/TelegramEngine/Messages/TelegramEngineMessages.swift', message_search)

    def peer_search(t):
        t = imported(t)
        t = replace(t, '            return _internal_searchPeers(accountPeerId: self.account.peerId, postbox: self.account.postbox, network: self.account.network, query: query, scope: scope)\n', '''            let litvinAccount = self.account.peerId.toInt64()
            return _internal_searchPeers(accountPeerId: self.account.peerId, postbox: self.account.postbox, network: self.account.network, query: query, scope: scope)
            |> map { first, second in
                return (first.filter { !LitvinProtection.shouldHide(account: litvinAccount, peer: $0.peer.id.toInt64()) }, second.filter { !LitvinProtection.shouldHide(account: litvinAccount, peer: $0.peer.id.toInt64()) })
            }
''', 'hidden remote peers')
        return replace(t, '            return self.account.postbox.searchPeers(query: query, predicate: predicate)\n            |> map { peers in\n', '''            let litvinAccount = self.account.peerId.toInt64()
            return self.account.postbox.searchPeers(query: query, predicate: predicate)
            |> map { peers in
                let peers = peers.filter { !LitvinProtection.shouldHide(account: litvinAccount, peer: $0.peerId.toInt64()) }
''', 'hidden local peers')
    patch(root, f'{CORE}/Sources/TelegramEngine/Contacts/TelegramEngineContacts.swift', peer_search)

    patch(root, f'{UI}/Sources/ApplicationContext.swift', lambda t: replace(imported(t), '                            if !isMuted {\n', '                            if !isMuted && !LitvinProtection.shouldHide(account: context.account.peerId.toInt64(), peer: firstMessage.id.peerId.toInt64()) {\n', 'hidden in-app notifications'))

    def notification(t):
        t = imported(t)
        anchor = '                    #if DEBUG\n                    if let locKey = payloadJson["loc-key"] as? String, locKey == "CONF_CALL_REQUEST" {'
        return replace(t, anchor, '''                    if let peerId, LitvinProtection.shouldRedactNotification(account: accountPeerId.toInt64(), peer: peerId.toInt64(), group: appGroupName) {
                        updateCurrentContent(NotificationContent(isLockedMessage: "Новое сообщение"))
                        completed()
                        return
                    }

''' + anchor, 'hidden push previews')
    patch(root, 'Telegram/NotificationService/Sources/NotificationService.swift', notification)
    patch(root, 'Telegram/NotificationService/BUILD', ui_build)


if __name__ == '__main__':
    if len(sys.argv) != 2:
        raise SystemExit('usage: feature_patches.py <telegram-ios-root>')
    apply(Path(sys.argv[1]))

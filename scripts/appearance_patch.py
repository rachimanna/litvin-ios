#!/usr/bin/env python3
"""Verified, idempotent integration edits against the pinned Telegram sources."""
import sys
from pathlib import Path

CORE = 'submodules/TelegramCore'
UI = 'submodules/TelegramUI'


def replace(text, old, new, label):
    if new in text:
        return text
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f'{label}: expected one anchor, found {count}: {old[:100]!r}')
    return text.replace(old, new, 1)


def imported(text, module='TelegramCore'):
    line = f'import {module}\n'
    if line in text:
        return text
    return line + text



def patch(root, path, transform):
    file = root / path
    old = file.read_text(encoding='utf-8')
    new = transform(old)
    if new != old:
        file.write_text(new, encoding='utf-8', newline='\n')
    print(f'[features] {path}')


def apply(root):
    patch(root, "submodules/Postbox/BUILD", lambda t: replace(t, '        "//submodules/LegacyMediaPickerUI",\n', '        "//submodules/LegacyMediaPickerUI",\n        "//submodules/LitvinFeatures/LitvinSettings",\n', "Litvin settings Postbox visibility"))
    # Local appearance is confined to presentation. Never modify EnginePeer,
    # StarsContext balances, account credentials or server entitlement checks.
    peer_info = f'{UI}/Components/PeerInfo/PeerInfoScreen'

    def appearance_header(t):
        t = imported(t)
        t = replace(t, 'peer.isPremium && !premiumConfiguration.isPremiumDisabled && (peer.id != self.context.account.peerId || self.isSettings || self.isMyProfile)',
            'LitvinAppearance.premium(account: self.context.account.peerId.toInt64(), peer: peer.id.toInt64(), original: peer.isPremium) && (!premiumConfiguration.isPremiumDisabled || LitvinAppearance.state(account: self.context.account.peerId.toInt64()).premium) && (peer.id != self.context.account.peerId || self.isSettings || self.isMyProfile)', 'local premium badge')
        t = replace(t, '            isPremium = peer.isPremium\n', '            isPremium = LitvinAppearance.premium(account: self.context.account.peerId.toInt64(), peer: peer.id.toInt64(), original: peer.isPremium)\n', 'local premium title spacing')
        return replace(t, '                var subtitle = formatPhoneNumber(context: self.context, number: user.phone ?? "")',
            '                var subtitle = LitvinAppearance.phone(account: self.context.account.peerId.toInt64(), peer: user.id.toInt64(), original: formatPhoneNumber(context: self.context, number: user.phone ?? ""))', 'local settings phone')
    patch(root, peer_info + '/Sources/PeerInfoHeaderNode.swift', appearance_header)

    def appearance_profile(t):
        t = imported(imported(t), 'LitvinSettings')
        t = replace(t, '        if let phone = user.phone {\n            let formattedPhone = formatPhoneNumber(context: context, number: phone)',
            '        if let phone = user.phone {\n            let formattedPhone = LitvinAppearance.phone(account: context.account.peerId.toInt64(), peer: user.id.toInt64(), original: formatPhoneNumber(context: context, number: phone))', 'local profile phone')
        return replace(t, '        let ItemVerification = 9004\n', '''        let ItemVerification = 9004
        items[.peerInfoTrailing]!.append(PeerInfoScreenActionItem(id: 19001, text: "Локальные подарки", action: {
            LitvinAppearanceTools.showGifts(context: context, peer: user.id.toInt64())
        }))
''', 'profile gift manager')
    patch(root, peer_info + '/Sources/PeerInfoProfileItems.swift', appearance_profile)

    def appearance_phone_menu(t):
        t = imported(t, 'LitvinSettings')
        return replace(t, '            var items: [ContextMenuItem] = []\n', '''            var items: [ContextMenuItem] = []
            if strongSelf.peerId == strongSelf.context.account.peerId {
                items.append(.action(ContextMenuActionItem(text: "Изменить локальный номер", icon: { _ in nil }, action: { _, done in
                    done(.default)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        LitvinAppearanceTools.editPhone(account: strongSelf.context.account.peerId.toInt64())
                    }
                })))
            }
''', 'phone local edit action')
    patch(root, peer_info + '/Sources/PeerInfoScreenOpenPhone.swift', appearance_phone_menu)
    patch(root, peer_info + '/Sources/PeerInfoScreenOpenPhone.swift', lambda t: replace(t,
        'if gesture == nil, formattedPhoneNumber.hasPrefix("+888") {',
        'if gesture == nil, formattedPhoneNumber.hasPrefix("+888"), self.peerId != self.context.account.peerId {', 'own collectible phone local menu'))

    def appearance_phone_settings(t):
        t = imported(t, 'LitvinSettings')
        old = '''                let introController = PrivacyIntroController(context: self.context, mode: .changePhoneNumber(phoneNumber), proceedAction: { [weak self] in
                    if let strongSelf = self, let navigationController = strongSelf.controller?.navigationController as? NavigationController {
                        navigationController.replaceTopController(ChangePhoneNumberController(context: strongSelf.context), animated: true)
                    }
                })
                push(introController)'''
        return replace(t, old, '''                LitvinAppearanceTools.phoneMenu(account: self.context.account.peerId.toInt64(), changeReal: { [weak self] in
                    guard let self else { return }
                    let introController = PrivacyIntroController(context: self.context, mode: .changePhoneNumber(phoneNumber), proceedAction: { [weak self] in
                        if let strongSelf = self, let navigationController = strongSelf.controller?.navigationController as? NavigationController {
                            navigationController.replaceTopController(ChangePhoneNumberController(context: strongSelf.context), animated: true)
                        }
                    })
                    self.controller?.push(introController)
                })''', 'settings phone choice')
    patch(root, peer_info + '/Sources/PeerInfoScreenSettingsActions.swift', appearance_phone_settings)

    def appearance_settings(t):
        t = imported(t)
        t = replace(t, 'label: .text(user.phone.flatMap({ formatPhoneNumber(context: context, number: $0) }) ?? "")',
            'label: .text(LitvinAppearance.phone(account: context.account.peerId.toInt64(), peer: user.id.toInt64(), original: user.phone.flatMap({ formatPhoneNumber(context: context, number: $0) }) ?? ""))', 'settings phone label')
        t = replace(t, '    if let starsState = data.starsState {\n        if !isPremiumDisabled || abs(starsState.balance.value) > 0 {', '    if let starsState = data.starsState {\n        let litvinBalance = litvinDisplayStars(account: context.account.peerId.toInt64(), original: starsState.balance)\n        if !isPremiumDisabled || abs(litvinBalance.value) > 0 {', 'settings stars display')
        t = t.replace('abs(starsState.balance.value)', 'abs(litvinBalance.value)')
        return replace(t, 'formatStarsAmountText(starsState.balance, dateTimeFormat: presentationData.dateTimeFormat)', 'formatStarsAmountText(litvinBalance, dateTimeFormat: presentationData.dateTimeFormat)', 'settings stars amount')
    patch(root, peer_info + '/Sources/PeerInfoSettingsItems.swift', appearance_settings)

    def appearance_refresh(t):
        t = imported(t)
        t = replace(t, '    var canAttachVideo: Bool?\n', '    private var litvinAppearanceObserver: NSObjectProtocol?\n    var canAttachVideo: Bool?\n', 'appearance observer field')
        t = replace(t, '        self.selectAddMemberDisposable.dispose()\n', '        if let litvinAppearanceObserver { NotificationCenter.default.removeObserver(litvinAppearanceObserver) }\n        self.selectAddMemberDisposable.dispose()\n', 'appearance observer disposal')
        return replace(t, '    override func didLoad() {\n        super.didLoad()\n', '''    override func didLoad() {
        super.didLoad()
        self.litvinAppearanceObserver = NotificationCenter.default.addObserver(forName: LitvinAppearance.changed, object: nil, queue: .main) { [weak self] _ in
            guard let self, let data = self.data else { return }
            if !litvinLocalGifts(account: self.context.account.peerId.toInt64(), peer: self.peerId.toInt64()).isEmpty && !data.availablePanes.contains(.gifts) { data.availablePanes.append(.gifts) }
            self.updateData(data)
            if let (layout, navigationHeight) = self.validLayout {
                self.containerLayoutUpdated(layout: layout, navigationHeight: navigationHeight, transition: .immediate, additive: false)
            }
        }
''', 'appearance profile refresh')
    patch(root, peer_info + '/Sources/PeerInfoScreen.swift', appearance_refresh)
    def local_gift_tab(t):
        t = replace(t, '    let availablePanes: [PeerInfoPaneKey]\n', '    var availablePanes: [PeerInfoPaneKey]\n', 'local gift tab live refresh')
        old = 'if let starGiftsCount = cachedData.starGiftsCount, starGiftsCount > 0 {'
        new = 'if (cachedData.starGiftsCount ?? 0) > 0 || !litvinLocalGifts(account: context.account.peerId.toInt64(), peer: peerView.peerId.toInt64()).isEmpty {'
        if new not in t:
            if t.count(old) != 2: raise RuntimeError('user gift tab anchors changed')
            t = t.replace(old, new)
        return t
    patch(root, peer_info + '/Sources/PeerInfoData.swift', local_gift_tab)

    def gift_entry(t):
        t = imported(t, 'LitvinSettings')
        return replace(t, '    func openPremiumGift() {\n', '''    func openPremiumGift(local: Bool = true) {
        if local, let giftPeer = self.data?.peer {
            LitvinGiftCatalog.show(context: self.context, peer: giftPeer.id.toInt64(), realGift: { [weak self] in self?.openPremiumGift(local: false) })
            return
        }
''', 'profile local gift catalog')
    patch(root, peer_info + '/Sources/PeerInfoScreen.swift', gift_entry)

    def appearance_gifts(t):
        prefix, separator, t = t.partition('public final class ProfileGiftsContext {')
        t, end_separator, suffix = t.partition('// MARK: - CraftGiftsContext')
        if not separator or not end_separator: raise RuntimeError('ProfileGiftsContext boundaries changed')
        t = replace(t, '    private let impl: QueueLocalObject<ProfileGiftsContextImpl>\n', '    private let impl: QueueLocalObject<ProfileGiftsContextImpl>\n    private let litvinAccountId: Int64\n', 'gift presentation account')
        t = replace(t, '            return ProfileGiftsContextImpl(queue: queue, account: account, peerId: peerId, collectionId: collectionId, sorting: sorting, filter: filter, limit: limit)\n', '            return ProfileGiftsContextImpl(queue: queue, account: account, peerId: peerId, collectionId: collectionId, sorting: sorting, filter: filter, limit: limit)\n', 'profile gift impl')
        anchor = '        let queue = self.queue\n        self.impl = QueueLocalObject(queue: queue, generate: {\n            return ProfileGiftsContextImpl'
        t = replace(t, anchor, '        self.litvinAccountId = account.peerId.toInt64()\n' + anchor, 'gift presentation account init')
        old = '''                disposable.set(impl.state.start(next: { value in
                    subscriber.putNext(value)
                }))'''
        new = '''                disposable.set((combineLatest(impl.state, litvinAppearanceUpdates())
                |> deliverOnMainQueue).start(next: { value, _ in
                    subscriber.putNext(litvinProfileGifts(account: impl.account.peerId.toInt64(), peer: impl.peerId.toInt64(), collection: impl.collectionId, state: value))
                }))'''
        # Capture immutable wrapper values; the impl's account fields are private.
        new = new.replace('impl.account.peerId.toInt64()', 'litvinAccount').replace('impl.peerId.toInt64()', 'litvinPeer').replace('impl.collectionId', 'litvinCollection')
        t = replace(t, '    public var state: Signal<ProfileGiftsContext.State, NoError> {\n        return Signal { subscriber in', '    public var state: Signal<ProfileGiftsContext.State, NoError> {\n        let litvinAccount = self.litvinAccountId\n        let litvinPeer = self.peerId.toInt64()\n        let litvinCollection = self.collectionId\n        return Signal { subscriber in', 'gift state context')
        t = replace(t, old, new, 'local profile gift state')
        t = replace(t, '            state = impl._state\n', '            state = impl._state.map { litvinProfileGifts(account: self.litvinAccountId, peer: self.peerId.toInt64(), collection: self.collectionId, state: $0) }\n', 'local gift current state')
        return prefix + separator + t + end_separator + suffix
    patch(root, f'{CORE}/Sources/TelegramEngine/Payments/StarGifts.swift', appearance_gifts)

    # Local gift previews do not enter sell/transfer/wear/purchase controllers.
    def local_gift_taps(t):
        anchor = '''                                if self.canSelect {
                                    if self.selectedItemIds.contains(itemReferenceId) {'''
        t = replace(t, anchor, '''                                if litvinIsLocalGift(product) {
                                    self.parentController?.present(UndoOverlayController(presentationData: presentationData, content: .info(title: "Локальный подарок", text: "Оформление видно только на этом устройстве. Управление — в профиле: Локальные NFT-подарки.", timeout: nil, customUndoText: nil), elevatedLayout: false, animateInAsReplacement: false, action: { _ in false }), in: .current)
                                    return
                                }
''' + anchor, 'local gift tap isolation')
        return replace(t, '(self.starsProducts ?? []).map { .profileGift(self.peerId, $0) }', '(self.starsProducts ?? []).filter { !litvinIsLocalGift($0) }.map { .profileGift(self.peerId, $0) }', 'local gift swipe isolation')
    gifts_ui = f'{UI}/Components/PeerInfo/PeerInfoVisualMediaPaneNode'
    patch(root, gifts_ui + '/Sources/GiftsListView.swift', local_gift_taps)
    patch(root, gifts_ui + '/Sources/PeerInfoGiftsPaneNode.swift', lambda t: replace(t,
        '    private func contextAction(gift: ProfileGiftsContext.State.StarGift, view: UIView, gesture: ContextGesture) {\n',
        '''    private func contextAction(gift: ProfileGiftsContext.State.StarGift, view: UIView, gesture: ContextGesture) {
        if litvinIsLocalGift(gift) { return }
''', 'local gift context isolation'))

    stars_ui = f'{UI}/Components/Stars/StarsTransactionsScreen'
    def appearance_stars(t):
        t = imported(t)
        t = replace(t, '        private var previousBalance: StarsAmount?\n', '        private var previousBalance: StarsAmount?\n        private var litvinAppearanceObserver: NSObjectProtocol?\n', 'stars appearance observer')
        t = replace(t, '            super.init(frame: frame)\n', '''            super.init(frame: frame)
            self.litvinAppearanceObserver = NotificationCenter.default.addObserver(forName: LitvinAppearance.changed, object: nil, queue: .main) { [weak self] _ in
                self?.state?.updated(transition: .immediate)
            }
''', 'stars live appearance refresh')
        t = replace(t, 'formattedBalance = formatStarsAmountText(self.starsState?.balance ?? StarsAmount.zero, dateTimeFormat: environment.dateTimeFormat)', 'formattedBalance = formatStarsAmountText(litvinDisplayStars(account: component.context.account.peerId.toInt64(), original: self.starsState?.balance ?? StarsAmount.zero), dateTimeFormat: environment.dateTimeFormat)', 'my stars top balance')
        t = replace(t, '                            count: self.starsState?.balance ?? StarsAmount.zero,', '                            count: litvinDisplayStars(account: component.context.account.peerId.toInt64(), original: self.starsState?.balance ?? StarsAmount.zero, enabled: !component.starsContext.ton),', 'my stars balance')
        return replace(t, '        deinit {\n            self.stateDisposable?.dispose()', '        deinit {\n            if let litvinAppearanceObserver { NotificationCenter.default.removeObserver(litvinAppearanceObserver) }\n            self.stateDisposable?.dispose()', 'stars observer disposal')
    patch(root, stars_ui + '/Sources/StarsTransactionsScreen.swift', appearance_stars)


if __name__ == '__main__':
    apply(Path(sys.argv[1]))


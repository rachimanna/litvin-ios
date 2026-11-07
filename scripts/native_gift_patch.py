"""Use Telegram's existing gift catalogue and detail pages for private previews."""


def apply(root, patch, replace):
    prefix = 'submodules/TelegramUI/Components/Gifts'

    def catalogue(t):
        t = replace(t, '        private var starsState: StarsContext.State?\n', '        private var starsState: StarsContext.State?\n        private var litvinAppearanceObserver: NSObjectProtocol?\n', 'catalogue appearance observer')
        t = replace(t, '            super.init(frame: frame)\n', '''            super.init(frame: frame)
            self.litvinAppearanceObserver = NotificationCenter.default.addObserver(forName: LitvinAppearance.changed, object: nil, queue: .main) { [weak self] _ in
                self?.state?.updated(transition: .immediate)
            }
''', 'catalogue live balance refresh')
        t = replace(t, '        deinit {\n            self.starsStateDisposable?.dispose()', '        deinit {\n            if let litvinAppearanceObserver { NotificationCenter.default.removeObserver(litvinAppearanceObserver) }\n            self.starsStateDisposable?.dispose()', 'catalogue observer disposal')
        t = replace(t, 'let formattedBalance = formatStarsAmountText(self.starsState?.balance ?? StarsAmount.zero, dateTimeFormat: environment.dateTimeFormat)', 'let formattedBalance = formatStarsAmountText(litvinDisplayStars(account: component.context.account.peerId.toInt64(), original: self.starsState?.balance ?? StarsAmount.zero, enabled: !component.starsContext.ton), dateTimeFormat: environment.dateTimeFormat)', 'catalogue displayed balance')
        anchor = '            let starGift = gift\n'
        return replace(t, anchor, anchor + '''            if litvinGiftPreviewEnabled(account: context.account.peerId.toInt64()) {
                if case .resale = self.starsFilter, case let .generic(collection) = gift,
                   let controller = environment.controller() as? GiftOptionsScreen {
                    let store = context.sharedContext.makeGiftStoreController(context: context, peerId: component.peerId, gift: collection)
                    (controller.parentController() ?? controller).push(store)
                    return
                }
                if litvinSaveGiftPreview(account: context.account.peerId.toInt64(), sender: context.account.peerId, peer: component.peerId, gift: gift) {
                    HapticFeedback().success()
                    component.completion?()
                    environment.controller()?.dismiss()
                } else {
                    environment.controller()?.present(textAlertController(context: context, title: nil, text: "Не удалось сохранить подарок. Лимит — 100 подарков на устройстве.", actions: [TextAlertAction(type: .defaultAction, title: strings.Common_OK, action: {})]), in: .window(.root))
                }
                return
            }
''', 'native catalogue preview send')
    patch(root, prefix + '/GiftOptionsScreen/Sources/GiftOptionsScreen.swift', catalogue)

    def purchase(t):
        anchor = ') {\n    let presentationData = context.sharedContext.currentPresentationData.with { $0 }\n'
        return replace(t, anchor, ''') {
    if litvinGiftPreviewEnabled(account: context.account.peerId.toInt64()) {
        if litvinSaveGiftPreview(account: context.account.peerId.toInt64(), sender: context.account.peerId, peer: recipientPeerId, gift: .unique(uniqueGift)) {
            HapticFeedback().success()
            updateProgress(false)
            completion()
        } else {
            let strings = context.sharedContext.currentPresentationData.with { $0 }.strings
            getController()?.present(textAlertController(context: context, title: nil, text: "Не удалось сохранить подарок. Лимит — 100 подарков на устройстве.", actions: [TextAlertAction(type: .defaultAction, title: strings.Common_OK, action: {})]), in: .window(.root))
        }
        return
    }
    let presentationData = context.sharedContext.currentPresentationData.with { $0 }
''', 'native NFT preview send without payment')
    patch(root, prefix + '/GiftViewScreen/Sources/GiftViewBuyGift.swift', purchase)

    def details(t):
        # Keep the private marker out of the normal message/description text.
        t = replace(t, 'gift.gift, gift.date, gift.convertStars, gift.text, gift.entities, gift.nameHidden,',
            'gift.gift, gift.date, gift.convertStars, (litvinIsLocalGift(gift) ? nil : gift.text), gift.entities, gift.nameHidden,', 'hide internal preview marker')
        # Real gifts retain all original actions. Preview entries have no server
        # reference and must never issue mutations against the borrowed NFT ID.
        signatures = [
            'func convertToStars()', 'func commitDropOriginalDetails()',
            'func sendGift(peerId: EnginePeer.Id)', 'func shareGift()',
            'func setAsGiftTheme()', 'func craftGift()', 'func transferGift()',
            'func resellGift(update: Bool = false)', 'func requestWearPreview()',
            'func commitWear(_ uniqueGift: StarGift.UniqueGift)', 'func commitTakeOff()',
            'func commitBuy(acceptedPrice: CurrencyAmount? = nil, skipConfirmation: Bool = false)',
            'func commitUpgrade()', 'func commitPrepaidUpgrade()', 'func openGiftBuyOffer()',
            'func commitGiftBuyOffer(peer: EnginePeer, price: CurrencyAmount, duration: Int32, allowPaidStars: Int64?)'
        ]
        for signature in signatures:
            anchor = '        ' + signature + ' {\n'
            t = replace(t, anchor, anchor + '            if self.subject.litvinIsPreview { return }\n', 'preview detail action: ' + signature)
        anchor = '            if let controller = controller() as? GiftViewScreen, let customAction = controller.customAction {\n'
        t = replace(t, anchor, '''            if state.subject.litvinIsPreview {
                buttonComponent = ButtonComponent(
                    background: buttonBackground,
                    content: AnyComponentWithIdentity(id: AnyHashable("closePreview"), component: AnyComponent(MultilineTextComponent(text: .plain(NSAttributedString(string: strings.Common_Close, font: Font.semibold(17.0), textColor: theme.list.itemCheckColors.foregroundColor, paragraphAlignment: .center))))),
                    isEnabled: true,
                    displaysProgress: false,
                    action: { [weak state] in state?.dismiss(animated: true) })
            } else if let controller = controller() as? GiftViewScreen, let customAction = controller.customAction {
''', 'preview detail close button')
        anchor = '        func updateSavedToProfile(_ added: Bool) {\n'
        t = replace(t, anchor, anchor + '''            if case let .profileGift(peerId, gift) = self.subject, litvinIsLocalGift(gift) {
                if !added {
                    LitvinAppearance.update(account: self.context.account.peerId.toInt64()) { $0.gifts[String(peerId.toInt64())]?.removeValue(forKey: litvinGiftKey(gift.gift)) }
                    self.getController()?.dismiss()
                }
                return
            }
''', 'preview profile visibility')
        extension = '''
extension GiftViewScreen.Subject {
    var litvinIsPreview: Bool {
        if case let .profileGift(_, gift) = self { return litvinIsLocalGift(gift) }
        return false
    }
}
'''
        if extension not in t: t += extension
        return t
    patch(root, prefix + '/GiftViewScreen/Sources/GiftViewScreen.swift', details)

    def preview_menu(t):
        anchor = '    private func contextAction(gift: ProfileGiftsContext.State.StarGift, view: UIView, gesture: ContextGesture) {\n'
        return replace(t, anchor, anchor + '''        if litvinIsLocalGift(gift) {
            let strings = self.context.sharedContext.currentPresentationData.with { $0 }.strings
            let alert = textAlertController(context: self.context, title: nil, text: "Убрать подарок из профиля?", actions: [
                TextAlertAction(type: .genericAction, title: strings.Common_Cancel, action: {}),
                TextAlertAction(type: .defaultAction, title: "Убрать", action: { [weak self] in
                    guard let self else { return }
                    LitvinAppearance.update(account: self.context.account.peerId.toInt64()) { $0.gifts[String(self.peerId.toInt64())]?.removeValue(forKey: litvinGiftKey(gift.gift)) }
                })
            ])
            self.parentController?.present(alert, in: .window(.root))
            return
        }
''', 'native remove preview menu')
    patch(root, 'submodules/TelegramUI/Components/PeerInfo/PeerInfoVisualMediaPaneNode/Sources/PeerInfoGiftsPaneNode.swift', preview_menu)

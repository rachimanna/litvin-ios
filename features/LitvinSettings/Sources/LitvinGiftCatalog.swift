import UIKit
import ComponentFlow
import AccountContext
import TelegramCore
import SwiftSignalKit
import GiftItemComponent

public enum LitvinGiftCatalog {
    public static func show(context: AccountContext, peer: Int64, realGift: (() -> Void)? = nil) {
        let controller = LitvinGiftCatalogController(context: context, peer: peer, giftId: nil, realGift: realGift)
        LitvinAppearanceUI.present(UINavigationController(rootViewController: controller))
    }
}

private final class LitvinGiftCell: UICollectionViewCell {
    let component = ComponentView<Empty>()
    override func prepareForReuse() {
        super.prepareForReuse()
        component.view?.removeFromSuperview()
    }
}

private final class LitvinGiftCatalogController: UIViewController, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    private let context: AccountContext
    private let peer: Int64
    private let giftId: Int64?
    private let realGift: (() -> Void)?
    private let tabs = UISegmentedControl(items: ["Подарки", "NFT"])
    private let message = UILabel()
    private let retry = UIButton(type: .system)
    private let collection: UICollectionView
    private var gifts: [StarGift] = []
    private var nft = false
    private var disposable: Disposable?
    private var refreshDisposable: Disposable?
    private var resale: ResaleGiftsContext?
    private var canLoadMore = false
    private var loading = true

    init(context: AccountContext, peer: Int64, giftId: Int64?, realGift: (() -> Void)?) {
        self.context = context; self.peer = peer; self.giftId = giftId; self.realGift = realGift
        let layout = UICollectionViewFlowLayout()
        layout.minimumInteritemSpacing = 8; layout.minimumLineSpacing = 8
        collection = UICollectionView(frame: .zero, collectionViewLayout: layout)
        super.init(nibName: nil, bundle: nil)
        title = giftId == nil ? "Отправить подарок" : "Выбрать NFT-подарок"
    }
    required init?(coder: NSCoder) { fatalError() }
    deinit { disposable?.dispose(); refreshDisposable?.dispose() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(close))
        if realGift != nil { navigationItem.leftBarButtonItem = UIBarButtonItem(title: "Купить настоящий", style: .plain, target: self, action: #selector(buyReal)) }
        tabs.selectedSegmentIndex = 0; tabs.addTarget(self, action: #selector(changeTab), for: .valueChanged)
        message.font = .systemFont(ofSize: 13); message.textColor = .secondaryLabel
        message.textAlignment = .center; message.numberOfLines = 0
        retry.setTitle("Повторить загрузку", for: .normal); retry.addTarget(self, action: #selector(load), for: .touchUpInside)
        collection.backgroundColor = .clear; collection.dataSource = self; collection.delegate = self
        collection.register(LitvinGiftCell.self, forCellWithReuseIdentifier: "gift")
        for item in [tabs, message, collection, retry] { item.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(item) }
        tabs.isHidden = giftId != nil
        NSLayoutConstraint.activate([
            tabs.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            tabs.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16), tabs.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            tabs.heightAnchor.constraint(equalToConstant: giftId == nil ? 32 : 0),
            message.topAnchor.constraint(equalTo: tabs.bottomAnchor, constant: 8), message.leadingAnchor.constraint(equalTo: tabs.leadingAnchor), message.trailingAnchor.constraint(equalTo: tabs.trailingAnchor),
            collection.topAnchor.constraint(equalTo: message.bottomAnchor, constant: 8), collection.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12), collection.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12), collection.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            retry.centerXAnchor.constraint(equalTo: collection.centerXAnchor), retry.centerYAnchor.constraint(equalTo: collection.centerYAnchor)
        ])
        load()
    }
    @objc private func close() { dismiss(animated: true) }
    @objc private func buyReal() { dismiss(animated: true, completion: realGift) }
    @objc private func changeTab() { nft = tabs.selectedSegmentIndex == 1; collection.reloadData(); updateMessage() }
    private var displayed: [StarGift] {
        guard nft && giftId == nil else { return gifts }
        return gifts.filter { if case let .generic(gift) = $0 { return gift.upgradeStars != nil || (gift.availability?.resale ?? 0) > 0 }; return true }
    }
    private func updateMessage() {
        message.text = loading && gifts.isEmpty ? "Загружаем каталог…" : (displayed.isEmpty ? "Подарки пока недоступны. Попробуй обновить каталог." : (nft && giftId == nil ? "Выбери коллекцию NFT. Подарок будет виден только тебе." : "Нажми подарок, чтобы добавить его в профиль только у себя. Звёзды не списываются."))
        retry.isHidden = loading || !displayed.isEmpty
    }
    @objc private func load() {
        loading = true; updateMessage(); disposable?.dispose(); refreshDisposable?.dispose()
        if let giftId {
            let resale = ResaleGiftsContext(account: context.account, giftId: giftId, forCrafting: false)
            self.resale = resale
            disposable = (resale.state |> deliverOnMainQueue).start(next: { [weak self] state in
                guard let self else { return }
                self.gifts = state.gifts
                switch state.dataState {
                case .loading: self.loading = true; self.canLoadMore = false
                case let .ready(more, _): self.loading = false; self.canLoadMore = more
                }
                self.collection.reloadData(); self.updateMessage()
            })
        } else {
            refreshDisposable = context.engine.payments.keepStarGiftsUpdated().start()
            disposable = (context.engine.payments.cachedStarGifts() |> deliverOnMainQueue).start(next: { [weak self] gifts in
                guard let self else { return }
                self.gifts = gifts ?? []; self.loading = false
                self.collection.reloadData(); self.updateMessage()
            })
        }
    }
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int { displayed.count }
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        let columns: CGFloat = collectionView.bounds.width > 600 ? 4 : 3
        let width = floor((collectionView.bounds.width - (columns - 1) * 8) / columns)
        return CGSize(width: width, height: width * 1.22)
    }
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "gift", for: indexPath) as! LitvinGiftCell
        let gift = displayed[indexPath.item]
        let subject: GiftItemComponent.Subject
        switch gift {
        case let .generic(gift): subject = .starGift(gift: gift, price: "")
        case let .unique(gift): subject = .uniqueGift(gift: gift, price: nil)
        }
        let presentation = context.sharedContext.currentPresentationData.with { $0 }
        let size = self.collectionView(collectionView, layout: collectionView.collectionViewLayout, sizeForItemAt: indexPath)
        _ = cell.component.update(transition: .immediate, component: AnyComponent(GiftItemComponent(
            context: context, style: .glass, theme: presentation.theme, strings: presentation.strings,
            subject: subject, action: { [weak self] in self?.select(gift) }
        )), environment: {}, containerSize: size)
        if let image = cell.component.view { cell.contentView.addSubview(image); image.frame = CGRect(origin: .zero, size: size) }
        return cell
    }
    func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        if indexPath.item >= displayed.count - 6, canLoadMore, !loading { loading = true; canLoadMore = false; resale?.loadMore() }
    }
    private func select(_ gift: StarGift) {
        if nft, giftId == nil, case let .generic(gift) = gift {
            navigationController?.pushViewController(LitvinGiftCatalogController(context: context, peer: peer, giftId: gift.id, realGift: nil), animated: true)
            return
        }
        guard let data = try? JSONEncoder().encode(gift), LitvinAppearance.update(account: context.account.peerId.toInt64(), { $0.gifts[String(peer), default: [:]][litvinGiftKey(gift)] = data }) else {
            LitvinAppearanceUI.info("Не удалось добавить подарок", "Максимум 100 локальных подарков."); return
        }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismiss(animated: true)
    }
}

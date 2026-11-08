import Foundation
import UIKit
import Display
import AsyncDisplayKit
import SwiftSignalKit
import TelegramPresentationData
import ItemListUI
import UIKitRuntimeUtils

// Settings row: title + current value on top, a slider below.
final class LitvinSliderItem: ListViewItem, ItemListItem {
    let presentationData: ItemListPresentationData
    let title: String
    let valueText: String
    let value: Float
    let minimumValue: Float
    let maximumValue: Float
    let sectionId: ItemListSectionId
    let updated: (Float) -> Void

    init(presentationData: ItemListPresentationData, title: String, valueText: String, value: Float, minimumValue: Float, maximumValue: Float, sectionId: ItemListSectionId, updated: @escaping (Float) -> Void) {
        self.presentationData = presentationData
        self.title = title
        self.valueText = valueText
        self.value = value
        self.minimumValue = minimumValue
        self.maximumValue = maximumValue
        self.sectionId = sectionId
        self.updated = updated
    }

    func nodeConfiguredForParams(async: @escaping (@escaping () -> Void) -> Void, params: ListViewItemLayoutParams, synchronousLoads: Bool, neighbors: ListViewItemNeighbors, completion: @escaping (ListViewItemNode, @escaping () -> (Signal<Void, NoError>?, (ListViewItemApply) -> Void)) -> Void) {
        async {
            let node = LitvinSliderItemNode()
            let (layout, apply) = node.asyncLayout()(self, params, itemListNeighbors(item: self, topFacet: neighbors.previous?.base(ItemListNeighborFacet.self), bottomFacet: neighbors.next?.base(ItemListNeighborFacet.self)))

            node.contentSize = layout.contentSize
            node.insets = layout.insets

            Queue.mainQueue().async {
                completion(node, {
                    return (nil, { _ in apply() })
                })
            }
        }
    }

    func updateNode(async: @escaping (@escaping () -> Void) -> Void, node: @escaping () -> ListViewItemNode, params: ListViewItemLayoutParams, neighbors: ListViewItemNeighbors, animation: ListViewItemUpdateAnimation, completion: @escaping (ListViewItemNodeLayout, @escaping (ListViewItemApply) -> Void) -> Void) {
        Queue.mainQueue().async {
            if let nodeValue = node() as? LitvinSliderItemNode {
                let makeLayout = nodeValue.asyncLayout()

                async {
                    let (layout, apply) = makeLayout(self, params, itemListNeighbors(item: self, topFacet: neighbors.previous?.base(ItemListNeighborFacet.self), bottomFacet: neighbors.next?.base(ItemListNeighborFacet.self)))
                    Queue.mainQueue().async {
                        completion(layout, { _ in
                            apply()
                        })
                    }
                }
            }
        }
    }
}

final class LitvinSliderItemNode: ListViewItemNode {
    private let backgroundNode: ASDisplayNode
    private let topStripeNode: ASDisplayNode
    private let bottomStripeNode: ASDisplayNode
    private let maskNode: ASImageNode

    private var titleLabel: UILabel?
    private var valueLabel: UILabel?
    private var slider: UISlider?

    private var item: LitvinSliderItem?
    private var layoutParams: ListViewItemLayoutParams?

    init() {
        self.backgroundNode = ASDisplayNode()
        self.backgroundNode.isLayerBacked = true

        self.topStripeNode = ASDisplayNode()
        self.topStripeNode.isLayerBacked = true

        self.bottomStripeNode = ASDisplayNode()
        self.bottomStripeNode.isLayerBacked = true

        self.maskNode = ASImageNode()

        super.init(layerBacked: false)
    }

    override func didLoad() {
        super.didLoad()

        let titleLabel = UILabel()
        titleLabel.font = UIFont.systemFont(ofSize: 17.0)
        self.view.addSubview(titleLabel)
        self.titleLabel = titleLabel

        let valueLabel = UILabel()
        valueLabel.font = UIFont.systemFont(ofSize: 17.0)
        valueLabel.textAlignment = .right
        self.view.addSubview(valueLabel)
        self.valueLabel = valueLabel

        let slider = UISlider()
        slider.disablesInteractiveTransitionGestureRecognizer = true
        slider.addTarget(self, action: #selector(self.sliderValueChanged), for: .valueChanged)
        self.view.addSubview(slider)
        self.slider = slider

        self.updateViews()
    }

    private func updateViews() {
        guard let item = self.item, let params = self.layoutParams, let titleLabel = self.titleLabel, let valueLabel = self.valueLabel, let slider = self.slider else {
            return
        }
        let theme = item.presentationData.theme
        let left = params.leftInset + 16.0
        let width = params.width - params.leftInset - params.rightInset - 32.0

        titleLabel.text = item.title
        titleLabel.textColor = theme.list.itemPrimaryTextColor
        titleLabel.frame = CGRect(x: left, y: 11.0, width: width * 0.7, height: 22.0)

        valueLabel.text = item.valueText
        valueLabel.textColor = theme.list.itemSecondaryTextColor
        valueLabel.frame = CGRect(x: left + width * 0.5, y: 11.0, width: width * 0.5, height: 22.0)

        slider.minimumValue = item.minimumValue
        slider.maximumValue = item.maximumValue
        if !slider.isTracking {
            slider.value = item.value
        }
        slider.minimumTrackTintColor = theme.list.itemAccentColor
        slider.frame = CGRect(x: left, y: 38.0, width: width, height: 34.0)
    }

    func asyncLayout() -> (_ item: LitvinSliderItem, _ params: ListViewItemLayoutParams, _ neighbors: ItemListNeighbors) -> (ListViewItemNodeLayout, () -> Void) {
        return { item, params, neighbors in
            let separatorHeight = UIScreenPixel
            let contentSize = CGSize(width: params.width, height: 80.0)
            let insets = itemListNeighborsGroupedInsets(neighbors, params)

            let layout = ListViewItemNodeLayout(contentSize: contentSize, insets: insets)
            let layoutSize = layout.size

            return (layout, { [weak self] in
                guard let strongSelf = self else {
                    return
                }
                strongSelf.item = item
                strongSelf.layoutParams = params

                let theme = item.presentationData.theme
                strongSelf.backgroundNode.backgroundColor = theme.list.itemBlocksBackgroundColor
                strongSelf.topStripeNode.backgroundColor = theme.list.itemBlocksSeparatorColor
                strongSelf.bottomStripeNode.backgroundColor = theme.list.itemBlocksSeparatorColor

                if strongSelf.backgroundNode.supernode == nil {
                    strongSelf.insertSubnode(strongSelf.backgroundNode, at: 0)
                }
                if strongSelf.topStripeNode.supernode == nil {
                    strongSelf.insertSubnode(strongSelf.topStripeNode, at: 1)
                }
                if strongSelf.bottomStripeNode.supernode == nil {
                    strongSelf.insertSubnode(strongSelf.bottomStripeNode, at: 2)
                }
                if strongSelf.maskNode.supernode == nil {
                    strongSelf.insertSubnode(strongSelf.maskNode, at: 3)
                }

                let hasCorners = itemListHasRoundedBlockLayout(params)
                var hasTopCorners = false
                var hasBottomCorners = false
                switch neighbors.top {
                case .sameSection(false):
                    strongSelf.topStripeNode.isHidden = true
                default:
                    hasTopCorners = true
                    strongSelf.topStripeNode.isHidden = hasCorners
                }
                let bottomStripeInset: CGFloat
                let bottomStripeOffset: CGFloat
                switch neighbors.bottom {
                case .sameSection(false):
                    bottomStripeInset = params.leftInset + 16.0
                    bottomStripeOffset = -separatorHeight
                    strongSelf.bottomStripeNode.isHidden = false
                default:
                    bottomStripeInset = 0.0
                    bottomStripeOffset = 0.0
                    hasBottomCorners = true
                    strongSelf.bottomStripeNode.isHidden = hasCorners
                }

                strongSelf.maskNode.image = hasCorners ? PresentationResourcesItemList.cornersImage(theme, top: hasTopCorners, bottom: hasBottomCorners, glass: true) : nil

                strongSelf.backgroundNode.frame = CGRect(origin: CGPoint(x: 0.0, y: -min(insets.top, separatorHeight)), size: CGSize(width: params.width, height: contentSize.height + min(insets.top, separatorHeight) + min(insets.bottom, separatorHeight)))
                strongSelf.maskNode.frame = strongSelf.backgroundNode.frame.insetBy(dx: params.leftInset, dy: 0.0)
                strongSelf.topStripeNode.frame = CGRect(origin: CGPoint(x: 0.0, y: -min(insets.top, separatorHeight)), size: CGSize(width: layoutSize.width, height: separatorHeight))
                strongSelf.bottomStripeNode.frame = CGRect(origin: CGPoint(x: bottomStripeInset, y: contentSize.height + bottomStripeOffset), size: CGSize(width: layoutSize.width - bottomStripeInset, height: separatorHeight))

                strongSelf.updateViews()
            })
        }
    }

    @objc private func sliderValueChanged() {
        guard let slider = self.slider else {
            return
        }
        self.item?.updated(slider.value)
    }
}

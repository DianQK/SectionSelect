//
//  ViewController.swift
//  SectionSelect
//
//  Created by DianQK on 2018/6/11.
//  Copyright © 2018 DianQK. All rights reserved.
//

import UIKit
import RxSwift
import RxCocoa
import Flix
import SnapKit

class CollectionViewCell: UICollectionViewCell {

    var reuseBag = DisposeBag()

    override func prepareForReuse() {
        super.prepareForReuse()
        self.reuseBag = DisposeBag()
    }

}

extension Reactive where Base: UIView {

    var backgroundColor: Binder<UIColor> {
        return Binder(self.base, binding: { (view, backgroundColor) in
            view.backgroundColor = backgroundColor
        })
    }

}

class ItemSelectProvider: AnimatableCollectionViewProvider, ProviderHiddenable {

    var isHidden: Bool {
        get {
            return self._isHidden.value
        }
        set {
            self._isHidden.accept(newValue)
        }
    }

    var _isHidden = BehaviorRelay(value: false)

    func configureCell(_ collectionView: UICollectionView, cell: Cell, indexPath: IndexPath, value: Value) {
        cell.titleLabel.text = value.title
        value.isSelected.asObservable()
            .map { $0 ? UIColor.red.withAlphaComponent(0.6) : UIColor.white }
            .bind(to: cell.contentView.rx.backgroundColor)
            .disposed(by: cell.reuseBag)
    }

    func itemSelected(_ collectionView: UICollectionView, indexPath: IndexPath, value: ItemSelectProvider.Value) {
        collectionView.deselectItem(at: indexPath, animated: true)
        value.isSelected.accept(!value.isSelected.value)
    }

    class Cell: CollectionViewCell {

        let titleLabel = UILabel()

        override init(frame: CGRect) {
            super.init(frame: frame)
            self.contentView.addSubview(titleLabel)
            titleLabel.snp.makeConstraints { (make) in
                make.center.equalTo(self.contentView)
            }
        }

        required init?(coder aDecoder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

    }

    struct Value: StringIdentifiableType, Equatable {

        static func == (lhs: ItemSelectProvider.Value, rhs: ItemSelectProvider.Value) -> Bool {
            return lhs.title == rhs.title
        }

        let title: String
        let isSelected = BehaviorRelay(value: false)

        var identity: String {
            return self.title
        }

    }

    func createValues() -> Observable<[Value]> {
        return Observable.combineLatest(Observable.just(self.items), self._isHidden.asObservable()) { $1 ? [] : $0 }
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath, value: Value) -> CGSize? {
        return CGSize(width: 80, height: 44)
    }

    let items: [Value]

    init(items: [String]) {
        self.items = items.map { Value(title: $0) }
    }

    var isAllSelected: Observable<Bool> {
        return Observable.combineLatest(self.items.map { $0.isSelected.asObservable() }).map { !$0.contains(false) }
            .debounce(0, scheduler: MainScheduler.instance)
    }

    func selectAll() {
        items.forEach { (value) in
            value.isSelected.accept(true)
        }
    }

    func unSelectedAll() {
        items.forEach { (value) in
            value.isSelected.accept(false)
        }
    }

}

class SelectButton: UIButton {

    override init(frame: CGRect) {
        super.init(frame: frame)
        self.setTitle("V", for: .selected)
        self.setTitle("O", for: .normal)
        self.setTitleColor(UIColor.black, for: .normal)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

}

class SectionHeaderSelectProvider: SingleUICollectionViewCellProvider {

    let selectButton = SelectButton(frame: .zero)
    let titleLabel = UILabel()
    let expandButton = UIButton()

    override init() {
        super.init()

        self.contentView.backgroundColor = UIColor.groupTableViewBackground

        self.contentView.addSubview(selectButton)
        selectButton.snp.makeConstraints { (make) in
            make.leading.equalTo(self.contentView).offset(15)
            make.centerY.equalTo(self.contentView)
        }

        self.contentView.addSubview(titleLabel)
        titleLabel.snp.makeConstraints { (make) in
            make.leading.equalTo(self.selectButton.snp.trailing).offset(30)
            make.centerY.equalTo(self.contentView)
        }

        expandButton.setTitle("V", for: .selected)
        expandButton.setTitle("^", for: .normal)
        expandButton.setTitleColor(UIColor.black, for: .normal)

        self.contentView.addSubview(expandButton)
        expandButton.snp.makeConstraints { (make) in
            make.trailing.equalTo(self.contentView).offset(-15)
            make.centerY.equalTo(self.contentView)
        }
    }

    override func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath, value: SingleCollectionViewProvider<UICollectionViewCell>) -> CGSize? {
        return CGSize(width: collectionView.bounds.width, height: 60)
    }

}

class SectionSelectProvider: AnimatableCollectionViewGroupProvider {

    let headerProvider = SectionHeaderSelectProvider()
    let itemSelectProvider: ItemSelectProvider

    var providers: [_AnimatableCollectionViewMultiNodeProvider] {
        return [headerProvider, itemSelectProvider]
    }

    func createAnimatableProviders() -> Observable<[_AnimatableCollectionViewMultiNodeProvider]> {
        return Observable.just([headerProvider, itemSelectProvider])
    }

    let disposeBag = DisposeBag()

    let isAllSelected: Observable<Bool>

    init(items: [String]) {
        self.itemSelectProvider = ItemSelectProvider(items: items)

        self.isAllSelected = self.itemSelectProvider.isAllSelected.share(replay: 1, scope: SubjectLifetimeScope.forever)
        isAllSelected.bind(to: headerProvider.selectButton.rx.isSelected).disposed(by: disposeBag)
        headerProvider.selectButton.rx.tap.withLatestFrom(isAllSelected)
            .subscribe(onNext: { [unowned self] (isAllSelected) in
                isAllSelected ? self.itemSelectProvider.unSelectedAll() : self.itemSelectProvider.selectAll()
            })
            .disposed(by: disposeBag)

        headerProvider.expandButton.rx.tap
            .subscribe(onNext: { [unowned self] in
                self.itemSelectProvider.isHidden = !self.itemSelectProvider.isHidden
                self.headerProvider.expandButton.isSelected = self.itemSelectProvider.isHidden
            })
            .disposed(by: disposeBag)
    }


}

class ViewController: UIViewController {

    let collectionViewLayout = UICollectionViewFlowLayout()

    lazy var collectionView = UICollectionView(frame: CGRect.zero, collectionViewLayout: self.collectionViewLayout)

    let disposeBag = DisposeBag()

    override func viewDidLoad() {
        super.viewDidLoad()
        collectionView.backgroundColor = UIColor.white
        self.view.addSubview(collectionView)
        collectionView.snp.makeConstraints { (make) in
            make.edges.equalTo(self.view)
        }

        let sectionSelectProvider = SectionHeaderSelectProvider()
        sectionSelectProvider.expandButton.isHidden = true
        sectionSelectProvider.titleLabel.text = "全选"

        let aSectionSelectProvider = SectionSelectProvider(items: (1...8).map { "A\($0)" })
        aSectionSelectProvider.headerProvider.titleLabel.text = "A区"

        let bSectionSelectProvider = SectionSelectProvider(items: (1...8).map { "B\($0)" })
        bSectionSelectProvider.headerProvider.titleLabel.text = "B区"

        let isAllSelected = Observable
            .combineLatest(aSectionSelectProvider.isAllSelected, bSectionSelectProvider.isAllSelected) { $0 && $1 }
            .share(replay: 1, scope: SubjectLifetimeScope.forever)
        isAllSelected.bind(to: sectionSelectProvider.selectButton.rx.isSelected).disposed(by: disposeBag)
        sectionSelectProvider.selectButton.rx.tap.withLatestFrom(isAllSelected)
            .subscribe(onNext: { (isAllSelected) in
                isAllSelected ? aSectionSelectProvider.itemSelectProvider.unSelectedAll() : aSectionSelectProvider.itemSelectProvider.selectAll()
                isAllSelected ? bSectionSelectProvider.itemSelectProvider.unSelectedAll() : bSectionSelectProvider.itemSelectProvider.selectAll()
            })
            .disposed(by: disposeBag)

        self.collectionView.flix.animatable.build([
            sectionSelectProvider,
            aSectionSelectProvider,
            bSectionSelectProvider,
            ])
    }

}

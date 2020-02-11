//
//  SearchExtensionView.swift
//  NIO1901
//
//  Created by LiuJie on 2019/5/23.
//  Copyright © 2019 Lojii. All rights reserved.
//

import UIKit



protocol SearchExtensionViewDelegate: class { // optional
    func searchExtensionViewDidSearch(searchOption: SearchOption) -> Void  // 点击了搜索按钮
    func searchExtensionViewDidSearch(searchOption: SearchOption,history:String) -> Void  // 点击了历史记录
}

class SearchExtensionView: UIView {
    // history \ type \ target \ ip \ host \ method \ state
    
    var _searchOption = SearchOption()
    var searchOption: SearchOption{
        get{ return _searchOption }
        set{
            _searchOption = newValue
            // update ui
            
        }
    }
    
    weak var delegate:SearchExtensionViewDelegate?
    
    let headViewH:CGFloat = 40
    let segmentedH:CGFloat = 45
    var clearBtn:UIButton?
    lazy var headView: UIView = {
        let headView = UIView(frame: CGRect(x: 0, y: 0, width: SCREENWIDTH, height: headViewH))
        
        clearBtn = UIButton(frame: CGRect(x: 0, y: 0, width: SCREENWIDTH/2, height:headViewH))
        clearBtn!.setTitle("Clear selected types".localized, for: .normal)
        clearBtn!.setTitleColor(ColorR, for: .normal)
        clearBtn!.titleLabel?.font = Font16
        clearBtn!.addTarget(self, action: #selector(clearSelectedTypes), for: .touchUpInside)
        headView.addSubview(clearBtn!)
        
        let searchBtn = UIButton(frame: CGRect(x: SCREENWIDTH/2, y: 0, width: SCREENWIDTH/2, height:headViewH))
        searchBtn.setTitle("Search".localized, for: .normal)
        searchBtn.setTitleColor(ColorA, for: .normal)
        searchBtn.titleLabel?.font = Font16
        searchBtn.addTarget(self, action: #selector(searchBtnDidClick), for: .touchUpInside)
        headView.addSubview(searchBtn)
        let lineView = UIView(frame: CGRect(x: 0, y: headViewH, width: SCREENWIDTH, height: 1))
        lineView.backgroundColor = ColorF
        headView.addSubview(lineView)
        return headView
    }()
    lazy var scrollView: UIScrollView = {
        let scrollView = UIScrollView()
        return scrollView
    }()
    var historyView = UIView()
    
    var subListViews = [UIView]()
    lazy var segmentedDataSource: JXSegmentedBaseDataSource = {
        let dataSource = JXSegmentedNumberDataSource()
        dataSource.isTitleColorGradientEnabled = true
        dataSource.titles = [
            "History".localized,
            SearchKey.suffix.name(),
            SearchKey.target.name(),
            SearchKey.host.name(),
            SearchKey.state.name(),
            SearchKey.methods.name()
        ]
        subListViews = [
            SearchHistoryView(delegate: self),
            SearchListView(taskID: taskID, searchKey: .suffix, delegate: self,tag: 1),// taskID
            SearchListView(taskID: taskID, searchKey: .target, delegate: self,tag: 2),
            SearchListView(taskID: taskID, searchKey: .host, delegate: self,tag: 3),
            SearchListView(taskID: taskID, searchKey: .state, delegate: self,tag: 4),
            SearchListView(taskID: taskID, searchKey: .methods, delegate: self,tag: 5)
        ]
        dataSource.numbers = [0, 0, 0, 0, 0, 0]
        dataSource.numberBackgroundColor = ColorSY
        dataSource.titleNormalColor = ColorB
        dataSource.titleSelectedColor = ColorR
        dataSource.titleNormalFont = Font14
        dataSource.isTitleZoomEnabled = true
        dataSource.numberFont = Font12
        dataSource.numberStringFormatterClosure = {(number) -> String in
            if number > 99 { return "99+" }
            if number > 999 { return "999+" }
            return "\(number)"
        }
        //reloadData(selectedIndex:)一定要调用
        dataSource.reloadData(selectedIndex: 0)
        return dataSource
    }()
    
    let segmentedView = JXSegmentedView()
    lazy var listContainerView: JXSegmentedListContainerView! = {
        return JXSegmentedListContainerView(dataSource: self)
    }()
    
    var taskID:NSNumber?
    
    init(frame:CGRect,taskID:NSNumber?) {
        self.taskID = taskID
        super.init(frame: frame)
        initUI()
    }
    
//    override init(frame: CGRect) {
//        super.init(frame: frame)
//        // 获取所有types
//        initUI()
//
//    }
    
    deinit{
        NotificationCenter.default.removeObserver(self)
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func initUI() -> Void {
        
        addSubview(headView)
        
        let line = UIView(frame: CGRect(x: 0, y: segmentedH, width: SCREENWIDTH, height: 1))
        line.backgroundColor = ColorF
        segmentedView.addSubview(line)
        segmentedView.frame = CGRect(x: 0, y: headView.frame.maxY, width: SCREENWIDTH, height: segmentedH)
        listContainerView.frame = CGRect(x: 0, y: segmentedView.frame.maxY, width: SCREENWIDTH, height: SCREENHEIGHT - NAVGATIONBARHEIGHT - headViewH - segmentedH)
        
        segmentedView.dataSource = segmentedDataSource
        segmentedView.delegate = self
        addSubview(segmentedView)
        
        segmentedView.contentScrollView = listContainerView.scrollView
        listContainerView.didAppearPercent = 0.01
        addSubview(listContainerView)
    }
    
    @objc func clearSelectedTypes(){
        searchOption.removeAll()
        showWith(searchOption: searchOption)
        hiddenKeyborad()
    }
    
    @objc func searchBtnDidClick(){
        delegate?.searchExtensionViewDidSearch(searchOption: searchOption)
    }
    
    func showWith(searchOption:SearchOption?){
        if searchOption != nil {
            self.searchOption = searchOption!
        }else{
            self.searchOption = SearchOption()
        }
        for v in subListViews {
            if let listView = v as? SearchListView {
                listView.selectedList = self.searchOption.getValues(key: listView.searchKey)
            }
        }
        // 更新右上角数字
        initNumbs()
        for sm in self.searchOption.searchMap {
            if let key = sm.first?.key ,let values = sm.first?.value{
                updateNumbs(key: key, numb: values.count)
            }
        }
        isHidden = false
    }
    
    func hiddenKeyborad(){
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: HidenKeyBoradNoti, object: nil)
        }
    }
    
    func hidden(){
        isHidden = true
    }
    
    func initNumbs(){
        if let segDataSource = segmentedDataSource as? JXSegmentedNumberDataSource {
            segDataSource.numbers = [0,0,0,0,0,0]
            segDataSource.reloadData(selectedIndex: segmentedView.selectedIndex)
            segmentedView.reloadData()
        }
        clearBtn?.setTitle("Clears selected conditions".localized, for: .normal)
    }
    
    func updateNumbs(key:SearchKey,numb:Int){
        var sum:Int = 0
        if let segDataSource = segmentedDataSource as? JXSegmentedNumberDataSource {
            var numbers = segDataSource.numbers
            if key == .suffix { numbers[1] = numb }
            if key == .target { numbers[2] = numb }
            if key == .host { numbers[3] = numb }
            if key == .state { numbers[4] = numb }
            if key == .methods { numbers[5] = numb }
            segDataSource.numbers = numbers
            segDataSource.reloadData(selectedIndex: segmentedView.selectedIndex)
            segmentedView.reloadData()
            sum = numbers.reduce(0, +)
        }
        clearBtn?.setTitle(sum > 0 ? "\("Clears selected conditions".localized)(\(sum))" : "Clears selected conditions".localized, for: .normal)
    }
    
}

extension SearchExtensionView: JXSegmentedViewDelegate {
    func segmentedView(_ segmentedView: JXSegmentedView, didSelectedItemAt index: Int) {
        if let dotDataSource = segmentedDataSource as? JXSegmentedDotDataSource {
            //先更新数据源的数据
            dotDataSource.dotStates[index] = false
            //再调用reloadItem(at: index)
            segmentedView.reloadItem(at: index)
        }
    }
    
    func segmentedView(_ segmentedView: JXSegmentedView, didClickSelectedItemAt index: Int) {
        //传递didClickSelectedItemAt事件给listContainerView，必须调用！！！
        listContainerView.didClickSelectedItem(at: index)
        hiddenKeyborad()
    }
    
    func segmentedView(_ segmentedView: JXSegmentedView, scrollingFrom leftIndex: Int, to rightIndex: Int, percent: CGFloat) {
        //传递scrollingFrom事件给listContainerView，必须调用！！！
        listContainerView.segmentedViewScrolling(from: leftIndex, to: rightIndex, percent: percent, selectedIndex: segmentedView.selectedIndex)
    }
}

extension SearchExtensionView: JXSegmentedListContainerViewDataSource {
    func numberOfLists(in listContainerView: JXSegmentedListContainerView) -> Int {
        if let titleDataSource = segmentedView.dataSource as? JXSegmentedBaseDataSource {
            return titleDataSource.dataSource.count
        }
        return 0
    }
    
    func listContainerView(_ listContainerView: JXSegmentedListContainerView, initListAt index: Int) -> JXSegmentedListContainerViewListDelegate {
        
        if let v = subListViews[index] as? JXSegmentedListContainerViewListDelegate {
            return v
        }else{
            return SearchHistoryView(delegate: self)
        }
    }
}

extension SearchExtensionView:SearchListViewDelegate,SearchHistoryViewDelegate {
    func searchListDidChange(listView: SearchListView, searchKey: SearchKey, list: [String]) {
        // 更新右上角数字
        updateNumbs(key: searchKey, numb: list.count)
        // 更新searchOption
        searchOption.replace(key: searchKey, values: list)
        hiddenKeyborad()
    }
    
    func historyDidClick(history: String) {
        delegate?.searchExtensionViewDidSearch(searchOption: searchOption, history: history)
    }
}

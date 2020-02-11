//
//  SearchListView.swift
//  NIO1901
//
//  Created by LiuJie on 2019/5/27.
//  Copyright © 2019 Lojii. All rights reserved.
//

import UIKit
import TunnelServices

protocol SearchListViewDelegate: class {
    func searchListDidChange(listView:SearchListView, searchKey:SearchKey, list:[String])
}

var SearchListViewRowHeight:CGFloat = 40

class SearchListView: UIView {

    weak var delegate:SearchListViewDelegate?
    
//    let typeMap = ["suffix":"Type","target":"User-Agent","host":"Host","state":"State","methods":"Methods"]

    lazy var tableView: UITableView = {
        let clearBtn = UIButton(frame: CGRect(x: 0, y: 0, width: SCREENWIDTH, height: SearchListViewRowHeight))
        clearBtn.setTitle("\("Clear the selected".localized) \(searchKey.name())", for: .normal)
        clearBtn.titleLabel?.font = Font14
        clearBtn.setTitleColor(ColorR, for: .normal)
        clearBtn.backgroundColor = .white
        clearBtn.addTarget(self, action: #selector(clearSelected), for: .touchUpInside)
        let line = UIView(frame: CGRect(x: 0, y: SearchListViewRowHeight, width: SCREENWIDTH, height: 1))
        line.backgroundColor = ColorF
        let headView = UIView(frame: CGRect(x: 0, y: 0, width: SCREENWIDTH, height: SearchListViewRowHeight))
        headView.addSubview(clearBtn)
        headView.backgroundColor = .white
        headView.addSubview(line)
        let tableView = UITableView()
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(SearchListCell.self, forCellReuseIdentifier: "SearchListCell")
        tableView.separatorStyle = .none
        tableView.rowHeight = SearchListViewRowHeight
        tableView.tableHeaderView = headView
        return tableView
    }()
    var _selectedList = [String]()
    var selectedList: [String] {
        get { return _selectedList }
        set {
            _selectedList = newValue
            tableView.reloadData()
        }
    }
    var searchKey:SearchKey
    var taskID:NSNumber?
    var searchResult:[[String:String]]?
    
    init(taskID:NSNumber?,searchKey:SearchKey,delegate:SearchListViewDelegate,tag:Int) {
        self.searchKey = searchKey
        self.taskID = taskID
        self.delegate = delegate
        super.init(frame: CGRect.zero)
        self.tag = tag
        initUI()
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func initUI(){
        addSubview(tableView)
        tableView.snp.makeConstraints { (m) in
            m.top.left.bottom.right.equalToSuperview()
        }
    }
    
    func loadData(){
        searchResult = Session.groupBy(taskID: taskID,type: searchKey.rawValue)
        tableView.reloadData()
    }
    
    @objc func clearSelected(){
        selectedList = []
        delegate?.searchListDidChange(listView: self, searchKey: searchKey, list: selectedList)
    }
    
}

extension SearchListView:UITableViewDelegate, UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return searchResult?.count ?? 0
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "SearchListCell") as! SearchListCell
        let result = searchResult?[indexPath.row]
        if let key = result?.keys.first {
            cell.checked = selectedList.contains(key)
        }
        cell.title = "\(result?.keys.first ?? "")".urlDecoded()  //"(\(result?.values.first ?? ""))"
        return cell
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let result = searchResult?[indexPath.row]
        if let key = result?.keys.first {
            if _selectedList.contains(key) {
                _selectedList.removeAll { (str) -> Bool in
                    return str == key
                }
            }else{
                _selectedList.append(key)
            }
        }
        tableView.reloadRows(at: [indexPath], with: .automatic)
        // 通知上级
        delegate?.searchListDidChange(listView: self, searchKey: searchKey, list: self.selectedList)
    }
    
}

extension SearchListView: JXSegmentedListContainerViewListDelegate {
    
    func listView() -> UIView {
        return self
    }
    
    func listDidAppear() {
        if searchResult == nil {
            loadData()
        }
    }
}

class SearchListCell: UITableViewCell {
    
    var _title:String = ""
    var title: String {
        get {
            return _title
        }
        set {
            _title = newValue
            titleLabel.text = _title
        }
    }
    
    var _checked:Bool = false
    var checked: Bool {
        get {
            return _checked
        }
        set {
            _checked = newValue
            indicator.isHidden = !_checked
            titleLabel.snp.remakeConstraints { (m) in
                m.left.equalToSuperview().offset(LRSpacing)
                m.centerY.height.equalToSuperview()
                m.right.equalToSuperview().offset(_checked ? -30 : -LRSpacing)
            }
        }
    }
    var indicator:UIImageView
    
    lazy var titleLabel: UILabel = {
        let titleLabel = UILabel()
        titleLabel.font = Font14
        titleLabel.textColor = ColorC
        titleLabel.numberOfLines = 2
        return titleLabel
    }()
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        self.indicator = UIImageView()
        indicator.image = UIImage(named: "checkmark")
        super.init(style: style, reuseIdentifier: reuseIdentifier)

        let line = UIView()
        line.backgroundColor = ColorF
        addSubview(self.indicator)
        addSubview(titleLabel)
        addSubview(line)
        indicator.isHidden = !_checked
        indicator.snp.makeConstraints { (m) in
            m.centerY.equalToSuperview()
            m.width.height.equalTo(20)
            m.right.equalToSuperview().offset(-LRSpacing)
        }
        
        titleLabel.snp.makeConstraints { (m) in
            m.left.equalToSuperview().offset(LRSpacing)
            m.centerY.height.equalToSuperview()
            m.right.equalToSuperview().offset(_checked ? -30 : -LRSpacing)
        }
        line.snp.makeConstraints { (m) in
            m.left.right.bottom.equalToSuperview()
            m.height.equalTo(1)
        }
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    
    
}

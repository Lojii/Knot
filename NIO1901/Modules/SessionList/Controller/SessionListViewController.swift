//
//  SessionListViewController.swift
//  NIO1901
//
//  Created by LiuJie on 2019/5/10.
//  Copyright © 2019 Lojii. All rights reserved.
//

import UIKit
import TunnelServices

class SessionListViewController: BaseViewController {
    
    var _searchOption = SearchOption()
    var searchOption: SearchOption {
        get { return _searchOption }
        set {
            _searchOption = newValue
            searchBar.text = _searchOption.searchWord
            if _searchOption.searchMap.count > 0{
                var count = 0
                for sm in _searchOption.searchMap {
                    if let vs = sm.first?.value {
                        count = vs.count + count
                    }
                }
                indicatorLabel.text = "\(count)"
            }else{
                indicatorLabel.text = "0"
                indicatorLabel.isHidden = true
            }
            updateSQLParams()
        }
    }
    var filterOption = SearchOption()
    var _focusOption = SearchOption()
    var focusOption: SearchOption {
        get { return _focusOption }
        set {
            _focusOption = newValue
            focusPre()
            updateSQLParams()
            search()
        }
    }
    var pageIndex = 0
    let pageSize = 50
    
    var currentTime = Date().timeIntervalSince1970  // 搜索时间起点
    var sqlParams = [String:[String]]()
    var sqlKeyWord:String?
    var _listEditing: Bool = false
    var listEditing: Bool {
        get { return _listEditing }
        set {
            _listEditing = newValue
            showFocusView = false
            tableView.setEditing(_listEditing, animated: true)
            searchBar.isHidden = _listEditing
            if !isSearching, searchOption.searchMap.count > 0 {
                indicatorLabel.isHidden = _listEditing
            }else{
                indicatorLabel.isHidden = true
            }
            filterHeadView.isHidden = _listEditing
            editToolView.isHidden = false
            rightBtn.setTitle(_listEditing ? "Cancel".localized : "Edit".localized, for: .normal)
            
            let tableFrame = CGRect(x: 0, y: NAVGATIONBARHEIGHT + filterHeadView.frame.height, width: SCREENWIDTH, height: SCREENHEIGHT - NAVGATIONBARHEIGHT - filterHeadView.frame.height)
            let tableFrameEdit = CGRect(x: 0, y: NAVGATIONBARHEIGHT, width: SCREENWIDTH, height: SCREENHEIGHT - NAVGATIONBARHEIGHT - 44 - XBOTTOMHEIGHT)
            let editToolFrame = CGRect(x: 0, y: tableFrame.maxY, width: SCREENWIDTH, height: 44 + XBOTTOMHEIGHT)
            let editToolFrameEdit = CGRect(x: 0, y: tableFrameEdit.maxY, width: SCREENWIDTH, height: 44 + XBOTTOMHEIGHT)
            UIView.animate(withDuration: 0.3, animations: {
                self.tableView.frame = self.listEditing ? tableFrameEdit : tableFrame
                self.editToolView.frame = self.listEditing ? editToolFrameEdit : editToolFrame
            }) { (finished) in
                if finished {
                    self.editToolView.isHidden = !self.listEditing
                }
            }
        }
    }
    var _selectedIndexs = [Int]()
    var selectedIndexs: [Int] {
        get { return _selectedIndexs }
        set {
            _selectedIndexs = newValue
            if _selectedIndexs.count > 0 {
                nextBtn.setTitle("\("Next".localized)(\(_selectedIndexs.count)/\(sessionsIDS.count))", for: .normal)
            }else{
                nextBtn.setTitle("Next".localized, for: .normal)
            }
        }
    }
    var selectAll = false
    var outputType:OutputType = .URL
    
    static let searchBarHeight:CGFloat = 30
    let littleSearchBar = CGRect(x: 44, y: STATUSBARHEIGHT + (44 - SessionListViewController.searchBarHeight) / 2, width: SCREENWIDTH - 64 - 44, height: SessionListViewController.searchBarHeight)
    let bigSearchBar = CGRect(x: LRSpacing, y: STATUSBARHEIGHT + (44 - SessionListViewController.searchBarHeight) / 2, width: SCREENWIDTH - 64 - LRSpacing, height: SessionListViewController.searchBarHeight)
    
    var sessions = [SessionItem]()
    var sessionsIDS = [Int]()
    var _currentIndex:Int = 0
    var currentIndex:Int {
        get { return _currentIndex }
        set {
            _currentIndex = newValue
            let title = "\(_currentIndex)/\(sessionsIDS.count)"
            focusSubTitleLabel.text = title
        }
    }
    var task:Task?
    var searchWord:String?
    var focuses:[String:[String]]?
    
    private var _isSearching: Bool = false
    var isSearching: Bool {
        get { return _isSearching }
        set {
            if _isSearching == newValue { return }
            _isSearching = newValue
            showLeftBtn = !_isSearching
            rightBtn.isHidden = _isSearching
            
            if !_isSearching, searchOption.searchMap.count > 0 {
                indicatorLabel.isHidden = false
            }else{
                indicatorLabel.isHidden = true
            }
            searchCancelBtn.isHidden = !_isSearching
            self.searchExtensionView.showWith(searchOption: self.searchOption.getACopy())
            view.bringSubviewToFront(searchExtensionView)
            UIView.animate(withDuration: 0.25, animations: {
                self.searchBar.frame = self._isSearching ? self.bigSearchBar : self.littleSearchBar
                self.searchExtensionView.layer.opacity = self._isSearching ? 1 : 0
            }) { (finished) in
                if finished {
                    if !self._isSearching {
                        self.searchExtensionView.hidden()
                    }
                }
            }
        }
    }
    private var _showFocusView:Bool = false
    var showFocusView: Bool {
        get{ return _showFocusView }
        set{
            _showFocusView = newValue
            view.bringSubviewToFront(focusView)
            focusPreView.isHidden = _showFocusView
            if _showFocusView {
                focusView.show(focuses: focusOption.getACopy())
            }else{
                focusView.hiden()
            }
        }
    }
    // 搜索框
    var indicatorLabel = UILabel()
    lazy var searchBar: UITextField = {
        let searchBar = UITextField()
        searchBar.backgroundColor = .white
        searchBar.layer.cornerRadius = 5
        searchBar.clipsToBounds = true
        searchBar.placeholder = "Search".localized
        let leftView = UIImageView(frame: CGRect(x: 0, y: 0, width: 30, height: 20))
        leftView.image = UIImage(named: "search")
        leftView.contentMode = UIView.ContentMode.scaleAspectFit
        searchBar.leftView = leftView
        searchBar.leftViewMode = .always
        searchBar.clearButtonMode = .always
        searchBar.textColor = ColorB
        searchBar.font = Font14
        searchBar.returnKeyType = .search
        searchBar.delegate = self
        return searchBar
    }()
    // 取消按钮
    lazy var searchCancelBtn: UIButton = {
        let searchCancelBtn = UIButton()
        searchCancelBtn.isHidden = !isSearching
        searchCancelBtn.setTitle("Cancel".localized, for: .normal)
        searchCancelBtn.setTitleColor(ColorA, for: .normal)
        searchCancelBtn.titleLabel?.font = Font16
        searchCancelBtn.frame = CGRect(x: SCREENWIDTH - 64, y: STATUSBARHEIGHT, width: 64, height: 44)
        searchCancelBtn.addTarget(self, action: #selector(cancelBtnDidClick), for: .touchUpInside)
        return searchCancelBtn
    }()
    // 搜索扩展页面
    lazy var searchExtensionView: SearchExtensionView = {
        let searchExtensionView = SearchExtensionView(frame: CGRect(x: 0, y: NAVGATIONBARHEIGHT, width: SCREENWIDTH, height: SCREENHEIGHT - NAVGATIONBARHEIGHT),taskID:task?.id)
        //isHidden = !isSearching
        if isSearching { searchExtensionView.showWith(searchOption: self.searchOption.getACopy()) }else{ searchExtensionView.hidden() }
        searchExtensionView.layer.opacity = 0
        searchExtensionView.backgroundColor = .white
        searchExtensionView.delegate = self
        return searchExtensionView
    }()
    // Focus
    lazy var focusView: SearchFocusView = {
        let focusView = SearchFocusView(frame: CGRect(x: 0, y: NAVGATIONBARHEIGHT + filterHeadView.frame.height, width: SCREENWIDTH, height: SCREENHEIGHT - NAVGATIONBARHEIGHT - filterHeadView.frame.height))
        focusView.isHidden = !self.showFocusView
        focusView.delegate = self
        return focusView
    }()
    var focusTitleLabel = UILabel()
    var focusSubTitleLabel = UILabel()
    var focusPreView = UIView()
    lazy var filterHeadView: UIView = {
        let filterHeadView = UIView(frame: CGRect(x: 0, y: NAVGATIONBARHEIGHT, width: SCREENWIDTH, height: 40))
        let title = "Focus"
        focusTitleLabel = UILabel(frame: CGRect(x: LRSpacing, y: 0, width: title.textWidth(font: Font16) + 10, height: filterHeadView.frame.height))
        focusTitleLabel.text = title
        focusTitleLabel.textAlignment = .left
        focusTitleLabel.textColor = ColorB
        focusTitleLabel.font = Font16
        
        focusSubTitleLabel = UILabel(frame: CGRect(x: 0, y: filterHeadView.frame.height - 15, width: focusTitleLabel.frame.maxX + LRSpacing, height: 15))
        focusSubTitleLabel.font = FontC11
        focusSubTitleLabel.textColor = ColorSR
        focusSubTitleLabel.textAlignment = .left
        focusTitleLabel.addSubview(focusSubTitleLabel)
        
        filterHeadView.addSubview(focusTitleLabel)
        filterHeadView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(focusDidClick)))
        focusPreView = UIView(frame: CGRect(x: focusTitleLabel.frame.maxX, y: 0, width: filterHeadView.frame.width - focusTitleLabel.frame.maxX - LRSpacing, height: filterHeadView.frame.height))
        filterHeadView.addSubview(focusPreView)
        return filterHeadView
    }()
    // tableView
    lazy var tableView: UITableView = {
        let tableViewFrame = CGRect(x: 0, y: NAVGATIONBARHEIGHT + filterHeadView.frame.height, width: SCREENWIDTH, height: SCREENHEIGHT - NAVGATIONBARHEIGHT - filterHeadView.frame.height)
        let tableView = UITableView(frame: tableViewFrame, style: .plain)
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(SessionCell.self, forCellReuseIdentifier: "SessionCell")
        tableView.separatorStyle = .none
        tableView.allowsMultipleSelectionDuringEditing = true
        tableView.configRefreshHeader(container: self) { [weak self] in
            self?.loadData()
        }
        tableView.configRefreshFooter(container: self, action: { [weak self] in
            self?.loadData(isMore: true)
        })
        tableView.switchRefreshHeader(to: .refreshing)
        return tableView
    }()
    var nextBtn = UIButton()
    lazy var editToolView: UIView = {
        let H:CGFloat = 44
        let editToolFrame = CGRect(x: 0, y: self.tableView.frame.maxY, width: SCREENWIDTH, height: H + XBOTTOMHEIGHT)
        let editToolView = UIView(frame: editToolFrame)
        editToolView.backgroundColor = ColorF
        let selectAllBtn = UIButton()
        selectAllBtn.frame = CGRect(x: 0, y: 0, width: 70, height: H)
        selectAllBtn.setTitle("Check all".localized, for: .normal)
        selectAllBtn.setTitleColor(ColorM, for: .normal)
        selectAllBtn.titleLabel?.font = Font16
        selectAllBtn.addTarget(self, action: #selector(selectAllBtnDidClick), for: .touchUpInside)
        let invertBtn = UIButton()
        invertBtn.frame = CGRect(x: selectAllBtn.frame.maxX, y: 0, width: 70, height: H)
        invertBtn.setTitle("Invert Check".localized, for: .normal)
        invertBtn.setTitleColor(ColorM, for: .normal)
        invertBtn.titleLabel?.font = Font16
        invertBtn.addTarget(self, action: #selector(invertAllBtnDidClick), for: .touchUpInside)
        nextBtn = UIButton()
        nextBtn.setTitle("Next".localized, for: .normal)
        nextBtn.frame = CGRect(x: SCREENWIDTH - 150, y: 0, width: 150, height: H)
        nextBtn.setTitleColor(ColorM, for: .normal)
        nextBtn.titleLabel?.font = Font16
        nextBtn.addTarget(self, action: #selector(nextBtnDidClick), for: .touchUpInside)
        editToolView.addSubview(selectAllBtn)
        editToolView.addSubview(invertBtn)
        editToolView.addSubview(nextBtn)
        return editToolView
    }()
    // init
    init(task:Task?) {
        self.task = task
//        searchOption
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    // life
    override func viewDidLoad() {
        super.viewDidLoad()
        initUI()
        NotificationCenter.default.addObserver(self, selector: #selector(hidenKeyborad), name: HidenKeyBoradNoti, object: nil)
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
        print("Session List VC deinit !")
    }
    func initUI(){
        // rightBtn
        rightBtn.setTitle("Edit".localized, for: .normal)
        rightBtn.setTitleColor(ColorA, for: .normal)
        rightBtn.addTarget(self, action: #selector(rightBtnDidClick), for: .touchUpInside)
        // searchBar
        navBar.isUserInteractionEnabled = true
        navBar.addSubview(searchBar)
        // 右上角数字指示器
        let vFont = Font12
        let vHeight:CGFloat = vFont.lineHeight + 5
        indicatorLabel = UILabel()
        indicatorLabel.textColor = .white
        indicatorLabel.font = vFont
        indicatorLabel.backgroundColor = ColorSY
        indicatorLabel.textAlignment = .center
        indicatorLabel.clipsToBounds = true
        indicatorLabel.layer.cornerRadius = vHeight / 2
        indicatorLabel.isHidden = true
//        indicatorLabel.
        navBar.addSubview(indicatorLabel)
        indicatorLabel.snp.makeConstraints({ (m) in
            m.centerY.equalTo(searchBar.snp.top).offset(5)
            m.centerX.equalTo(searchBar.snp.right)
            m.height.width.equalTo(vHeight)
        })
        
        navBar.addSubview(searchCancelBtn)
        searchBar.frame = littleSearchBar
        view.addSubview(searchExtensionView)
        // filterHeadView
        view.addSubview(filterHeadView)
        view.addSubview(focusView)
        // list
        view.addSubview(tableView)
        // editTool
        view.addSubview(editToolView)
    }
    
    func updateSQLParams(){
        let searchParams = SearchOption()
        searchParams.searchWord = searchOption.searchWord
        for sm in searchOption.searchMap {
            if let kv = sm.first {
                searchParams.addMap(key: kv.key, values: kv.value)
            }
        }
        for sm in focusOption.searchMap {
            if let kv = sm.first {
//                searchParams.addMap(key: kv.key, values: kv.value)
                searchParams.replace(key: kv.key, values: kv.value)
            }
        }
        sqlParams = [String:[String]]()
        for sm in searchParams.searchMap {
            if let kv = sm.first {
                sqlParams["\(kv.key)"] = kv.value
            }
        }
        sqlKeyWord = searchParams.searchWord
    }
    
    func loadData(isMore:Bool = false) -> Void {
        let taskID = task?.id == nil ? nil : "\(task!.id!)"
        if !isMore {
            pageIndex = 0
            currentIndex = 0
            currentTime = Date().timeIntervalSince1970
            sessions.removeAll()
            updateSQLParams()
            sessionsIDS = Session.countWith(taskID: taskID, keyWord: sqlKeyWord, params: sqlParams,
                                            orderBy: nil, timeInterval: currentTime)
            tableView.switchRefreshFooter(to: .normal)
        }
        let results = Session.findAll(taskID: taskID, keyWord: sqlKeyWord, params: sqlParams, pageSize: pageSize,
                                      pageIndex: pageIndex, orderBy: nil, timeInterval: currentTime)
        pageIndex = pageIndex + 1
        for s in results {
            sessions.append(SessionItem(s))
        }
        if !isMore {
            if results.count <= 0 {
                // TODO:NO More !
            }
            currentIndex = sessions.count > 0 ? 1 : 0
            tableView.switchRefreshHeader(to: .normal(.success, 0))
        }else{
            if results.count < pageSize {
                tableView.switchRefreshFooter(to: .noMoreData)
            }else{
                tableView.switchRefreshFooter(to: .normal)
            }
        }
        tableView.reloadData()
    }
    
    func search(){
        tableView.switchRefreshHeader(to: .refreshing)
        isSearching = false
//        print("searchOption:\(searchOption.searchMap) -- word:\(searchOption.searchWord)")
//        loadData()
        
        // 保存历史记录
        guard let word = searchBar.text else {
            return
        }
        if word == "" {
            return
        }
        let defaults = UserDefaults.standard
        var historys = defaults.stringArray(forKey: SearchHistoryUserDefaults) ?? [String]()
        historys.removeAll { (str) -> Bool in
            return str == word
        }
        historys.append(word)
        if historys.count > 10 {
            historys.remove(at: 0)
        }
        defaults.set(historys, forKey: SearchHistoryUserDefaults)
        defaults.synchronize()
        NotificationCenter.default.post(name: SearchHistoryDidUpdateNoti, object: nil)
    }
    
    @objc func cancelBtnDidClick(){
        isSearching = false
        view.endEditing(true)
    }
    
    @objc func focusDidClick(){
        showFocusView = focusView.isHidden
    }
    
    @objc func rightBtnDidClick(){
        if listEditing {
            listEditing = false
            selectedIndexs.removeAll()
            return
        }
        PopViewController.show(titles: ["Export link".localized,"Export cURL".localized,"Export HTTP Archive (.har)".localized], viewController: self) { (index) in
            self.listEditing = true
            if index == 0 {
                self.outputType = .URL
                self.navBar.titleLable.text = "Export link".localized
            }
            if index == 1 {
                self.outputType = .CURL
                self.navBar.titleLable.text = "Export cURL".localized
            }
            if index == 2 {
                self.outputType = .HAR
                self.navBar.titleLable.text = "Export HTTP Archive (.har)".localized
            }
        }
    }
    
    @objc func selectAllBtnDidClick(){
        selectedIndexs.removeAll()
        for sessionId in sessionsIDS {
            selectedIndexs.append(sessionId)
        }
        tableView.reloadData()
    }
    
    @objc func invertAllBtnDidClick(){
        var tmpIds = [Int]()
        for sessionId in sessionsIDS {
            tmpIds.append(sessionId)
        }
        tmpIds.removeAll { (id) -> Bool in
            return selectedIndexs.contains(id)
        }
        selectedIndexs = tmpIds
        tableView.reloadData()
    }
    
    @objc func nextBtnDidClick(){
        ZKProgressHUD.show()
        OutputUtil.output(ids: selectedIndexs, type: outputType) { (filePath) in
            ZKProgressHUD.dismiss()
//            print("File:\(filePath ?? "")")
            guard let fp = filePath else {
                ZKProgressHUD.showError("Export failed".localized)
                return
            }
            if let fileUrl = URL(string: fp) {
                let vc = VisualActivityViewController(url: fileUrl)
                //(UIActivity.ActivityType?, Bool, [Any]?, Error?) -> Void
                vc.completionWithItemsHandler = { (type,success,items,error) in
                    try? FileManager.default.removeItem(at: fileUrl)
                }
                self.present(vc, animated: true, completion: nil)
            }
        }
    }
    
    @objc func hidenKeyborad(){
        view.endEditing(true)
    }
    
    func focusPre(){
        for v in focusPreView.subviews { v.removeFromSuperview()}
        var offX:CGFloat = 0
        let vFont = Font12
        let vHeight:CGFloat = vFont.lineHeight + 5
        let w = focusPreView.frame.width
        let h = focusPreView.frame.height
        let vSpacing:CGFloat = 2
        for sm in focusOption.searchMap {
            if let kv = sm.first {
                for v in kv.value {
                    var vWidth = v.textWidth(font: vFont) + 10
                    if vWidth > w { vWidth = w }
                    let vLabel = UILabel(frame: CGRect(x: offX, y: (h - vHeight) / 2, width: vWidth, height: vHeight))
                    vLabel.font = vFont
                    vLabel.textColor = .white
                    vLabel.text = v
                    vLabel.backgroundColor = ColorSG
                    vLabel.textAlignment = .center
                    vLabel.clipsToBounds = true
                    vLabel.layer.cornerRadius = vHeight / 3.5
                    focusPreView.addSubview(vLabel)
                    offX = offX + vWidth + vSpacing
                    if offX > w {
                        return
                    }
                }
            }
        }
    }
}

extension SessionListViewController:UITextFieldDelegate {
    func textFieldDidBeginEditing(_ textField: UITextField) {
        isSearching = true
        showFocusView = false
    }
    
    func textFieldShouldClear(_ textField: UITextField) -> Bool {
        return true
    }
    
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        view.endEditing(true)

        searchExtensionView.searchOption.searchWord = textField.text ?? ""
        searchOption = searchExtensionView.searchOption.getACopy()
        
        search()
        isSearching = false
        return true
    }
}

extension SessionListViewController:UITableViewDelegate,UITableViewDataSource {
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return sessions[indexPath.row].sessionCellHeight
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return sessions.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "SessionCell") as! SessionCell
        let session = sessions[indexPath.row]
        cell.session = session
        cell.delegate = self
        cell.indexPath = indexPath
        if tableView.isEditing {
            let selected = selectedIndexs.contains(session.session.id?.intValue ?? -1)
            if selected {
                tableView.selectRow(at: indexPath, animated: false, scrollPosition: .none)
            }
        }
        return cell
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard let session = sessions[indexPath.row].session else { return }
        if tableView.isEditing { return }
        tableView.deselectRow(at: indexPath, animated: true)
        let vc = SessionDetailViewController(session: session)
        navigationController?.pushViewController(vc, animated: true)
    }
    
    func tableView(_ tableView: UITableView, editingStyleForRowAt indexPath: IndexPath) -> UITableViewCell.EditingStyle {
        return .none
    }
    
    func tableView(_ tableView: UITableView, didEndDisplaying cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        if let firstRows = tableView.indexPathsForVisibleRows?.first {
//            if lastRows.row + 1 >= sessionsIDS.count {
//                currentIndex = sessionsIDS.count
//            }else{
//                currentIndex = firstRows.row + 1
//            }
            currentIndex = firstRows.row + 1
        }else{
            currentIndex = 0
        }
    }
}

extension SessionListViewController:SearchExtensionViewDelegate,SessionCellDelegate, CellPopViewControllerDelegate,SearchFocusViewDelegate {
    
    
    func searchExtensionViewDidSearch(searchOption: SearchOption) {
        searchOption.searchWord = searchBar.text ?? ""
        self.searchOption = searchOption.getACopy()
        search()
        view.endEditing(true)
    }
    
    func searchExtensionViewDidSearch(searchOption: SearchOption, history: String) {
        searchOption.searchWord = history
        self.searchOption = searchOption.getACopy()
        search()
        view.endEditing(true)
    }
    
    func moreBtnDidClick(session: Session?) {
        if let s = session {
            let popup = PopupController.create(self)
                .customize(
                    [
                        .layout(.bottom),
                        .animation(.slideUp),
                        .backgroundStyle(.blackFilter(alpha: 0.5)),
                        .dismissWhenTaps(true),
                        .scrollable(true)
                    ]
            )
            let container = CellPopViewController(session: s, focusOption: focusOption.getACopy())
            container.closeHandler = {
                popup.dismiss()
            }
            container.delegate = self
            popup.show(container)
        }
    }
    
    func sessionCellSelectedChange(session: Session?, selected: Bool, indexPath:IndexPath?) {
        guard let id = session?.id, let index = indexPath else { return }
        if !selected {
            selectedIndexs.append(id.intValue)
            tableView.selectRow(at: index, animated: false, scrollPosition: .none)
        }else{
            if selectedIndexs.contains(id.intValue) {
                selectedIndexs.removeAll { (sid) -> Bool in
                    return sid == id.intValue
                }
            }
            tableView.deselectRow(at: index, animated: false)
        }
    }
    
    func cellPopViewDidFocuse(focuseOption: SearchOption) {
        self.focusOption = focuseOption
    }
    
    func cellPopViewOutput(session: Session, type: OutputType) {
        ZKProgressHUD.show()
        OutputUtil.output(session: session, type: type) { (result) in
            ZKProgressHUD.dismiss()
            if result == "" { return }
            guard let r = result else{
                ZKProgressHUD.showError("Export failed".localized)
                return
            }
            if let fileUrl = URL(string: r) {
                let vc = VisualActivityViewController(url: fileUrl)
                vc.completionWithItemsHandler = { (type,success,items,error) in
                    try? FileManager.default.removeItem(at: fileUrl)
                }
                self.present(vc, animated: true, completion: nil)
            }
        }
    }
    
    func cellPopViewCollect(session: Session) {
        print("cellPopViewCollect")
    }
    
    func focusViewDidFocuse(focuseOption: SearchOption) {
        self.focusOption = focuseOption
        showFocusView = false
    }
    
    func focusViewAddToFiter(focuseOption: SearchOption) {
        showFocusView = false
        // add
        // reload
    }
    
    func focusViewDidHiden() {
        focusPreView.isHidden = false
    }
}

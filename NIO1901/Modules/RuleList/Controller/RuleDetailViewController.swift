//
//  RuleDetailViewController.swift
//  NIO1901
//
//  Created by LiuJie on 2019/6/8.
//  Copyright © 2019 Lojii. All rights reserved.
//

import UIKit
import TunnelServices

class RuleDetailViewController: BaseViewController {
    
    var rule:Rule
    var isNew = false
    var ruleChanged = false
    
    var segmentedView:IDSegmentedView
    var subVCs:[UIViewController]!
    
    lazy var pageViewController: UIPageViewController = {
        let pageViewController = UIPageViewController(transitionStyle: .scroll, navigationOrientation: .horizontal, options: [UIPageViewController.OptionsKey.spineLocation : UIPageViewController.SpineLocation.min])
        pageViewController.delegate = self
        pageViewController.dataSource = self
        pageViewController.view.frame = CGRect(x: 0, y: NAVGATIONBARHEIGHT, width: SCREENWIDTH, height: SCREENHEIGHT - NAVGATIONBARHEIGHT)
        return pageViewController
    }()
    
    init(rule:Rule?) {
        if rule == nil {
            self.isNew = true
        }
        let newRule = Rule()
        newRule.name = ""
        newRule.defaultStrategy = .DIRECT
        newRule.defaultBlacklistEnable = true
        newRule.createTime = Date().fullSting
        self.rule = rule ?? newRule
        self.segmentedView = IDSegmentedView(items: ["Overview".localized,"Match rule".localized])// ,"拦截规则","DNS映射"
        let overVC = RuleOverViewController(rule: self.rule)
        overVC.view.tag = 0
        let editVC = RuleEditViewController(rule: self.rule)
        editVC.view.tag = 1
//        let interceptVC = InterceptRulesViewController()
//        interceptVC.view.tag = 2
        subVCs = [overVC,editVC]
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        KeyboardManager.share.addMonitorViewController(self)
        addChild(pageViewController)
//        pageViewController.view.bounds = view.frame
        view.addSubview(pageViewController.view)
        NotificationCenter.default.addObserver(self, selector: #selector(currentRuleDidChange(noti:)), name: CurrentRuleDidChange, object: nil)
        setUI()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    func setUI() -> Void {
        let cancelBtn = UIButton()
        cancelBtn.setTitle("Cancel".localized, for: .normal)
        cancelBtn.setTitleColor(ColorM, for: .normal)
        cancelBtn.addTarget(self, action: #selector(cancelBtnclick), for: .touchUpInside)
        cancelBtn.titleLabel?.font = Font16
        navBar.addSubview(cancelBtn)
        cancelBtn.snp.makeConstraints { (m) in
            m.left.equalToSuperview()
            m.centerY.equalTo(rightBtn)
            m.width.height.equalTo(rightBtn)
        }
        showLeftBtn = false
        navBar.addSubview(segmentedView)
        segmentedView.id_setSegmentStyle(textColor: ColorA, selectedColor: ColorM, textFont: Font14)
        segmentedView.selectedSegmentIndex = 0
        segmentedView.apportionsSegmentWidthsByContent = true
        segmentedView.snp.makeConstraints { (m) in
            m.centerX.centerY.equalTo(navBar.titleLable)
            m.height.equalTo(25)
            m.width.equalTo(SCREENWIDTH/3*2)
        }
        segmentedView.addTarget(self, action: #selector(segmentedViewChange(sender:)), for: .valueChanged)
        let index = segmentedView.selectedSegmentIndex
        pageViewController.setViewControllers([subVCs[index]], direction: .forward, animated: false, completion: nil)
        
//        let moreImg = UIImage(named: "more1")?.imageWithTintColor(color: ColorM)
//        rightBtn.setImage(moreImg, for: .normal)
//        rightBtn.imageEdgeInsets = UIEdgeInsets(top: 0, left: LRSpacing, bottom: 0, right: LRSpacing)
//        rightBtn.imageView?.contentMode = .scaleAspectFit
        rightBtn.setTitle("Done".localized, for: .normal)
        rightBtn.setTitleColor(ColorM, for: .normal)
        rightBtn.titleLabel?.font = Font16
    }
    
    @objc func segmentedViewChange(sender:IDSegmentedView) -> Void{
        let index = sender.selectedSegmentIndex
        let tag = pageViewController.viewControllers?.first?.view.tag ?? 0
        sender.isUserInteractionEnabled = false
        pageViewController.setViewControllers([subVCs[index]], direction: index > tag ? .forward : .reverse, animated: true ) { (_) in
            sender.isUserInteractionEnabled = true
        }
    }
    
    override func rightBtnClick() {
        try? rule.saveToDB()
        NotificationCenter.default.post(name: CurrentRuleListChange, object: nil)
        self.dismiss(animated: true, completion: nil)
    }
    
    @objc func currentRuleDidChange(noti:Notification){
        ruleChanged = true
    }
    
    @objc func cancelBtnclick(){
        if ruleChanged {
            IDDialog.id_show(title: "Save changes or not".localized, msg: nil, countDownNumber: nil, leftActionTitle:"Cancel".localized, rightActionTitle: "Ok".localized, leftHandler: {
                self.dismiss(animated: true, completion: nil)
            }) {
                try? self.rule.saveToDB()
                NotificationCenter.default.post(name: CurrentRuleListChange, object: nil)
                self.dismiss(animated: true, completion: nil)
            }
        }else{
            dismiss(animated: true, completion: nil)
        }
    }
}

extension RuleDetailViewController: UIPageViewControllerDelegate,UIPageViewControllerDataSource{
    func pageViewController(_ pageViewController: UIPageViewController, viewControllerBefore viewController: UIViewController) -> UIViewController? {
        let tag = viewController.view.tag
        return tag > 0 ? subVCs[tag-1] : nil
    }
    
    func pageViewController(_ pageViewController: UIPageViewController, viewControllerAfter viewController: UIViewController) -> UIViewController? {
        let tag = viewController.view.tag
        return tag < subVCs.count-1 ? subVCs[tag+1] : nil
    }
    
    func pageViewController(_ pageViewController: UIPageViewController, didFinishAnimating finished: Bool, previousViewControllers: [UIViewController], transitionCompleted completed: Bool) {
        if let vc = pageViewController.viewControllers?.first {
            segmentedView.selectedSegmentIndex = vc.view.tag
        }
    }
}

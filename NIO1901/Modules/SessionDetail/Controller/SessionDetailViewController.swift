//
//  SessionDetailViewController.swift
//  NIO1901
//
//  Created by LiuJie on 2019/5/14.
//  Copyright © 2019 Lojii. All rights reserved.
//

import UIKit
import TunnelServices

class SessionDetailViewController: BaseViewController {
    
    var session:Session
    var segmentedView:IDSegmentedView
    var subVCs:[UIViewController]!
    
    lazy var pageViewController: UIPageViewController = {
        let pageViewController = UIPageViewController(transitionStyle: .scroll, navigationOrientation: .horizontal, options: [UIPageViewController.OptionsKey.spineLocation : UIPageViewController.SpineLocation.min])
        pageViewController.delegate = self
        pageViewController.dataSource = self
        return pageViewController
    }()
    
    init(session:Session) {
        self.session = session
        self.segmentedView = IDSegmentedView(items: ["Request".localized,"Response".localized,"Overview".localized])
        let reqVC = SessionRequestViewController(session)
        reqVC.view.tag = 0
        let rspVC = SessionResponseViewController(session)
        rspVC.view.tag = 1
        let oveVC = SessionOverViewViewController(session)
        oveVC.view.tag = 2
        subVCs = [reqVC,rspVC,oveVC]
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        addChild(pageViewController)
        pageViewController.view.bounds = view.frame
        view.addSubview(pageViewController.view)
        setUI()
    }
    
    func setUI() -> Void {
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

        let moreImg = UIImage(named: "more1")?.imageWithTintColor(color: ColorM)
        rightBtn.setImage(moreImg, for: .normal)
        rightBtn.imageEdgeInsets = UIEdgeInsets(top: 0, left: LRSpacing, bottom: 0, right: LRSpacing)
        rightBtn.imageView?.contentMode = .scaleAspectFit
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
        PopViewController.show(titles: ["Export link".localized,"Export cURL".localized,"Export HTTP Archive (.har)".localized], viewController: self) { (index) in
            var type:OutputType = .URL
            if index == 1 { type = .CURL }
            if index == 2 { type = .HAR }
            ZKProgressHUD.show()
            OutputUtil.output(session: self.session, type: type, compeleHandle: { (result) in
                ZKProgressHUD.dismiss()
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
            })
        }
    }
}

extension SessionDetailViewController: UIPageViewControllerDelegate,UIPageViewControllerDataSource{
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

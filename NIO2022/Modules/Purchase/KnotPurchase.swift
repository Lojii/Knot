//
//  Purchase.swift
//  NIO2022
//
//  Created by LiuJie on 2022/4/10.
//

import UIKit
import StoreKit
import SwiftEntryKit
import Bugly

let PurchaseError = "PurchaseError"
let GROUPNAME = "group.lojii.nio.2022"

enum KnotProductType:String,CaseIterable {
    case HappyKnot = "knot.unlock" // 导出以及完全列表展示
}

class KnotProduct{
    var id:String = ""
    var name:String = ""
    var price:String = ""
    var description:String = ""
    var raw:Any?
    var rawIsSKProduct:Bool = true
}

class BuyView: UIView{
    
    lazy var indicator:UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView()
        indicator.startAnimating()
        indicator.hidesWhenStopped = false
        if #available(iOS 13.0, *) {
            indicator.style = .large
        } else {
            indicator.style = .whiteLarge
        }
        return indicator
    }()
    lazy var loadingView:UIView = {
        let lv = UIView()
        lv.addSubview(indicator)
        indicator.snp.makeConstraints { make in
            make.centerX.equalTo(lv.snp.centerX)
            make.centerY.equalTo(lv.snp.centerY)
            make.width.height.equalTo(50)
        }
        addSubview(lv)
        lv.snp.makeConstraints { make in
            make.left.equalToSuperview()
            make.top.equalToSuperview()
            make.bottom.equalToSuperview()
            make.right.equalToSuperview()
        }
        return lv
    }()
    var purchaseProduct:KnotProductType
    var product:KnotProduct?
    var completeHandle: (Bool) -> Void
    let infos = [
        "knot.unlock": [
            "name": "More Happy".localized,
            "msg": ["Full list access".localized,"Multi-format content export".localized]
        ]
    ]
    
    init(_ purchaseProduct:KnotProductType, completeHandle:@escaping (Bool) -> Void) {
        self.purchaseProduct = purchaseProduct
        self.completeHandle = completeHandle
        super.init(frame: CGRect.zero)
        backgroundColor = .white
        layer.cornerRadius = 10
        clipsToBounds = true

        loadData()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func loadData(){
        snp.makeConstraints { make in
            make.width.equalTo(SCREENWIDTH - LRSpacing * 2)
            make.height.equalTo(200)
        }
        showLoading(true)
        KnotPurchase.productInfo(purchaseProduct: purchaseProduct) { product in
            DispatchQueue.main.async{
            self.dismisssLoading()
            if((product) != nil){
                self.product = product
            }else{
                if #available(iOS 15.0, *) {
                    ZKProgressHUD.showMessage("Failed to get goods".localized)
                    self.completeHandle(false)
                    SwiftEntryKit.dismiss()
                    return
                }
                self.product = nil
            }
            self.setUI(self.purchaseProduct)
            }
        }
    }
    
    func setUI(_ purchaseProduct:KnotProductType){
        var suInfo:[String:Any]?
        if let suProduct = product {
            suInfo = infos[suProduct.id]
        }else{
            suInfo = infos[purchaseProduct.rawValue]
        }
        guard let info = suInfo else { return  }
        
        let closeBtn = UIButton()
        closeBtn.setImage(UIImage(named: "close-2"), for: .normal)
        addSubview(closeBtn)
        let nameLabel = UILabel()
        nameLabel.text =  info["name"] as? String
        nameLabel.textColor = ColorA
        nameLabel.font = Font18
        nameLabel.textAlignment = .center
        addSubview(nameLabel)
        let restoreBtn = UIButton()
        restoreBtn.setTitle("Restore".localized, for: .normal)
        restoreBtn.titleLabel?.font = Font16
        restoreBtn.setTitleColor(ColorC, for: .normal)
        addSubview(restoreBtn)
        nameLabel.snp.makeConstraints { make in
            make.centerX.equalTo(snp.centerX)
            make.top.equalTo(snp.top).offset(16)
        }
        closeBtn.snp.makeConstraints { make in
            make.centerY.equalTo(nameLabel.snp.centerY)
            make.left.equalTo(snp.left).offset(LRSpacing)
            make.width.height.equalTo(20)
        }
        restoreBtn.snp.makeConstraints { make in
            make.centerY.equalTo(nameLabel.snp.centerY)
            make.right.equalTo(snp.right).offset(-LRSpacing)
        }
        //
        var offY = 30
        var tmpV = nameLabel
        if let msgs = info["msg"] as? [String] {
            for msg in msgs {
                let msgLabel = UILabel()
                msgLabel.text = msg
                msgLabel.textColor = ColorB
                msgLabel.font = Font16
                msgLabel.numberOfLines = 0
                addSubview(msgLabel)
                msgLabel.snp.makeConstraints { make in
                    make.left.equalTo(snp.left).offset(LRSpacing)
                    make.right.equalTo(snp.right).offset(-LRSpacing)
                    make.top.equalTo(tmpV.snp.bottom).offset(offY)
                }
                offY = 15
                tmpV = msgLabel
            }
        }
        //
        let buyButton = UIButton()
        if product != nil {
            buyButton.setTitle("\("Buy".localized)(\(product!.price))", for: .normal)
        }else{
            buyButton.setTitle("\("Go to Buy".localized)", for: .normal)
        }
        
        buyButton.setTitleColor(ColorA, for: .normal)
        buyButton.backgroundColor = UIColor(red: 0.96, green: 0.91, blue: 0.41, alpha: 1)
        buyButton.layer.cornerRadius = 10
        buyButton.clipsToBounds = true
        addSubview(buyButton)
        buyButton.snp.makeConstraints { make in
            make.centerX.equalTo(snp.centerX)
            make.height.equalTo(50)
            make.width.equalTo(SCREENWIDTH - LRSpacing * 4)
            make.top.equalTo(tmpV.snp.bottom).offset(30)
        }
        snp.remakeConstraints { make in
            make.width.equalTo(SCREENWIDTH - LRSpacing * 2)
            make.bottom.equalTo(buyButton.snp.bottom).offset(20)
        }
        
        closeBtn.addTarget(self, action: #selector(close), for: .touchUpInside)
        restoreBtn.addTarget(self, action: #selector(restore), for: .touchUpInside)
        buyButton.addTarget(self, action: #selector(buy), for: .touchUpInside)
    }
    
    func showLoading(_ isWhite:Bool = false){
        loadingView.isHidden = false
        if isWhite {
            loadingView.backgroundColor = .white
            indicator.color = .gray
        }else{
            loadingView.backgroundColor = UIColor(redValue: 0, green: 0, blue: 0, alpha: 0.3)
            indicator.color = .white
        }
        bringSubviewToFront(loadingView)
    }
    
    func dismisssLoading(){
        self.loadingView.isHidden = true
    }
    
    @objc func close(){
        completeHandle(false)
        SwiftEntryKit.dismiss()
    }
    
    @objc func restore(){
        showLoading()
        KnotPurchase.restore(purchaseProduct: purchaseProduct) { res in
            DispatchQueue.main.async{
            self.dismisssLoading()
            if(res){ SwiftEntryKit.dismiss() }
            self.completeHandle(res)
            }
        }
    }
    
    @objc func buy(){
        showLoading()
        if #available(iOS 15.0, *) {
            if let p15 = product?.raw as? Product {
                KnotPurchase.pay15(product: p15, purchaseProduct: purchaseProduct) { res in
                    DispatchQueue.main.async{
                    self.dismisssLoading()
                    if(res){ SwiftEntryKit.dismiss() }
                    self.completeHandle(res)
                    }
                }
            }else{
                self.dismisssLoading()
                self.completeHandle(false)
            }
        } else {
            KnotPurchase.pay(purchaseProduct: purchaseProduct) { res in
                DispatchQueue.main.async{
                self.dismisssLoading()
                if(res){ SwiftEntryKit.dismiss() }
                self.completeHandle(res)
                }
            }
        }
    }
}

class KnotPurchase: NSObject {
    
    static func productLocalPrice(_ product:SKProduct) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = product.priceLocale
        return formatter.string(from: product.price) ?? ""
    }
    
    // 检查，并展示商品购买pop视图
    static func check(_ purchaseProduct:KnotProductType, completeHandle:@escaping (Bool) -> Void){
//        showStoreView(purchaseProduct, completeHandle: completeHandle)
//        return
        if hasProduct(purchaseProduct) {
            completeHandle(true)
        }else{
            showStoreView(purchaseProduct, completeHandle: completeHandle)
        }
    }
    
    static func check(_ purchaseProduct:KnotProductType) -> Bool {
        return hasProduct(purchaseProduct)
    }
    //
    static func showStoreView(_ purchaseProduct:KnotProductType, completeHandle:@escaping (Bool) -> Void){
        var attributes = EKAttributes.bottomFloat
        attributes.entryBackground = .gradient(gradient: .init(colors: [EKColor(.red), EKColor(.green)], startPoint: .zero, endPoint: CGPoint(x: 1, y: 1)))
        attributes.popBehavior = .animated(animation: .init(translate: .init(duration: 0.3), scale: .init(from: 1, to: 0.7, duration: 0.7)))
        attributes.shadow = .active(with: .init(color: .black, opacity: 0.5, radius: 10, offset: .zero))
        attributes.scroll = .enabled(swipeable: false, pullbackAnimation: .jolt)
        attributes.entryInteraction = .absorbTouches
        attributes.screenInteraction = .absorbTouches
        attributes.entryBackground = .color(color: .standardContent)
        attributes.screenBackground = .color(color: EKColor(UIColor(white: 0.5, alpha: 0.5)))
        attributes.displayDuration = .infinity
        
        SwiftEntryKit.display(entry: BuyView(purchaseProduct, completeHandle: completeHandle), using: attributes)
    }
    
    // 是否已购买
    static func hasProduct(_ purchaseProduct:KnotProductType) -> Bool {
        let gud = UserDefaults(suiteName: GROUPNAME)
        if let value = gud?.string(forKey: purchaseProduct.rawValue) {
            if value.contains(purchaseProduct.rawValue) {
                return true
            }
        }
        return false
    }
    
    // 购买、恢复成功后,设置UserDefaults
    static func paySuccess(_ purchaseProduct:KnotProductType){
        DispatchQueue.main.async {
            let gud = UserDefaults(suiteName: GROUPNAME)
            gud?.set(purchaseProduct.rawValue + Date().fullSting, forKey: purchaseProduct.rawValue) // rawValue.md5 + deviceID + UDID + time + yan 加密 ?
            gud?.synchronize()
        }
    }
    
    // 购买、恢复失败后，设置UserDefaults
    static func payFailed(_ purchaseProduct:KnotProductType){
        DispatchQueue.main.async {
            let gud = UserDefaults(suiteName: GROUPNAME)
            gud?.removeObject(forKey: purchaseProduct.rawValue)
            gud?.synchronize()
        }
    }
    
    // 初始化
    static func initPurchase(){
        paySuccess(.HappyKnot)
//        if #available(iOS 15.0, *) {
//            Mercato.listenForTransactions(finishAutomatically: false) { transaction in
//                await transaction.finish()
//            }
//        }
    }
    @available(iOS 15.0, *)
    static func pay15(product:Product,purchaseProduct:KnotProductType,completeHandle:@escaping (Bool) -> Void) {
        Task.detached {
            do{
                try await Mercato.purchase(product: product, quantity: 1, finishAutomatically: false, appAccountToken: nil, simulatesAskToBuyInSandbox: false)
                paySuccess(purchaseProduct)
                completeHandle(true)
            }catch{
                payFailed(purchaseProduct)
                completeHandle(false)
                DispatchQueue.main.async {ZKProgressHUD.showMessage("failure")}
            }
        }
    }
    static func pay(purchaseProduct:KnotProductType,completeHandle:@escaping (Bool) -> Void) {
        InAppPurchases.purchaseProduct(productIdentifier: purchaseProduct.rawValue) { success in
            print(success)
            if success {
                print("Purchase Success: \(purchaseProduct.rawValue)")
                paySuccess(purchaseProduct)
                completeHandle(true)
            }else{
                payFailed(purchaseProduct)
                completeHandle(false)
                ZKProgressHUD.showMessage("failure")
            }
        }
    }
    // 恢复购买,定期执行？
    static func restore(purchaseProduct:KnotProductType?, completeHandle: ((Bool) -> Void)?){
//
        if #available(iOS 15.0, *) {
            Task.detached{
                do{
                    var flag = false
                    try await Mercato.restorePurchases()
                    for await result in Transaction.currentEntitlements {
                        if case let .verified(transaction) = result {
                            let pId = transaction.productID
                            if let pType = KnotProductType(rawValue: pId) {
                                if pType == purchaseProduct { flag = true }
                                paySuccess(pType)
                            }else{
                                print("未知商品，可能需要升级！")
                            }
                        }
                    }
                    print("恢复完成")
                    if purchaseProduct != nil {
                        if((completeHandle) != nil){ completeHandle!(flag) }
                    }else{
                        if((completeHandle) != nil){ completeHandle!(true) }
                    }
                }catch let error{
                    print("恢复失败")
                    if((completeHandle) != nil){ completeHandle!(false) }
                    DispatchQueue.main.async {
                        if "\(error)" == "unknown" {
                            ZKProgressHUD.showMessage("Unknown error, Please try again later")
                        }
//                        let str = error.localizedDescription
//                        ZKProgressHUD.showMessage(error.localizedDescription)
//                        VisualActivityViewController.share(text: error.localizedDescription + "-" + str + "-" + "\(error)", on: UIApplication.topViewController()!)
                    }
                }
            }
        }else{
            InAppPurchases.restorePurchase() { productIdentifiers, error  in
                if productIdentifiers.count > 0 {
                    var flag = false
                    for p in productIdentifiers {
                        if let pType = KnotProductType(rawValue: p) {
                            if pType == purchaseProduct { flag = true }
                            paySuccess(pType)
                        }else{
                            print("未知商品，可能需要升级！")
                        }
                    }
                    print("Restore Success: \(productIdentifiers)")
                    if purchaseProduct != nil {
                        if((completeHandle) != nil){ completeHandle!(flag) }
                    }else{
                        if((completeHandle) != nil){ completeHandle!(true) }
                    }
                }else {
                    print("Nothing to Restore")
                    if((completeHandle) != nil){
                        completeHandle!(false)
                    }
                }
//                if error != nil {
//                    let str = error.debugDescription
//                    ZKProgressHUD.showMessage(error!.localizedDescription)
//                    VisualActivityViewController.share(text: error!.localizedDescription + "---" + str + "---" + "\(error!)", on: UIApplication.topViewController()!)
//                }
            }
        }
    }
    @available(iOS 15.0, *)
    static func productInfo15(purchaseProduct:KnotProductType, completeHandle:@escaping (KnotProduct?) -> Void){
        Task.detached {
            do{
                let productIds: Set<String> = [purchaseProduct.rawValue]
                let products = try await Mercato.retrieveProducts(productIds: productIds)
                if products.count > 0 {
                    let product = products[0]
                    let knotP = KnotProduct()
                    knotP.id = product.id
                    knotP.name = product.displayName
                    knotP.price = product.displayPrice
                    knotP.description = product.description
                    knotP.raw = product
                    knotP.rawIsSKProduct = false
                    print("Product: \(knotP.name)-\(knotP.description), price: \(knotP.price)")
                    completeHandle(knotP)
                }else{
                    completeHandle(nil)
                }
            }catch{
                completeHandle(nil)
            }
        }
    }
    // 获取商品信息
    static func productInfo(purchaseProduct:KnotProductType, completeHandle:@escaping (KnotProduct?) -> Void){
        if #available(iOS 15.0, *) {
            productInfo15(purchaseProduct: purchaseProduct, completeHandle: completeHandle)
        }else{
            InAppPurchases.requestProducts([purchaseProduct.rawValue]) { products in
                if let ps = products, ps.count > 0 {
                    let knotP = KnotProduct()
                    knotP.id = purchaseProduct.rawValue
                    knotP.name = ps.first!.localizedTitle
                    knotP.price = KnotPurchase.productLocalPrice(ps.first!)
                    knotP.description = ps.first!.localizedDescription
                    knotP.raw = ps.first!
                    knotP.rawIsSKProduct = true
                    print("Product: \(knotP.name)-\(knotP.description), price: \(knotP.price)")
                    completeHandle(knotP)
                    return
                }
                Bugly.reportException(withCategory: 6, name: PurchaseError,
                                      reason: "static func productInfo Error: \(purchaseProduct.rawValue)",
                                      callStack: [],
                                      extraInfo: [PurchaseError:""],
                                      terminateApp: false)
                completeHandle(nil)
            }
        }
    }

}

public extension UIApplication {
    class func topViewController(controller: UIViewController? = UIApplication.shared.keyWindow?.rootViewController) -> UIViewController? {
        if let navigationController = controller as? UINavigationController {
            return topViewController(controller: navigationController.visibleViewController)
        }
        if let tabController = controller as? UITabBarController {
            if let selected = tabController.selectedViewController {
                return topViewController(controller: selected)
            }
        }
        if let presented = controller?.presentedViewController {
            return topViewController(controller: presented)
        }
        return controller
    }
}

//
//  HomeVC.swift
//  NIO2022
//
//  Created by LiuJie on 2022/3/25.
//

import Foundation
import UIKit
import SnapKit
//import SwiftyStoreKit

class HomeVC: UIViewController {
    
//    var launchButton:LaunchButton?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        view.backgroundColor = .white
//        setUI()
        
        let fullWH = UIScreen.main.bounds.size
        let btn = UIButton(frame: CGRect(x: (fullWH.width - 200) / 2, y: 200, width: 200, height: 200))
        btn.setTitle("Run", for: .normal)
        btn.backgroundColor = .green
        btn.titleLabel?.textColor = .white
        btn.addTarget(self, action: #selector(startVPN), for: .touchUpInside)
//        btn.addTarget(self, action: #selector(buy), for: .touchUpInside)
//        btn.addTarget(self, action: #selector(restore), for: .touchUpInside)
        view.addSubview(btn)
        
//        SwiftyStoreKit.completeTransactions(atomically: true) { purchases in
//            for purchase in purchases {
//                switch purchase.transaction.transactionState {
//                case .purchased, .restored:
//                    if purchase.needsFinishTransaction {
//                        // Deliver content from server, then:
//                        SwiftyStoreKit.finishTransaction(purchase.transaction)
//                    }
//                    // Unlock content
//                case .failed, .purchasing, .deferred:
//                    break // do nothing
//                @unknown default:
//                    break
//                }
//            }
//        }
    }
    
    func setUI() -> Void {
//        launchButton = LaunchButton(frame: CGRect.zero);
//        view.addSubview(launchButton!)
//
//        launchButton?.snp.makeConstraints({ make in
////            make.width.
//        })
        
    }
    // 获取商品列表
    @objc func startVPN(){
//        SwiftyStoreKit.retrieveProductsInfo(["knot.01"]) { result in
//            if let product = result.retrievedProducts.first {
//                let name = product.localizedTitle
//                let priceString = product.localizedPrice!
//                print("Product: \(name)-\(product.localizedDescription), price: \(priceString)")
//            }
//            else if let invalidProductId = result.invalidProductIDs.first {
//                print("Invalid product identifier: \(invalidProductId)")
//            }
//            else {
//                print("Error: \(result.error.debugDescription)")
//            }
//        }
    }
    // 购买
    @objc func buy(){
//        SwiftyStoreKit.purchaseProduct("knot.01", quantity: 1, atomically: true) { result in
//            switch result {
//            case .success(let purchase):
//                print("Purchase Success: \(purchase.productId)")
//            case .error(let error):
//                switch error.code {
//                case .unknown: print("Unknown error. Please contact support")
//                case .clientInvalid: print("Not allowed to make the payment")
//                case .paymentCancelled: break
//                case .paymentInvalid: print("The purchase identifier was invalid")
//                case .paymentNotAllowed: print("The device is not allowed to make the payment")
//                case .storeProductNotAvailable: print("The product is not available in the current storefront")
//                case .cloudServicePermissionDenied: print("Access to cloud service information is not allowed")
//                case .cloudServiceNetworkConnectionFailed: print("Could not connect to the network")
//                case .cloudServiceRevoked: print("User has revoked permission to use this cloud service")
//                default: print((error as NSError).localizedDescription)
//                }
//            }
//        }
    }
    // 恢复购买
    @objc func restore(){
//        SwiftyStoreKit.restorePurchases(atomically: true) { results in
//            if results.restoreFailedPurchases.count > 0 {
//                print("Restore Failed: \(results.restoreFailedPurchases)")
//            }
//            else if results.restoredPurchases.count > 0 {
//                print("Restore Success: \(results.restoredPurchases)")
//            }
//            else {
//                print("Nothing to Restore")
//            }
//        }
    }
    
    @objc func stop(){
        
    }
    
    @objc func showDir(){
        
    }
    
    
    deinit {
        
    }
    
}

//
//  IAPHandler.swift
//  InAppPurchases-Generic
//
//  Created by uMmaRr on 11/01/2022.
//

import Foundation
import StoreKit


extension SKProduct {
  public func localizedPrice() -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .currency
    formatter.locale = self.priceLocale
    return formatter.string(from: self.price) ?? ""
  }
}


internal let IAP = IAPHandler.sharedInstance

internal typealias ProductIdentifier = String
internal typealias ProductWithExpireDate = [ProductIdentifier: Date]

internal typealias ProductsRequestHandler = (_ response: SKProductsResponse?, _ error: Error?) -> ()
internal typealias PurchaseHandler = (_ productIdentifier: ProductIdentifier?, _ error: Error?) -> ()
internal typealias RestoreHandler = (_ productIdentifiers: Set<ProductIdentifier>, _ error: Error?) -> ()
internal typealias ValidateHandler = (_ statusCode: Int?, _ products: ProductWithExpireDate?, _ json: [String: Any]?) -> ()

internal class IAPHandler: NSObject {
  
  private override init() {
    super.init()
    
    addObserver()
  }
  internal static let sharedInstance = IAPHandler()
  
  fileprivate var productsRequest: SKProductsRequest?
  fileprivate var productsRequestHandler: ProductsRequestHandler?
  
  fileprivate var purchaseHandler: PurchaseHandler?
  fileprivate var restoreHandler: RestoreHandler?
  
  private var observerAdded = false
  
  internal func addObserver() {
    if !observerAdded {
      observerAdded = true
      SKPaymentQueue.default().add(self)
    }
  }
  
  internal func removeObserver() {
    if observerAdded {
      observerAdded = false
      SKPaymentQueue.default().remove(self)
    }
  }
}

// MARK: StoreKit API
extension IAPHandler {
  
  internal func requestProducts(_ productIdentifiers: Set<ProductIdentifier>, handler: @escaping ProductsRequestHandler) {
    productsRequest?.cancel()
    productsRequestHandler = handler
    
    productsRequest = SKProductsRequest(productIdentifiers: productIdentifiers)
    productsRequest?.delegate = self
    productsRequest?.start()
  }
  
  internal func purchaseProduct(_ productIdentifier: ProductIdentifier, handler: @escaping PurchaseHandler) {
    purchaseHandler = handler
    
    let payment = SKMutablePayment()
    payment.productIdentifier = productIdentifier
    SKPaymentQueue.default().add(payment)
  }
  
  internal func restorePurchases(_ handler: @escaping RestoreHandler) {
    restoreHandler = handler
    SKPaymentQueue.default().restoreCompletedTransactions()
  }
  
  /*
   * password: Only used for receipts that contain auto-renewable subscriptions.
   *           It's your app’s shared secret (a hexadecimal string) which was generated on iTunesConnect.
   */
  internal func validateReceipt(_ password: String? = nil, handler: @escaping ValidateHandler) {
    validateReceiptInternal(true, password: password) { (statusCode, products, json) in
      
      if let statusCode = statusCode , statusCode == ReceiptStatus.testReceipt.rawValue {
        self.validateReceiptInternal(false, password: password, handler: { (statusCode, products, json) in
          handler(statusCode, products, json)
        })
        
      } else {
        handler(statusCode, products, json)
      }
    }
  }
}

// MARK: SKProductsRequestDelegate
extension IAPHandler: SKProductsRequestDelegate {
  public func productsRequest(_ request: SKProductsRequest, didReceive response: SKProductsResponse) {
    productsRequestHandler?(response, nil)
    clearRequestAndHandler()
  }
  
  public func request(_ request: SKRequest, didFailWithError error: Error) {
    productsRequestHandler?(nil, error)
    clearRequestAndHandler()
  }
  
  private func clearRequestAndHandler() {
    productsRequest = nil
    productsRequestHandler = nil
  }
}

// MARK: SKPaymentTransactionObserver
extension IAPHandler: SKPaymentTransactionObserver {
  
  public func paymentQueue(_ queue: SKPaymentQueue, updatedTransactions transactions: [SKPaymentTransaction]) {
    for transaction in transactions {
      switch (transaction.transactionState) {

      case SKPaymentTransactionState.purchased:
        completePurchaseTransaction(transaction)
        
      case SKPaymentTransactionState.restored:
        finishTransaction(transaction)
        
      case SKPaymentTransactionState.failed:
        failedTransaction(transaction)
        
      case SKPaymentTransactionState.purchasing,
           SKPaymentTransactionState.deferred:
        break
          
      @unknown default:
          failedTransaction(transaction)
      }
    }
  }
  
  public func paymentQueueRestoreCompletedTransactionsFinished(_ queue: SKPaymentQueue) {
    completeRestoreTransactions(queue, error: nil)
  }
  
  public func paymentQueue(_ queue: SKPaymentQueue, restoreCompletedTransactionsFailedWithError error: Error) {
    completeRestoreTransactions(queue, error: error)
  }
  
  private func completePurchaseTransaction(_ transaction: SKPaymentTransaction) {
    purchaseHandler?(transaction.payment.productIdentifier, transaction.error)
    purchaseHandler = nil
    
    finishTransaction(transaction)
  }
  
  private func completeRestoreTransactions(_ queue: SKPaymentQueue, error: Error?) {
    var productIdentifiers = Set<ProductIdentifier>()
    
    for transaction in queue.transactions {
      if let productIdentifier = transaction.original?.payment.productIdentifier {
        productIdentifiers.insert(productIdentifier)
      }
      
      finishTransaction(transaction)
    }
    
    restoreHandler?(productIdentifiers, error)
    restoreHandler = nil
  }
  
  private func failedTransaction(_ transaction: SKPaymentTransaction) {
    // NOTE: Both purchase and restore may come to this state. So need to deal with both handlers.
    
    purchaseHandler?(nil, transaction.error)
    purchaseHandler = nil
    
    restoreHandler?(Set<ProductIdentifier>(), transaction.error)
    restoreHandler = nil
    
    finishTransaction(transaction)
  }
  
  // MARK: Helper
  
  private func finishTransaction(_ transaction: SKPaymentTransaction) {
    switch transaction.transactionState {
    case SKPaymentTransactionState.purchased,
         SKPaymentTransactionState.restored,
         SKPaymentTransactionState.failed:
      
      SKPaymentQueue.default().finishTransaction(transaction)
      
    default:
      break
    }
  }
}

// MARK: Validate Receipt
extension IAPHandler {
  
  fileprivate func validateReceiptInternal(_ isProduction: Bool, password: String?, handler: @escaping ValidateHandler) {
    
    let serverURL = isProduction
      ? "https://buy.itunes.apple.com/verifyReceipt"
      : "https://sandbox.itunes.apple.com/verifyReceipt"
    
    let appStoreReceiptURL = Bundle.main.appStoreReceiptURL
    guard let receiptData = receiptData(appStoreReceiptURL, password: password), let url = URL(string: serverURL) else {
      handler(ReceiptStatus.noRecipt.rawValue, nil, nil)
      return
    }
    
    let request = NSMutableURLRequest(url: url)
    request.httpMethod = "POST"
    request.httpBody = receiptData
    
    let task = URLSession.shared.dataTask(with: request as URLRequest) { (data, response, error) in
      
      guard let data = data, error == nil else {
        handler(nil, nil, nil)
        return
      }
      
      do {
        let json = try JSONSerialization.jsonObject(with: data, options:[]) as? [String: Any]
        
        let statusCode = json?["status"] as? Int
        let products = self.parseValidateResultJSON(json)
        handler(statusCode, products, json)
        
      } catch {
        handler(nil, nil, nil)
      }
    }
    task.resume()
  }
  
  internal func parseValidateResultJSON(_ json: [String: Any]?) -> ProductWithExpireDate? {
    
    var products = ProductWithExpireDate()
    var canceledProducts = ProductWithExpireDate()
    var productDateDict = [String: [ProductDateHelper]]()
    let dateOf5000 = Date(timeIntervalSince1970: 95617584000) // 5000-01-01
    
    var totalInAppPurchaseList = [[String: Any]]()
    if let receipt = json?["receipt"] as? [String: Any],
      let inAppPurchaseList = receipt["in_app"] as? [[String: Any]] {
      totalInAppPurchaseList += inAppPurchaseList
    }
    if let inAppPurchaseList = json?["latest_receipt_info"] as? [[String: Any]] {
      totalInAppPurchaseList += inAppPurchaseList
    }
    
    for inAppPurchase in totalInAppPurchaseList {
      if let productID = inAppPurchase["product_id"] as? String,
        let purchaseDate = parseDate(inAppPurchase["purchase_date_ms"] as? String) {
        
        let expiresDate = parseDate(inAppPurchase["expires_date_ms"] as? String)
        let cancellationDate = parseDate(inAppPurchase["cancellation_date_ms"] as? String)
        
        let productDateHelper = ProductDateHelper(purchaseDate: purchaseDate, expiresDate: expiresDate, canceledDate: cancellationDate)
        if productDateDict[productID] == nil {
          productDateDict[productID] = [productDateHelper]
        } else {
          productDateDict[productID]?.append(productDateHelper)
        }
        
        if let cancellationDate = cancellationDate {
          if let lastCanceledDate = canceledProducts[productID] {
            if lastCanceledDate.timeIntervalSince1970 < cancellationDate.timeIntervalSince1970 {
              canceledProducts[productID] = cancellationDate
            }
          } else {
            canceledProducts[productID] = cancellationDate
          }
        }
      }
    }
    
    for (productID, productDateHelpers) in productDateDict {
      var date = Date(timeIntervalSince1970: 0)
      let lastCanceledDate = canceledProducts[productID]
      
      for productDateHelper in productDateHelpers {
        let validDate = productDateHelper.getValidDate(lastCanceledDate: lastCanceledDate, unlimitedDate: dateOf5000)
        if date.timeIntervalSince1970 < validDate.timeIntervalSince1970 {
          date = validDate
        }
      }
      
      products[productID] = date
    }
    
    return products.isEmpty ? nil : products
  }

  private func receiptData(_ appStoreReceiptURL: URL?, password: String?) -> Data? {
    guard let receiptURL = appStoreReceiptURL, let receipt = try? Data(contentsOf: receiptURL) else {
        return nil
    }
    
    do {
      let receiptData = receipt.base64EncodedString()
      var requestContents = ["receipt-data": receiptData]
      if let password = password {
        requestContents["password"] = password
      }
      let requestData = try JSONSerialization.data(withJSONObject: requestContents, options: [])
      return requestData
      
    } catch let error {
      NSLog("\(error)")
    }
    
    return nil
  }
  
  private func parseDate(_ str: String?) -> Date? {
    guard let str = str, let msTimeInterval = TimeInterval(str) else {
      return nil
    }
    
    return Date(timeIntervalSince1970: msTimeInterval / 1000)
  }
}

internal struct ProductDateHelper {
  var purchaseDate = Date(timeIntervalSince1970: 0)
  var expiresDate: Date? = nil
  var canceledDate: Date? = nil
  
  func getValidDate(lastCanceledDate: Date?, unlimitedDate: Date) -> Date {
    if let lastCanceledDate = lastCanceledDate {
      return (purchaseDate.timeIntervalSince1970 > lastCanceledDate.timeIntervalSince1970)
        ? (expiresDate ?? unlimitedDate)
        : lastCanceledDate
    }
    
    if let canceledDate = canceledDate {
      return canceledDate
    } else if let expiresDate = expiresDate {
      return expiresDate
    } else {
      return unlimitedDate
    }
  }
}

internal enum ReceiptStatus: Int {
  case noRecipt = -999
  case valid = 0
  case testReceipt = 21007
}

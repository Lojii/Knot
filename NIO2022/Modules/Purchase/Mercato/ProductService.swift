//
//  File.swift
//  
//
//  Created by Pavel Tikhonenko on 09.10.2021.
//

import Foundation
import StoreKit

@available(iOS 15.0, *)
class ProductService
{

    private var cachedProducts: [Product] = []
	
	@MainActor
	public func retrieveProducts(productIds: Set<String>) async throws -> [Product]
	{
		do
		{
            if checkProductIdsMatchingCachedIds(productIds) {
                return cachedProducts
            }
			let products = try await Product.products(for: productIds)
			cachedProducts = products
            
			return products
		} catch {
			throw MercatoError.storeKit(error: error as! StoreKitError)
		}
	}
	
	func isPurchased(_ product: Product) async throws -> Bool
	{
		return try await isPurchased(product.id)
	}
	
	func isPurchased(_ productIdentifier: String) async throws -> Bool
	{
		guard let result = await Transaction.latest(for: productIdentifier) else
		{
			return false
		}
		
		let transaction = try checkVerified(result)
		return transaction.revocationDate == nil && !transaction.isUpgraded
	}
}


@available(iOS 15.0, *)
private extension ProductService
{
    func checkProductIdsMatchingCachedIds(_ productIds: Set<String>) -> Bool {
        if cachedProducts.isEmpty {
            return false
        }
        
        let cachedProductIds = Set(cachedProducts.map(\.id))
        return cachedProductIds == productIds
    }
}

//
//  File.swift
//  
//
//  Created by Pavel Tikhonenko on 09.10.2021.
//


import StoreKit

@available(iOS 15.0, *)
public struct Purchase
{
	public let product: Product
	public let transaction: Transaction
	public let needsFinishTransaction: Bool
}

@available(iOS 15.0, *)
extension Purchase
{
	var productId: String
	{
		transaction.productID
	}
	
	var quantity: Int
	{
		transaction.purchasedQuantity
	}
	
	func finish() async
	{
		await transaction.finish()
	}
}

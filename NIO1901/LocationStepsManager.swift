////
////  LocationStepsManager.swift
////  NIO1901
////
////  Created by LiuJie on 2019/4/22.
////  Copyright © 2019 Lojii. All rights reserved.
////
//
//import UIKit
//import CoreLocation
//
//class LocationStepsManager: NSObject {
//    private override init() {
//        super.init()
//    }
//
//    public static let shared = LocationStepsManager()
//    /// 定位服务必须设置为全局变量
//    let locationManager = CLLocationManager()
//
//    fileprivate var currentLocation: CLLocationCoordinate2D? {
//        didSet {
//            startWork()
//        }
//    }
//    fileprivate var currentStepCount: Int = 0
//
//    fileprivate var isAllowWork: Bool = false
//
//    /// 时间间隔
//    fileprivate let storeTimeInterval: TimeInterval = 120.0
//    fileprivate let uploadTimeInterval: TimeInterval = 120.0
//
//    /// 请求后台持续GPS定位服务
//    func availableLocationService() {
//        let locationServicesEnabled = CLLocationManager.locationServicesEnabled()
//        guard locationServicesEnabled else {
//            print("您的定位服务已关闭")
//            return
//        }
//
//        let status = CLLocationManager.authorizationStatus()
//
//        switch status {
//        case .authorizedAlways, .notDetermined, .authorizedWhenInUse:
//            startLocation()
//        default:
//            print("无法获得您的持续定位权限")
//        }
//    }
//
//    /// 开始定位
//    fileprivate func startLocation() {
//        locationManager.distanceFilter = 10
//        locationManager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
//        locationManager.delegate = self
//        /// 首先请求总是访问权限
//        locationManager.requestAlwaysAuthorization()
//        /// 然后请求使用期间访问权限
//        locationManager.requestWhenInUseAuthorization()
//        /// 是否允许系统自动暂停位置更新服务，默认为 true，设置为 false，否则会自动暂停定位服务，app 20分钟后就不会上传位置了
//        locationManager.pausesLocationUpdatesAutomatically = false
//
//        if #available(iOS 9.0, *) {
//            // 如果APP处于后台,则会出现蓝条
//            locationManager.allowsBackgroundLocationUpdates = true
//        }
//        locationManager.startUpdatingLocation()
//    }
//
//    fileprivate func startWork() {
//        if !isAllowWork {
//            isAllowWork = true
//        }
//    }
//
//}
//
//// MARK: - CLLocationManagerDelegate
//extension LocationStepsManager: CLLocationManagerDelegate {
//    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
//        // WGS-84 坐标，GPS 原生数据
//        guard let coor = locations.last?.coordinate else { return }
////        print("WGS84:\(coor)")
//    }
//
//    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
//        print("定位失败")
//    }
//}

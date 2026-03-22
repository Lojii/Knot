//
//  AppNotification.swift
//  TunnelServices
//
//  Type-safe notification names, replacing scattered string-based NSNotification.Name.
//

import Foundation

public enum AppNotification {

    // MARK: - Task Lifecycle

    public static let taskDidChanged = NSNotification.Name("TaskDidChangedNotification")
    public static let taskValueDidChanged = "TaskValueDidChanged"
    public static let taskConfigDidChanged = "TaskConfigDidChanged"

    // MARK: - Network

    public static let networkChanged = NSNotification.Name("NetWorkChangedNoti")
    public static let localHTTPServerChanged = NSNotification.Name("LocalHTTPServerChanged")

    // MARK: - History & UI

    public static let historyTaskDidChanged = NSNotification.Name("HistoryTaskDidChanged")
    public static let hideKeyboard = NSNotification.Name("HidenKeyBoradNoti")

    // MARK: - Rule

    public static let currentRuleListChange = NSNotification.Name("CurrentRuleListChange")
    public static let currentSelectedRuleChanged = NSNotification.Name("CurrentSelectedRuleChanged")
    public static let currentRuleDidChange = NSNotification.Name("CurrentRuleDidChange")

    // MARK: - Search

    public static let searchHistoryDidUpdate = NSNotification.Name("SearchHistoryDidUpdateNoti")
}

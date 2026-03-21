//
//  HelperWindow.swift
//  KnotHelper
//
//  Copyright © 2026 Lojii. All rights reserved.
//

import SwiftUI

struct HelperWindow: View {
    @ObservedObject var vm: HelperViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {

            // MARK: Status row
            HStack(spacing: 8) {
                Circle()
                    .fill(vm.isRunning ? Color.green : Color.gray)
                    .frame(width: 10, height: 10)
                Text(vm.statusText)
                    .font(.headline)
                Spacer()
            }

            Divider()

            // MARK: Forwarding options
            Toggle("Forward TCP", isOn: $vm.forwardTCP)
                .onChange(of: vm.forwardTCP) { _ in vm.commitConfig() }
            Toggle("Forward UDP", isOn: $vm.forwardUDP)
                .onChange(of: vm.forwardUDP) { _ in vm.commitConfig() }

            // MARK: Port
            HStack {
                Text("Port:")
                TextField("9090", text: $vm.portText)
                    .frame(width: 70)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { vm.commitConfig() }
            }

            Divider()

            // MARK: Enable / Disable button
            Button(vm.isRunning ? "Disable" : "Enable") {
                vm.toggleEnabled()
            }
            .buttonStyle(.borderedProminent)
            .tint(vm.isRunning ? .red : .accentColor)
            .frame(maxWidth: .infinity)

            // MARK: Main app status
            HStack(spacing: 6) {
                Circle()
                    .fill(vm.mainAppRunning ? Color.green : Color.gray)
                    .frame(width: 8, height: 8)
                Text(vm.mainAppRunning ? "Knot is running" : "Knot is not running")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(16)
        .frame(width: 280)
    }
}

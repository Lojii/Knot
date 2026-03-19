import SwiftUI

/// Chat-style message bubble for WebSocket frames and gRPC messages
public struct MessageBubble: View {
    let text: String
    let isOutbound: Bool  // true = client→server (right), false = server→client (left)
    let timestamp: String
    let type: String       // "text", "binary", "close", etc.

    public init(text: String, isOutbound: Bool, timestamp: String, type: String = "text") {
        self.text = text
        self.isOutbound = isOutbound
        self.timestamp = timestamp
        self.type = type
    }

    public var body: some View {
        HStack {
            if isOutbound { Spacer(minLength: 40) }

            VStack(alignment: isOutbound ? .trailing : .leading, spacing: 2) {
                Text(text)
                    .font(.system(size: 12, design: .monospaced))
                    .padding(8)
                    .background(isOutbound ? Color.green.opacity(0.15) : Color.gray.opacity(0.15))
                    .cornerRadius(10)
                    .textSelection(.enabled)

                HStack(spacing: 4) {
                    if type != "text" {
                        Text(type.uppercased())
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(.orange)
                    }
                    Text(timestamp)
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }
            }

            if !isOutbound { Spacer(minLength: 40) }
        }
    }
}

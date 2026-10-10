import SwiftUI

/// Full-width takeover shown in the notch while a call is ringing. Sits below
/// the physical notch and offers Accept / Decline without leaving the notch.
struct CallCardView: View {
    let call: IncomingCall
    let notchHeight: CGFloat
    var onAccept: () -> Void
    var onDecline: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: notchHeight)

            HStack(spacing: 12) {
                avatar

                VStack(alignment: .leading, spacing: 2) {
                    Text(call.callerName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text("Incoming \(call.appName) call")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                HStack(spacing: 8) {
                    if call.canDecline {
                        Button(action: onDecline) {
                            Label("Decline", systemImage: "phone.down.fill")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(Capsule().fill(Color.red.opacity(0.85)))
                        }
                        .buttonStyle(.plain)
                    }

                    if call.canAccept {
                        Button(action: onAccept) {
                            Label("Accept", systemImage: "phone.fill")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.black)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 7)
                                .background(Capsule().fill(Color.green))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)
        }
    }

    private var avatar: some View {
        ZStack {
            Circle().fill(Color.white.opacity(0.12))
            Text(initials)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(width: 38, height: 38)
    }

    private var initials: String {
        let letters = call.callerName
            .split(separator: " ")
            .prefix(2)
            .compactMap { $0.first }
        return letters.isEmpty ? "?" : String(letters).uppercased()
    }
}

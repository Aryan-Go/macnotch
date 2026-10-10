import SwiftUI

/// The WhatsApp tab: a compact conversation browser with a quick-reply composer.
struct WhatsAppView: View {
    @ObservedObject var model: WhatsAppModel

    var body: some View {
        HStack(spacing: 12) {
            chatList
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(width: 1)
            conversation
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
    }

    // MARK: - Chat list

    private var chatList: some View {
        VStack(alignment: .leading, spacing: 6) {
            header("Chats")
            if !model.isAvailable {
                note("Open WhatsApp once, then reopen the notch.")
            } else if model.chats.isEmpty {
                note("No conversations found.")
            } else {
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(model.chats) { chat in
                            chatRow(chat)
                        }
                    }
                }
            }
        }
        .frame(width: 200, alignment: .leading)
    }

    private func chatRow(_ chat: WhatsAppChat) -> some View {
        let isSelected = chat.id == model.selected?.id
        return Button {
            model.select(chat)
        } label: {
            HStack(spacing: 8) {
                ZStack {
                    Circle().fill(Color.white.opacity(0.12))
                    Text(initial(chat.name))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                }
                .frame(width: 26, height: 26)

                VStack(alignment: .leading, spacing: 1) {
                    Text(chat.name)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.95))
                        .lineLimit(1)
                    Text(chat.lastMessage.isEmpty ? "—" : chat.lastMessage)
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.45))
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                if chat.unread > 0 {
                    Text("\(chat.unread)")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color.green))
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.white.opacity(isSelected ? 0.14 : 0))
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Conversation

    private var conversation: some View {
        VStack(alignment: .leading, spacing: 8) {
            header(model.selected?.name ?? "Messages")

            if model.selected == nil {
                note("Pick a conversation to reply.")
                Spacer()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(model.messages) { message in
                            bubble(message)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: .infinity)

                composer
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func bubble(_ message: WhatsAppMessage) -> some View {
        HStack {
            if message.isFromMe { Spacer(minLength: 40) }
            Text(message.text)
                .font(.system(size: 11))
                .foregroundStyle(message.isFromMe ? .black : .white.opacity(0.9))
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(message.isFromMe ? Color.green.opacity(0.85) : Color.white.opacity(0.12))
                )
            if !message.isFromMe { Spacer(minLength: 40) }
        }
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let note = model.note {
                Text(note)
                    .font(.system(size: 10))
                    .foregroundStyle(.orange.opacity(0.9))
            }

            HStack(spacing: 8) {
                TextField(model.canReply ? "Message" : "Open WhatsApp to reply", text: $model.draft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.white.opacity(0.1))
                    )
                    .disabled(!model.canReply)
                    .onSubmit { model.send() }

                Button {
                    model.send()
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.black)
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(Color.green))
                }
                .buttonStyle(.plain)
                .disabled(!model.canReply || model.draft.trimmingCharacters(in: .whitespaces).isEmpty)
                .opacity(model.canReply ? 1 : 0.4)
            }

            if !Permissions.hasAccessibility {
                Button {
                    Permissions.requestAccessibility()
                    Permissions.openAccessibilitySettings()
                } label: {
                    Text("Grant Accessibility to send from the notch")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.orange.opacity(0.9))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Shared bits

    private func header(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .tracking(0.6)
            .foregroundStyle(.white.opacity(0.4))
            .lineLimit(1)
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(.white.opacity(0.45))
            .fixedSize(horizontal: false, vertical: true)
    }

    private func initial(_ name: String) -> String {
        name.first.map { String($0).uppercased() } ?? "?"
    }
}

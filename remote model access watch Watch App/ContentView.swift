import SwiftUI
import WatchKit

struct Message: Identifiable, Codable, Equatable {
    var id = UUID()
    let content: String
    let isUser: Bool

    static func == (lhs: Message, rhs: Message) -> Bool {
        return lhs.id == rhs.id &&
               lhs.content == rhs.content &&
               lhs.isUser == rhs.isUser
    }
}

struct SettingsView: View {
    @Binding var serverEndpoint: String
    @Binding var apiKey: String
    @Binding var modelLabel: String
    @Binding var modelRequestName: String
    @Environment(\.dismiss) var dismiss

    var body: some View {
        Form {
            Section("Model") {
                TextField("Model Label", text: $modelLabel)
                TextField("Model Request Name", text: $modelRequestName)
            }

            Section("API Configuration") {
                TextField("API Key (leave blank if self hosting)", text: $apiKey)
                TextField("Server Endpoint", text: $serverEndpoint)
            }

            Button("Done") {
                dismiss()
            }
        }
    }
}

struct ChatView: View {
    let messages: [Message]
    let modelLabel: String

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(messages) { message in
                        HStack(alignment: .center, spacing: 0) {
                            if message.isUser {
                                Spacer(minLength: 30)
                                Text(message.content)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 6)
                                    .background(Color.blue.opacity(0.2))
                                    .cornerRadius(12)
                                    .padding(.trailing, 4)
                            } else {
                                Text(message.content.trimmingCharacters(in: .whitespacesAndNewlines))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 6)
                                    .background(Color.gray.opacity(0.2))
                                    .cornerRadius(12)
                                    .padding(.leading, 4)
                                Spacer(minLength: 30)
                            }
                        }
                        .id(message.id)
                    }
                }
                .padding(.horizontal, 2)
                .onChange(of: messages.count) { _, _ in
                    if let lastMessage = messages.last {
                        withAnimation {
                            proxy.scrollTo(lastMessage.id, anchor: .bottom)
                        }
                    }
                }
            }
            .padding(.bottom, 2)
        }
    }
}

struct ContentView: View {
    @AppStorage("messages") private var messagesData: Data = Data()
    @AppStorage("modelLabel") private var modelLabel: String = ""
    @AppStorage("modelRequestName") private var modelRequestName: String = ""
    @AppStorage("apiKey") private var apiKey = ""
    @AppStorage("serverEndpoint") private var serverEndpoint = ""

    @State private var messages: [Message] = []
    @State private var currentMessage = ""
    @State private var showingSettings = false
    @State private var isLoading = false

    init() {
        if let savedMessages = try? JSONDecoder().decode([Message].self, from: messagesData) {
            _messages = State(initialValue: savedMessages)
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if !modelLabel.isEmpty {
                    Text(modelLabel)
                        .font(.footnote)
                        .padding(.top, 1)
                }

                if messages.isEmpty {
                    Spacer()
                    Text("No messages")
                        .foregroundColor(.gray)
                    Spacer()
                } else {
                    ChatView(messages: messages, modelLabel: modelLabel)
                        .edgesIgnoringSafeArea(.horizontal)
                }

                TextField("tiny message", text: $currentMessage, onCommit: sendMessage)
                    .textFieldStyle(.round)
                    .disabled(isLoading || serverEndpoint.isEmpty)
            }
            .navigationTitle("Chat")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView(
                serverEndpoint: $serverEndpoint,
                apiKey: $apiKey,
                modelLabel: $modelLabel,
                modelRequestName: $modelRequestName
            )
        }
    }

    func persistMessages() {
        if let encoded = try? JSONEncoder().encode(messages) {
            messagesData = encoded
        }
    }

    func sendMessage() {
        guard !currentMessage.isEmpty, !serverEndpoint.isEmpty else { return }

        let userMessage = Message(content: currentMessage, isUser: true)
        messages.append(userMessage)
        persistMessages()

        let messageToSend = currentMessage
        currentMessage = ""  // Clear the message
        isLoading = true

        Task {
            guard let url = URL(string: serverEndpoint) else { return }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            if !apiKey.isEmpty {
                request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            }

            let payload: [String: Any] = [
                "model": modelRequestName,
                "messages": [["role": "user", "content": messageToSend]]
            ]

            do {
                request.httpBody = try JSONSerialization.data(withJSONObject: payload)
                let (data, _) = try await URLSession.shared.data(for: request)
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let choices = json["choices"] as? [[String: Any]],
                   let content = choices.first?["message"] as? [String: String],
                   let responseText = content["content"] {
                    DispatchQueue.main.async {
                        let trimmedResponse = responseText.trimmingCharacters(in: .whitespacesAndNewlines)
                        messages.append(Message(content: trimmedResponse, isUser: false))
                        persistMessages()
                        isLoading = false
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    messages.append(Message(content: "Error: \(error.localizedDescription)", isUser: false))
                    persistMessages()
                    isLoading = false
                }
            }
        }
    }
}

struct TextFieldStyle_round: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .font(.footnote)
            .frame(height: 10)
            .background(Color.gray.opacity(0.2))
            .cornerRadius(3)
    }
}

extension TextFieldStyle where Self == TextFieldStyle_round {
    static var round: TextFieldStyle_round { TextFieldStyle_round() }
}

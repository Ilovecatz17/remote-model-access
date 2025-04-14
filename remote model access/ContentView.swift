import SwiftUI

struct ConnectionError: Identifiable {
    var id: UUID = UUID()
    var message: String
}

struct ContentView: View {
    @AppStorage("savedChats") private var savedChatsData: Data = Data()
    @AppStorage("modelLabel") private var modelLabel: String = "Default Model"
    @AppStorage("modelRequestName") private var modelRequestName: String = "chat"
    @AppStorage("apiKey") private var apiKey: String = ""
    @AppStorage("serverEndpoint") private var serverEndpoint: String = ""
    @AppStorage("contextSize") private var contextSize: Int = 1024
    @AppStorage("chatTitlesData") private var chatTitlesData: Data = Data()
    @State private var chats: [[[String: String]]] = []
    @State private var selectedChatIndex: Int? = nil
    @State private var userMessage: String = ""
    @State private var responseMessage: String = ""
    @State private var isChatting: Bool = false
    @State private var lastVisibleIndex: Int? = nil
    @State private var chatTitles: [String] = []

    init() {
        if let loadedChats = try? JSONDecoder().decode([[[String: String]]].self, from: savedChatsData) {
            _chats = State(initialValue: loadedChats)
        } else {
            _chats = State(initialValue: [[]])
        }
        _chatTitles = State(initialValue: (0..<(_chats.wrappedValue.count)).map { "Chat \($0 + 1)" })
        if let decodedTitles = try? JSONDecoder().decode([String].self, from: chatTitlesData) {
            _chatTitles = State(initialValue: decodedTitles)
        }
    }

    var body: some View {
        NavigationView {
            VStack {
                if isChatting {
                    ChatView(
                        userMessage: $userMessage,
                        responseMessage: $responseMessage,
                        chats: $chats,
                        selectedChatIndex: $selectedChatIndex,
                        isChatting: $isChatting,
                        apiKey: $apiKey,
                        serverEndpoint: $serverEndpoint,
                        contextSize: $contextSize,
                        modelRequestName: $modelRequestName,
                        chatTitles: $chatTitles,
                        lastVisibleIndex: $lastVisibleIndex
                    )
                    .toolbar {
                        ToolbarItem(placement: .navigationBarLeading) {
                            Button("Settings") {
                                isChatting = false
                            }
                        }
                    }
                } else {
                    Form {
                        Section(header: Text("Model Settings")) {
                            TextField("Model Label", text: $modelLabel)
                            TextField("Model Request Name", text: $modelRequestName)
                        }
                        
                        Section(header: Text("API Configuration")) {
                            TextField("API Key", text: $apiKey)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                            TextField("Server Endpoint", text: $serverEndpoint)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                            HStack {
                                Text("Context Size:")
                                TextField("Context Size", value: $contextSize, formatter: NumberFormatter())
                                    .keyboardType(.numberPad)
                                    .frame(width: 80)
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                                Stepper("", value: $contextSize, step: 64)
                                    .labelsHidden()
                            }
                        }
                        
                        Section(header: Text("Chats")) {
                            ForEach(chats.indices, id: \.self) { index in
                                HStack {
                                    Button(chatTitles.indices.contains(index) ? chatTitles[index] : "Chat \(index + 1)") {
                                        selectedChatIndex = index
                                        isChatting = true
                                    }
                                    Spacer()
                                    Button(action: {
                                        renameChat(at: index)
                                    }) {
                                        Image(systemName: "pencil")
                                    }
                                    .buttonStyle(BorderlessButtonStyle())
                                }
                                .swipeActions {
                                    Button(role: .destructive) {
                                        deleteChat(at: index)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                            }
                            Button("New Chat") {
                                chats.append([])
                                chatTitles.append("Chat \(chats.count)")
                                if let encoded = try? JSONEncoder().encode(chatTitles) {
                                    chatTitlesData = encoded
                                }
                                selectedChatIndex = chats.count - 1
                                isChatting = true
                            }
                        }
                    }
                    .background(Color(UIColor.systemBackground))
                }
            }
            .background(Color(UIColor.systemBackground))
        }
    }
    
    func deleteChat(at index: Int) {
        chats.remove(at: index)  // Remove the chat at the given index
        chatTitles.remove(at: index)
        if let encoded = try? JSONEncoder().encode(chatTitles) {
            chatTitlesData = encoded
        }
        if selectedChatIndex == index {
            selectedChatIndex = nil  // Clear the selected chat index if the deleted chat was selected
        } else if selectedChatIndex != nil && selectedChatIndex! > index {
            selectedChatIndex! -= 1  // Adjust selectedChatIndex if necessary
        }

        // Save the updated chats array
        if let encoded = try? JSONEncoder().encode(chats) {
            savedChatsData = encoded
        }
    }
    
    func renameChat(at index: Int) {
        let alert = UIAlertController(title: "Rename Chat", message: "Enter a new name", preferredStyle: .alert)
        alert.addTextField { textField in
            textField.text = chatTitles[index]
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Save", style: .default, handler: { _ in
            if let newName = alert.textFields?.first?.text, !newName.isEmpty {
                chatTitles[index] = newName
                if let encoded = try? JSONEncoder().encode(chatTitles) {
                    chatTitlesData = encoded
                }
            }
        }))

        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let root = scene.windows.first?.rootViewController {
            root.present(alert, animated: true)
        }
    }
}

struct ChatView: View {
    @Binding var userMessage: String
    @Binding var responseMessage: String
    @Binding var chats: [[[String: String]]]
    @Binding var selectedChatIndex: Int?
    @Binding var isChatting: Bool
    @Binding var apiKey: String
    @Binding var serverEndpoint: String
    @Binding var contextSize: Int
    @Binding var modelRequestName: String
    @Binding var chatTitles: [String]
    @Binding var lastVisibleIndex: Int?
    
    @State private var scrollOffset: CGFloat = 0
    @State private var lastMessageID = UUID()
    @State private var connectionError: ConnectionError? = nil
    @State private var isWaitingForResponse: Bool = false

    var body: some View {
        VStack {
            VStack {
                Text(modelRequestName)
                    .font(.headline)
                    .fontWeight(.medium)
                    .padding(.top, 0)

                if let selectedIndex = selectedChatIndex, chatTitles.indices.contains(selectedIndex) {
                    Text(chatTitles[selectedIndex])
                        .font(.subheadline)
                        .foregroundColor(.gray)
                        .padding(.top, 0)
                }
            }
            .frame(maxWidth: .infinity, alignment: .top)
            .padding(.horizontal)
            .padding(.top, 5)
            
            ScrollView {
                ScrollViewReader { proxy in
                    VStack {
                        if let selectedIndex = selectedChatIndex {
                            ForEach(Array(chats[selectedIndex].enumerated()), id: \.element) { idx, message in
                                Text("\(message["role"] ?? "Unknown"): \(message["content"] ?? "")")
                                    .foregroundColor(message["role"] == "system" ? .red : .primary)
                                    .padding()
                                    .id(idx)
                            }
                        }
                        if isWaitingForResponse {
                            ProgressView()
                                .padding()
                        }
                    }
                    .onAppear {
                        if let selectedIndex = selectedChatIndex {
                            let target = chats[selectedIndex].indices.last
                            if let target = target {
                                DispatchQueue.main.async {
                                    withAnimation {
                                        proxy.scrollTo(target, anchor: .bottom)
                                    }
                                }
                            }
                        }
                    }
                    .onChange(of: chats) { _, _ in
                        if let selectedIndex = selectedChatIndex {
                            let target = chats[selectedIndex].indices.last
                            if let target = target {
                                DispatchQueue.main.async {
                                    withAnimation {
                                        proxy.scrollTo(target, anchor: .bottom)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .background(Color(UIColor.systemBackground))
            
            HStack {
                TextField("Type your message", text: $userMessage, onCommit: {
                    sendMessage()
                    DispatchQueue.main.async {
                        userMessage = ""
                    }
                })
                .textFieldStyle(RoundedBorderTextFieldStyle())
                
                Button("Send") {
                    sendMessage()
                    userMessage = ""
                }
                .padding(.leading)
            }
            .padding()
        }
        .onAppear {
            loadChatHistory()
        }
        .onDisappear {
            if let selectedIndex = selectedChatIndex {
                lastVisibleIndex = chats[selectedIndex].count - 1
            }
        }
        .alert(item: $connectionError) { error in
            Alert(title: Text("Connection Error"), message: Text(error.message), dismissButton: .default(Text("OK")))
        }
    }
    
    func sendMessage() {
        guard let selectedIndex = selectedChatIndex else { return }

        let trimmedMessage = userMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedMessage.isEmpty else { return }

        let userMessageDict = ["role": "user", "content": trimmedMessage]
        chats[selectedIndex].append(userMessageDict)

        let systemPrompt: [String: String] = ["role": "system", "content": ""]
        let messages = [systemPrompt] + chats[selectedIndex]

        let body: [String: Any] = [
            "model": modelRequestName,
            "messages": messages,
            "max_tokens": contextSize
        ]

        guard let url = URL(string: serverEndpoint), !serverEndpoint.isEmpty else {
            DispatchQueue.main.async {
                connectionError = ConnectionError(message: "Failed to reach server, check and make sure your API configuration is correct.")
                let errorMessageDict = ["role": "system", "content": "Connection Error"]
                chats[selectedIndex].append(errorMessageDict)
            }
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
        } catch {
            print("Failed to serialize request body: \(error)")
            return
        }

        DispatchQueue.main.async {
            isWaitingForResponse = true
        }

        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                isWaitingForResponse = false
            }
            if error != nil {
                DispatchQueue.main.async {
                    connectionError = ConnectionError(message: "Failed to reach server, check and make sure your API configuration is correct.")
                    let errorMessageDict = ["role": "system", "content": "Connection Error"]
                    chats[selectedIndex].append(errorMessageDict)
                }
                return
            }

            guard let data = data else {
                print("No data in response")
                return
            }

            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let choices = json["choices"] as? [[String: Any]],
                   let message = choices.first?["message"] as? [String: String],
                   let content = message["content"] {
                    
                    DispatchQueue.main.async {
                        let botMessageDict = ["role": "assistant", "content": content]
                        chats[selectedIndex].append(botMessageDict)
                        persistChats()
                        lastMessageID = UUID()
                    }
                } else {
                    print("Invalid response format: \(String(data: data, encoding: .utf8) ?? "")")
                }
            } catch {
                print("Failed to decode response: \(error)")
            }
        }

        task.resume()
    }
    
    func loadChatHistory() {
    }
    
    func persistChats() {
        if let encoded = try? JSONEncoder().encode(chats) {
            UserDefaults.standard.set(encoded, forKey: "savedChats")
        }
    }
}

struct ScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

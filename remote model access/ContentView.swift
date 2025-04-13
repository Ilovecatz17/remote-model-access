import SwiftUI

struct ContentView: View {
    @AppStorage("savedChats") private var savedChatsData: Data = Data()
    @AppStorage("modelLabel") private var modelLabel: String = "Default Model"
    @AppStorage("modelRequestName") private var modelRequestName: String = "chat"
    @AppStorage("apiKey") private var apiKey: String = ""
    @AppStorage("serverEndpoint") private var serverEndpoint: String = ""
    @AppStorage("contextSize") private var contextSize: Int = 1024
    @State private var chats: [[[String: String]]] = []
    @State private var selectedChatIndex: Int? = nil
    @State private var userMessage: String = ""
    @State private var responseMessage: String = ""
    @State private var isChatting: Bool = false

    init() {
        if let loadedChats = try? JSONDecoder().decode([[[String: String]]].self, from: savedChatsData) {
            _chats = State(initialValue: loadedChats)
        } else {
            _chats = State(initialValue: [[]])
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
                        modelRequestName: $modelRequestName
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
                                Button("Chat \(index + 1)") {
                                    selectedChatIndex = index
                                    isChatting = true
                                }
                            }
                            Button("New Chat") {
                                chats.append([])
                                selectedChatIndex = chats.count - 1
                                isChatting = true
                            }
                        }
                    }
                }
            }
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
    
    @State private var scrollOffset: CGFloat = 0

    var body: some View {
        VStack {
            VStack {
                Text(modelRequestName)
                    .font(.headline)
                    .fontWeight(.medium)
                    .padding(.top, 0)

                if let selectedIndex = selectedChatIndex {
                    Text("Chat \(selectedIndex + 1)")
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
                            ForEach(chats[selectedIndex], id: \.self) { message in
                                Text("\(message["role"] ?? "Unknown"): \(message["content"] ?? "")")
                                    .padding()
                            }
                        }
                    }
                    .background(GeometryReader {
                        Color.clear.preference(key: ScrollOffsetKey.self, value: $0.frame(in: .global).minY)
                    })
                    .onPreferenceChange(ScrollOffsetKey.self) { value in
                        scrollOffset = value
                    }
                }
            }
            
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

        guard let url = URL(string: serverEndpoint) else {
            print("Invalid server endpoint")
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

        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("Error: \(error)")
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

import SwiftUI
import UIKit

struct ConnectionError: Identifiable {
    var id = UUID()
    var message: String
}

struct CustomizationView: View {
    @Binding var modelLabel: String
    @Binding var modelRequestName: String
    @Binding var apiKey: String
    @Binding var serverEndpoint: String
    @Binding var contextSize: Int
    @Binding var showExportAlert: Bool
    @Binding var showImportAlert: Bool
    @Binding var autoSummarizeTitles: Bool
    var exportSettings: () -> Void
    var importSettings: () -> Void

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Model")) {
                    TextField("Model Label", text: $modelLabel)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                    TextField("Model Request Name", text: $modelRequestName)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                }
                Section(header: Text("API Configuration")) {
                    TextField("API Key (leave blank if self hosting)", text: $apiKey)
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
                Section(header: Text("Configuration")) {
                    Toggle("Auto-Summarize Chat Titles", isOn: $autoSummarizeTitles)
                    Button("Export Settings to Clipboard") {
                        exportSettings()
                    }
                    Button("Import Settings from Clipboard") {
                        importSettings()
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .alert("Settings Exported", isPresented: $showExportAlert) {
                Button("OK", role: .cancel) { }
            }
            .alert("Settings Imported", isPresented: $showImportAlert) {
                Button("OK", role: .cancel) { }
            }
        }
    }
}

struct ContentView: View {
    @AppStorage("savedChats") private var savedChatsData: Data = Data()
    @AppStorage("modelLabel") private var modelLabel: String = "Default Model"
    @AppStorage("modelRequestName") private var modelRequestName: String = "chat"
    @AppStorage("apiKey") private var apiKey: String = ""
    @AppStorage("serverEndpoint") private var serverEndpoint: String = ""
    @AppStorage("contextSize") private var contextSize: Int = 1024
    @AppStorage("chatTitlesData") private var chatTitlesData: Data = Data()
    @AppStorage("chatNumbersData") private var chatNumbersData: Data = Data()
    @AppStorage("autoSummarizeTitles") private var autoSummarizeTitles: Bool = false
    @State private var chats: [[[String: String]]] = []
    @State private var selectedChatIndex: Int? = nil
    @State private var userMessage: String = ""
    @State private var responseMessage: String = ""
    @State private var isChatting: Bool = false
    @State private var lastVisibleIndex: Int? = nil
    @State private var chatTitles: [String] = []
    @State private var chatNumbers: [Int] = []
    @State private var showingAboutSheet: Bool = false
    @State private var showingCustomizationSheet: Bool = false
    @State private var showExportAlert = false
    @State private var showImportAlert = false
    @State private var showClearAllAlert = false

    init() {
        if let loadedChats = try? JSONDecoder().decode([[[String: String]]].self, from: savedChatsData) {
            _chats = State(initialValue: loadedChats)
        } else {
            _chats = State(initialValue: [[]])
        }
        if let decodedTitles = try? JSONDecoder().decode([String].self, from: chatTitlesData) {
            _chatTitles = State(initialValue: decodedTitles)
        } else {
            _chatTitles = State(initialValue: Array(repeating: "", count: _chats.wrappedValue.count))
        }
        if let decodedNumbers = try? JSONDecoder().decode([Int].self, from: chatNumbersData) {
            _chatNumbers = State(initialValue: decodedNumbers)
        } else {
            _chatNumbers = State(initialValue: (0..<_chats.wrappedValue.count).map { $0 + 1 })
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
                        chatNumbers: $chatNumbers,
                        lastVisibleIndex: $lastVisibleIndex,
                        autoSummarizeTitles: $autoSummarizeTitles,
                        summarizeChatTitle: summarizeChatTitle
                    )
                } else {
                    Form {
                        Section(header:
                            HStack {
                                Text("Chats")
                                Spacer()
                                Button(action: { showClearAllAlert = true }) {
                                    Image(systemName: "trash")
                                        .foregroundColor(.red)
                                }
                                .buttonStyle(BorderlessButtonStyle())
                                .alert("Clear All Chats?", isPresented: $showClearAllAlert) {
                                    Button("Cancel", role: .cancel) { }
                                    Button("Clear All", role: .destructive) {
                                        clearAllChats()
                                    }
                                } message: {
                                    Text("Are you sure you want to delete all chats? This cannot be undone.")
                                }
                            }
                        ) {
                            ForEach(chats.indices, id: \.self) { index in
                                HStack {
                                    Button(
                                        chatTitles.indices.contains(index) && !chatTitles[index].isEmpty
                                            ? chatTitles[index]
                                            : "Chat \(chatNumbers.indices.contains(index) ? chatNumbers[index] : index + 1)"
                                    ) {
                                        selectedChatIndex = index
                                        isChatting = true
                                    }
                                    .contextMenu {
                                        Button(role: .destructive) {
                                            deleteChat(at: index)
                                        } label: {
                                            Label("Delete Chat", systemImage: "trash")
                                        }
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
                                let nextNumber = (chatNumbers.max() ?? 0) + 1
                                chatNumbers.append(nextNumber)
                                chatTitles.append("")
                                selectedChatIndex = chats.count - 1
                                isChatting = true
                                persistChatNumbers()
                                persistChatTitles()
                                persistChats()
                            }
                        }
                    }
                    .background(Color(UIColor.systemBackground))
                }
            }
            .background(Color(UIColor.systemBackground))
            .toolbar {
                if !isChatting {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button(action: { showingAboutSheet = true }) {
                            Image(systemName: "info.circle")
                        }
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(action: { showingCustomizationSheet = true }) {
                            Image(systemName: "gearshape")
                        }
                    }
                }
                if isChatting {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Settings") {
                            isChatting = false
                        }
                    }
                }
            }
            .sheet(isPresented: $showingAboutSheet) {
                VStack(spacing: 12) {
                    Text("😻")
                        .font(.system(size: 60))

                    Text("Remote Model Access")
                        .font(.title2)
                        .fontWeight(.bold)

                    Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")")
                        .font(.subheadline)

                    Text("Created by ILoveCatz17")

                    Link("GitHub Repository", destination: URL(string: "https://github.com/Ilovecatz17/remote-model-access")!)

                    Button("Close") {
                        showingAboutSheet = false
                    }
                    .padding(.top)
                }
                .padding()
            }
            .sheet(isPresented: $showingCustomizationSheet) {
                CustomizationView(
                    modelLabel: $modelLabel,
                    modelRequestName: $modelRequestName,
                    apiKey: $apiKey,
                    serverEndpoint: $serverEndpoint,
                    contextSize: $contextSize,
                    showExportAlert: $showExportAlert,
                    showImportAlert: $showImportAlert,
                    autoSummarizeTitles: $autoSummarizeTitles,
                    exportSettings: exportSettings,
                    importSettings: importSettings
                )
            }
        }
    }

    func persistChatTitles() { if let encoded = try? JSONEncoder().encode(chatTitles) { chatTitlesData = encoded } }
    func persistChatNumbers() { if let encoded = try? JSONEncoder().encode(chatNumbers) { chatNumbersData = encoded } }
    func persistChats() { if let encoded = try? JSONEncoder().encode(chats) { savedChatsData = encoded } }
    func deleteChat(at index: Int) {
        chats.remove(at: index)
        chatTitles.remove(at: index)
        chatNumbers.remove(at: index)
        if selectedChatIndex == index { selectedChatIndex = nil }
        else if selectedChatIndex != nil && selectedChatIndex! > index { selectedChatIndex! -= 1 }
        persistChats(); persistChatTitles(); persistChatNumbers()
    }
    func renameChat(at index: Int) {
        let alert = UIAlertController(title: "Rename Chat", message: "Enter a new name", preferredStyle: .alert)
        alert.addTextField { textField in textField.text = chatTitles[index] }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Save", style: .default, handler: { _ in
            if let newName = alert.textFields?.first?.text, !newName.isEmpty {
                chatTitles[index] = newName; persistChatTitles()
            }
        }))
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let root = scene.windows.first?.rootViewController { root.present(alert, animated: true) }
    }
    func exportSettings() {
        let config: [String: Any] = [
            "modelRequestName": modelRequestName,
            "apiKey": apiKey,
            "serverEndpoint": serverEndpoint,
            "contextSize": contextSize,
            "modelLabel": modelLabel,
            "autoSummarizeTitles": autoSummarizeTitles
        ]
        if let data = try? JSONSerialization.data(withJSONObject: config, options: .prettyPrinted),
           let jsonString = String(data: data, encoding: .utf8) {
            UIPasteboard.general.string = jsonString
        }
        showExportAlert = true
    }
    func importSettings() {
        guard let jsonString = UIPasteboard.general.string,
              let data = jsonString.data(using: .utf8),
              let config = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else { return }
        modelRequestName = config["modelRequestName"] as? String ?? modelRequestName
        apiKey = config["apiKey"] as? String ?? apiKey
        serverEndpoint = config["serverEndpoint"] as? String ?? serverEndpoint
        contextSize = config["contextSize"] as? Int ?? contextSize
        modelLabel = config["modelLabel"] as? String ?? modelLabel
        autoSummarizeTitles = config["autoSummarizeTitles"] as? Bool ?? autoSummarizeTitles
        showImportAlert = true
    }
    func clearAllChats() {
        chats = []; chatTitles = []; chatNumbers = []; selectedChatIndex = nil
        persistChats(); persistChatTitles(); persistChatNumbers()
    }

    // Summarize chat title using the user's AI model (updated prompt)
    func summarizeChatTitle(at index: Int) {
        guard autoSummarizeTitles,
              chats.indices.contains(index),
              !chats[index].isEmpty,
              let url = URL(string: serverEndpoint), !serverEndpoint.isEmpty else { return }

        let messages = chats[index].prefix(10)
        let summaryPrompt: [String: String] = [
            "role": "user",
            "content": "What is the main topic of this conversation? Respond with a short phrase suitable as a chat title."
        ]
        let payload: [String: Any] = [
            "model": modelRequestName,
            "messages": Array(messages) + [summaryPrompt],
            "max_tokens": 24
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        } catch { return }

        URLSession.shared.dataTask(with: request) { data, _, _ in
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = json["choices"] as? [[String: Any]],
                  let message = choices.first?["message"] as? [String: Any],
                  let content = message["content"] as? String else { return }
            DispatchQueue.main.async {
                chatTitles[index] = content.trimmingCharacters(in: .whitespacesAndNewlines)
                persistChatTitles()
            }
        }.resume()
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
    @Binding var chatNumbers: [Int]
    @Binding var lastVisibleIndex: Int?
    @Binding var autoSummarizeTitles: Bool
    var summarizeChatTitle: (Int) -> Void

    @State private var connectionError: ConnectionError? = nil
    @State private var isWaitingForResponse: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            VStack {
                Text(modelRequestName)
                    .font(.headline)
                    .fontWeight(.medium)
                    .padding(.top, 0)
                if let selectedIndex = selectedChatIndex, chatTitles.indices.contains(selectedIndex) {
                    Text(
                        chatTitles[selectedIndex].isEmpty
                            ? "Chat \(chatNumbers.indices.contains(selectedIndex) ? chatNumbers[selectedIndex] : (selectedIndex + 1))"
                            : chatTitles[selectedIndex]
                    )
                        .font(.subheadline)
                        .foregroundColor(.gray)
                        .padding(.top, 0)
                }
            }
            .frame(maxWidth: .infinity, alignment: .top)
            .padding(.horizontal)
            .padding(.top, 5)
            ZStack {
                Color(UIColor.systemGroupedBackground)
                    .edgesIgnoringSafeArea(.all)
                ScrollView {
                    ScrollViewReader { proxy in
                        VStack(spacing: 8) {
                            if let selectedIndex = selectedChatIndex {
                                if chats[selectedIndex].filter({ $0["role"] != "system" }).isEmpty {
                                    Spacer(minLength: 80)
                                    Text("This chat is empty.")
                                        .foregroundColor(.gray)
                                        .padding()
                                } else {
                                    ForEach(Array(chats[selectedIndex].enumerated()), id: \.element) { idx, message in
                                        if message["role"] == "system" { EmptyView() } else {
                                            HStack {
                                                if message["role"] == "user" {
                                                    Spacer()
                                                    Text(message["content"] ?? "")
                                                        .padding(8)
                                                        .background(Color.blue.opacity(0.15))
                                                        .cornerRadius(8)
                                                        .foregroundColor(.primary)
                                                } else {
                                                    Text(message["content"] ?? "")
                                                        .padding(8)
                                                        .background(Color.gray.opacity(0.15))
                                                        .cornerRadius(8)
                                                        .foregroundColor(.primary)
                                                    Spacer()
                                                }
                                            }
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 2)
                                        }
                                    }
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
            }
            .background(Color(UIColor.systemGroupedBackground))
            Divider()
                .padding(.bottom, 2)
            HStack(alignment: .center, spacing: 8) {
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
            .background(Color(UIColor.secondarySystemGroupedBackground))
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
        let userMessageDict: [String: String] = ["role": "user", "content": trimmedMessage]
        chats[selectedIndex].append(userMessageDict)
        // Summarize chat title if enabled
        if autoSummarizeTitles {
            summarizeChatTitle(selectedIndex)
        }
        let systemPrompt: [String: String] = ["role": "system", "content": ""]
        let messages = [systemPrompt] + chats[selectedIndex]
        let jsonPayload: [String: Any] = [
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
        var jsonRequest = URLRequest(url: url)
        jsonRequest.httpMethod = "POST"
        jsonRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !apiKey.isEmpty {
            jsonRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: jsonPayload, options: .prettyPrinted)
            jsonRequest.httpBody = jsonData
        } catch {
            print("Failed to serialize request body: \(error)")
            return
        }
        DispatchQueue.main.async {
            isWaitingForResponse = true
        }
        let task = URLSession.shared.dataTask(with: jsonRequest) { data, response, error in
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
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    if let choices = json["choices"] as? [[String: Any]],
                       let message = choices.first?["message"] as? [String: String],
                       let content = message["content"] {
                        DispatchQueue.main.async {
                            let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
                            let botMessageDict = ["role": "assistant", "content": trimmedContent]
                            chats[selectedIndex].append(botMessageDict)
                            // Summarize again after assistant reply
                            if autoSummarizeTitles {
                                summarizeChatTitle(selectedIndex)
                            }
                            persistChats()
                        }
                    }
                }
            } catch {
                print("Failed to decode response: \(error)")
            }
        }
        task.resume()
    }
    func persistChats() {
        if let encoded = try? JSONEncoder().encode(chats) {
            UserDefaults.standard.set(encoded, forKey: "savedChats")
        }
    }
}

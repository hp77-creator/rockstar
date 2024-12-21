import Foundation

enum APIError: Error {
    case invalidURL
    case networkError(Error)
    case invalidResponse
    case decodingError(Error)
}

class APIClient: NSObject, URLSessionWebSocketDelegate {
    private let baseURL = "http://localhost:54321"
    private let wsURLs = [
        "ws://localhost:54321/ws",
        "ws://127.0.0.1:54321/ws"
    ]
    private var currentWSURLIndex = 0
    private var session: URLSession!
    private var webSocket: URLSessionWebSocketTask?
    private var isConnected = false
    private var reconnectTimer: Timer?
    private var connectionAttempts = 0
    private let maxConnectionAttempts = 3
    weak var delegate: ClipboardUpdateDelegate?
    
    override init() {
        super.init()
        
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 2 // Shorter timeout for faster failure detection
        config.timeoutIntervalForResource = 5
        
        // Allow local network connections
        if #available(macOS 11.0, *) {
            config.waitsForConnectivity = true
            config.allowsExpensiveNetworkAccess = true
            config.allowsConstrainedNetworkAccess = true
        }
        
        self.session = URLSession(configuration: config, delegate: self, delegateQueue: .main)
        print("APIClient initialized with baseURL: \(baseURL)")
        connectWebSocket()
    }
    
    deinit {
        print("APIClient deinitializing")
        disconnectWebSocket()
        session.invalidateAndCancel()
    }
    
    private func connectWebSocket() {
        guard webSocket == nil else { return }
        
        // Reset connection attempts if we're trying a new URL
        if currentWSURLIndex == 0 {
            connectionAttempts = 0
        }
        
        // Check if we've exceeded max attempts for all URLs
        if connectionAttempts >= maxConnectionAttempts && currentWSURLIndex >= wsURLs.count - 1 {
            print("Failed to connect after trying all URLs")
            handleWebSocketError()
            return
        }
        
        // Get current URL to try
        let wsURL = wsURLs[currentWSURLIndex]
        guard let url = URL(string: wsURL) else {
            print("Invalid WebSocket URL: \(wsURL)")
            return
        }
        
        print("Attempting WebSocket connection to \(wsURL) (Attempt \(connectionAttempts + 1))")
        
        webSocket = session.webSocketTask(with: url)
        webSocket?.resume()
        
        receiveMessage()
        connectionAttempts += 1
    }
    
    private func disconnectWebSocket() {
        webSocket?.cancel(with: .goingAway, reason: nil)
        webSocket = nil
        isConnected = false
    }
    
    private func receiveMessage() {
        webSocket?.receive { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    self.handleWebSocketMessage(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        self.handleWebSocketMessage(text)
                    }
                @unknown default:
                    break
                }
                // Continue receiving messages
                self.receiveMessage()
                
            case .failure(let error):
                print("WebSocket receive error: \(error)")
                self.handleWebSocketError()
            }
        }
    }
    
    private func handleWebSocketMessage(_ text: String) {
        guard let data = text.data(using: .utf8) else { return }
        
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .custom { decoder in
                let container = try decoder.singleValueContainer()
                let dateString = try container.decode(String.self)
                
                let formats = [
                    "yyyy-MM-dd'T'HH:mm:ss.SSSZ",
                    "yyyy-MM-dd'T'HH:mm:ssZ",
                    "yyyy-MM-dd'T'HH:mm:ss'Z'"
                ]
                
                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: "en_US_POSIX")
                
                for format in formats {
                    formatter.dateFormat = format
                    if let date = formatter.date(from: dateString) {
                        return date
                    }
                }
                
                print("Failed to parse date: \(dateString)")
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date format")
            }
            
            let message = try decoder.decode(WebSocketMessage.self, from: data)
            if message.type == "clipboard_change" {
                if let clip = message.payload {
                    DispatchQueue.main.async { [weak self] in
                        self?.delegate?.didReceiveNewClip(clip)
                    }
                }
            }
        } catch {
            print("Error decoding WebSocket message: \(error)")
        }
    }
    
    private func handleWebSocketError() {
        disconnectWebSocket()
        
        // Try next URL if available
        if currentWSURLIndex < wsURLs.count - 1 {
            currentWSURLIndex += 1
            print("Switching to next WebSocket URL: \(wsURLs[currentWSURLIndex])")
            connectWebSocket()
            return
        }
        
        // Reset to first URL for next attempt
        currentWSURLIndex = 0
        
        // Schedule reconnection with exponential backoff
        let backoffTime = min(pow(2.0, Double(connectionAttempts)), 30.0)
        print("Scheduling reconnection in \(backoffTime) seconds")
        
        reconnectTimer?.invalidate()
        reconnectTimer = Timer.scheduledTimer(withTimeInterval: backoffTime, repeats: false) { [weak self] _ in
            self?.connectWebSocket()
        }
    }
    
    // URLSessionWebSocketDelegate methods
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        print("WebSocket connected successfully to \(wsURLs[currentWSURLIndex])")
        isConnected = true
        connectionAttempts = 0  // Reset attempts on successful connection
    }
    
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        print("WebSocket closed with code: \(closeCode)")
        isConnected = false
        handleWebSocketError()
    }
    
    // Keep the HTTP methods for initial load and manual refresh
    func getClips() async throws -> [ClipboardItem] {
        guard let url = URL(string: "\(baseURL)/api/clips") else {
            throw APIError.invalidURL
        }
        
        print("Requesting clips from: \(url)")
        
        do {
            let (data, response) = try await session.data(from: url)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                print("Invalid response: \(response)")
                throw APIError.invalidResponse
            }
            
            // Print raw JSON for debugging
            if let jsonString = String(data: data, encoding: .utf8) {
                print("Raw JSON response from \(url.absoluteString): \(jsonString)")
            }
            
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .custom { decoder in
                let container = try decoder.singleValueContainer()
                let dateString = try container.decode(String.self)
                
                // Try parsing with different date formats
                let formats = [
                    "yyyy-MM-dd'T'HH:mm:ss.SSSZ",
                    "yyyy-MM-dd'T'HH:mm:ssZ",
                    "yyyy-MM-dd'T'HH:mm:ss'Z'"
                ]
                
                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: "en_US_POSIX")
                
                for format in formats {
                    formatter.dateFormat = format
                    if let date = formatter.date(from: dateString) {
                        return date
                    }
                }
                
                print("Failed to parse date: \(dateString)")
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date format")
            }
            
            // First try to decode the raw response to inspect it
            if let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                print("Raw JSON structure:")
                for (index, item) in json.enumerated() {
                    print("Item \(index):")
                    for (key, value) in item {
                        print("  \(key): \(type(of: value)) = \(value)")
                    }
                }
            }
            
            do {
                let clips = try decoder.decode([ClipboardItem].self, from: data)
                print("Successfully decoded \(clips.count) clips")
                return clips
            } catch {
                print("Decoding error: \(error)")
                if let decodingError = error as? DecodingError {
                    switch decodingError {
                    case .keyNotFound(let key, _):
                        print("Missing key: \(key)")
                    case .typeMismatch(let type, let context):
                        print("Type mismatch: expected \(type) at \(context.codingPath)")
                    case .valueNotFound(let type, let context):
                        print("Value not found: expected \(type) at \(context.codingPath)")
                    case .dataCorrupted(let context):
                        print("Data corrupted: \(context)")
                    @unknown default:
                        print("Unknown decoding error")
                    }
                }
                throw APIError.decodingError(error)
            }
        } catch let error as DecodingError {
            throw APIError.decodingError(error)
        } catch {
            throw APIError.networkError(error)
        }
    }
    
    func pasteClip(at index: Int) async throws {
        guard let url = URL(string: "\(baseURL)/api/clips/\(index)/paste") else {
            throw APIError.invalidURL
        }
        
        print("Sending paste request for clip at index: \(index)")
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 5 // 5 second timeout
        
        do {
            let (data, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                print("Invalid response type: \(response)")
                throw APIError.invalidResponse
            }
            
            guard httpResponse.statusCode == 200 else {
                let errorMessage = String(data: data, encoding: .utf8) ?? "No error message"
                print("Server error: HTTP \(httpResponse.statusCode), \(errorMessage)")
                throw APIError.invalidResponse
            }
            
            print("Successfully pasted clip at index \(index)")
        } catch let error as URLError {
            print("Network error during paste: \(error.localizedDescription)")
            throw APIError.networkError(error)
        } catch {
            print("Unexpected error during paste: \(error)")
            throw APIError.networkError(error)
        }
    }
}

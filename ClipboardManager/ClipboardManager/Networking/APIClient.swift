import Foundation

// Add Logger import
import SwiftUI

enum APIError: Error, Equatable {
    case invalidURL
    case networkError(Error)
    case invalidResponse
    case decodingError(Error)
    case sessionInvalidated
    
    static func == (lhs: APIError, rhs: APIError) -> Bool {
        switch (lhs, rhs) {
        case (.invalidURL, .invalidURL),
             (.invalidResponse, .invalidResponse),
             (.sessionInvalidated, .sessionInvalidated):
            return true
        case (.networkError(let lhsError), .networkError(let rhsError)):
            return lhsError.localizedDescription == rhsError.localizedDescription
        case (.decodingError(let lhsError), .decodingError(let rhsError)):
            return lhsError.localizedDescription == rhsError.localizedDescription
        default:
            return false
        }
    }
}

struct SearchResult: Codable {
    let clip: ClipboardItem
    let score: Double
    let lastUsed: Date
    
    enum CodingKeys: String, CodingKey {
        case clip
        case score
        case lastUsed = "last_used"
    }
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
    private var isSessionValid = true
    weak var delegate: ClipboardUpdateDelegate?
    
    override init() {
        super.init()
        
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 5  // Increased from 2s to 5s for initial connection
        config.timeoutIntervalForResource = 10 // Increased from 5s to 10s for total operation
        
        if #available(macOS 11.0, *) {
            config.waitsForConnectivity = true
            config.allowsExpensiveNetworkAccess = true
            config.allowsConstrainedNetworkAccess = true
        }
        
        self.session = URLSession(configuration: config, delegate: self, delegateQueue: .main)
        Logger.debug("APIClient initialized with baseURL: \(baseURL)")
        connectWebSocket()
    }
    
    deinit {
        Logger.debug("APIClient deinitializing")
        disconnect()
    }
    
    // MARK: - WebSocket Methods
    
    private func connectWebSocket() {
        guard webSocket == nil, isSessionValid else { return }
        
        // Reset connection attempts when starting fresh
        if currentWSURLIndex == 0 {
            connectionAttempts = 0
        }
        
        // Don't give up on WebSocket connection, keep retrying
        // This helps with server that's slow to start
        let wsURL = wsURLs[currentWSURLIndex]
        guard let url = URL(string: wsURL) else {
            Logger.error("Invalid WebSocket URL: \(wsURL)")
            return
        }
        
        Logger.debug("Attempting WebSocket connection to \(wsURL) (Attempt \(connectionAttempts + 1))")
        
        webSocket = session.webSocketTask(with: url)
        webSocket?.resume()
        
        receiveMessage()
        connectionAttempts += 1
        
        // If this attempt fails, try the next URL
        if connectionAttempts >= maxConnectionAttempts {
            connectionAttempts = 0
            currentWSURLIndex = (currentWSURLIndex + 1) % wsURLs.count
        }
    }
    
    private func disconnectWebSocket() {
        webSocket?.cancel(with: .goingAway, reason: nil)
        webSocket = nil
        isConnected = false
        reconnectTimer?.invalidate()
        reconnectTimer = nil
    }
    
    func disconnect() {
        Logger.debug("Disconnecting APIClient")
        isSessionValid = false
        disconnectWebSocket()
        session.invalidateAndCancel()
    }
    
    private func receiveMessage() {
        guard isSessionValid else { return }
        
        webSocket?.receive { [weak self] result in
            guard let self = self, self.isSessionValid else { return }
            
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
                self.receiveMessage()
                
            case .failure(let error):
                Logger.error("WebSocket receive error: \(error)")
                self.handleWebSocketError()
            }
        }
    }
    
    private func handleWebSocketMessage(_ text: String) {
        guard isSessionValid else { return }
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
                
                Logger.error("Failed to parse date: \(dateString)")
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
            Logger.error("Error decoding WebSocket message: \(error)")
        }
    }
    
    private func handleWebSocketError() {
        guard isSessionValid else { return }
        
        disconnectWebSocket()
        
        if currentWSURLIndex < wsURLs.count - 1 {
            currentWSURLIndex += 1
            Logger.debug("Switching to next WebSocket URL: \(wsURLs[currentWSURLIndex])")
            connectWebSocket()
            return
        }
        
        currentWSURLIndex = 0
        
        let backoffTime = min(pow(2.0, Double(connectionAttempts)), 30.0)
        Logger.debug("Scheduling reconnection in \(backoffTime) seconds")
        
        reconnectTimer?.invalidate()
        reconnectTimer = Timer.scheduledTimer(withTimeInterval: backoffTime, repeats: false) { [weak self] _ in
            guard let self = self, self.isSessionValid else {
                Logger.debug("Session invalidated, cancelling reconnection")
                return
            }
            self.connectWebSocket()
        }
    }
    
    // MARK: - URLSessionWebSocketDelegate
    
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        Logger.debug("WebSocket connected successfully to \(wsURLs[currentWSURLIndex])")
        isConnected = true
        connectionAttempts = 0
    }
    
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        Logger.debug("WebSocket closed with code: \(closeCode)")
        isConnected = false
        handleWebSocketError()
    }
    
    // MARK: - API Methods
    
    func getClips(offset: Int = 0, limit: Int? = nil) async throws -> [ClipboardItem] {
        guard isSessionValid else { throw APIError.sessionInvalidated }
        
        let effectiveLimit: Int
        if let limit = limit {
            effectiveLimit = limit
        } else {
            let userLimit = UserDefaults.standard.integer(forKey: UserDefaultsKeys.maxClipsShown)
            effectiveLimit = userLimit > 0 ? userLimit : 10
        }
        
        var urlComponents = URLComponents(string: "\(baseURL)/api/clips")
        urlComponents?.queryItems = [
            URLQueryItem(name: "limit", value: String(effectiveLimit)),
            URLQueryItem(name: "offset", value: String(offset))
        ]
        
        guard let url = urlComponents?.url else {
            throw APIError.invalidURL
        }
        
        Logger.debug("Requesting clips from: \(url)")
        
        do {
            let (data, response) = try await session.data(from: url)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                Logger.error("Invalid response: \(response)")
                throw APIError.invalidResponse
            }
            
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
                
                Logger.error("Failed to parse date: \(dateString)")
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date format")
            }
            
            do {
                let clips = try decoder.decode([ClipboardItem].self, from: data)
                Logger.debug("Successfully decoded \(clips.count) clips")
                return clips
            } catch {
                Logger.error("Decoding error: \(error)")
                throw APIError.decodingError(error)
            }
        } catch let error as DecodingError {
            throw APIError.decodingError(error)
        } catch {
            throw APIError.networkError(error)
        }
    }
    
    func searchClips(query: String, offset: Int = 0, limit: Int = 20) async throws -> [ClipboardItem] {
        guard isSessionValid else { throw APIError.sessionInvalidated }
        
        var urlComponents = URLComponents(string: "\(baseURL)/api/search")
        urlComponents?.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "offset", value: String(offset)),
            URLQueryItem(name: "limit", value: String(limit))
        ]
        
        guard let url = urlComponents?.url else {
            throw APIError.invalidURL
        }
        
        Logger.debug("Searching clips with query: \(query)")
        
        do {
            let (data, response) = try await session.data(from: url)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                Logger.error("Invalid response: \(response)")
                throw APIError.invalidResponse
            }
            
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
                
                Logger.error("Failed to parse date: \(dateString)")
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date format")
            }
            
            let searchResults = try decoder.decode([SearchResult].self, from: data)
            return searchResults.map { $0.clip }
        } catch {
            Logger.error("Search error: \(error)")
            throw APIError.networkError(error)
        }
    }
    
    func pasteClip(at index: Int) async throws {
        guard isSessionValid else { throw APIError.sessionInvalidated }
        
        guard let url = URL(string: "\(baseURL)/api/clips/\(index)/paste") else {
            throw APIError.invalidURL
        }
        
        Logger.debug("Sending paste request for clip at index: \(index)")
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 5
        
        do {
            let (data, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                Logger.error("Invalid response type: \(response)")
                throw APIError.invalidResponse
            }
            
            guard httpResponse.statusCode == 200 else {
                if let errorData = try? JSONDecoder().decode([String: String].self, from: data) {
                    let errorMessage = errorData["error"] ?? errorData["detail"] ?? "Unknown error"
                    Logger.error("Server error: HTTP \(httpResponse.statusCode), \(errorMessage)")
                    throw APIError.networkError(NSError(domain: "ClipboardManager",
                                                      code: httpResponse.statusCode,
                                                      userInfo: [NSLocalizedDescriptionKey: errorMessage]))
                } else if let errorMessage = String(data: data, encoding: .utf8) {
                    Logger.error("Server error: HTTP \(httpResponse.statusCode), \(errorMessage)")
                    throw APIError.networkError(NSError(domain: "ClipboardManager",
                                                      code: httpResponse.statusCode,
                                                      userInfo: [NSLocalizedDescriptionKey: errorMessage]))
                } else {
                    Logger.error("Server error: HTTP \(httpResponse.statusCode), no error message")
                    throw APIError.invalidResponse
                }
            }
            
            Logger.debug("Successfully pasted clip at index \(index)")
        } catch let error as URLError {
            Logger.error("Network error during paste: \(error.localizedDescription)")
            throw APIError.networkError(error)
        } catch {
            Logger.error("Unexpected error during paste: \(error)")
            throw APIError.networkError(error)
        }
    }
    
    func deleteClip(id: String) async throws {
        guard isSessionValid else { throw APIError.sessionInvalidated }
        
        guard let url = URL(string: "\(baseURL)/api/clips/id/\(id)") else {
            throw APIError.invalidURL
        }
        
        Logger.debug("Sending delete request for clip: \(id)")
        
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.timeoutInterval = 5
        
        let (_, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            Logger.error("Invalid response: \(response)")
            throw APIError.invalidResponse
        }
        
        Logger.debug("Successfully deleted clip \(id)")
    }
    
    func clearClips() async throws {
        guard isSessionValid else { throw APIError.sessionInvalidated }
        
        guard let url = URL(string: "\(baseURL)/api/clips") else {
            throw APIError.invalidURL
        }
        
        Logger.debug("Sending clear all clips request")
        
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.timeoutInterval = 5
        
        let (_, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            Logger.error("Invalid response: \(response)")
            throw APIError.invalidResponse
        }
        
        Logger.debug("Successfully cleared all clips")
    }
}

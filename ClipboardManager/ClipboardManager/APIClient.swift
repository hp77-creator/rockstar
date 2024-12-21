import Foundation

enum APIError: Error {
    case invalidURL
    case networkError(Error)
    case invalidResponse
    case decodingError(Error)
}

class APIClient {
    private let baseURL = "http://localhost:54321"
    private let session: URLSession
    
    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 2 // Shorter timeout for faster failure detection
        config.timeoutIntervalForResource = 5
        
        // Allow local network connections
        if #available(macOS 11.0, *) {
            config.waitsForConnectivity = true
            config.allowsExpensiveNetworkAccess = true
            config.allowsConstrainedNetworkAccess = true
        }
        
        self.session = URLSession(configuration: config)
        print("APIClient initialized with baseURL: \(baseURL)")
    }
    
    deinit {
        print("APIClient deinitializing, invalidating session")
        session.invalidateAndCancel()
    }
    
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

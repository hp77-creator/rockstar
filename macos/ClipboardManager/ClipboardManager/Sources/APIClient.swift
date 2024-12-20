import Foundation

enum APIError: Error {
    case invalidURL
    case networkError(Error)
    case invalidResponse
    case decodingError(Error)
}

class APIClient {
    private let baseURL = "http://localhost:54321"
    
    func getClips() async throws -> [ClipboardItem] {
        guard let url = URL(string: "\(baseURL)/api/clips") else {
            throw APIError.invalidURL
        }
        
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                throw APIError.invalidResponse
            }
            
            return try JSONDecoder().decode([ClipboardItem].self, from: data)
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
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                throw APIError.invalidResponse
            }
        } catch {
            throw APIError.networkError(error)
        }
    }
}

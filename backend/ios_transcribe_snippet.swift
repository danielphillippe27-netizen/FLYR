// Minimal Swift snippet: upload audio to POST /v1/transcribe and print transcript.
// Add to your iOS app; use your backend URL and API key.

import Foundation

func transcribeAudio(url: URL, apiBaseURL: String, apiKey: String) async throws -> String {
    let endpoint = URL(string: "\(apiBaseURL)/v1/transcribe")!
    var request = URLRequest(url: endpoint)
    request.httpMethod = "POST"
    request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")

    let boundary = "Boundary-\(UUID().uuidString)"
    request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

    let data = try Data(contentsOf: url)
    var body = Data()
    body.append("--\(boundary)\r\n".data(using: .utf8)!)
    body.append("Content-Disposition: form-data; name=\"file\"; filename=\"audio.m4a\"\r\n".data(using: .utf8)!)
    body.append("Content-Type: audio/mp4\r\n\r\n".data(using: .utf8)!)
    body.append(data)
    body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
    request.httpBody = body

    let (responseData, response) = try await URLSession.shared.data(for: request)
    guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
        throw NSError(domain: "Transcribe", code: (response as? HTTPURLResponse)?.statusCode ?? -1, userInfo: [NSLocalizedDescriptionKey: String(data: responseData, encoding: .utf8) ?? "Unknown error"])
    }

    struct Transcript: Decodable { let text: String }
    let decoded = try JSONDecoder().decode(Transcript.self, from: responseData)
    return decoded.text
}

// Usage:
// let text = try await transcribeAudio(url: audioFileURL, apiBaseURL: "http://localhost:8000", apiKey: "your-secret-key")
// print(text)

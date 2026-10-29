import Foundation

struct APIError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// Parla amb l'aplicació web d'Apps Script (Api.gs). Totes les crides són POST amb JSON.
/// Apps Script respon amb una redirecció 302; URLSession la segueix sola i hi arriba la resposta.
struct AppsScriptClient {
    let baseURL: URL
    let key: String

    private struct Envelope: Decodable {
        let ok: Bool
        let error: String?
    }

    func call<T: Decodable>(_ action: String, _ params: [String: Any] = [:]) async throws -> T {
        var body = params
        body["action"] = action
        body["k"] = key

        var request = URLRequest(url: baseURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 90
        request.setValue("text/plain;charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data: Data
        do {
            data = try await URLSession.shared.data(for: request).0
        } catch let error as URLError where error.code == .timedOut {
            throw APIError(message: "Google ha tardat massa a respondre. Torna-ho a provar.")
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            throw APIError(message: "No hi ha connexió amb Google (\(error.localizedDescription)). Les dades guardades al mòbil es continuen veient.")
        }

        let decoder = JSONDecoder()
        guard let envelope = try? decoder.decode(Envelope.self, from: data) else {
            throw APIError(message: "Resposta inesperada de Google. Revisa que l'URL acabi en /exec i que l'accés sigui \"Qualsevol usuari\".")
        }
        guard envelope.ok else {
            throw APIError(message: envelope.error ?? "Error desconegut")
        }
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw APIError(message: "No entenc la resposta de Google (\(action)): \(error)")
        }
    }
}

struct Pong: Decodable {
    let ok: Bool
}

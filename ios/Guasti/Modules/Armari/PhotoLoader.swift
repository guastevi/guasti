import SwiftUI
import UIKit

enum PhotoSize: String {
    case thumb, medium, full
}

/// Baixa les fotos de Drive a través de l'Apps Script i les guarda al mòbil.
/// Un cop baixada, una foto no es torna a demanar mai més.
actor PhotoLoader {
    static let shared = PhotoLoader()

    private struct PhotoData: Decodable {
        let base64: String
    }

    private let memory = NSCache<NSString, UIImage>()
    private var inflight: [String: Task<UIImage?, Never>] = [:]
    private let directory: URL

    // Apps Script no aguanta gaires peticions alhora: en fem com a molt 4.
    private let maxConcurrent = 4
    private var active = 0
    private var waiting: [CheckedContinuation<Void, Never>] = []

    init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        directory = caches.appendingPathComponent("armari-fotos", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        memory.countLimit = 300
    }

    func image(path: String, size: PhotoSize) async -> UIImage? {
        guard !path.isEmpty else { return nil }
        let key = cacheKey(path, size)
        if let image = memory.object(forKey: key as NSString) { return image }
        if let data = try? Data(contentsOf: fileURL(key)), let image = UIImage(data: data) {
            memory.setObject(image, forKey: key as NSString)
            return image
        }
        if let task = inflight[key] { return await task.value }

        let task = Task<UIImage?, Never> { await self.download(path: path, size: size, key: key) }
        inflight[key] = task
        let image = await task.value
        inflight[key] = nil
        return image
    }

    /// Desa una foto que acabem de pujar, perquè es vegi a l'instant.
    func prime(_ data: Data, for path: String) {
        for size in [PhotoSize.thumb, .medium, .full] {
            let key = cacheKey(path, size)
            try? data.write(to: fileURL(key))
            memory.removeObject(forKey: key as NSString)
        }
    }

    private func download(path: String, size: PhotoSize, key: String) async -> UIImage? {
        await acquire()
        defer { release() }
        guard let client = await MainActor.run(body: { Connection.shared.client }) else { return nil }
        do {
            let response: PhotoData = try await client.call("armari.photo", ["path": path, "size": size.rawValue])
            guard let data = Data(base64Encoded: response.base64), let image = UIImage(data: data) else { return nil }
            try? data.write(to: fileURL(key))
            memory.setObject(image, forKey: key as NSString)
            return image
        } catch {
            return nil
        }
    }

    private func acquire() async {
        if active < maxConcurrent {
            active += 1
            return
        }
        await withCheckedContinuation { waiting.append($0) }
    }

    private func release() {
        if waiting.isEmpty {
            active -= 1
        } else {
            waiting.removeFirst().resume()
        }
    }

    private func cacheKey(_ path: String, _ size: PhotoSize) -> String {
        size.rawValue + "_" + path.replacingOccurrences(of: "/", with: "_")
    }

    private func fileURL(_ key: String) -> URL {
        directory.appendingPathComponent(key)
    }
}

/// Mostra una foto de l'armari, amb un fons gris mentre es carrega.
struct DrivePhoto: View {
    let path: String
    var size: PhotoSize = .thumb
    var contentMode: ContentMode = .fill

    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else {
                Rectangle().fill(Color(.secondarySystemFill))
                if path.isEmpty || failed {
                    Image(systemName: "tshirt")
                        .font(.title)
                        .foregroundStyle(.tertiary)
                } else {
                    ProgressView()
                }
            }
        }
        .task(id: path + size.rawValue) {
            failed = false
            // Primer la versió petita (ja guardada) i després la gran, si cal.
            if size != .thumb, image == nil {
                image = await PhotoLoader.shared.image(path: path, size: .thumb)
            }
            if let better = await PhotoLoader.shared.image(path: path, size: size) {
                image = better
            } else if image == nil {
                failed = true
            }
        }
    }
}

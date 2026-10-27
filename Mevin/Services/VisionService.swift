import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Reads a screenshot through OpenAI vision and returns application names.
/// Nothing except the downscaled JPEG leaves the machine.
enum VisionService {
    enum Failure: Error, Equatable {
        case noKey
        case rejected
        case noNetwork
        case rateLimited
        case timeout
        case invalidJSON
        case noneFound
        case allAlreadyInProfile
        case tooLarge
        case unreadable

        var message: String {
            switch self {
            case .noKey: return "Add an OpenAI key in AI settings to read screenshots."
            case .rejected: return "Your OpenAI key was rejected. Check it in AI settings."
            case .noNetwork: return "Couldn't reach OpenAI. Check your connection."
            case .rateLimited: return "OpenAI is rate limiting. Try again in a moment."
            case .timeout: return "That took too long. Try again."
            case .invalidJSON: return "Couldn't read that image. Try a clearer screenshot."
            case .noneFound: return "Couldn't identify any apps in that image."
            case .allAlreadyInProfile: return "Everything in that screenshot is already in this profile."
            case .tooLarge: return "That image is too large to read."
            case .unreadable: return "Couldn't read that image. Try a clearer screenshot."
            }
        }
    }

    private static let maxEdge: CGFloat = 1536
    private static let maxBytes = 10 * 1024 * 1024
    private static let timeout: TimeInterval = 30

    static func image(fromPasteboard board: NSPasteboard = .general) -> NSImage? {
        if let image = NSImage(pasteboard: board) { return image }
        let urls = board.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] ?? []
        return urls.compactMap { NSImage(contentsOf: $0) }.first
    }

    static func image(fromFile url: URL) -> NSImage? {
        NSImage(contentsOf: url)
    }

    /// Loads the first PNG, JPEG or HEIC from a drop or paste. One image.
    static func loadImage(from providers: [NSItemProvider], completion: @escaping (NSImage?) -> Void) -> Bool {
        if let provider = providers.first(where: { $0.canLoadObject(ofClass: NSImage.self) }) {
            provider.loadObject(ofClass: NSImage.self) { object, _ in
                let image = object as? NSImage
                Task { @MainActor in completion(image) }
            }
            return true
        }
        if let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }) {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                let url: URL?
                if let value = item as? URL {
                    url = value
                } else if let data = item as? Data, let text = String(data: data, encoding: .utf8) {
                    url = URL(string: text)
                } else if let text = item as? String {
                    url = URL(string: text)
                } else {
                    url = nil
                }
                let image = url.flatMap { NSImage(contentsOf: $0) }
                Task { @MainActor in completion(image) }
            }
            return true
        }
        return false
    }

    /// Downscale, JPEG 0.8, no metadata. A Retina Mission Control grab is far
    /// larger than this and would cost several times more for no extra signal.
    static func prepare(_ image: NSImage) -> Swift.Result<Data, Failure> {
        guard let cg = rasterized(image) else { return .failure(.unreadable) }
        let longest = max(cg.width, cg.height)
        let scale = longest > Int(maxEdge) ? maxEdge / CGFloat(longest) : 1
        let width = max(1, Int(CGFloat(cg.width) * scale))
        let height = max(1, Int(CGFloat(cg.height) * scale))
        guard let resized = resize(cg, width: width, height: height) else {
            return .failure(.unreadable)
        }
        guard let jpeg = jpegData(resized, quality: 0.8) else { return .failure(.unreadable) }
        if jpeg.count > maxBytes { return .failure(.tooLarge) }
        return .success(jpeg)
    }

    static func identify(jpeg: Data, apiKey: String) async -> Swift.Result<[AppMatcher.NamedApp], Failure> {
        var request = URLRequest(url: AIProvider.openaiChatURL, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": AIProvider.openaiVisionModel,
            "temperature": 0,
            "response_format": [
                "type": "json_schema",
                "json_schema": [
                    "name": "apps_in_screenshot",
                    "strict": true,
                    "schema": [
                        "type": "object",
                        "properties": [
                            "apps": [
                                "type": "array",
                                "items": [
                                    "type": "object",
                                    "properties": [
                                        "name": ["type": "string"],
                                        "confidence": ["type": "string", "enum": ["high", "low"]]
                                    ],
                                    "required": ["name", "confidence"],
                                    "additionalProperties": false
                                ]
                            ]
                        ],
                        "required": ["apps"],
                        "additionalProperties": false
                    ]
                ]
            ],
            "messages": [
                [
                    "role": "system",
                    "content": """
                    List only macOS applications you can actually identify in this image.
                    Use the application's common name, for example Visual Studio Code, not VS Code or Code.
                    Do not guess. If an icon is unclear, leave it out.
                    Return only JSON matching the schema. No prose.
                    confidence is high or low.
                    """
                ],
                [
                    "role": "user",
                    "content": [
                        ["type": "text", "text": "Which macOS applications are visible in this screenshot?"],
                        [
                            "type": "image_url",
                            "image_url": [
                                "url": "data:image/jpeg;base64,\(jpeg.base64EncodedString())"
                            ]
                        ]
                    ]
                ]
            ]
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if status == 401 || status == 403 { return .failure(.rejected) }
            if status == 429 { return .failure(.rateLimited) }
            if !(200..<300).contains(status) { return .failure(.invalidJSON) }
            return decodeApps(from: data)
        } catch let error as URLError {
            if error.code == .timedOut { return .failure(.timeout) }
            return .failure(.noNetwork)
        } catch {
            return .failure(.noNetwork)
        }
    }

    private static func decodeApps(from data: Data) -> Swift.Result<[AppMatcher.NamedApp], Failure> {
        struct Envelope: Decodable {
            struct Choice: Decodable {
                struct Message: Decodable { var content: String? }
                var message: Message
            }
            var choices: [Choice]
        }
        struct Payload: Decodable {
            struct Item: Decodable {
                var name: String
                var confidence: String
            }
            var apps: [Item]
        }

        guard let envelope = try? JSONDecoder().decode(Envelope.self, from: data),
              let content = envelope.choices.first?.message.content,
              let payloadData = content.data(using: .utf8),
              let payload = try? JSONDecoder().decode(Payload.self, from: payloadData)
        else {
            return .failure(.invalidJSON)
        }

        let apps = payload.apps.compactMap { item -> AppMatcher.NamedApp? in
            let name = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return nil }
            let confidence: AppMatcher.Confidence = item.confidence.lowercased() == "low" ? .low : .high
            return AppMatcher.NamedApp(name: name, confidence: confidence)
        }
        if apps.isEmpty { return .failure(.noneFound) }
        return .success(apps)
    }

    private static func rasterized(_ image: NSImage) -> CGImage? {
        var rect = CGRect(origin: .zero, size: image.size)
        return image.cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }

    private static func resize(_ image: CGImage, width: Int, height: Int) -> CGImage? {
        let color = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: color,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }

    private static func jpegData(_ image: CGImage, quality: CGFloat) -> Data? {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, "public.jpeg" as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return data as Data
    }
}

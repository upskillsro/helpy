import Foundation

enum AssistantBundledAssets {
    private static let transcriptionExecutableNames = [
        "whisper-cli",
        "llama-cli"
    ]

    static var bundledAssistantDirectory: URL? {
        for baseURL in candidateResourceBaseURLs {
            let bundledDirectoryURL = baseURL.appendingPathComponent("BundledAssistant", isDirectory: true)
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: bundledDirectoryURL.path, isDirectory: &isDirectory),
               isDirectory.boolValue {
                return bundledDirectoryURL
            }
        }
        return nil
    }

    static var transcriptionCommandPath: String? {
        for executableName in transcriptionExecutableNames {
            if let executableURL = bundledExecutableURL(named: executableName) {
                return executableURL.path
            }
        }
        return nil
    }

    static var transcriptionModelPath: String? {
        guard let modelsDirectoryURL = bundledDirectoryURL(named: "models") else {
            return nil
        }

        let preferredModelNames = [
            "ggml-large-v3-turbo.bin",
            "whisper-medium-q4_1.bin",
            "ggml-small.bin",
            "ggml-small.en.bin",
            "model.bin"
        ]

        for modelName in preferredModelNames {
            let candidateURL = modelsDirectoryURL.appendingPathComponent(modelName)
            if FileManager.default.fileExists(atPath: candidateURL.path) {
                return candidateURL.path
            }
        }

        guard let candidateURLs = try? FileManager.default.contentsOfDirectory(
            at: modelsDirectoryURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        return candidateURLs
            .filter { ["bin", "gguf"].contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .first?
            .path
    }

    private static var candidateResourceBaseURLs: [URL] {
        var urls: [URL] = []
        if let resourceURL = Bundle.main.resourceURL {
            urls.append(resourceURL)
        }
        if let resourceURL = Bundle.module.resourceURL {
            urls.append(resourceURL)
        }
        return Array(Set(urls))
    }

    private static func bundledDirectoryURL(named name: String) -> URL? {
        guard let bundledAssistantDirectory else { return nil }

        let candidateURL = bundledAssistantDirectory.appendingPathComponent(name, isDirectory: true)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: candidateURL.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return nil
        }
        return candidateURL
    }

    private static func bundledExecutableURL(named name: String) -> URL? {
        guard let bundledAssistantDirectory else { return nil }

        let candidateURLs = [
            bundledAssistantDirectory.appendingPathComponent(name),
            bundledAssistantDirectory.appendingPathComponent("bin", isDirectory: true).appendingPathComponent(name)
        ]

        for candidateURL in candidateURLs where FileManager.default.isExecutableFile(atPath: candidateURL.path) {
            return candidateURL
        }

        return nil
    }
}

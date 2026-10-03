#if DEBUG
import AppKit
import DesktopRewriteKit

enum VisualIntentReplay {
    static func run(config: SupabaseConfig, auth: AuthService) async throws {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "--visual-intent-replay"), args.count > index + 1,
              let outputIndex = args.firstIndex(of: "--output"), args.count > outputIndex + 1 else {
            throw RewriteError.backend("Use --visual-intent-replay request.json --output DIRECTORY [--repeat 3]")
        }
        let repeats: Int
        if let i = args.firstIndex(of: "--repeat"), args.count > i + 1 { repeats = Int(args[i + 1]) ?? 0 }
        else { repeats = 1 }
        guard (1...3).contains(repeats) else { throw RewriteError.invalidResponse }
        let input = URL(fileURLWithPath: args[index + 1])
        let data = try Data(contentsOf: input)
        guard data.count <= 12_000_000 else { throw RewriteError.invalidResponse }
        let request = try JSONDecoder().decode(VisualIntentRequest.self, from: data)
        try request.validate()
        let folder = URL(fileURLWithPath: args[outputIndex + 1], isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        let service = DesktopRewriteService(config: config, auth: auth)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        for run in 1...repeats {
            let file = folder.appendingPathComponent("\(request.captureId)-\(UUID().uuidString)-run\(run).json")
            let start = Date()
            do {
                let response = try await service.visualIntent(request)
                try encoder.encode(response).write(to: file, options: .atomic)
            } catch {
                let message: String
                if case RewriteError.backend(let detail) = error { message = detail }
                else { message = error.localizedDescription }
                let failed: [String: Any] = ["captureId": request.captureId, "targetId": request.targetId,
                    "status": "request_failed", "message": message, "requestMs": Int(Date().timeIntervalSince(start) * 1000)]
                try JSONSerialization.data(withJSONObject: failed, options: [.prettyPrinted, .sortedKeys]).write(to: file, options: .atomic)
                print("Saved failed attempt \(file.path)")
                throw error
            }
            print("Saved \(file.path)")
        }
    }
}
#endif

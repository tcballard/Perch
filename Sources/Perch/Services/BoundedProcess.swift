import Foundation

enum BoundedProcessError: Error {
    case launchFailed
    case timedOut
    case outputTooLarge
    case unsuccessful(Int32)
}

struct BoundedProcess: Sendable {
    static func run(
        executable: URL,
        arguments: [String],
        timeout: TimeInterval = 2,
        outputLimit: Int = 1_000_000
    ) async throws -> Data {
        try await Task.detached(priority: .utility) {
            let process = Process()
            let output = Pipe()
            let errors = Pipe()
            process.executableURL = executable
            process.arguments = arguments
            process.standardOutput = output
            process.standardError = errors

            do {
                try process.run()
            } catch {
                throw BoundedProcessError.launchFailed
            }

            let deadline = Date().addingTimeInterval(timeout)
            while process.isRunning, Date() < deadline {
                try await Task.sleep(for: .milliseconds(20))
            }
            guard !process.isRunning else {
                process.terminate()
                throw BoundedProcessError.timedOut
            }
            guard process.terminationStatus == 0 else {
                throw BoundedProcessError.unsuccessful(process.terminationStatus)
            }

            let data = output.fileHandleForReading.readDataToEndOfFile()
            guard data.count <= outputLimit else {
                throw BoundedProcessError.outputTooLarge
            }
            return data
        }.value
    }
}

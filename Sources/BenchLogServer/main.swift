import BenchLogServerKit
import Foundation
import IOKit.pwr_mgt

// BenchLogServer: the BenchLog server built into the app (Contents/MacOS/BenchLogServer).
//   BenchLogServer            in Terminal; settings from the environment, like server/ with npm start:
//     PORT            8420
//     DATA_DIR        ~/Library/Application Support/BenchLog Server   (library.sqlite, files/, token)
//     BENCHLOG_TOKEN  (optional) overrides the token in DATA_DIR/token
//   BenchLogServer --agent    as the login item "Use This Mac as the Server" registers: logs to
//                             DATA_DIR/server.log and keeps the Mac from sleeping while idle.

setvbuf(stdout, nil, _IOLBF, 0)
let environment = ProcessInfo.processInfo.environment
let agent = CommandLine.arguments.contains("--agent")
let port = UInt16(environment["PORT"] ?? "") ?? BenchLogServer.defaultPort
let dataDirectory = environment["DATA_DIR"].map { URL(fileURLWithPath: $0, isDirectory: true) }
    ?? URL.applicationSupportDirectory.appending(path: "BenchLog Server", directoryHint: .isDirectory)

do {
    try FileManager.default.createDirectory(at: dataDirectory, withIntermediateDirectories: true)
    if agent {
        // The log restarts past 5 MB, so it never fills the disk.
        let log = dataDirectory.appending(path: "server.log")
        if let size = try? log.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > 5_000_000 { try? FileManager.default.removeItem(at: log) }
        freopen(log.path, "a", stdout)
        freopen(log.path, "a", stderr)
        setvbuf(stdout, nil, _IOLBF, 0)
    }
    let token: String
    if let given = environment["BENCHLOG_TOKEN"]?.trimmingCharacters(in: .whitespaces), !given.isEmpty {
        token = given
    } else {
        let (saved, created) = try BenchLogServer.token(in: dataDirectory)
        if created {
            print("New library token (enter it in BenchLog > Settings > Sync): \(saved)")
            print("It is saved in \(dataDirectory.appending(path: "token").path).")
        }
        token = saved
    }
    let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    let server = try BenchLogServer(dataDirectory: dataDirectory, token: token, version: version) { line in
        print(Date.now.formatted(.iso8601.year().month().day().time(includingFractionalSeconds: true)), line)
    }
    Task {
        do {
            try await server.start(port: port)
            print("BenchLog server \(version) on port \(port), data in \(dataDirectory.path)")
        } catch {
            print("BenchLog server could not listen on port \(port): \(error)")
            exit(1)
        }
    }
    var assertion: IOPMAssertionID = 0
    if agent {
        IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleSystemSleep as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                    "BenchLog server: other Macs sync with this one" as CFString, &assertion)
    }
    for sig in [SIGINT, SIGTERM] {
        signal(sig, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
        source.setEventHandler { server.stop(); exit(0) }
        source.resume()
        _ = Unmanaged.passRetained(source)
    }
    dispatchMain()
} catch {
    print("BenchLog server could not start: \(error)")
    exit(1)
}

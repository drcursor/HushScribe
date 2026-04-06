import Foundation

actor SessionStore {
    private let sessionsDirectory: URL
    private var currentFile: URL?
    private var fileHandle: FileHandle?
    private let encoder = JSONEncoder()

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        sessionsDirectory = appSupport.appendingPathComponent("HushScribe/sessions", isDirectory: true)

        try? FileManager.default.createDirectory(at: sessionsDirectory, withIntermediateDirectories: true)

        encoder.dateEncodingStrategy = .iso8601
    }

    func startSession() {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let filename = "session_\(formatter.string(from: Date())).jsonl"
        currentFile = sessionsDirectory.appendingPathComponent(filename)

        FileManager.default.createFile(atPath: currentFile!.path, contents: nil)
        fileHandle = try? FileHandle(forWritingTo: currentFile!)
    }

    func appendRecord(_ record: SessionRecord) {
        guard let fileHandle else { return }

        do {
            let data = try encoder.encode(record)
            fileHandle.seekToEndOfFile()
            fileHandle.write(data)
            fileHandle.write("\n".data(using: .utf8)!)
        } catch {
            print("SessionStore: failed to write record: \(error)")
        }
    }

    func endSession() {
        try? fileHandle?.close()
        fileHandle = nil
        currentFile = nil
    }

    var sessionsDirectoryURL: URL { sessionsDirectory }
}

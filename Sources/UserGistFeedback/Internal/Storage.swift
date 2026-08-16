import Foundation

/// Resolves and manages on-disk storage paths under
/// `Library/Caches/UserGist/{writeKeyHash}/`.
///
/// All file I/O is confined to callers on a serial background queue.
/// The storage layer only builds URLs and exposes read/write primitives;
/// it does NOT manage concurrency.
final class Storage {
    enum StorageError: Error {
        case directoryCreationFailed(URL, Error)
        case readFailed(URL, Error)
        case writeFailed(URL, Error)
    }

    let root: URL
    let eventsLog: URL
    let identityFile: URL
    let consentFile: URL
    let armedTriggersFile: URL
    let frequencyCapsFile: URL
    let showHistoryFile: URL

    private let fileManager: FileManager

    init(writeKeyHash: String, fileManager: FileManager = .default) throws {
        self.fileManager = fileManager
        let caches = try fileManager.url(
            for: .cachesDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let root = caches
            .appendingPathComponent("UserGist", isDirectory: true)
            .appendingPathComponent(writeKeyHash, isDirectory: true)

        do {
            try fileManager.createDirectory(
                at: root,
                withIntermediateDirectories: true,
                attributes: nil
            )
        } catch {
            throw StorageError.directoryCreationFailed(root, error)
        }

        self.root = root
        self.eventsLog = root.appendingPathComponent("events.log")
        self.identityFile = root.appendingPathComponent("identity.json")
        self.consentFile = root.appendingPathComponent("consent.json")
        self.armedTriggersFile = root.appendingPathComponent("armed_triggers.json")
        self.frequencyCapsFile = root.appendingPathComponent("frequency_caps.json")
        self.showHistoryFile = root.appendingPathComponent("show_history.json")
    }

    // MARK: - Primitive I/O

    func readData(at url: URL) throws -> Data? {
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        do {
            return try Data(contentsOf: url)
        } catch {
            throw StorageError.readFailed(url, error)
        }
    }

    func writeData(_ data: Data, to url: URL) throws {
        do {
            try data.write(to: url, options: [.atomic])
        } catch {
            throw StorageError.writeFailed(url, error)
        }
    }

    func appendData(_ data: Data, to url: URL) throws {
        do {
            if fileManager.fileExists(atPath: url.path) {
                let handle = try FileHandle(forWritingTo: url)
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
            } else {
                try data.write(to: url, options: [.atomic])
            }
        } catch {
            throw StorageError.writeFailed(url, error)
        }
    }

    func deleteFile(at url: URL) throws {
        guard fileManager.fileExists(atPath: url.path) else { return }
        do {
            try fileManager.removeItem(at: url)
        } catch {
            throw StorageError.writeFailed(url, error)
        }
    }

    /// Total size (in bytes) of a file on disk, or `0` if missing.
    func fileSize(at url: URL) -> Int {
        guard let attrs = try? fileManager.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? NSNumber else { return 0 }
        return size.intValue
    }

    // MARK: - Codable helpers

    func readJSON<T: Decodable>(_ type: T.Type, at url: URL) throws -> T? {
        guard let data = try readData(at: url), !data.isEmpty else { return nil }
        return try JSONDecoder.usergist().decode(type, from: data)
    }

    func writeJSON<T: Encodable>(_ value: T, to url: URL) throws {
        let data = try JSONEncoder.usergist().encode(value)
        try writeData(data, to: url)
    }
}

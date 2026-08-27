import Foundation

/// Persists locally rendered campaign/event pairs until their matching server
/// instruction is consumed, preventing a relaunch from replaying the surface.
final class LocalInstructionDedupe {
    private static let maxKeys = 200

    private let read: () throws -> [String]?
    private let write: ([String]) throws -> Void
    private let remove: () throws -> Void
    private let onError: (Error) -> Void
    private var keys: [String] = []

    convenience init(storage: Storage, logger: UserGistLogger) {
        self.init(
            read: {
                try storage.readJSON(
                    [String].self,
                    at: storage.localInstructionDedupeFile
                )
            },
            write: {
                try storage.writeJSON($0, to: storage.localInstructionDedupeFile)
            },
            remove: {
                try storage.deleteFile(at: storage.localInstructionDedupeFile)
            },
            onError: {
                logger.warn("unable to persist local instruction dedupe state: \($0)")
            }
        )
    }

    init(
        read: @escaping () throws -> [String]?,
        write: @escaping ([String]) throws -> Void,
        remove: @escaping () throws -> Void,
        onError: @escaping (Error) -> Void = { _ in }
    ) {
        self.read = read
        self.write = write
        self.remove = remove
        self.onError = onError
    }

    func hydrate() {
        do {
            let stored = try read() ?? []
            var seen: Set<String> = []
            let newestUnique = stored.reversed().compactMap { key -> String? in
                guard !key.isEmpty, seen.insert(key).inserted else { return nil }
                return key
            }
            keys = Array(newestUnique.prefix(Self.maxKeys).reversed())
        } catch {
            keys = []
            onError(error)
        }
    }

    func remember(_ key: String) {
        keys.removeAll { $0 == key }
        keys.append(key)
        if keys.count > Self.maxKeys {
            keys.removeFirst(keys.count - Self.maxKeys)
        }
        persist()
    }

    func consume(_ key: String) -> Bool {
        guard let index = keys.firstIndex(of: key) else { return false }
        keys.remove(at: index)
        persist()
        return true
    }

    func clear() {
        keys.removeAll()
        do {
            try remove()
        } catch {
            onError(error)
        }
    }

    var count: Int { keys.count }

    func contains(_ key: String) -> Bool {
        keys.contains(key)
    }

    private func persist() {
        do {
            try write(keys)
        } catch {
            onError(error)
        }
    }
}

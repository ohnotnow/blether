import Foundation

/// Which channel connection answers to which Claude Code session. Pure, so the lookup rules are tested
/// without sockets. Connections are known by an opaque id the server hands out.
struct SessionRegistry<Connection: Hashable> {
    private var entries: [(connection: Connection, key: SessionKey)] = []

    var count: Int { entries.count }

    /// A later registration with the same session id wins the lookup; the earlier one stays until it
    /// closes itself (Claude Code has been seen to connect twice at startup, blether-VYQvH).
    mutating func register(_ connection: Connection, key: SessionKey) {
        entries.removeAll { $0.connection == connection }
        entries.append((connection, key))
    }

    mutating func remove(_ connection: Connection) {
        entries.removeAll { $0.connection == connection }
    }

    /// Exact session id first; then the pid, for a resumed session whose hook still carries the old id;
    /// then, when exactly one session is connected, that one. nil means nobody to tell.
    func lookup(_ key: SessionKey) -> Connection? {
        if let id = key.id, let match = entries.last(where: { $0.key.id == id }) { return match.connection }
        if let pid = key.pid, let match = entries.last(where: { $0.key.pid == pid }) { return match.connection }
        if entries.count == 1 { return entries[0].connection }
        return nil
    }
}

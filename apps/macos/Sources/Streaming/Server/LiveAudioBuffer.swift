import Foundation
import os

/// Fixed-size byte ring shared between the real-time capture callback (writer) and the HTTP
/// server (readers). Positions are absolute byte offsets since the start of capture.
final class LiveAudioBuffer: @unchecked Sendable {
    private let capacity: Int
    private let storage: UnsafeMutablePointer<UInt8>
    private var written = 0
    private let lock = OSAllocatedUnfairLock()

    /// `capacity` must be a multiple of the 4-byte stereo Int16 frame.
    init(capacity: Int) {
        self.capacity = capacity
        storage = .allocate(capacity: capacity)
    }

    deinit { storage.deallocate() }

    var totalWritten: Int { lock.withLockUnchecked { written } }

    func write(_ bytes: UnsafeRawBufferPointer) {
        guard let base = bytes.baseAddress, !bytes.isEmpty else { return }
        lock.withLockUnchecked {
            var source = base.assumingMemoryBound(to: UInt8.self)
            var count = bytes.count
            if count > capacity {
                source += count - capacity
                written += count - capacity
                count = capacity
            }
            let offset = written % capacity
            let firstPart = min(count, capacity - offset)
            (storage + offset).update(from: source, count: firstPart)
            if firstPart < count { storage.update(from: source + firstPart, count: count - firstPart) }
            written += count
        }
    }

    /// Returns up to `maxBytes` written after `position` and advances it. A position older than the
    /// ring jumps to the oldest byte still held.
    func read(from position: inout Int, maxBytes: Int) -> Data {
        lock.withLockUnchecked {
            position = max(position, written - capacity)
            let count = min(written - position, maxBytes)
            guard count > 0 else { return Data() }
            var data = Data(count: count)
            data.withUnsafeMutableBytes { out in
                let destination = out.baseAddress!.assumingMemoryBound(to: UInt8.self)
                let offset = position % capacity
                let firstPart = min(count, capacity - offset)
                destination.update(from: storage + offset, count: firstPart)
                if firstPart < count { (destination + firstPart).update(from: storage, count: count - firstPart) }
            }
            position += count
            return data
        }
    }
}

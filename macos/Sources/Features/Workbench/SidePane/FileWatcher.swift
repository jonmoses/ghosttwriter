import Foundation

/// Watches one file for changes and calls `onChange` on the main actor once the events settle.
///
/// The file and its directory are both watched: an in-place write fires on the file's
/// descriptor, while an atomic save (write a temp file, rename it over the original) replaces
/// the inode, so the file's descriptor is re-opened on the path and the directory catches
/// the rename itself.
final class FileWatcher {
    private let url: URL
    private let debounce: TimeInterval
    private let onChange: @MainActor () -> Void

    private var fileSource: DispatchSourceFileSystemObject?
    private var dirSource: DispatchSourceFileSystemObject?
    private var pending: Task<Void, Never>?
    private var signature: Signature?

    /// What identifies one version of the file on disk.
    private struct Signature: Equatable {
        var inode: UInt64
        var size: Int64
        var mtime: timespec

        static func == (a: Signature, b: Signature) -> Bool {
            a.inode == b.inode && a.size == b.size
                && a.mtime.tv_sec == b.mtime.tv_sec && a.mtime.tv_nsec == b.mtime.tv_nsec
        }
    }

    init(url: URL, debounce: TimeInterval = 0.15, onChange: @escaping @MainActor () -> Void) {
        self.url = url
        self.debounce = debounce
        self.onChange = onChange
    }

    deinit { stop() }

    /// Begins watching. Events are handled on the main queue.
    func start() {
        stop()
        signature = Self.signature(of: url.path)
        openFileSource()
        let dir = url.deletingLastPathComponent().path
        let fd = open(dir, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: .write, queue: .main)
        source.setEventHandler { [weak self] in self?.directoryChanged() }
        source.setCancelHandler { close(fd) }
        source.resume()
        dirSource = source
    }

    /// Stops watching and drops any pending callback.
    func stop() {
        pending?.cancel()
        pending = nil
        fileSource?.cancel()
        fileSource = nil
        dirSource?.cancel()
        dirSource = nil
    }

    private func openFileSource() {
        fileSource?.cancel()
        fileSource = nil
        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .extend, .rename, .delete], queue: .main)
        source.setEventHandler { [weak self, weak source] in
            guard let self, let source else { return }
            self.fileChanged(source.data)
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        fileSource = source
    }

    private func fileChanged(_ events: DispatchSource.FileSystemEvent) {
        if events.contains(.rename) || events.contains(.delete) {
            // An atomic save replaced the inode; follow the path to the new file.
            openFileSource()
        }
        signature = Self.signature(of: url.path)
        schedule()
    }

    private func directoryChanged() {
        // The directory changes for any file in it, so only react when this file did.
        let now = Self.signature(of: url.path)
        guard now != signature else { return }
        if fileSource == nil || now?.inode != signature?.inode { openFileSource() }
        signature = now
        schedule()
    }

    /// Restarts the debounce. The wait is a main-actor `Task.sleep`, so under load it wakes in
    /// deadline order with other main-actor sleepers rather than overtaking them.
    private func schedule() {
        pending?.cancel()
        let onChange = self.onChange
        let delay = UInt64(max(debounce, 0) * 1_000_000_000)
        pending = Task { @MainActor in
            try? await Task.sleep(nanoseconds: delay)
            guard !Task.isCancelled else { return }
            onChange()
        }
    }

    private static func signature(of path: String) -> Signature? {
        var st = stat()
        guard stat(path, &st) == 0 else { return nil }
        return Signature(inode: UInt64(st.st_ino), size: Int64(st.st_size), mtime: st.st_mtimespec)
    }
}

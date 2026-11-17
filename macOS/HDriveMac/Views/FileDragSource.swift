import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct FileDragSelection {
    let files: [RemoteFileItem]
    let client: WebDAVClient
}

/// A passive AppKit drag source lets a SwiftUI row provide one promise per selected item.
struct FileDragSource: NSViewRepresentable {
    let selection: () -> FileDragSelection?
    let onError: (Error) -> Void
    func makeNSView(context: Context) -> FileDragView { FileDragView() }
    func updateNSView(_ view: FileDragView, context: Context) {
        view.selection = selection; view.onError = onError
    }
    static func dismantleNSView(_ view: FileDragView, coordinator: ()) { view.stopMonitoring() }
}

final class FileDragView: NSView, NSDraggingSource {
    var selection: (() -> FileDragSelection?)?
    var onError: ((Error) -> Void)?
    private var monitor: Any?
    private var origin: NSPoint?
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        stopMonitoring()
        guard window != nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]) { [weak self] event in
            guard let self, event.window === self.window else { return event }
            let point = self.convert(event.locationInWindow, from: nil)
            switch event.type {
            case .leftMouseDown:
                guard !self.isHiddenOrHasHiddenAncestor else {
                    self.origin = nil
                    return event
                }
                let visible = self.visibleRect
                let inside = !visible.isEmpty && visible.contains(point)
                self.origin = inside && event.clickCount == 1 ? point : nil
            case .leftMouseUp:
                self.origin = nil
            case .leftMouseDragged:
                guard let start = self.origin, hypot(point.x - start.x, point.y - start.y) >= 5 else { return event }
                self.origin = nil
                guard let capture = self.selection?(), !capture.files.isEmpty else { return event }
                let batch = DragBatch(prepare: { try await FileExportService.prepare(capture.files, client: capture.client) })
                batch.start()
                let providers = FileDragPromise.providers(for: capture, batch: batch, onError: self.onError ?? { _ in })
                let items: [NSDraggingItem] = providers.enumerated().map { index, provider in
                    let item = NSDraggingItem(pasteboardWriter: provider)
                    let image = NSWorkspace.shared.icon(for: capture.files[index].isDirectory ? .folder : .data)
                    item.setDraggingFrame(NSRect(x: point.x - 20 + CGFloat(min(index, 3) * 3), y: point.y - 20 - CGFloat(min(index, 3) * 3), width: 40, height: 40), contents: image)
                    return item
                }
                let session = self.beginDraggingSession(with: items, event: event, source: self)
                session.draggingFormation = .pile

                // Write lazy file URLs to the drag pasteboard for external apps (WhatsApp, Chrome, Safari, Slack, etc.)
                // This ensures external targets receive file URLs without creating duplicate visual dragging items.
                let urlWriters = (0..<capture.files.count).map { index in
                    LazyFileURLWriter { [weak self] in
                        guard let urls = batch.blockingValue(onError: self?.onError), index < urls.count else { return nil }
                        return urls[index]
                    }
                }
                session.draggingPasteboard.writeObjects(urlWriters)

                // Add internal drag payload with remote hrefs for internal folder drop/move
                if let internalData = try? JSONEncoder().encode(capture.files.map { $0.href }) {
                    session.draggingPasteboard.setData(internalData, forType: NSPasteboard.PasteboardType("com.hdrv.remote-hrefs"))
                }
                return nil
            default: break
            }
            return event
        }
    }
    func stopMonitoring() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil; origin = nil
    }
    deinit { if let monitor { NSEvent.removeMonitor(monitor) } }
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .copy }
}

/// A promised pasteboard writer that provides .fileURL and .string lazily on drop.
/// Returning .promised ensures AppKit starts the drag session instantly without blocking,
/// while providing full compatibility with apps (WhatsApp, Chrome, Slack, etc.) that inspect
/// public.file-url and NSFilenamesPboardType.
final class LazyFileURLWriter: NSObject, NSPasteboardWriting {
    let getURL: () -> URL?

    init(getURL: @escaping () -> URL?) {
        self.getURL = getURL
    }

    func writableTypes(for pasteboard: NSPasteboard) -> [NSPasteboard.PasteboardType] {
        return [.fileURL, .string]
    }

    func writingOptions(forType type: NSPasteboard.PasteboardType, pasteboard: NSPasteboard) -> NSPasteboard.WritingOptions {
        return .promised
    }

    func pasteboardPropertyList(forType type: NSPasteboard.PasteboardType) -> Any? {
        guard let url = getURL() else { return nil }
        if type == .fileURL {
            return (url as NSURL).pasteboardPropertyList(forType: .fileURL)
        }
        if type == .string {
            return url.path
        }
        return nil
    }
}

final class FileDragPromise: NSObject, NSFilePromiseProviderDelegate {
    private let name: String
    private let index: Int
    private let batch: DragBatch
    private let onError: (Error) -> Void
    private init(name: String, index: Int, batch: DragBatch, onError: @escaping (Error) -> Void) {
        self.name = name; self.index = index; self.batch = batch; self.onError = onError
    }
    static func providers(for selection: FileDragSelection, prepare: (() async throws -> [URL])? = nil, batch: DragBatch? = nil, onError: @escaping (Error) -> Void) -> [NSFilePromiseProvider] {
        let effectiveBatch = batch ?? DragBatch(prepare: prepare ?? { try await FileExportService.prepare(selection.files, client: selection.client) })
        let names = FileExportService.exportNames(selection.files, config: selection.client.config)
        return selection.files.enumerated().map { index, file in
            let delegate = FileDragPromise(name: names[index], index: index, batch: effectiveBatch, onError: onError)
            let type = file.isDirectory ? UTType.folder : (UTType(filenameExtension: (names[index] as NSString).pathExtension) ?? .data)
            let provider = NSFilePromiseProvider(fileType: type.identifier, delegate: delegate)
            provider.userInfo = delegate // NSFilePromiseProvider's delegate reference is weak.
            return provider
        }
    }
    func filePromiseProvider(_ filePromiseProvider: NSFilePromiseProvider, fileNameForType fileType: String) -> String { name }
    func filePromiseProvider(_ filePromiseProvider: NSFilePromiseProvider, writePromiseTo url: URL, completionHandler: @escaping (Error?) -> Void) {
        Task {
            do {
                let files = try await batch.value()
                // The receiver chooses the destination. Never overwrite an existing item.
                try FileManager.default.copyItem(at: files[index], to: url)
                completionHandler(nil)
            } catch {
                await MainActor.run { onError(error) }
                completionHandler(error)
            }
        }
    }
}

final class DragBatch: @unchecked Sendable {
    private let lock = NSLock()
    private var task: Task<[URL], Error>?
    private let prepare: () async throws -> [URL]

    init(prepare: @escaping () async throws -> [URL]) {
        self.prepare = prepare
    }

    @discardableResult
    func start() -> Task<[URL], Error> {
        lock.lock()
        defer { lock.unlock() }
        if let task { return task }
        let t = Task { try await prepare() }
        self.task = t
        return t
    }

    func value() async throws -> [URL] {
        let t = start()
        return try await t.value
    }

    func blockingValue(onError: ((Error) -> Void)? = nil) -> [URL]? {
        let t = start()
        var completed = false
        var result: Result<[URL], Error>?

        Task {
            do {
                let urls = try await t.value
                result = .success(urls)
            } catch {
                result = .failure(error)
            }
            completed = true
        }

        let timeout = Date(timeIntervalSinceNow: 25.0)
        while !completed && Date() < timeout {
            RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.05))
        }

        switch result {
        case .success(let urls):
            return urls
        case .failure(let error):
            onError?(error)
            return nil
        case .none:
            return nil
        }
    }
}

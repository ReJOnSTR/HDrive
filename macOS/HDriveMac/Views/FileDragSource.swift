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
    private var captured: FileDragSelection?
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
                // Capture the selection before the SwiftUI row changes it on mouse-down.
                let inside = self.visibleRect.contains(point) && !self.isHiddenOrHasHiddenAncestor
                self.origin = inside && event.clickCount == 1 ? point : nil
                self.captured = self.origin == nil ? nil : self.selection?()
            case .leftMouseUp:
                self.origin = nil; self.captured = nil
            case .leftMouseDragged:
                guard let start = self.origin, hypot(point.x - start.x, point.y - start.y) >= 5,
                      let capture = self.captured, !capture.files.isEmpty else { return event }
                self.origin = nil; self.captured = nil
                let providers = FileDragPromise.providers(for: capture, onError: self.onError ?? { _ in })
                let items = providers.enumerated().map { index, provider in
                    let item = NSDraggingItem(pasteboardWriter: provider)
                    let image = NSWorkspace.shared.icon(for: capture.files[index].isDirectory ? .folder : .data)
                    item.setDraggingFrame(NSRect(x: point.x + CGFloat(index % 4) * 4, y: point.y, width: 40, height: 40), contents: image)
                    return item
                }
                let session = self.beginDraggingSession(with: items, event: event, source: self)
                session.draggingFormation = .pile
                return nil
            default: break
            }
            return event
        }
    }
    func stopMonitoring() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil; origin = nil; captured = nil
    }
    deinit { if let monitor { NSEvent.removeMonitor(monitor) } }
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .copy }
}

final class FileDragPromise: NSObject, NSFilePromiseProviderDelegate {
    private let name: String
    private let index: Int
    private let batch: DragBatch
    private let onError: (Error) -> Void
    private init(name: String, index: Int, batch: DragBatch, onError: @escaping (Error) -> Void) {
        self.name = name; self.index = index; self.batch = batch; self.onError = onError
    }
    static func providers(for selection: FileDragSelection, prepare: (() async throws -> [URL])? = nil, onError: @escaping (Error) -> Void) -> [NSFilePromiseProvider] {
        let batch = DragBatch(prepare: prepare ?? { try await FileExportService.prepare(selection.files, client: selection.client) })
        let names = FileExportService.exportNames(selection.files, config: selection.client.config)
        return selection.files.enumerated().map { index, file in
            let delegate = FileDragPromise(name: names[index], index: index, batch: batch, onError: onError)
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

private actor DragBatch {
    private var task: Task<[URL], Error>?
    private let prepare: () async throws -> [URL]
    init(prepare: @escaping () async throws -> [URL]) { self.prepare = prepare }
    func value() async throws -> [URL] {
        if let task { return try await task.value }
        let task = Task { try await prepare() }; self.task = task
        return try await task.value
    }
}

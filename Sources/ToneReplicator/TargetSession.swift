import AppKit
import Combine
import UniformTypeIdentifiers

@MainActor
final class TargetSession: ObservableObject {
    @Published private(set) var library = TargetLibrary()
    @Published private(set) var importing = false
    @Published var startText = "0"
    @Published var durationText = "10"
    @Published var title = ""
    @Published var artist = ""
    @Published var recordingVersion = ""
    @Published var part = ""
    @Published var claimDraft = TargetClaim()
    @Published var message = "Import a local recording and choose the guitar section you want to match."
    @Published var error: String?
    private var store: TargetStore?
    private var loadFailed = false
    var selected: TargetReference? { library.selected }
    var selectedAnalysisURL: URL? {
        guard let selected, let store else { return nil }
        return store.assets.appendingPathComponent(selected.id.uuidString).appendingPathComponent("analysis.wav")
    }

    init() {
        do {
            let project = try ProjectStore.standard()
            let store = TargetStore(root: project.url.deletingLastPathComponent())
            self.store = store
            library = try store.load()
            updateFields()
        } catch { loadFailed = true; self.error = error.localizedDescription }
    }
    private func updateFields() {
        title = selected?.title ?? ""; artist = selected?.artist ?? ""
        recordingVersion = selected?.recordingVersion ?? ""; part = selected?.part ?? ""
        claimDraft = TargetClaim()
    }
    private func commit(_ next: TargetLibrary) throws {
        guard !loadFailed, let store else { throw TargetError.invalidLibrary }
        try store.save(next); library = next
    }
    func select(_ id: UUID?) {
        guard !importing else { return }
        do {
            guard id == nil || library.references.contains(where: { $0.id == id }) else { throw TargetError.missingTarget }
            var next = library; next.selectedID = id
            try commit(next); updateFields(); error = nil
        } catch { self.error = error.localizedDescription }
    }
    func chooseAudio() {
        guard !importing, !loadFailed, let store else { return }
        guard let start = Double(startText), let duration = Double(durationText),
              start.isFinite, start >= 0, duration.isFinite, (1...30).contains(duration) else {
            error = TargetError.invalidClip.localizedDescription; return
        }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio]; panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false; panel.prompt = "Import reference"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        importing = true; error = nil; message = "Preserving source and analyzing your selected section…"
        Task {
            do {
                let record = try await Task.detached(priority: .userInitiated) {
                    let access = url.startAccessingSecurityScopedResource()
                    defer { if access { url.stopAccessingSecurityScopedResource() } }
                    return try ReferenceImporter.importAudio(url: url, start: start, duration: duration, store: store)
                }.value
                var next = library; next.references.append(record); next.selectedID = record.id
                try commit(next); updateFields()
                message = "Reference saved locally. Your original recording is preserved."
            } catch { self.error = error.localizedDescription; message = "Import did not complete. Existing targets are unchanged." }
            importing = false
        }
    }
    func saveDetails() {
        guard !importing else { return }
        do {
            guard let index = library.references.firstIndex(where: { $0.id == library.selectedID }) else { throw TargetError.missingTarget }
            var next = library
            next.references[index].title = title
            next.references[index].artist = artist
            next.references[index].recordingVersion = recordingVersion
            next.references[index].part = part
            try commit(next); error = nil; message = "Target details saved."
        } catch { self.error = error.localizedDescription }
    }
    func addClaim() {
        guard !importing else { return }
        do {
            guard let index = library.references.firstIndex(where: { $0.id == library.selectedID }) else { throw TargetError.missingTarget }
            var claim = claimDraft; claim.id = UUID(); claim.assessedAt = Date()
            try claim.validate()
            var next = library; next.references[index].claims.append(claim)
            try commit(next); claimDraft = TargetClaim(); error = nil; message = "Evidence claim saved with its source and status."
        } catch { self.error = error.localizedDescription }
    }
    func revealFiles() {
        guard let selected, let store else { return }
        let original = store.assets.appendingPathComponent(selected.id.uuidString).appendingPathComponent(selected.originalFilename)
        NSWorkspace.shared.activateFileViewerSelecting([original])
    }
}

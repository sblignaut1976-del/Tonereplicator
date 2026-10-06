import XCTest
@testable import ToneReplicator

final class ProjectTests: XCTestCase {
    func testRoutingSurvivesRestart() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = ProjectStore(url: dir.appendingPathComponent("project.json"))
        var project = try store.load()
        project.selectedInterfaceUID = "fixture-interface"
        var route = RoutingPreset(); route.inputUID = "fixture-interface"; route.outputUID = "fixture-interface"; route.inputChannel = 1
        project.routingByInterface[project.selectedInterfaceUID] = route
        try store.save(project)
        XCTAssertEqual(try ProjectStore(url: store.url).load(), project)
    }
    func testNewerSchemaAndWrongRateAreRejectedWithoutOverwrite() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = ProjectStore(url: dir.appendingPathComponent("project.json"))
        for text in ["{\"schemaVersion\":3,\"analysisRate\":44100}", "{\"schemaVersion\":1,\"analysisRate\":48000}", "broken"] {
            let data = Data(text.utf8); try data.write(to: store.url)
            XCTAssertThrowsError(try store.load())
            XCTAssertEqual(try Data(contentsOf: store.url), data)
        }
    }
}

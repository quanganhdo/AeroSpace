@testable import AppBundle
import XCTest

@MainActor
final class DwindleInsertionTest: XCTestCase {
    override func setUp() async throws { setUpWorkspacesForTests() }

    func testInsertionPreservesUnsplitSiblingSize() async throws {
        let workspace = Workspace.get(byName: name)
        let root = workspace.rootTilingContainer
        root.layout = .dwindle

        let splitWindow = TestWindow.new(id: 1, parent: root, adaptiveWeight: 70)
        let unaffectedWindow = TestWindow.new(id: 2, parent: root, adaptiveWeight: 30)

        try await workspace.layoutWorkspace()
        let unaffectedRectBeforeInsertion = unaffectedWindow.lastAppliedLayoutVirtualRect
        splitWindow.markAsMostRecentChild()
        assertEquals(workspace.mostRecentWindowRecursive?.windowId, splitWindow.windowId)

        _ = insertNewDwindleWindow(id: 3, in: workspace)
        assertEquals(root.children.count, 2)
        try await workspace.layoutWorkspace()

        assertRectEquals(unaffectedWindow.lastAppliedLayoutVirtualRect, unaffectedRectBeforeInsertion)
    }

    func testNestedInsertionPreservesEveryUnaffectedBranchSize() async throws {
        let workspace = Workspace.get(byName: name)
        let root = workspace.rootTilingContainer
        root.layout = .dwindle

        let nested = TilingContainer(
            parent: root,
            adaptiveWeight: 70,
            .v,
            .dwindle,
            index: INDEX_BIND_LAST,
        )
        let splitWindow = TestWindow.new(id: 1, parent: nested, adaptiveWeight: 60)
        let nestedUnaffectedWindow = TestWindow.new(id: 2, parent: nested, adaptiveWeight: 40)
        let rootUnaffectedWindow = TestWindow.new(id: 3, parent: root, adaptiveWeight: 30)

        try await workspace.layoutWorkspace()
        let nestedUnaffectedRectBeforeInsertion = nestedUnaffectedWindow.lastAppliedLayoutVirtualRect
        let rootUnaffectedRectBeforeInsertion = rootUnaffectedWindow.lastAppliedLayoutVirtualRect
        splitWindow.markAsMostRecentChild()
        assertEquals(workspace.mostRecentWindowRecursive?.windowId, splitWindow.windowId)

        _ = insertNewDwindleWindow(id: 4, in: workspace)
        assertEquals(root.children.count, 2)
        try await workspace.layoutWorkspace()

        assertRectEquals(nestedUnaffectedWindow.lastAppliedLayoutVirtualRect, nestedUnaffectedRectBeforeInsertion)
        assertRectEquals(rootUnaffectedWindow.lastAppliedLayoutVirtualRect, rootUnaffectedRectBeforeInsertion)
    }

    func testInsertionSplitsNearestDwindleSlotAboveNonDwindleBranch() async throws {
        let workspace = Workspace.get(byName: name)
        let root = workspace.rootTilingContainer
        root.layout = .dwindle

        let nestedDwindle = TilingContainer(
            parent: root,
            adaptiveWeight: 70,
            .v,
            .dwindle,
            index: INDEX_BIND_LAST,
        )
        let tilesBranch = TilingContainer(
            parent: nestedDwindle,
            adaptiveWeight: 60,
            .h,
            .tiles,
            index: INDEX_BIND_LAST,
        )
        let splitWindow = TestWindow.new(id: 1, parent: tilesBranch, adaptiveWeight: 70)
        TestWindow.new(id: 2, parent: tilesBranch, adaptiveWeight: 30)
        let nestedUnaffectedWindow = TestWindow.new(id: 3, parent: nestedDwindle, adaptiveWeight: 40)
        let rootUnaffectedWindow = TestWindow.new(id: 4, parent: root, adaptiveWeight: 30)

        try await workspace.layoutWorkspace()
        let nestedUnaffectedRectBeforeInsertion = nestedUnaffectedWindow.lastAppliedLayoutVirtualRect
        let rootUnaffectedRectBeforeInsertion = rootUnaffectedWindow.lastAppliedLayoutVirtualRect
        splitWindow.markAsMostRecentChild()

        let newWindow = insertNewDwindleWindow(id: 5, in: workspace)
        try await workspace.layoutWorkspace()

        let splitContainer = tilesBranch.parent as? TilingContainer
        assertEquals(splitContainer?.layout, .dwindle)
        assertEquals(splitContainer?.parent, nestedDwindle)
        assertEquals(newWindow.parent, splitContainer)
        assertEquals(tilesBranch.layout, .tiles)
        assertRectEquals(nestedUnaffectedWindow.lastAppliedLayoutVirtualRect, nestedUnaffectedRectBeforeInsertion)
        assertRectEquals(rootUnaffectedWindow.lastAppliedLayoutVirtualRect, rootUnaffectedRectBeforeInsertion)
    }

    func testInsertionBeforeInitialLayoutUsesBalancedProvisionalWeights() async throws {
        let workspace = Workspace.get(byName: name)
        let root = workspace.rootTilingContainer
        root.layout = .dwindle

        let splitWindow = TestWindow.new(id: 1, parent: root, adaptiveWeight: 70)
        let unaffectedWindow = TestWindow.new(id: 2, parent: root, adaptiveWeight: 30)
        splitWindow.markAsMostRecentChild()

        _ = insertNewDwindleWindow(id: 3, in: workspace)
        try await workspace.layoutWorkspace()

        let splitContainer = root.children.first as? TilingContainer
        assertEquals(splitContainer?.lastAppliedLayoutVirtualRect?.width, unaffectedWindow.lastAppliedLayoutVirtualRect?.width)
    }

    private func insertNewDwindleWindow(id: UInt32, in workspace: Workspace) -> TestWindow {
        let binding = unbindAndGetBindingDataForNewTilingWindowForDwindleLayout(workspace, window: nil)
        return TestWindow.new(
            id: id,
            parent: binding.parent,
            adaptiveWeight: binding.adaptiveWeight,
        )
    }
}

private func assertRectEquals(
    _ actual: Rect?,
    _ expected: Rect?,
    file: StaticString = #filePath,
    line: UInt = #line,
) {
    guard let actual, let expected else {
        XCTFail("Expected two layout rectangles", file: file, line: line)
        return
    }
    assertEquals(actual.topLeftX, expected.topLeftX, additionalMsg: "topLeftX", file: file, line: line)
    assertEquals(actual.topLeftY, expected.topLeftY, additionalMsg: "topLeftY", file: file, line: line)
    assertEquals(actual.width, expected.width, additionalMsg: "width", file: file, line: line)
    assertEquals(actual.height, expected.height, additionalMsg: "height", file: file, line: line)
}

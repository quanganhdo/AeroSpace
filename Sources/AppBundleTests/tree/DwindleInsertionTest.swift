@testable import AppBundle
import Common
import Testing

@MainActor
@Suite(.serializedGlobally)
struct DwindleInsertionTest {
    init() { setUpWorkspacesForTests() }

    @Test func testInsertionPreservesUnsplitSiblingSize() async throws {
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

    @Test func testNestedInsertionPreservesEveryUnaffectedBranchSize() async throws {
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

    @Test func testInsertionSplitsNearestDwindleSlotAboveNonDwindleBranch() async throws {
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

    @Test func testInsertionBeforeInitialLayoutUsesBalancedProvisionalWeights() async throws {
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

    @Test func testInsertionIgnoresInvisibleChildWhenChoosingAndSplittingSlot() async throws {
        let workspace = Workspace.get(byName: name)
        let root = workspace.rootTilingContainer
        root.layout = .dwindle
        let splitWindow = TestWindow.new(id: 1, parent: root, adaptiveWeight: 70)
        let unaffectedWindow = TestWindow.new(id: 2, parent: root, adaptiveWeight: 30)
        let invisibleWindow = TestWindow.new(id: 3, parent: root)
        invisibleWindow.lifeStatus = .invisible
        try await workspace.layoutWorkspace()
        let unaffectedRect = unaffectedWindow.lastAppliedLayoutVirtualRect
        splitWindow.markAsMostRecentChild()
        invisibleWindow.markAsMostRecentChild()

        let newWindow = insertNewDwindleWindow(id: 4, in: workspace)
        try await workspace.layoutWorkspace()

        let splitContainer = try #require(splitWindow.parent as? TilingContainer)
        #expect(splitContainer !== root)
        #expect(newWindow.parent === splitContainer)
        #expect(splitContainer.children == [splitWindow, newWindow])
        #expect(invisibleWindow.parent === root)
        #expect(invisibleWindow.lifeStatus == .invisible)
        assertRectEquals(unaffectedWindow.lastAppliedLayoutVirtualRect, unaffectedRect)
    }

    @Test func testInsertionSplitsAliveSlotAboveMustBeFlattenedDwindleAncestor() async throws {
        let workspace = Workspace.get(byName: name)
        let root = workspace.rootTilingContainer
        root.layout = .dwindle
        let transparentContainer = TilingContainer(parent: root, adaptiveWeight: 70, .v, .dwindle, index: INDEX_BIND_LAST)
        let splitWindow = TestWindow.new(id: 1, parent: transparentContainer)
        let invisibleWindow = TestWindow.new(id: 2, parent: transparentContainer)
        invisibleWindow.lifeStatus = .invisible
        transparentContainer.lifeStatus = .mustBeFlattened
        let unaffectedWindow = TestWindow.new(id: 3, parent: root, adaptiveWeight: 30)
        try await workspace.layoutWorkspace()
        let unaffectedRect = unaffectedWindow.lastAppliedLayoutVirtualRect
        splitWindow.markAsMostRecentChild()

        let newWindow = insertNewDwindleWindow(id: 4, in: workspace)
        try await workspace.layoutWorkspace()

        let splitContainer = try #require(transparentContainer.parent as? TilingContainer)
        #expect(splitContainer !== root)
        #expect(splitContainer.parent === root)
        #expect(newWindow.parent === splitContainer)
        #expect(transparentContainer.children == [splitWindow, invisibleWindow])
        #expect(transparentContainer.lifeStatus == .mustBeFlattened)
        assertRectEquals(unaffectedWindow.lastAppliedLayoutVirtualRect, unaffectedRect)
    }

    private func insertNewDwindleWindow(id: OpaqueWindowId, in workspace: Workspace) -> TestWindow {
        let binding = unbindAndGetBindingDataForNewTilingWindowForDwindleLayout(workspace)
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
    sourceLocation: SourceLocation = #_sourceLocation,
) {
    guard let actual, let expected else {
        Issue.record("Expected two layout rectangles", sourceLocation: sourceLocation)
        return
    }
    assertEquals(actual.topLeftX, expected.topLeftX, additionalMsg: "topLeftX", sourceLocation: sourceLocation)
    assertEquals(actual.topLeftY, expected.topLeftY, additionalMsg: "topLeftY", sourceLocation: sourceLocation)
    assertEquals(actual.width, expected.width, additionalMsg: "width", sourceLocation: sourceLocation)
    assertEquals(actual.height, expected.height, additionalMsg: "height", sourceLocation: sourceLocation)
}

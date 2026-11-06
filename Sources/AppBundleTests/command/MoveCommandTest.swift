@testable import AppBundle
import Common
import Testing

@MainActor
@Suite(.serializedGlobally)
struct MoveCommandTest {
    init() { setUpWorkspacesForTests() }

    @Test func testParse() {
        assertNil(parseCommand("move --fail-if-fullscreen left").errorOrNil)
        assertNil(parseCommand("move --fail-if-macos-native-fullscreen --window-id 1 right").errorOrNil)
    }

    @Test func testFailIfFullscreen() async {
        let root = Workspace.get(byName: name).rootTilingContainer.apply {
            let window = TestWindow.new(id: 1, parent: $0)
            assertEquals(window.focusWindow(), true)
            window.isFullscreen = true
            TestWindow.new(id: 2, parent: $0)
        }

        let result = await parseCommand("move --fail-if-fullscreen right").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(result.exitCode.rawValue, 2)
        assertEquals(root.layoutDescription, .h_tiles([.window(1), .window(2)]))
    }

    @Test func testFailIfMacosNativeFullscreen() async {
        let root = Workspace.get(byName: name).rootTilingContainer.apply {
            let window = TestWindow.new(id: 1, parent: $0)
            assertEquals(window.focusWindow(), true)
            window.isMacosFullscreenForTest = true
            TestWindow.new(id: 2, parent: $0)
        }

        let result = await parseCommand("move --fail-if-macos-native-fullscreen right").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(result.exitCode.rawValue, 2)
        assertEquals(root.layoutDescription, .h_tiles([.window(1), .window(2)]))
    }

    @Test func testFailIfFullscreenAllowsRegularWindows() async {
        let root = Workspace.get(byName: name).rootTilingContainer.apply {
            assertEquals(TestWindow.new(id: 1, parent: $0).focusWindow(), true)
            TestWindow.new(id: 2, parent: $0)
        }

        let result = await parseCommand("move --fail-if-fullscreen --fail-if-macos-native-fullscreen right").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(result.exitCode.rawValue, 0)
        assertEquals(root.layoutDescription, .h_tiles([.window(2), .window(1)]))
    }

    @Test func testMove_swapWindows() async {
        let root = Workspace.get(byName: name).rootTilingContainer.apply {
            assertEquals(TestWindow.new(id: 1, parent: $0).focusWindow(), true)
            TestWindow.new(id: 2, parent: $0)
        }

        await parseCommand("move right").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(root.layoutDescription, .h_tiles([.window(2), .window(1)]))
    }

    @Test func testMove_swapWindows_skipsTombstones() async {
        let root = Workspace.get(byName: name).rootTilingContainer.apply {
            assertEquals(TestWindow.new(id: 1, parent: $0).focusWindow(), true)
            TestWindow.new(id: 2, parent: $0).lifeStatus = .dead
            TestWindow.new(id: 3, parent: $0)
        }

        await parseCommand("move right").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(root.layoutDescription, .h_tiles([.window(2), .window(3), .window(1)]))

        await parseCommand("move left").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(root.layoutDescription, .h_tiles([.window(2), .window(1), .window(3)]))
    }

    @Test func testMoveInto_skipsTombstones() async {
        let root = Workspace.get(byName: name).rootTilingContainer.apply {
            assertEquals(TestWindow.new(id: 1, parent: $0).focusWindow(), true)
            TilingContainer.newVTiles(parent: $0, adaptiveWeight: 1).apply {
                TestWindow.new(id: 2, parent: $0).lifeStatus = .dead
                TestWindow.new(id: 3, parent: $0).lifeStatus = .invisible
                $0.lifeStatus = .deadOrInvisible
            }
            TilingContainer.newVTiles(parent: $0, adaptiveWeight: 1).apply {
                TestWindow.new(id: 4, parent: $0)
                TestWindow.new(id: 5, parent: $0).lifeStatus = .dead // The most recent child of its parent
            }
        }

        await parseCommand("move right").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(
            root.layoutDescription,
            .h_tiles([
                .v_tiles([.window(2), .window(3)]),
                .v_tiles([.window(4), .window(1), .window(5)]),
            ]),
        )
    }

    @Test func testMoveInto_deepTargetInsideMustBeFlattenedContainer_bindsOutsideOfIt() async {
        let root = Workspace.get(byName: name).rootTilingContainer.apply {
            assertEquals(TestWindow.new(id: 1, parent: $0).focusWindow(), true)
            TilingContainer.newVTiles(parent: $0, adaptiveWeight: 1).apply {
                TestWindow.new(id: 2, parent: $0)
                TilingContainer.newVTiles(parent: $0, adaptiveWeight: 1).apply {
                    TestWindow.new(id: 3, parent: $0).lifeStatus = .dead
                    TestWindow.new(id: 4, parent: $0)
                    $0.lifeStatus = .mustBeFlattened
                }
            }
        }

        await parseCommand("move right").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(
            root.layoutDescription,
            .h_tiles([
                .v_tiles([
                    .window(2),
                    .v_tiles([.window(3), .window(4)]),
                    .window(1),
                ]),
            ]),
        )
    }

    @Test func testMoveInto_skipsMustBeFlattenedContainers() async {
        config.enableNormalizationFlattenContainers = true

        let root = Workspace.get(byName: name).rootTilingContainer.apply {
            assertEquals(TestWindow.new(id: 1, parent: $0).focusWindow(), true)
            // Same orientation as the root. Without tombstones it would have been flattened
            TilingContainer.newHTiles(parent: $0, adaptiveWeight: 1).apply {
                TestWindow.new(id: 2, parent: $0).lifeStatus = .dead
                TestWindow.new(id: 3, parent: $0)
                $0.lifeStatus = .mustBeFlattened
            }
        }

        await parseCommand("move right").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(root.layoutDescription, .h_tiles([.h_tiles([.window(2), .window(3)]), .window(1)]))

        await parseCommand("move left").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(root.layoutDescription, .h_tiles([.window(1), .h_tiles([.window(2), .window(3)])]))
    }

    @Test func testMoveOut_skipsMustBeFlattenedContainers() async {
        let root = Workspace.get(byName: name).rootTilingContainer.apply {
            TestWindow.new(id: 1, parent: $0)
            // Same orientation as the root. Without tombstones it would have been flattened
            TilingContainer.newHTiles(parent: $0, adaptiveWeight: 1).apply {
                TestWindow.new(id: 2, parent: $0).lifeStatus = .dead
                TilingContainer.newVTiles(parent: $0, adaptiveWeight: 1).apply {
                    assertEquals(TestWindow.new(id: 3, parent: $0).focusWindow(), true)
                    TestWindow.new(id: 4, parent: $0)
                }
                $0.lifeStatus = .mustBeFlattened
            }
        }

        await parseCommand("move right").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(
            root.layoutDescription,
            .h_tiles([
                .window(1),
                .h_tiles([.window(2), .v_tiles([.window(4)])]),
                .window(3),
            ]),
        )
    }

    @Test func testMoveOut_whenOnlyTombstoneSiblings() async {
        let root = Workspace.get(byName: name).rootTilingContainer.apply {
            TilingContainer.newVTiles(parent: $0, adaptiveWeight: 1).apply {
                assertEquals(TestWindow.new(id: 1, parent: $0).focusWindow(), true)
                TestWindow.new(id: 2, parent: $0)
            }
            TestWindow.new(id: 3, parent: $0).lifeStatus = .dead
        }

        await parseCommand("move right").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(root.layoutDescription, .h_tiles([.v_tiles([.window(2)]), .window(1), .window(3)]))
    }

    @Test func testMoveInto_findTopMostContainerWithRightOrientation() async {
        let root = Workspace.get(byName: name).rootTilingContainer.apply {
            TestWindow.new(id: 0, parent: $0)
            assertEquals(TestWindow.new(id: 1, parent: $0).focusWindow(), true)
            TilingContainer.newHTiles(parent: $0, adaptiveWeight: 1).apply {
                TilingContainer.newHTiles(parent: $0, adaptiveWeight: 1).apply {
                    TestWindow.new(id: 2, parent: $0)
                }
            }
        }

        await parseCommand("move right").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(
            root.layoutDescription,
            .h_tiles([
                .window(0),
                .h_tiles([
                    .window(1),
                    .h_tiles([
                        .window(2),
                    ]),
                ]),
            ]),
        )
    }

    @Test func testMove_mru() async {
        var window3: Window!
        let root = Workspace.get(byName: name).rootTilingContainer.apply {
            TestWindow.new(id: 0, parent: $0)
            assertEquals(TestWindow.new(id: 1, parent: $0).focusWindow(), true)
            TilingContainer.newVTiles(parent: $0, adaptiveWeight: 1).apply {
                TilingContainer.newHTiles(parent: $0, adaptiveWeight: 1).apply {
                    TestWindow.new(id: 2, parent: $0)
                    window3 = TestWindow.new(id: 3, parent: $0)
                }
                TestWindow.new(id: 4, parent: $0)
            }
        }
        window3.markAsMostRecentChild()

        await parseCommand("move right").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(
            root.layoutDescription,
            .h_tiles([
                .window(0),
                .v_tiles([
                    .h_tiles([
                        .window(1),
                        .window(2),
                        .window(3),
                    ]),
                    .window(4),
                ]),
            ]),
        )
    }

    @Test func testSwap_preserveWeight() async {
        let root = Workspace.get(byName: name).rootTilingContainer
        let window1 = TestWindow.new(id: 1, parent: root, adaptiveWeight: 1)
        let window2 = TestWindow.new(id: 2, parent: root, adaptiveWeight: 2)
        _ = window2.focusWindow()

        await parseCommand("move left").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(window2.hWeight, 2)
        assertEquals(window1.hWeight, 1)
    }

    @Test func testMoveIn_newWeight() async {
        var window1: Window!
        var window2: Window!
        Workspace.get(byName: name).rootTilingContainer.apply {
            TestWindow.new(id: 0, parent: $0, adaptiveWeight: 1)
            window1 = TestWindow.new(id: 1, parent: $0, adaptiveWeight: 2)
            TilingContainer.newVTiles(parent: $0, adaptiveWeight: 1).apply {
                window2 = TestWindow.new(id: 2, parent: $0, adaptiveWeight: 1)
            }
        }
        _ = window1.focusWindow()

        await parseCommand("move right").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(window2.hWeight, 1)
        assertEquals(window2.vWeight, 1)
        assertEquals(window1.vWeight, 1)
        assertEquals(window1.hWeight, 1)
    }

    @Test func testCreateImplicitContainer() async {
        let workspace = Workspace.get(byName: name)
        workspace.rootTilingContainer.apply {
            TestWindow.new(id: 1, parent: $0)
            assertEquals(TestWindow.new(id: 2, parent: $0).focusWindow(), true)
            TestWindow.new(id: 3, parent: $0)
        }

        let result = await parseCommand("move up").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(
            workspace.layoutDescription,
            .workspace([
                .v_tiles([
                    .window(2),
                    .h_tiles([.window(1), .window(3)]),
                ]),
            ]),
        )
        assertEquals(result.exitCode.rawValue, 0)
    }

    @Test func testStop_onRootNode() async {
        let workspace = Workspace.get(byName: name)
        workspace.rootTilingContainer.apply {
            assertEquals(TestWindow.new(id: 1, parent: $0).focusWindow(), true)
            TestWindow.new(id: 2, parent: $0)
            TestWindow.new(id: 3, parent: $0)
        }

        let result = await parseCommand("move --boundaries-action stop left").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(
            workspace.layoutDescription,
            .workspace([
                .h_tiles([.window(1), .window(2), .window(3)]),
            ]),
        )
        assertEquals(result.exitCode.rawValue, 0)
    }

    @Test func testStop_onRootNode_withOppositeOrientation() async {
        let workspace = Workspace.get(byName: name)
        workspace.rootTilingContainer.apply {
            assertEquals(TestWindow.new(id: 1, parent: $0).focusWindow(), true)
            TestWindow.new(id: 2, parent: $0)
            TestWindow.new(id: 3, parent: $0)
        }

        let result = await parseCommand("move --boundaries-action stop up").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(
            workspace.layoutDescription,
            .workspace([
                .h_tiles([.window(1), .window(2), .window(3)]),
            ]),
        )
        assertEquals(result.exitCode.rawValue, 0)
    }

    @Test func testStop_onRootNode_whenNoBoundary() async {
        let workspace = Workspace.get(byName: name)
        workspace.rootTilingContainer.apply {
            TestWindow.new(id: 1, parent: $0)
            assertEquals(TestWindow.new(id: 2, parent: $0).focusWindow(), true)
            TestWindow.new(id: 3, parent: $0)
        }

        let result = await parseCommand("move --boundaries-action stop left").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(
            workspace.layoutDescription,
            .workspace([
                .h_tiles([.window(2), .window(1), .window(3)]),
            ]),
        )
        assertEquals(result.exitCode.rawValue, 0)
    }

    @Test func testStop_onInnerNode() async {
        let workspace = Workspace.get(byName: name)
        workspace.rootTilingContainer.apply {
            TestWindow.new(id: 1, parent: $0)
            TilingContainer.newVTiles(parent: $0, adaptiveWeight: 1).apply {
                assertEquals(TestWindow.new(id: 2, parent: $0).focusWindow(), true)
                TestWindow.new(id: 3, parent: $0)
            }
        }

        let result = await parseCommand("move --boundaries-action stop right").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(
            workspace.layoutDescription,
            .workspace([
                .h_tiles([.window(1), .v_tiles([.window(3)]), .window(2)]),
            ]),
        )
        assertEquals(result.exitCode.rawValue, 0)
    }

    @Test func testFail() async {
        let workspace = Workspace.get(byName: name)
        workspace.rootTilingContainer.apply {
            assertEquals(TestWindow.new(id: 1, parent: $0).focusWindow(), true)
            TestWindow.new(id: 2, parent: $0)
            TestWindow.new(id: 3, parent: $0)
        }

        let result = await parseCommand("move --boundaries-action fail left").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(
            workspace.layoutDescription,
            .workspace([
                .h_tiles([.window(1), .window(2), .window(3)]),
            ]),
        )
        assertEquals(result.exitCode.rawValue, 2)
    }

    @Test func testMoveOut() async {
        let root = Workspace.get(byName: name).rootTilingContainer.apply {
            TestWindow.new(id: 1, parent: $0)
            TilingContainer.newVTiles(parent: $0, adaptiveWeight: 1).apply {
                assertEquals(TestWindow.new(id: 2, parent: $0).focusWindow(), true)
                TestWindow.new(id: 3, parent: $0)
                TestWindow.new(id: 4, parent: $0)
            }
        }

        await parseCommand("move left").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(
            root.layoutDescription,
            .h_tiles([
                .window(1),
                .window(2),
                .v_tiles([
                    .window(3),
                    .window(4),
                ]),
            ]),
        )
    }

    @Test func testMoveOutWithNormalization_right() async {
        config.enableNormalizationFlattenContainers = true

        let workspace = Workspace.get(byName: name).apply {
            TestWindow.new(id: 1, parent: $0.rootTilingContainer)
            assertEquals(TestWindow.new(id: 2, parent: $0.rootTilingContainer).focusWindow(), true)
        }

        await parseCommand("move right").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(
            workspace.rootTilingContainer.layoutDescription,
            .h_tiles([
                .window(1),
                .window(2),
            ]),
        )
        assertEquals(globalFocus.windowOrNil?.windowId, 2)
    }

    @Test func testMoveOutWithNormalization_left() async {
        config.enableNormalizationFlattenContainers = true

        let workspace = Workspace.get(byName: name).apply {
            assertEquals(TestWindow.new(id: 1, parent: $0.rootTilingContainer).focusWindow(), true)
            TestWindow.new(id: 2, parent: $0.rootTilingContainer)
        }

        await parseCommand("move left").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(
            workspace.rootTilingContainer.layoutDescription,
            .h_tiles([
                .window(1),
                .window(2),
            ]),
        )
        assertEquals(globalFocus.windowOrNil?.windowId, 1)
    }

    @Test func testDwindleCreateImplicitContainerPreservesDwindleRootForNextInsertion() async {
        let workspace = Workspace.get(byName: name)
        workspace.rootTilingContainer.apply {
            $0.layout = .dwindle
            TestWindow.new(id: 1, parent: $0)
            assertEquals(TestWindow.new(id: 2, parent: $0).focusWindow(), true)
            TestWindow.new(id: 3, parent: $0)
        }

        let result = await parseCommand("move up").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(result.exitCode.rawValue, 0)
        assertEquals(
            workspace.layoutDescription,
            .workspace([
                .dwindle([
                    .window(2),
                    .dwindle([.window(1), .window(3)]),
                ]),
            ]),
        )

        let binding = unbindAndGetBindingDataForNewTilingWindowForDwindleLayout(workspace)
        TestWindow.new(id: 4, parent: binding.parent, adaptiveWeight: binding.adaptiveWeight)

        assertEquals(
            workspace.layoutDescription,
            .workspace([
                .dwindle([
                    .dwindle([.window(2), .window(4)]),
                    .dwindle([.window(1), .window(3)]),
                ]),
            ]),
        )
    }

    @Test func testDwindleMoveInPreservesLayoutSlots() async throws {
        let workspace = Workspace.get(byName: name)
        let root = workspace.rootTilingContainer
        root.layout = .dwindle
        let movingWindow = TestWindow.new(id: 1, parent: root, adaptiveWeight: 30)
        let nested = TilingContainer(parent: root, adaptiveWeight: 70, .v, .dwindle, index: INDEX_BIND_LAST)
        let unaffectedWindow = TestWindow.new(id: 2, parent: nested, adaptiveWeight: 60)
        let targetWindow = TestWindow.new(id: 3, parent: nested, adaptiveWeight: 40)
        try await workspace.layoutWorkspace()
        let movingSlot = try #require(movingWindow.lastAppliedLayoutVirtualRect)
        let unaffectedSlot = try #require(unaffectedWindow.lastAppliedLayoutVirtualRect)
        let targetSlot = try #require(targetWindow.lastAppliedLayoutVirtualRect)
        _ = movingWindow.focusWindow()

        await parseCommand("move right").cmdOrDie.run(.defaultEnv, .emptyStdin)
        try await workspace.layoutWorkspace()

        assertMoveRectEquals(movingWindow.lastAppliedLayoutVirtualRect, targetSlot)
        assertMoveRectEquals(targetWindow.lastAppliedLayoutVirtualRect, movingSlot)
        assertMoveRectEquals(unaffectedWindow.lastAppliedLayoutVirtualRect, unaffectedSlot)
    }

    @Test func testDwindleMoveOutPreservesLayoutSlots() async throws {
        let workspace = Workspace.get(byName: name)
        let root = workspace.rootTilingContainer
        root.layout = .dwindle
        let outerWindow = TestWindow.new(id: 1, parent: root, adaptiveWeight: 30)
        let nested = TilingContainer(parent: root, adaptiveWeight: 70, .v, .dwindle, index: INDEX_BIND_LAST)
        let movingWindow = TestWindow.new(id: 2, parent: nested, adaptiveWeight: 60)
        let unaffectedWindow = TestWindow.new(id: 3, parent: nested, adaptiveWeight: 40)
        try await workspace.layoutWorkspace()
        let outerSlot = try #require(outerWindow.lastAppliedLayoutVirtualRect)
        let movingSlot = try #require(movingWindow.lastAppliedLayoutVirtualRect)
        let unaffectedSlot = try #require(unaffectedWindow.lastAppliedLayoutVirtualRect)
        _ = movingWindow.focusWindow()

        await parseCommand("move left").cmdOrDie.run(.defaultEnv, .emptyStdin)
        try await workspace.layoutWorkspace()

        assertMoveRectEquals(movingWindow.lastAppliedLayoutVirtualRect, outerSlot)
        assertMoveRectEquals(outerWindow.lastAppliedLayoutVirtualRect, movingSlot)
        assertMoveRectEquals(unaffectedWindow.lastAppliedLayoutVirtualRect, unaffectedSlot)
    }

    @Test func testDwindleMoveOutTargetsDirectionalLeafWhenBothSlotsAreContainers() async throws {
        let workspace = Workspace.get(byName: name)
        let root = workspace.rootTilingContainer
        root.layout = .dwindle
        let leftSlot = TilingContainer(parent: root, adaptiveWeight: 60, .v, .dwindle, index: INDEX_BIND_LAST)
        let movingWindow = TestWindow.new(id: 1, parent: leftSlot, adaptiveWeight: 70)
        let leftUnaffectedWindow = TestWindow.new(id: 2, parent: leftSlot, adaptiveWeight: 30)
        let rightSlot = TilingContainer(parent: root, adaptiveWeight: 40, .v, .dwindle, index: INDEX_BIND_LAST)
        TestWindow.new(id: 3, parent: rightSlot, adaptiveWeight: 60)
        let targetWindow = TestWindow.new(id: 4, parent: rightSlot, adaptiveWeight: 40)
        targetWindow.markAsMostRecentChild()
        try await workspace.layoutWorkspace()
        let movingSlot = try #require(movingWindow.lastAppliedLayoutVirtualRect)
        let leftUnaffectedSlot = try #require(leftUnaffectedWindow.lastAppliedLayoutVirtualRect)
        let targetSlot = try #require(targetWindow.lastAppliedLayoutVirtualRect)
        _ = movingWindow.focusWindow()

        let result = await parseCommand("move right").cmdOrDie.run(.defaultEnv, .emptyStdin)
        try await workspace.layoutWorkspace()

        assertEquals(result.exitCode.rawValue, 0)
        assertMoveRectEquals(movingWindow.lastAppliedLayoutVirtualRect, targetSlot)
        assertMoveRectEquals(targetWindow.lastAppliedLayoutVirtualRect, movingSlot)
        assertMoveRectEquals(leftUnaffectedWindow.lastAppliedLayoutVirtualRect, leftUnaffectedSlot)
    }

    @Test func testDwindleSwapPreservesLayoutSlots() async throws {
        let workspace = Workspace.get(byName: name)
        let root = workspace.rootTilingContainer
        root.layout = .dwindle
        let window1 = TestWindow.new(id: 1, parent: root, adaptiveWeight: 70)
        let window2 = TestWindow.new(id: 2, parent: root, adaptiveWeight: 30)
        try await workspace.layoutWorkspace()
        let slot1 = try #require(window1.lastAppliedLayoutVirtualRect)
        let slot2 = try #require(window2.lastAppliedLayoutVirtualRect)
        _ = window1.focusWindow()

        await parseCommand("move right").cmdOrDie.run(.defaultEnv, .emptyStdin)
        try await workspace.layoutWorkspace()

        assertMoveRectEquals(window1.lastAppliedLayoutVirtualRect, slot2)
        assertMoveRectEquals(window2.lastAppliedLayoutVirtualRect, slot1)
    }

    @Test(arguments: ["move right", "swap right"])
    func testDwindleSwapPreservesTransparentTabSlot(command: String) async throws {
        config.enableNormalizationFlattenContainers = true
        let workspace = Workspace.get(byName: name)
        let root = workspace.rootTilingContainer
        root.layout = .dwindle
        let movingWindow = TestWindow.new(id: 1, parent: root, adaptiveWeight: 30)
        let tabSlot = TilingContainer(parent: root, adaptiveWeight: 70, .v, .dwindle, index: INDEX_BIND_LAST)
        let targetWindow = TestWindow.new(id: 2, parent: tabSlot)
        let invisibleTab = TestWindow.new(id: 3, parent: tabSlot)
        invisibleTab.lifeStatus = .invisible
        tabSlot.lifeStatus = .mustBeFlattened
        try await workspace.layoutWorkspace()
        let movingRect = try #require(movingWindow.lastAppliedLayoutVirtualRect)
        let targetRect = try #require(targetWindow.lastAppliedLayoutVirtualRect)
        #expect(movingWindow.focusWindow())

        let result = await parseCommand(command).cmdOrDie.run(.defaultEnv, .emptyStdin)
        try await workspace.layoutWorkspace()

        #expect(result.exitCode.rawValue == 0)
        #expect(root.children == [tabSlot, movingWindow])
        #expect(tabSlot.children == [targetWindow, invisibleTab])
        #expect(tabSlot.lifeStatus == .mustBeFlattened)
        #expect(globalFocus.windowOrNil === movingWindow)
        assertMoveRectEquals(movingWindow.lastAppliedLayoutVirtualRect, targetRect)
        assertMoveRectEquals(targetWindow.lastAppliedLayoutVirtualRect, movingRect)
    }

    @Test func testDwindleMoveInSkipsDeadMostRecentTarget() async {
        let root = Workspace.get(byName: name).rootTilingContainer
        root.layout = .dwindle
        let movingWindow = TestWindow.new(id: 1, parent: root, adaptiveWeight: 30)
        let nested = TilingContainer(parent: root, adaptiveWeight: 70, .v, .dwindle, index: INDEX_BIND_LAST)
        TestWindow.new(id: 2, parent: nested, adaptiveWeight: 60)
        TestWindow.new(id: 3, parent: nested, adaptiveWeight: 40).lifeStatus = .dead
        assertEquals(movingWindow.focusWindow(), true)

        let result = await parseCommand("move right").cmdOrDie.run(.defaultEnv, .emptyStdin)

        assertEquals(result.exitCode.rawValue, 0)
        assertEquals(root.layoutDescription, .dwindle([
            .window(2),
            .dwindle([.window(1), .window(3)]),
        ]))
        assertEquals(globalFocus.windowOrNil?.windowId, 1)
    }
}

extension TreeNode {
    var layoutDescription: LayoutDescription {
        return switch nodeCases {
            case .window(let window): .window(window.windowId)
            case .workspace(let workspace): .workspace(workspace.children.map(\.layoutDescription))
            case .floatingWindowsContainer(let container): .floatingWindowsContainer(container.children.map(\.layoutDescription))
            case .macosMinimizedWindowsContainer: .macosMinimized
            case .macosFullscreenWindowsContainer: .macosFullscreen
            case .macosHiddenAppsWindowsContainer: .macosHiddeAppWindow
            case .monitor: .monitor
            case .workspacesContainer: .workspacesContainer
            case .macosPopupWindowsContainer: .macosPopupWindowsContainer
            case .tilingContainer(let container):
                switch container.layout {
                    case .tiles:
                        container.orientation == .h
                            ? .h_tiles(container.children.map(\.layoutDescription))
                            : .v_tiles(container.children.map(\.layoutDescription))
                    case .accordion:
                        container.orientation == .h
                            ? .h_accordion(container.children.map(\.layoutDescription))
                            : .v_accordion(container.children.map(\.layoutDescription))
                    case .dwindle:
                        .dwindle(container.children.map(\.layoutDescription))
                }
        }
    }
}

enum LayoutDescription: Equatable {
    case workspace([LayoutDescription])
    case h_tiles([LayoutDescription])
    case v_tiles([LayoutDescription])
    case h_accordion([LayoutDescription])
    case v_accordion([LayoutDescription])
    case floatingWindowsContainer([LayoutDescription])
    case dwindle([LayoutDescription])
    case window(OpaqueWindowId)
    case macosPopupWindowsContainer
    case macosMinimized
    case macosHiddeAppWindow
    case macosFullscreen

    // todo think about it
    case workspacesContainer
    case monitor
}

private func assertMoveRectEquals(
    _ actual: Rect?,
    _ expected: Rect,
    sourceLocation: SourceLocation = #_sourceLocation,
) {
    guard let actual else {
        Issue.record("Expected an applied layout rectangle", sourceLocation: sourceLocation)
        return
    }
    assertEquals(actual.topLeftX, expected.topLeftX, additionalMsg: "topLeftX", sourceLocation: sourceLocation)
    assertEquals(actual.topLeftY, expected.topLeftY, additionalMsg: "topLeftY", sourceLocation: sourceLocation)
    assertEquals(actual.width, expected.width, additionalMsg: "width", sourceLocation: sourceLocation)
    assertEquals(actual.height, expected.height, additionalMsg: "height", sourceLocation: sourceLocation)
}

import XCTest

final class TwoSidesUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testBundledExpandedWordBankLoadsAndPlays() {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launch()
        let count = app.staticTexts["可多选 · 50000 个词"]
        XCTAssertTrue(count.waitForExistence(timeout: 8), "正式词库应从应用资源加载全部五万个词")
        tap(app.buttons["wordSources"], in: app)
        XCTAssertTrue(app.navigationBars["词库来源"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "THUOCL")).firstMatch.exists)
        app.buttons["完成"].tap()
        tap(app.buttons["startGame"], in: app)
        waitUntilEnabled(app.buttons["gameCorrect"])
        XCTAssertTrue(app.staticTexts["promptAnswer"].exists)
        keepScreenshot("正式五万词库加载并开始游戏", from: app)
    }

    @MainActor
    func testCompleteMatchAndKeepAnswersHiddenWhilePaused() {
        let app = launch()
        tap(app.buttons["startGame"], in: app)

        waitUntilEnabled(app.buttons["gameCorrect"])
        waitForAnswer("长颈鹿", in: app)
        tap(app.buttons["gameCorrect"], in: app)

        waitForAnswer("咖啡", in: app)
        waitUntilEnabled(app.buttons["gameSkip"])
        tap(app.buttons["gameSkip"], in: app)

        waitForAnswer("自拍", in: app)
        tap(app.buttons["gamePause"], in: app, scrollDown: true)
        XCTAssertTrue(app.staticTexts["pausedTitle"].waitForExistence(timeout: 3))
        assertAnswersAbsent(in: app)
        keepScreenshot("暂停：答案已隐藏", from: app)

        tap(app.buttons["resumeGame"], in: app)
        waitForAnswer("自拍", in: app)

        let nextTurn = app.buttons["nextTurn"]
        XCTAssertTrue(nextTurn.waitForExistence(timeout: 30))
        XCTAssertTrue(nextTurn.label.contains("薄荷队"))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "回合结束")).firstMatch.exists)
        keepScreenshot("第一回合：正确与跳过记录", from: app)
        tap(nextTurn, in: app)

        XCTAssertTrue(app.staticTexts["薄荷队，接招！"].waitForExistence(timeout: 5))
        waitUntilEnabled(app.buttons["gameCorrect"])
        XCTAssertTrue(app.staticTexts["默契挑战完成"].waitForExistence(timeout: 30))
        XCTAssertTrue(app.buttons["nextTurn"].label.contains("再来一局"))
        keepScreenshot("两队完成后的总结果", from: app)

        tap(app.buttons["backToLobby"], in: app)
        XCTAssertTrue(app.staticTexts["两面猜"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["startGame"].exists)
    }

    @MainActor
    func testAudiencePreviewOnlyExposesPublicHints() {
        let app = launch(arguments: ["--preview-audience"])
        let category = app.staticTexts["audienceCategory"]
        XCTAssertTrue(category.waitForExistence(timeout: 5))
        XCTAssertEqual(category.label, "动物世界")
        XCTAssertEqual(app.staticTexts["audienceCharacterCount"].label, "3 个字")

        let timer = app.descendants(matching: .any).matching(identifier: "audienceTimer").firstMatch
        XCTAssertTrue(timer.exists)
        XCTAssertEqual(timer.value as? String, "42 秒")
        XCTAssertFalse(app.staticTexts["promptAnswer"].exists)
        assertAnswersAbsent(in: app)
        keepScreenshot("猜词方：只见类别字数时间", from: app)
    }

    @MainActor
    func testBackgroundPausesAndHidesAnswer() {
        let app = launch()
        tap(app.buttons["startGame"], in: app)
        waitUntilEnabled(app.buttons["gameCorrect"])
        waitForAnswer("长颈鹿", in: app)

        XCUIDevice.shared.press(.home)
        app.activate()

        XCTAssertTrue(app.staticTexts["pausedTitle"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["promptAnswer"].exists)
        assertAnswersAbsent(in: app)
        keepScreenshot("从后台返回：已暂停且答案隐藏", from: app)

        tap(app.buttons["resumeGame"], in: app)
        waitForAnswer("长颈鹿", in: app)
        waitUntilEnabled(app.buttons["gameCorrect"])
        keepScreenshot("明确继续后恢复原词卡", from: app)
    }

    @MainActor
    func testSimulatorCameraFailureStillAllowsSingleScreenPlay() throws {
        #if targetEnvironment(simulator)
        let app = launch()
        tap(app.buttons["cameraToggle"], in: app)
        let cameraError = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "模拟器没有可用相机")
        ).firstMatch
        XCTAssertTrue(cameraError.waitForExistence(timeout: 5))
        keepScreenshot("相机不可用时提供明确说明", from: app)

        tap(app.buttons["startGame"], in: app)
        waitUntilEnabled(app.buttons["gameCorrect"])
        waitForAnswer("长颈鹿", in: app)
        #else
        throw XCTSkip("本用例专门验证模拟器无相机时的降级行为。")
        #endif
    }

    /// Uses the real capture session: the simulator's unavailable-camera path
    /// cannot expose deadlocks between stopRunning and preview teardown.
    @MainActor
    func testDuoCameraAccessoryClosesAndReopensWithoutFreezing() throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("需要展开的 Duo 真机来验证相机和外屏关闭与重新开启。")
        #else
        let app = launch()
        let hierarchy = XCTAttachment(string: app.debugDescription)
        hierarchy.name = "Duo 启动时的窗口与按钮位置"
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
        keepScreenshot("Duo 真机测试起始画面", from: app)
        addUIInterruptionMonitor(withDescription: "相机权限") { alert in
            let allow = alert.buttons.matching(NSPredicate(
                format: "label IN %@", ["允许", "好", "Allow", "OK"]
            )).firstMatch
            guard allow.exists else { return false }
            allow.tap()
            return true
        }

        let previewReady = app.staticTexts["外屏已就绪"]
        for useCloseButton in [true, false, true, false] {
            tap(app.buttons["cameraToggle"], in: app)
            XCTAssertTrue(previewReady.waitForExistence(timeout: 15), "展开的 Duo 应启动相机并让外屏就绪")
            let close = useCloseButton ? app.buttons["cameraClose"] : app.buttons["cameraToggle"]
            tap(close, in: app)
            let stopped = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "exists == false"), object: app.buttons["cameraClose"]
            )
            XCTAssertEqual(XCTWaiter.wait(for: [stopped], timeout: 10), .completed,
                           "关闭必须完成，不能卡住主线程")
            XCTAssertEqual(app.buttons["cameraToggle"].label, "开启")
            XCTAssertTrue(app.buttons["cameraToggle"].isEnabled)

            // A separate sheet interaction proves that the main UI still responds.
            tap(app.buttons["previewButton"], in: app)
            XCTAssertTrue(app.navigationBars["两种视角"].waitForExistence(timeout: 3))
            app.buttons["明白了"].tap()
        }

        tap(app.buttons["startGame"], in: app)
        waitUntilEnabled(app.buttons["gameCorrect"])
        keepScreenshot("真机重复关闭后仍可游戏", from: app)
        #endif
    }

    @MainActor
    func testDuoCameraBackgroundStopsAndPauses() throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("需要 Duo 真机来验证双屏运行中的后台停止。")
        #else
        let app = launch()
        tap(app.buttons["cameraToggle"], in: app)
        XCTAssertTrue(app.staticTexts["外屏已就绪"].waitForExistence(timeout: 15))
        tap(app.buttons["startGame"], in: app)
        waitUntilEnabled(app.buttons["gameCorrect"])
        // A synthetic Home press alone does not prove backgrounding on Duo.
        // Verify the state transition after switching apps before testing resume.
        XCUIApplication(bundleIdentifier: "com.apple.Preferences").activate()
        let backgrounded = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            app.state == .runningBackground || app.state == .runningBackgroundSuspended
        }, object: app)
        XCTAssertEqual(XCTWaiter.wait(for: [backgrounded], timeout: 10), .completed,
                       "必须先确认应用真的进入后台，才能验证后台停止")
        app.activate()
        XCTAssertTrue(app.staticTexts["pausedTitle"].waitForExistence(timeout: 10))
        let backgroundStopped = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"), object: app.buttons["cameraClose"]
        )
        XCTAssertEqual(XCTWaiter.wait(for: [backgroundStopped], timeout: 10), .completed)
        assertAnswersAbsent(in: app)
        tap(app.buttons["resumeGame"], in: app)
        waitUntilEnabled(app.buttons["gameCorrect"])
        keepScreenshot("真机相机后台停止后可继续游戏", from: app)
        #endif
    }

    @MainActor
    private func launch(arguments: [String] = []) -> XCUIApplication {
        #if targetEnvironment(simulator)
        XCUIDevice.shared.orientation = .portrait
        #endif
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"] + arguments
        app.launch()
        return app
    }

    @MainActor
    private func waitUntilEnabled(_ button: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == true AND enabled == true"), object: button
        )
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 8), .completed,
                       "游戏按钮应在准备倒计时后启用", file: file, line: line)
    }

    @MainActor
    private func waitForAnswer(_ answer: String, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == true AND label CONTAINS %@", answer),
            object: app.staticTexts["promptAnswer"]
        )
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 5), .completed,
                       "描述者应看到词卡：\(answer)", file: file, line: line)
    }

    @MainActor
    private func assertAnswersAbsent(in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        for answer in ["长颈鹿", "咖啡", "自拍"] {
            let exposedAnswer = app.descendants(matching: .any).matching(
                NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", answer, answer)
            ).firstMatch
            XCTAssertFalse(exposedAnswer.exists, "不应向此画面暴露答案：\(answer)", file: file, line: line)
        }
    }

    @MainActor
    private func tap(_ element: XCUIElement, in app: XCUIApplication, scrollDown: Bool = false,
                     file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: 5), "找不到目标按钮", file: file, line: line)
        for _ in 0..<6 {
            if element.isHittable { break }
            #if targetEnvironment(simulator)
            if scrollDown { app.swipeDown() } else { app.swipeUp() }
            #else
            let scroll = app.scrollViews.firstMatch
            let surface = scroll.exists ? scroll : app
            if scrollDown { surface.swipeDown() } else { surface.swipeUp() }
            #endif
        }
        XCTAssertTrue(element.isHittable, "滚动后按钮仍不可点击", file: file, line: line)
        element.tap()
    }

    @MainActor
    private func keepScreenshot(_ name: String, from app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

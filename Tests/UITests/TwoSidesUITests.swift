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

    @MainActor
    private func launch(arguments: [String] = []) -> XCUIApplication {
        XCUIDevice.shared.orientation = .portrait
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
            if scrollDown { app.swipeDown() } else { app.swipeUp() }
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

import XCTest

final class AIResponseUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testStartRecordingAutomaticallyStartsListening() {
        let app = launchApp()

        app.buttons["startRecordingButton"].tap()

        XCTAssertTrue(app.buttons["listenButton"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["transcriptionStatusLabel"].waitForLabel(containing: "Listening active", timeout: 5))
    }

    func testStopAndListenAgainStartsNewSession() {
        let app = launchApp()

        app.buttons["startRecordingButton"].tap()
        XCTAssertTrue(app.staticTexts["transcriptionStatusLabel"].waitForLabel(containing: "Listening active", timeout: 5))

        app.buttons["stopRecordingButton"].tap()
        XCTAssertTrue(app.staticTexts["transcriptionStatusLabel"].waitForLabel(containing: "Transcript saved", timeout: 5))

        app.buttons["listenButton"].tap()
        XCTAssertTrue(app.staticTexts["transcriptionStatusLabel"].waitForLabel(containing: "Listening active", timeout: 5))
    }

    func testResponseWorksWithoutTranscript() {
        let app = launchApp(environment: ["UITEST_TRANSCRIPTS": ""])

        app.buttons["startRecordingButton"].tap()
        app.buttons["responseButton"].tap()

        XCTAssertTrue(app.staticTexts["aiResponseText"].waitForLabel(containing: "priority should be onboarding optimization", timeout: 5))
    }

    func testResponseAfterTranscriptUpdate() {
        let app = launchApp(environment: ["UITEST_TRANSCRIPTS": "We discussed the product roadmap and onboarding flow."])

        app.buttons["startRecordingButton"].tap()
        XCTAssertTrue(app.staticTexts["transcriptionStatusLabel"].waitForLabel(containing: "Listening active", timeout: 5))

        app.buttons["stopRecordingButton"].tap()
        XCTAssertTrue(app.staticTexts["contextUpdatedBadge"].waitForExistence(timeout: 5))

        app.buttons["responseButton"].tap()
        XCTAssertTrue(app.staticTexts["aiResponseText"].waitForLabel(containing: "priority should be onboarding optimization", timeout: 5))
    }

    func testProjectSaveAndResponseFlowCompletes() {
        let app = launchApp(environment: ["UITEST_PRELOAD_PROJECT": "0"])

        app.buttons["startRecordingButton"].tap()
        app.buttons["Knowledge"].tap()

        let projectNameField = app.textFields["projectNameField"]
        XCTAssertTrue(projectNameField.waitForExistence(timeout: 5))
        projectNameField.tap()
        projectNameField.typeText("New Initiative")
        app.buttons["saveProjectButton"].tap()
        app.buttons["Done"].tap()

        app.buttons["responseButton"].tap()

        XCTAssertTrue(app.staticTexts["aiResponseText"].waitForLabel(containing: "priority should be onboarding optimization", timeout: 5))
    }

    private func launchApp(environment: [String: String] = [:]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting"]
        app.launchEnvironment = [
            "UITEST_AUTHENTICATED": "1"
        ].merging(environment) { _, new in new }
        app.launch()
        XCTAssertTrue(app.buttons["startRecordingButton"].waitForExistence(timeout: 5))
        return app
    }
}

private extension XCUIElement {
    func waitForLabel(containing text: String, timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate(format: "label CONTAINS %@", text)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: self)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }
}

import XCTest

/// The demo path, driven the way a person would: type a problem, read the
/// steps, open the lesson.
///
/// It runs the real on-device model, so it needs a device or simulator where
/// Apple Intelligence actually answers. An iOS 26.4 simulator reports the model
/// available and then fails every request; the iOS 26.5 simulator works.
final class DemoPathUITests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    func testTypeAProblemThenStepsThenLesson() {
        let app = XCUIApplication()
        // A fresh install asks for the camera before anything else.
        addUIInterruptionMonitor(withDescription: "Camera permission") { alert in
            let allow = alert.buttons["Allow"]
            guard allow.exists else { return false }
            allow.tap()
            return true
        }
        app.launch()

        let typeButton = app.buttons
            .containing(NSPredicate(format: "label CONTAINS[c] 'type a problem'")).firstMatch
        XCTAssertTrue(typeButton.waitForExistence(timeout: 10))
        typeButton.tap()

        // The first tap can be spent dismissing the camera prompt.
        let editor = app.textViews.firstMatch
        if !editor.waitForExistence(timeout: 3) { typeButton.tap() }
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.tap()
        editor.typeText("Solve the system of equations: x + y = 10 and x - y = 4")
        app.buttons["Solve"].firstMatch.tap()

        // The footer is drawn only once the steps are on screen.
        let footer = app.staticTexts
            .containing(NSPredicate(format: "label BEGINSWITH 'Worked out on this device'")).firstMatch
        XCTAssertTrue(footer.waitForExistence(timeout: 60), "no steps within 60 s")
        let finalAnswer = app.webViews.staticTexts
            .containing(NSPredicate(format: "label CONTAINS 'Final answer'")).firstMatch
        XCTAssertTrue(finalAnswer.waitForExistence(timeout: 10), "steps arrived with no final answer")
        add(XCTAttachment(screenshot: app.screenshot()))

        app.buttons["Lesson"].tap()
        let lesson = app.webViews.staticTexts
            .containing(NSPredicate(format: "label CONTAINS[c] 'equation'")).firstMatch
        XCTAssertTrue(lesson.waitForExistence(timeout: 60), "no lesson within 60 s")
        add(XCTAttachment(screenshot: app.screenshot()))
    }
}

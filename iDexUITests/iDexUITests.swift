import XCTest

@MainActor
final class iDexUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testSampleIsIdentifiedByBundledModel() throws {
        let app = launchInEnglish()
        XCTAssertTrue(element("viewfinder", in: app).waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["SAMPLE TARGET"].exists)
        app.buttons["sample-button"].tap()
        let identify = app.buttons["identify-button"]
        XCTAssertTrue(identify.isEnabled)
        attachScreenshot("scanner-sample-en", app: app)
        identify.tap()

        // The sample follows the camera's Core ML pipeline; no launch argument
        // replaces inference with a canned result.
        XCTAssertTrue(app.staticTexts["IDENTIFIED"].waitForExistence(timeout: 45), app.debugDescription)
        XCTAssertEqual(app.staticTexts["pokemon-name"].label, "Pikachu")
        XCTAssertEqual(app.staticTexts["entry-number"].label, "No. 025")
        XCTAssertTrue(app.buttons["read-button"].exists)
        XCTAssertFalse(element("scan-message", in: app).exists)
        attachScreenshot("pikachu-recognition", app: app)
    }

    func testLanguageSwitchPersistsAcrossLaunches() throws {
        let app = launchInEnglish()
        app.buttons["settings-button"].tap()
        XCTAssertTrue(app.buttons["language-zhHans"].waitForExistence(timeout: 5))
        app.buttons["language-zhHans"].tap()
        XCTAssertTrue(app.navigationBars["设备设置"].waitForExistence(timeout: 5))
        app.buttons["settings-done"].tap()
        XCTAssertTrue(app.buttons["identify-button"].label.contains("识别"))
        attachScreenshot("scanner-zh", app: app)
        app.terminate()

        // This launch reads the persisted selection without a language override.
        app.launchArguments = ["-idex.soundEnabled", "NO"]
        app.launch()
        XCTAssertTrue(app.buttons["settings-button"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["identify-button"].label.contains("识别"))
        app.buttons["settings-button"].tap()
        XCTAssertTrue(app.navigationBars["设备设置"].waitForExistence(timeout: 5))
        app.buttons["language-en"].tap()
        XCTAssertTrue(app.navigationBars["Device settings"].waitForExistence(timeout: 5))
        app.buttons["settings-done"].tap()
        XCTAssertTrue(app.buttons["identify-button"].label.contains("IDENTIFY"))
    }

    func testCatalogSearchAcceptsEnglishChineseAndDexNumber() throws {
        let app = launchInEnglish()
        openCatalog(in: app)
        let search = app.searchFields.firstMatch
        if !search.exists {
            // iOS 27 presents .searchable as a bottom search button until used.
            let revealSearch = app.buttons["Search"]
            XCTAssertTrue(revealSearch.waitForExistence(timeout: 5))
            revealSearch.tap()
        }
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("Pikachu")
        let pikachu = app.buttons["pokemon-25"]
        XCTAssertTrue(pikachu.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["pokemon-1"].exists)
        attachScreenshot("catalog-english-search", app: app)

        replaceSearchText("皮卡丘", in: search)
        XCTAssertTrue(pikachu.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["pokemon-1"].exists)
        replaceSearchText("006", in: search)
        let charizard = app.buttons["pokemon-6"]
        XCTAssertTrue(charizard.waitForExistence(timeout: 5))
        XCTAssertFalse(pikachu.exists)
        charizard.tap()

        XCTAssertTrue(app.staticTexts["pokemon-name"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["pokemon-name"].label, "Charizard")
        XCTAssertEqual(app.staticTexts["entry-number"].label, "No. 006")
        XCTAssertTrue(app.staticTexts["ARCHIVE"].exists)
        attachScreenshot("charizard-archive", app: app)
    }

    private func launchInEnglish() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-idex.language", "en", "-idex.soundEnabled", "NO"]
        app.launch()
        XCTAssertTrue(app.buttons["settings-button"].waitForExistence(timeout: 10))
        return app
    }

    private func openCatalog(in app: XCUIApplication) {
        let catalog = app.buttons["catalog-button"]
        if !catalog.isHittable {
            app.buttons["record-button"].tap()
        }
        XCTAssertTrue(catalog.waitForExistence(timeout: 5))
        catalog.tap()
        XCTAssertTrue(app.navigationBars["Kanto archive"].waitForExistence(timeout: 5))
    }

    private func replaceSearchText(_ text: String, in field: XCUIElement) {
        field.tap()
        if let clear = field.buttons.allElementsBoundByIndex.first, clear.isHittable {
            clear.tap()
        } else if let current = field.value as? String {
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count))
        }
        field.typeText(text)
    }

    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func attachScreenshot(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

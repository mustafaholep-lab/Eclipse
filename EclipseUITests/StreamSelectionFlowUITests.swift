import XCTest

/// Drives the iPhone path that crashed on the custom build:
/// search → movie detail → source sheet → stream picker → player.
///
/// The CI job serves a local Torrentio + TorBox shaped addon
/// (scripts/e2e/fake_torrentio_addon.py) whose streams resolve to mkv, mp4
/// and avi files, so every step runs against real network I/O and real
/// playback without any private key or stream link.
final class StreamSelectionFlowUITests: XCTestCase {
    private static let movieCard = "search.result.movie-27205"
    private static let addonRow = "services.stremio.addon.Torrentio"

    private var environment: [String: String] { ProcessInfo.processInfo.environment }
    private var addonURL: String { environment["ECLIPSE_E2E_ADDON_URL"] ?? "http://127.0.0.1:8765/manifest.json" }
    private var language: String { environment["ECLIPSE_E2E_LANGUAGE"] ?? "tr" }

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    // MARK: - Scenarios

    func test01_MovieDetailOpensAndStaysAlive() {
        let app = launch()
        openMovieDetail(app)
        settle(app, seconds: 8, step: "movie detail loaded")
        XCTAssertTrue(app.buttons["detail.play"].exists, "Play button disappeared from the detail page")
    }

    func test02_PickerSelectionStartsPlayer() {
        let app = launch()
        openMovieDetail(app)
        openSourceSheet(app)
        openStreamPicker(app)
        pickStream(app, index: 0)
        expectPlayer(app, step: "first stream (mkv)")
    }

    func test03_CancelReopenAndChangeSource() {
        let app = launch()
        openMovieDetail(app)
        openSourceSheet(app)

        openStreamPicker(app)
        cancelStreamPicker(app)
        settle(app, seconds: 2, step: "picker cancelled")

        openStreamPicker(app)
        pickStream(app, index: 1)
        expectPlayer(app, step: "second stream (mp4)")

        guard closePlayer(app) else {
            // Closing needs the on-screen controls; if they cannot be reached the
            // source change is still exercised from a fresh launch.
            app.terminate()
            let relaunched = launch()
            openMovieDetail(relaunched)
            openSourceSheet(relaunched)
            openStreamPicker(relaunched)
            pickStream(relaunched, index: 3)
            expectPlayer(relaunched, step: "changed source (avi) after relaunch")
            return
        }
        settle(app, seconds: 2, step: "player closed")
        openStreamPicker(app)
        pickStream(app, index: 3)
        expectPlayer(app, step: "changed source (avi)")
    }

    func test04_RapidRepeatedTapsOnOneStream() {
        let app = launch()
        openMovieDetail(app)
        openSourceSheet(app)
        openStreamPicker(app)
        let row = streamRow(app, index: 2)
        row.doubleTap()
        if row.exists, row.isHittable { row.tap() }
        expectPlayer(app, step: "rapidly tapped stream (hevc mkv)")
    }

    func test05_StremioStyleListStartsPlayer() {
        let app = launch(stremioStyle: true)
        openMovieDetail(app)
        openSourceSheet(app)
        let row = app.descendants(matching: .any)["services.stremioStyle.stream.0"]
        XCTAssertTrue(row.waitForExistence(timeout: 90), "Stremio-style stream row never appeared")
        row.tap()
        let play = app.alerts.buttons["Play"]
        XCTAssertTrue(play.waitForExistence(timeout: 15), "Play confirmation never appeared")
        play.tap()
        expectPlayer(app, step: "Stremio-style row")
    }

    func test06_AutoModeStartsPlayer() {
        let app = launch(autoMode: true)
        openMovieDetail(app)
        tap(app.buttons["detail.play"], "detail Play")
        expectPlayer(app, step: "Auto Mode", timeout: 120)
    }

    /// The crashing iPhone (iOS 18.7.9) had three subtitle addons. Playback
    /// started, AltyaziDB and OpenSubtitles answered at once, and the app
    /// aborted inside Swift concurrency right after the slow, empty AnimeSub+
    /// search finished. This replays those addons and timings.
    func test08_PlaybackSurvivesSubtitleAddonSearch() {
        let app = launch(subtitleAddons: true)
        openMovieDetail(app)
        openSourceSheet(app)
        openStreamPicker(app)
        pickStream(app, index: 0)
        expectPlayer(app, step: "stream with three subtitle addons")
        settle(app, seconds: 20, step: "subtitle addon search after playback start")
        attachScreenshot(app, name: "player-after-subtitle-search")
    }

    /// "Choose another source" inside the player presents the source sheet over
    /// the playing video and hands the new stream to the same player.
    func test07_ChangeSourceFromInsidePlayer() {
        let app = launch(playerServicesButton: true)
        openMovieDetail(app)
        openSourceSheet(app)
        openStreamPicker(app)
        pickStream(app, index: 1)
        expectPlayer(app, step: "stream before in-player change (mp4)")

        let services = app.buttons["player.services"]
        var opened = false
        for _ in 0..<3 where !opened {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            if services.waitForExistence(timeout: 3), services.isHittable {
                services.tap()
                opened = true
            }
        }
        XCTAssertTrue(opened, "Player source button never became tappable")
        openStreamPicker(app)
        pickStream(app, index: 0)
        settle(app, seconds: 4, step: "in-player source change handoff")
        expectPlayer(app, step: "stream after in-player change (mkv)")
    }

    // MARK: - Steps

    private func launch(
        autoMode: Bool = false,
        stremioStyle: Bool = false,
        playerServicesButton: Bool = false,
        subtitleAddons: Bool = false
    ) -> XCUIApplication {
        let app = XCUIApplication()
        let base = addonURL.replacingOccurrences(of: "/manifest.json", with: "")
        let addons = [addonURL] + (subtitleAddons
            ? ["animesub", "altyazidb", "opensubtitles"].map { "\(base)/subs/\($0)/manifest.json" }
            : [])
        app.launchEnvironment = [
            "ECLIPSE_UI_TEST": "1",
            "ECLIPSE_UI_TEST_INITIAL_TAB": "search",
            "ECLIPSE_UI_TEST_STREMIO_ADDON": addons.joined(separator: ","),
            "ECLIPSE_UI_TEST_APP_LANGUAGE": language,
            "ECLIPSE_UI_TEST_AUTO_MODE": autoMode ? "1" : "0",
            "ECLIPSE_UI_TEST_STREMIO_STYLE": stremioStyle ? "1" : "0",
            "ECLIPSE_UI_TEST_PLAYER_SERVICES_BUTTON": playerServicesButton ? "1" : "0"
        ]
        app.launchArguments += [
            "-AppleLanguages", "(\(language))",
            "-AppleLocale", language == "tr" ? "tr_TR" : "en_US"
        ]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30), "App did not reach the foreground")
        return app
    }

    private func openMovieDetail(_ app: XCUIApplication) {
        let field = app.textFields["search.field"]
        XCTAssertTrue(field.waitForExistence(timeout: 60), "Search field never appeared")
        field.tap()
        field.typeText("Inception\n")
        let card = app.descendants(matching: .any)[Self.movieCard]
        XCTAssertTrue(card.waitForExistence(timeout: 60), "Inception never appeared in search results")
        card.tap()
        let play = app.buttons["detail.play"]
        XCTAssertTrue(play.waitForExistence(timeout: 60), "Movie detail never opened")
        let enabled = NSPredicate(format: "enabled == true")
        let wait = expectation(for: enabled, evaluatedWith: play)
        XCTAssertEqual(XCTWaiter.wait(for: [wait], timeout: 60), .completed, "Play stayed disabled; the test addon was not installed")
        assertAlive(app, step: "movie detail")
    }

    private func openSourceSheet(_ app: XCUIApplication) {
        tap(app.buttons["detail.play"], "detail Play")
        settle(app, seconds: 1, step: "source sheet presented")
    }

    private func openStreamPicker(_ app: XCUIApplication) {
        let row = app.descendants(matching: .any)[Self.addonRow]
        XCTAssertTrue(row.waitForExistence(timeout: 90), "Torrentio row never appeared in the source sheet")
        // The row is a plain-style button whose centre is an empty Spacer, which
        // does not take touches; tap its title like a person would.
        let title = row.staticTexts.firstMatch
        if title.exists, title.isHittable {
            title.tap()
        } else {
            row.coordinate(withNormalizedOffset: CGVector(dx: 0.12, dy: 0.5)).tap()
        }
        guard streamRow(app, index: 0).waitForExistence(timeout: 20) else {
            attachHierarchy(app, name: "stream picker missing")
            XCTFail("Stream picker never opened")
            return
        }
        assertAlive(app, step: "stream picker")
    }

    private func streamRow(_ app: XCUIApplication, index: Int) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "streamPicker.stremio."))
            .element(boundBy: index)
    }

    private func pickStream(_ app: XCUIApplication, index: Int) {
        let row = streamRow(app, index: index)
        XCTAssertTrue(row.waitForExistence(timeout: 20), "Stream row \(index) missing")
        tap(row, "stream row \(index)")
    }

    private func cancelStreamPicker(_ app: XCUIApplication) {
        for label in ["İptal", "Cancel"] {
            let button = app.navigationBars.buttons[label]
            if button.exists {
                button.tap()
                XCTAssertTrue(
                    waitForDisappearance(streamRow(app, index: 0), timeout: 10),
                    "Stream picker stayed open after Cancel"
                )
                return
            }
        }
        XCTFail("Stream picker Cancel button not found")
    }

    private func expectPlayer(_ app: XCUIApplication, step: String, timeout: TimeInterval = 45) {
        let mpv = app.descendants(matching: .any)["player.mpv"]
        let avPlayer = app.descendants(matching: .any)["player.avplayer"]
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            assertAlive(app, step: "\(step) – waiting for player")
            if mpv.exists || avPlayer.exists { break }
            Thread.sleep(forTimeInterval: 0.5)
        }
        XCTAssertTrue(mpv.exists || avPlayer.exists, "Player never appeared after \(step)")
        settle(app, seconds: 10, step: "\(step) – playing")
        attachScreenshot(app, name: "player-\(step)")
    }

    private func closePlayer(_ app: XCUIApplication) -> Bool {
        let close = app.buttons["player.close"]
        for _ in 0..<3 {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            if close.waitForExistence(timeout: 3), close.isHittable {
                close.tap()
                for label in ["Close", "Kapat"] where app.alerts.buttons[label].waitForExistence(timeout: 1) {
                    app.alerts.buttons[label].tap()
                }
                return waitForDisappearance(app.descendants(matching: .any)["player.mpv"], timeout: 10)
            }
        }
        return false
    }

    // MARK: - Helpers

    private func tap(_ element: XCUIElement, _ name: String) {
        XCTAssertTrue(element.waitForExistence(timeout: 30), "\(name) missing")
        element.tap()
    }

    private func settle(_ app: XCUIApplication, seconds: Int, step: String) {
        for _ in 0..<(seconds * 2) {
            Thread.sleep(forTimeInterval: 0.5)
            assertAlive(app, step: step)
        }
    }

    private func assertAlive(_ app: XCUIApplication, step: String) {
        guard app.state != .runningForeground else { return }
        attachScreenshot(app, name: "not-running-\(step)")
        XCTFail("Eclipse stopped running (state \(app.state.rawValue)) during: \(step)")
    }

    private func waitForDisappearance(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        let gone = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: element)
        return XCTWaiter.wait(for: [gone], timeout: timeout) == .completed
    }

    private func attachHierarchy(_ app: XCUIApplication, name: String) {
        attachScreenshot(app, name: name)
        let attachment = XCTAttachment(string: app.debugDescription)
        attachment.name = "\(name) – accessibility tree"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func attachScreenshot(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

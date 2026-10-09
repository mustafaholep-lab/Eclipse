import Foundation
import XCTest
@testable import Eclipse

final class SubtitleDocumentTests: XCTestCase {
    func testSRTParsesMultilineTurkishAndSkipsMalformedBlock() throws {
        let source = "odd-id\r\n00:00:01,250 --> 00:00:03,500\r\nŞimdi başlayalım.\r\nİğne, ölçü ve çay.\r\n\r\nbroken\r\nnot a timestamp\r\nuntouched\r\n\r\n42\r\n00:00:04,000 --> 00:00:05,000\r\nMerhaba\r\n"
        let document = try SubtitleDocument.parse(source, format: .srt)
        XCTAssertEqual(document.dialogueUnits.count, 2)
        XCTAssertEqual(document.units[0].start, 1.25)
        XCTAssertEqual(document.units[0].end, 3.5)
        XCTAssertEqual(document.units[0].plainText, "Şimdi başlayalım.\r\nİğne, ölçü ve çay.")
        XCTAssertEqual(document.units[1].originalText, "Merhaba")
    }

    func testVTTParsesSettingsAndOmitsNonCueSections() throws {
        let source = "WEBVTT - sample\n\nNOTE transcript note\nNot dialogue\n\nSTYLE\n::cue { color: yellow }\n\nREGION\nid:anime\n\nscene-1\n00:01.000 --> 00:03.000 align:start position:10%\n<c.green>Merhaba</c> dünya\nİkinci satır\n"
        let document = try SubtitleDocument.parse(source, format: .vtt)
        let cue = try XCTUnwrap(document.dialogueUnits.first)
        XCTAssertEqual(document.units.count, 1)
        XCTAssertEqual(cue.start, 1)
        XCTAssertEqual(cue.end, 3)
        XCTAssertEqual(cue.plainText, "Merhaba dünya\nİkinci satır")
        XCTAssertEqual(cue.originalText, "<c.green>Merhaba</c> dünya\nİkinci satır")
    }

    func testASSParsesDynamicFieldsAndDeduplicatesDialoguePreviews() throws {
        let document = try SubtitleDocument.parse(assFixture, format: .ass)
        XCTAssertEqual(document.units.count, 8)
        XCTAssertEqual(document.dialogueUnits.count, 2)
        let cue = document.dialogueUnits[0]
        XCTAssertEqual(cue.start, 1)
        XCTAssertEqual(cue.end, 3)
        XCTAssertEqual(cue.plainText, "Şimdi, burada\nİğne ve çay")
        XCTAssertEqual(cue.originalText, "{\\i1}Şimdi, burada{\\i0}\\Nİğne ve çay")
        XCTAssertEqual(document.units[1].duplicateOf, cue.id)
    }

    func testASSPlainTextPreservesLiteralBraces() throws {
        let source = "[Events]\nFormat: Start, End, Text\nDialogue: 0:00:01.00,0:00:02.00,{\\i1}{\\b1}Literal {ASS_TAG_0} ve \\N çizgi \\h boşluk"
        let cue = try XCTUnwrap(SubtitleDocument.parse(source, format: .ass).dialogueUnits.first)
        XCTAssertEqual(cue.plainText, "Literal {ASS_TAG_0} ve \n çizgi   boşluk")
        XCTAssertTrue(cue.originalText.contains("{\\i1}{\\b1}"))
    }

    func testASSNonDialogueHeuristicsAndNormalNamedStyle() throws {
        let document = try SubtitleDocument.parse(assFixture, format: .ass)
        XCTAssertEqual(document.units.map(\.skipReason), [nil, nil, .drawing, .karaoke, .sign, .effect, .openingOrEnding, nil])
        XCTAssertEqual(document.dialogueUnits.last?.plainText, "Normal konuşma")
    }

    func testSSAWithTextInMiddleRetainsCommas() throws {
        let source = "[Script Info]\n[V4 Styles]\n[Events]\nFormat: Start, Text, End, Style, Layer\nDialogue: 0:00:01.00,Merhaba, dünya,0:00:02.00,Default,0\n"
        let cue = try XCTUnwrap(SubtitleDocument.parse(source, format: .ssa).dialogueUnits.first)
        XCTAssertEqual(cue.plainText, "Merhaba, dünya")
        XCTAssertEqual(cue.end, 2)
    }

    func testInvalidVTTAndNonUTF8InputFailSafely() {
        XCTAssertThrowsError(try SubtitleDocument.parse("not webvtt", format: .vtt))
        XCTAssertThrowsError(try SubtitleDocument.parse(Data([0xFF]), format: .srt))
    }

    func testPreviewOnlyShowsDialogueAndHonorsLimit() throws {
        let lines = try SubtitlePreview.dialogueLines(Data(assFixture.utf8), format: .ass)
        XCTAssertEqual(lines, ["Şimdi, burada\nİğne ve çay", "Normal konuşma"])
        XCTAssertEqual(try SubtitlePreview.dialogueLines(Data(assFixture.utf8), format: .ass, limit: 1), [lines[0]])
        XCTAssertTrue(try SubtitlePreview.dialogueLines(Data(assFixture.utf8), format: .ass, limit: 0).isEmpty)
    }

    private var assFixture: String {
        """
        [Script Info]
        Title: Synthetic anime sample
        [V4+ Styles]
        Format: Name, Fontname, Fontsize
        Style: Default,Arial,20
        [Events]
        Format: Start, End, Style, Layer, Effect, Text
        Dialogue: 0:00:01.00,0:00:03.00,Default,0,,{\\i1}Şimdi, burada{\\i0}\\Nİğne ve çay
        Dialogue: 0:00:01.00,0:00:03.00,Default,1,,{\\i1}Şimdi, burada{\\i0}\\Nİğne ve çay
        Dialogue: 0:00:03.00,0:00:04.00,Default,0,,{\\p1}m 0 0 l 100 100{\\p0}
        Dialogue: 0:00:04.00,0:00:05.00,Default,0,,{\\kf20}La{\\ko30}la
        Dialogue: 0:00:04.00,0:00:05.00,Signs,0,,Exit
        Dialogue: 0:00:04.00,0:00:05.00,Default,0,scroll,scrolling effect
        Dialogue: 0:00:04.00,0:00:05.00,OP Romaji,0,,Opening lyrics
        Dialogue: 0:00:04.00,0:00:05.00,Spoken Lines,0,,{\\b1}Normal konuşma
        [Custom Data]
        AnimeOffset: 12
        """
    }
}

import Foundation
import XCTest
@testable import Eclipse

final class SubtitleDocumentTests: XCTestCase {
    func testSRTKeepsCRLFMultilineOddIndexTurkishAndMalformedBlock() throws {
        let source = "odd-id\r\n00:00:01,250 --> 00:00:03,500\r\nŞimdi başlayalım.\r\nİğne, ölçü ve çay.\r\n\r\nbroken\r\nnot a timestamp\r\nuntouched\r\n\r\n42\r\n00:00:04,000 --> 00:00:05,000\r\nMerhaba\r\n"
        var document = try SubtitleDocument.parse(source, format: .srt)
        XCTAssertEqual(try document.serialize(), source)
        XCTAssertEqual(document.translatableUnits.count, 2)
        XCTAssertEqual(document.units[0].start, 1.25)
        XCTAssertEqual(document.units[0].plainText, "Şimdi başlayalım.\r\nİğne, ölçü ve çay.")
        try document.applyTranslation(id: document.units[0].id, text: "Hello.\r\nTea.")
        let output = try document.serialize()
        XCTAssertTrue(output.contains("00:00:01,250 --> 00:00:03,500\r\nHello.\r\nTea."))
        XCTAssertTrue(output.contains("broken\r\nnot a timestamp\r\nuntouched"))
        XCTAssertTrue(output.contains("42\r\n00:00:04,000 --> 00:00:05,000\r\nMerhaba"))
    }

    func testVTTKeepsHeaderIdentifiersSettingsAndNonCueSections() throws {
        let source = "WEBVTT - sample\n\nNOTE transcript note\nThis is not dialogue\n\nSTYLE\n::cue { color: yellow }\n\nREGION\nid:anime\n\nscene-1\n00:01.000 --> 00:03.000 align:start position:10% line:90% size:80% vertical:rl\n<c.green>Merhaba</c> dünya\nİkinci satır\n"
        var document = try SubtitleDocument.parse(source, format: .vtt)
        XCTAssertEqual(document.translatableUnits.count, 1)
        XCTAssertEqual(try document.serialize(), source)
        let unit = try XCTUnwrap(document.translatableUnits.first)
        XCTAssertEqual(unit.start, 1)
        XCTAssertEqual(unit.end, 3)
        XCTAssertEqual(unit.plainText, "Merhaba dünya\nİkinci satır")
        let text = unit.translationTemplate.replacingOccurrences(of: "Merhaba", with: "Hello")
        try document.applyTranslation(id: unit.id, text: text)
        let output = try document.serialize()
        XCTAssertTrue(output.contains("<c.green>Hello</c> dünya"))
        XCTAssertTrue(output.contains("align:start position:10% line:90% size:80% vertical:rl"))
        XCTAssertTrue(output.contains("NOTE transcript note\nThis is not dialogue"))
        XCTAssertTrue(output.contains("STYLE\n::cue { color: yellow }"))
        XCTAssertTrue(output.contains("REGION\nid:anime"))
    }

    func testASSRoundTripDynamicFormatCommaTagsBreaksAndUnknownSection() throws {
        let source = assFixture
        var document = try SubtitleDocument.parse(source, format: .ass)
        XCTAssertEqual(try document.serialize(), source)
        XCTAssertEqual(document.units.count, 8)
        XCTAssertEqual(document.translatableUnits.count, 2)
        let dialogue = document.translatableUnits[0]
        XCTAssertEqual(dialogue.start, 1)
        XCTAssertEqual(dialogue.end, 3)
        XCTAssertEqual(dialogue.plainText, "Şimdi, burada\nİğne ve çay")
        XCTAssertTrue(dialogue.translationTemplate.contains("\u{E000}B1_ass:0_"))
        XCTAssertEqual(document.units[1].duplicateOf, dialogue.id)
        let translated = dialogue.translationTemplate
            .replacingOccurrences(of: "Şimdi, burada", with: "Now, here")
            .replacingOccurrences(of: "İğne ve çay", with: "Needle and tea")
        try document.applyTranslation(id: dialogue.id, text: translated)
        let output = try document.serialize()
        XCTAssertEqual(output.components(separatedBy: "{\\i1}Now, here{\\i0}\\NNeedle and tea").count - 1, 2)
        XCTAssertTrue(output.contains("[Custom Data]\nAnimeOffset: 12"))
        XCTAssertTrue(output.contains("Dialogue: 0:00:04.00,0:00:05.00,Spoken Lines,0,,{\\b1}Normal konuşma"))
        XCTAssertTrue(output.contains("[V4+ Styles]\nFormat: Name, Fontname"))
    }

    func testASSProtectedTagsCollisionAndValidation() throws {
        let source = "[Events]\nFormat: Start, End, Text\nDialogue: 0:00:01.00,0:00:02.00,{\\an8}{\\pos(100,200)}Literal {ASS_TAG_0} ve \\N çizgi \\h boşluk"
        var document = try SubtitleDocument.parse(source, format: .ass)
        // Positioning-heavy lines are skipped; use a normal tagged dialogue for validation.
        XCTAssertEqual(document.units[0].skipReason, .sign)
        let normal = "[Events]\nFormat: Start, End, Text\nDialogue: 0:00:01.00,0:00:02.00,{\\i1}{\\b1}Literal {ASS_TAG_0} ve \\N çizgi \\h boşluk"
        document = try SubtitleDocument.parse(normal, format: .ass)
        let unit = try XCTUnwrap(document.translatableUnits.first)
        XCTAssertTrue(unit.plainText.contains("Literal {ASS_TAG_0}"))
        XCTAssertTrue(unit.translationTemplate.contains("{ASS_TAG_0}"))
        XCTAssertThrowsError(try document.applyTranslation(id: unit.id, text: "Lost tags"))
        XCTAssertEqual(try document.serialize(), normal)
        let translated = unit.translationTemplate.replacingOccurrences(of: "Literal", with: "Gerçek")
        try document.applyTranslation(id: unit.id, text: translated)
        XCTAssertTrue(try document.serialize().contains("{\\i1}{\\b1}Gerçek {ASS_TAG_0} ve \\N çizgi \\h boşluk"))
    }

    func testASSNonDialogueHeuristicsAndNormalNamedStyle() throws {
        let document = try SubtitleDocument.parse(assFixture, format: .ass)
        XCTAssertEqual(document.units.map(\.skipReason), [nil, nil, .drawing, .karaoke, .sign, .effect, .openingOrEnding, nil])
        XCTAssertEqual(document.translatableUnits.last?.plainText, "Normal konuşma")
    }

    func testSSAWithTextInMiddleRetainsCommaAndFieldsAfterText() throws {
        let source = "[Script Info]\nTitle: Example\n[V4 Styles]\nFormat: Name, Fontname\n[Events]\nFormat: Start, Text, End, Style, Layer\nDialogue: 0:00:01.00,Merhaba, dünya,0:00:02.00,Default,0\n"
        var document = try SubtitleDocument.parse(source, format: .ssa)
        XCTAssertEqual(document.translatableUnits.first?.plainText, "Merhaba, dünya")
        XCTAssertEqual(try document.serialize(), source)
        try document.applyTranslation(id: document.translatableUnits[0].id, text: "Hello, world")
        XCTAssertTrue(try document.serialize().contains("Dialogue: 0:00:01.00,Hello, world,0:00:02.00,Default,0"))
    }

    func testInvalidVTTAndNonUTF8InputFailSafely() {
        XCTAssertThrowsError(try SubtitleDocument.parse("not webvtt", format: .vtt))
        XCTAssertThrowsError(try SubtitleDocument.parse(Data([0xFF]), format: .srt))
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
        Dialogue: 0:00:04.00,0:00:05.00,Signs,0,,{\\pos(100,200)}Exit
        Dialogue: 0:00:04.00,0:00:05.00,Default,0,scroll,scrolling effect
        Dialogue: 0:00:04.00,0:00:05.00,OP Romaji,0,,Opening lyrics
        Dialogue: 0:00:04.00,0:00:05.00,Spoken Lines,0,,{\\b1}Normal konuşma
        [Custom Data]
        AnimeOffset: 12
        """
    }
}

// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import XCTest
@testable import ThirteenYearsClockKit

final class PCOAttachmentTests: XCTestCase {
    private func json(_ text: String) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
    }

    func testParsesFileAndLinkAttachments() throws {
        let page = try json("""
        {"data": [
          {"type": "Attachment", "id": "1", "attributes": {"filename": "Chart.pdf", "content_type": "application/pdf", "file_size": 20480, "display_name": "Lead Sheet", "pco_type": "AttachmentS3", "attachable_type": "Song", "downloadable": true, "streamable": false}},
          {"type": "Attachment", "id": "2", "attributes": {"filename": "", "linked_url": "https://example.com/song", "pco_type": "AttachmentLink", "display_name": "Reference"}},
          {"type": "Attachment", "id": "3", "attributes": {"filename": "click.mp3", "content_type": "audio/mpeg", "streamable": true}}
        ]}
        """)
        let attachments = PCOClient.parseAttachments(page)
        XCTAssertEqual(attachments.map(\.id), ["1", "2", "3"])
        XCTAssertEqual(attachments[0].title, "Lead Sheet")
        XCTAssertEqual(attachments[0].fileSize, 20480)
        XCTAssertEqual(attachments[0].kind, .pdf)
        XCTAssertTrue(attachments[0].isDownloadable)
        XCTAssertEqual(attachments[0].attachableType, "Song")
        XCTAssertNil(attachments[1].filename)
        XCTAssertEqual(attachments[1].kind, .link)
        XCTAssertEqual(attachments[1].externalLink?.host, "example.com")
        XCTAssertEqual(attachments[2].kind, .audio)
        XCTAssertTrue(attachments[2].isStreamable)
        XCTAssertEqual(attachments[2].title, "click.mp3")
    }

    func testNonWebLinkedURLIsNotExternal() {
        let info = PCOAttachmentInfo(id: "1", filename: "a.txt", linkedURL: "file:///etc/passwd")
        XCTAssertNil(info.externalLink)
        XCTAssertFalse(info.isLink)
    }

    func testOpenResponseRequiresHTTPS() throws {
        let good = try json("""
        {"data": {"type": "AttachmentActivity", "id": "9", "attributes": {"attachment_url": "https://files.example.com/signed?token=abc"}}}
        """)
        XCTAssertEqual(PCOClient.parseAttachmentOpenURL(good)?.host, "files.example.com")

        let insecure = try json("""
        {"data": {"attributes": {"attachment_url": "http://files.example.com/x"}}}
        """)
        XCTAssertNil(PCOClient.parseAttachmentOpenURL(insecure))

        let local = try json("""
        {"data": {"attributes": {"attachment_url": "file:///tmp/x"}}}
        """)
        XCTAssertNil(PCOClient.parseAttachmentOpenURL(local))

        let credentials = try json("""
        {"data": {"attributes": {"attachment_url": "https://user:pw@evil.example/x"}}}
        """)
        XCTAssertNil(PCOClient.parseAttachmentOpenURL(credentials))

        XCTAssertNil(PCOClient.parseAttachmentOpenURL([:]))
        XCTAssertNil(PCOClient.parseAttachmentOpenURL(try json("{\"data\": {\"attributes\": {}}}")))
    }

    func testSignedURLHostRules() {
        XCTAssertTrue(PCOClient.isSignedDownloadURL(URL(string: "https://s3.amazonaws.com/bucket/key?sig=1")!))
        XCTAssertFalse(PCOClient.isSignedDownloadURL(URL(string: "http://s3.amazonaws.com/bucket")!))
        XCTAssertFalse(PCOClient.isSignedDownloadURL(URL(string: "ftp://example.com/a")!))
    }

    func testParsesArrangementChart() throws {
        let page = try json("""
        {"data": {"type": "Arrangement", "id": "a1", "attributes": {"name": "Default", "chord_chart": "VERSE 1\\nG      C\\nAmazing grace", "lyrics": "Amazing grace", "chord_chart_key": "G", "sequence": ["Verse 1", "Chorus 1"], "bpm": 72, "meter": "4/4"}}}
        """)
        let chart = try XCTUnwrap(PCOClient.parseArrangementChart(page))
        XCTAssertEqual(chart.arrangementId, "a1")
        XCTAssertEqual(chart.chordChartKey, "G")
        XCTAssertEqual(chart.sequence, ["Verse 1", "Chorus 1"])
        XCTAssertEqual(chart.bpm, 72)
        XCTAssertEqual(chart.meter, "4/4")
        XCTAssertTrue(chart.hasChart)
        XCTAssertTrue(chart.hasLyrics)
        XCTAssertNil(PCOClient.parseArrangementChart([:]))
    }

    func testOwnerPaths() {
        XCTAssertEqual(PCOAttachmentOwner.item(serviceTypeId: "st", planId: "p", itemId: "i").attachmentsPath,
                       "services/v2/service_types/st/plans/p/items/i/attachments")
        XCTAssertEqual(PCOAttachmentOwner.song(id: "s").attachmentsPath, "services/v2/songs/s/attachments")
        XCTAssertEqual(PCOAttachmentOwner.arrangement(songId: "s", arrangementId: "a").attachmentsPath,
                       "services/v2/songs/s/arrangements/a/attachments")
        XCTAssertEqual(PCOAttachmentOwner.media(id: "m").attachmentsPath, "services/v2/media/m/attachments")
        XCTAssertEqual(PCOAttachmentOwner.plan(serviceTypeId: "st", planId: "p").attachmentsPath,
                       "services/v2/service_types/st/plans/p/attachments")
    }

    func testOwnersForItem() {
        var item = PCOTimerItem(id: "i1", title: "Song", itemType: "song", sequence: 1, lengthInSeconds: 200, pcoServiceTypeId: "st", pcoPlanId: "p")
        item.details = PCOItemDetails(song: PCOSongInfo(id: "s1"), arrangement: PCOArrangementInfo(id: "a1"), media: PCOMediaInfo(id: "m1"))
        let owners = PCOAttachmentOwner.owners(for: item)
        XCTAssertEqual(owners.map(\.groupTitle), ["Item", "Song", "Arrangement", "Media"])
        let reference = PCOAttachmentOwner.chartReference(for: item)
        XCTAssertEqual(reference?.songId, "s1")
        XCTAssertEqual(reference?.arrangementId, "a1")

        let manual = PCOTimerItem(id: "x", title: "Manual", itemType: "item", sequence: 1, lengthInSeconds: 60)
        XCTAssertTrue(PCOAttachmentOwner.owners(for: manual).isEmpty)
        XCTAssertNil(PCOAttachmentOwner.chartReference(for: manual))
    }

    func testSafeFileName() {
        XCTAssertEqual(PCOClient.safeFileName("a/b\\c:d.pdf"), "a_b_c_d.pdf")
        XCTAssertEqual(PCOClient.safeFileName("..", fallbackExtension: "pdf"), "Attachment.pdf")
        XCTAssertEqual(PCOClient.safeFileName("Chart", fallbackExtension: "pdf"), "Chart.pdf")
        XCTAssertEqual(PCOClient.safeFileName("Chart.png", fallbackExtension: "pdf"), "Chart.png")
        XCTAssertLessThanOrEqual(PCOClient.safeFileName(String(repeating: "x", count: 300) + ".pdf").count, 110)
    }

    func testReferenceCacheInvalidates() {
        let cache = PCOReferenceCache()
        cache.store([PCOAttachmentInfo(id: "1")], for: "k")
        cache.store(PCOArrangementChart(arrangementId: "a"), for: "s/a")
        XCTAssertEqual(cache.attachments(for: "k")?.count, 1)
        XCTAssertNotNil(cache.chart(for: "s/a"))
        cache.removeAll()
        XCTAssertNil(cache.attachments(for: "k"))
        XCTAssertNil(cache.chart(for: "s/a"))
    }
}

final class ChordChartParserTests: XCTestCase {
    func testInlineChords() {
        let chart = ChordChartParser.parse("[G]Amazing [C]grace how [D]sweet")
        XCTAssertEqual(chart.format, .chordPro)
        let line = chart.sections[0].lines[0]
        XCTAssertEqual(line.text, "Amazing grace how sweet")
        XCTAssertEqual(line.chords, [
            ChordChart.Chord(column: 0, name: "G"),
            ChordChart.Chord(column: 8, name: "C"),
            ChordChart.Chord(column: 18, name: "D"),
        ])
        XCTAssertEqual(line.chordRow, "G       C         D")
    }

    func testInlineSlashAndExtendedChordsAndNonChordBrackets() {
        let chart = ChordChartParser.parse("[Em7/B]Hello [Bb]there [not a chord] ok")
        let line = chart.sections[0].lines[0]
        XCTAssertEqual(line.chords.map(\.name), ["Em7/B", "Bb"])
        XCTAssertEqual(line.text, "Hello there [not a chord] ok")
    }

    func testHeadings() {
        let text = "VERSE 1\n[G]Line one\n\nChorus:\n[C]Line two\n[Bridge]\n[D]Line three"
        let chart = ChordChartParser.parse(text)
        XCTAssertEqual(chart.sections.map(\.title), ["VERSE 1", "Chorus", "Bridge"])
        XCTAssertEqual(chart.sections[0].lines.count, 1)
        XCTAssertEqual(chart.sections[1].lines.count, 1)
    }

    func testChordOnlyBracketLineIsNotHeading() {
        let chart = ChordChartParser.parse("[G]\n")
        XCTAssertNil(chart.sections.first?.title)
        XCTAssertEqual(chart.sections.first?.lines.first?.chords.map(\.name), ["G"])
    }

    func testPlainTwoLineFormat() {
        let text = "VERSE 1\nG        C       D\nAmazing grace how sweet\n\nCHORUS\nEm   D\nHow sweet the sound"
        let chart = ChordChartParser.parse(text)
        XCTAssertEqual(chart.format, .plain)
        XCTAssertEqual(chart.sections.map(\.title), ["VERSE 1", "CHORUS"])
        let line = chart.sections[0].lines[0]
        XCTAssertEqual(line.text, "Amazing grace how sweet")
        XCTAssertEqual(line.chords, [
            ChordChart.Chord(column: 0, name: "G"),
            ChordChart.Chord(column: 9, name: "C"),
            ChordChart.Chord(column: 17, name: "D"),
        ])
        XCTAssertEqual(chart.sections[1].lines[0].chordRow, "Em   D")
    }

    func testLyricLineThatLooksLikeWordsIsNotChords() {
        let chart = ChordChartParser.parse("Am I\nBe a light")
        XCTAssertEqual(chart.format, .lyricsOnly)
        XCTAssertFalse(chart.hasChords)
        XCTAssertEqual(chart.sections[0].lines.map(\.text), ["Am I", "Be a light"])
    }

    func testChordOnlyLineBeforeBlank() {
        let chart = ChordChartParser.parse("INTRO\nG  C  D\n\nVERSE 1\nG\nHello")
        XCTAssertEqual(chart.sections[0].title, "INTRO")
        XCTAssertEqual(chart.sections[0].lines[0].text, "")
        XCTAssertEqual(chart.sections[0].lines[0].chordRow, "G  C  D")
        XCTAssertEqual(chart.sections[1].lines[0].text, "Hello")
    }

    func testLyricsOnlyModeDropsChordOnlyLines() {
        let chart = ChordChartParser.parse("INTRO\nG  C\n\nVERSE 1\n[G]Hello\n\n\n[C]World")
        XCTAssertTrue(chart.sections[0].lyricLines.isEmpty)
        XCTAssertEqual(chart.sections[1].lyricLines.map(\.text), ["Hello", "", "World"])
    }

    func testDirectivesAndMetadata() {
        let text = "{title: Amazing Grace}\n{key: G}\n{start_of_chorus}\n[G]Sing\n{end_of_chorus}\n{comment: Verse 2}\n[C]Again"
        let chart = ChordChartParser.parse(text)
        XCTAssertEqual(chart.metadata["title"], "Amazing Grace")
        XCTAssertEqual(chart.metadata["key"], "G")
        XCTAssertEqual(chart.sections.map(\.title), ["Chorus", "Verse 2"])
    }

    func testEmptyInput() {
        XCTAssertTrue(ChordChartParser.parse("").isEmpty)
        XCTAssertTrue(ChordChartParser.parse("  \n\n \r\n").isEmpty)
        XCTAssertEqual(ChordChartParser.parse("").format, .lyricsOnly)
    }

    func testWindowsLineEndings() {
        let chart = ChordChartParser.parse("VERSE\r\n[G]One\r\n[C]Two\r\n")
        XCTAssertEqual(chart.sections[0].lines.count, 2)
        XCTAssertEqual(chart.sections[0].lines[1].text, "Two")
    }

    func testOverlappingChordsStaySeparated() {
        let line = ChordChart.Line(text: "ab", chords: [
            ChordChart.Chord(column: 0, name: "Gsus4"),
            ChordChart.Chord(column: 1, name: "C"),
        ])
        XCTAssertEqual(line.chordRow, "Gsus4 C")
    }
}

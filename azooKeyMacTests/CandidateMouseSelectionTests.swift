import Cocoa
import Core
import KanaKanjiConverterModuleWithDefaultDictionary
import XCTest

@testable import azooKeyMac

@MainActor
final class CandidateMouseSelectionTests: XCTestCase {
    private func presentations(_ texts: [String]) -> [CandidatePresentation] {
        texts.map {
            CandidatePresentation(candidate: Candidate(text: $0, value: 0, composingCount: .surfaceCount(0), lastMid: 0, data: []))
        }
    }

    private func table(in view: NSView) -> NSTableView? {
        if let table = view as? NSTableView {
            return table
        }
        return view.subviews.lazy.compactMap { self.table(in: $0) }.first
    }

    private func click(_ point: NSPoint, in window: NSWindow, type: NSEvent.EventType = .leftMouseDown) async throws {
        let event = try XCTUnwrap(NSEvent.mouseEvent(
            with: type, location: point, modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1
        ))
        window.sendEvent(event)
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }

    func testClickSelectsThePointedCandidateInBothLists() async throws {
        _ = NSApplication.shared
        for controller in [CandidatesViewController(), PredictionCandidatesViewController()] as [BaseCandidateViewController] {
            let window = CandidateWindow(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            window.contentViewController = controller
            window.becomesKeyOnlyIfNeeded = true
            defer { window.orderOut(nil) }
            controller.updateCandidatePresentations(self.presentations(["父", "ちち", "乳"]), selectionIndex: 0, cursorLocation: .zero)
            window.contentView?.layoutSubtreeIfNeeded()
            window.orderFront(nil)
            let table = try XCTUnwrap(self.table(in: controller.view))
            var clickedTexts: [String] = []
            controller.candidateClicked = { _ in
                clickedTexts.append(controller.getSelectedCandidate()!.text)
            }
            let rect = table.rect(ofRow: 2)

            try await self.click(table.convert(NSPoint(x: rect.midX, y: rect.midY), to: nil), in: window)

            XCTAssertEqual(clickedTexts, ["乳"])
            XCTAssertEqual(controller.getSelectedCandidate()?.text, "乳")
            XCTAssertFalse(window.isKeyWindow)
        }
    }

    func testBlankSpaceAndSecondaryButtonsDoNotAcceptACandidate() async throws {
        _ = NSApplication.shared
        let controller = CandidatesViewController()
        let window = CandidateWindow(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.contentViewController = controller
        defer { window.orderOut(nil) }
        controller.updateCandidatePresentations(self.presentations(["父", "ちち"]), selectionIndex: 0, cursorLocation: .zero)
        window.setContentSize(NSSize(width: 300, height: 300))
        window.contentView?.layoutSubtreeIfNeeded()
        window.orderFront(nil)
        let table = try XCTUnwrap(self.table(in: controller.view))
        var clickedRows: [Int] = []
        controller.candidateClicked = { clickedRows.append($0) }
        let rect = table.rect(ofRow: 1)
        let point = table.convert(NSPoint(x: rect.midX, y: rect.midY), to: nil)

        try await self.click(point, in: window, type: .rightMouseDown)
        try await self.click(point, in: window, type: .otherMouseDown)
        try await self.click(table.convert(NSPoint(x: rect.midX, y: rect.maxY + 40), to: nil), in: window)

        XCTAssertEqual(clickedRows, [])
        XCTAssertEqual(controller.getSelectedCandidate()?.text, "父")
    }

    func testClickAfterPageNavigationUsesTheVisibleCandidate() async throws {
        _ = NSApplication.shared
        let controller = CandidatesViewController()
        let window = CandidateWindow(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.contentViewController = controller
        defer { window.orderOut(nil) }
        controller.updateCandidatePresentations(self.presentations((1...21).map { "候補\($0)" }), selectionIndex: 0, cursorLocation: .zero)
        window.orderFront(nil)
        window.contentView?.layoutSubtreeIfNeeded()
        _ = controller.selectCandidatePage(1)
        let table = try XCTUnwrap(self.table(in: controller.view))
        var clickedTexts: [String] = []
        controller.candidateClicked = { _ in
            clickedTexts.append(controller.getSelectedCandidate()!.text)
        }
        let rect = table.rect(ofRow: 11)

        try await self.click(table.convert(NSPoint(x: rect.midX, y: rect.midY), to: nil), in: window)

        XCTAssertEqual(clickedTexts, ["候補12"])
    }

    func testClickKeepsThePointedCandidateWhenResultsAreReordered() async throws {
        _ = NSApplication.shared
        let controller = CandidatesViewController()
        let window = CandidateWindow(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.contentViewController = controller
        defer { window.orderOut(nil) }
        controller.updateCandidatePresentations(self.presentations(["父", "ちち", "乳"]), selectionIndex: 0, cursorLocation: .zero)
        window.contentView?.layoutSubtreeIfNeeded()
        window.orderFront(nil)
        let table = try XCTUnwrap(self.table(in: controller.view))
        var clickedTexts: [String] = []
        controller.candidateClicked = { _ in clickedTexts.append(controller.getSelectedCandidate()!.text) }
        let rect = table.rect(ofRow: 1)
        let event = try XCTUnwrap(NSEvent.mouseEvent(
            with: .leftMouseDown, location: table.convert(NSPoint(x: rect.midX, y: rect.midY), to: nil),
            modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil,
            eventNumber: 0, clickCount: 1, pressure: 1
        ))

        window.sendEvent(event)
        controller.updateCandidatePresentations(self.presentations(["乳", "父", "ちち"]), selectionIndex: 0, cursorLocation: .zero)
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }

        XCTAssertEqual(clickedTexts, ["ちち"])
    }
}

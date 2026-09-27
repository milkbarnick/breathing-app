import SwiftData
import XCTest
@testable import Wayfare

/// Applying `/v1/sync` responses: idempotent upserts keyed by lowercased id, tombstones, local edits kept.
final class SyncApplyTests: XCTestCase {
    private func response(tripDeletedAt: String = "null", itemId: String = "3fa85f64-5717-4562-b3fc-2c963f66afa6",
                          itemDeletedAt: String = "null", title: String = "TP 202") throws -> SyncResponseDTO {
        let trip = DTOCodingTests.tripJSON.replacingOccurrences(of: "\"deletedAt\": null",
                                                                with: "\"deletedAt\": \(tripDeletedAt)")
        let item = DTOCodingTests.itemJSON
            .replacingOccurrences(of: "3fa85f64-5717-4562-b3fc-2c963f66afa6", with: itemId)
            .replacingOccurrences(of: "\"deletedAt\": null", with: "\"deletedAt\": \(itemDeletedAt)")
            .replacingOccurrences(of: "TP 202 JFK → LIS", with: title)
        let body = """
        { "trips": [\(trip)], "items": [\(item)], "members": [\(DTOCodingTests.memberJSON)], "cursor": 1727000001000 }
        """
        return try JSONCoding.makeDecoder().decode(SyncResponseDTO.self, from: Data(body.utf8))
    }

    @MainActor
    private func counts(_ context: ModelContext) throws -> [Int] {
        [
            try context.fetchCount(FetchDescriptor<Trip>()),
            try context.fetchCount(FetchDescriptor<Item>()),
            try context.fetchCount(FetchDescriptor<Member>()),
        ]
    }

    @MainActor
    func testRepeatedRowsAreUpsertedNotDuplicated() throws {
        let services = AppServices(inMemory: true, previewUser: SampleData.user)
        let context = services.container.mainContext
        try services.sync.apply(response())
        try services.sync.apply(response())
        // The same item id in uppercase must match the existing row too.
        try services.sync.apply(response(itemId: "3FA85F64-5717-4562-B3FC-2C963F66AFA6", title: "Renamed"))
        XCTAssertEqual(try counts(context), [1, 1, 1])
        let item = try XCTUnwrap(context.fetch(FetchDescriptor<Item>()).first)
        XCTAssertEqual(item.id, "3fa85f64-5717-4562-b3fc-2c963f66afa6")
        XCTAssertEqual(item.title, "Renamed")
        XCTAssertFalse(item.needsPush)
    }

    @MainActor
    func testUnpushedLocalEditIsNotOverwritten() throws {
        let services = AppServices(inMemory: true, previewUser: SampleData.user)
        let context = services.container.mainContext
        try services.sync.apply(response())
        let item = try XCTUnwrap(context.fetch(FetchDescriptor<Item>()).first)
        item.title = "Edited offline"
        item.markEdited()
        try services.sync.apply(response(title: "Server version"))
        XCTAssertEqual(item.title, "Edited offline")
        XCTAssertTrue(item.needsPush)
    }

    @MainActor
    func testTombstonesDeleteLocalRows() throws {
        let services = AppServices(inMemory: true, previewUser: SampleData.user)
        let context = services.container.mainContext
        try services.sync.apply(response())

        try services.sync.apply(response(itemDeletedAt: "1727000002000"))
        XCTAssertEqual(try counts(context), [1, 0, 1])

        try services.sync.apply(response(tripDeletedAt: "1727000003000", itemDeletedAt: "1727000003000"))
        XCTAssertEqual(try counts(context), [0, 0, 0], "a trip tombstone removes its items and members")
    }
}

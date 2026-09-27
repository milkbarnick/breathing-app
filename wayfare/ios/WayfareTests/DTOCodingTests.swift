import XCTest
@testable import Wayfare

/// DTOs against the JSON samples in docs/api-contract.md.
final class DTOCodingTests: XCTestCase {
    private let decoder = JSONCoding.makeDecoder()
    private let encoder = JSONCoding.makeEncoder()

    private func json(_ text: String) -> Data {
        Data(text.utf8)
    }

    private func object(_ data: Data) throws -> [String: Any] {
        let value = try JSONSerialization.jsonObject(with: data)
        return try XCTUnwrap(value as? [String: Any])
    }

    // MARK: - Samples copied from the contract

    static let tripJSON = """
    {
      "id": "0f8fad5b-d9cb-469f-a165-70867728950e",
      "ownerId": "7c9e6679-7425-40de-944b-e07fc1f90ae7",
      "title": "Lisbon & Porto",
      "destination": "Portugal",
      "startDate": "2026-10-01",
      "endDate": "2026-10-09",
      "timeZone": "Europe/Lisbon",
      "coverEmoji": "🇵🇹",
      "colorHex": "#2F6FEB",
      "notes": "",
      "updatedAt": 1727000000000,
      "deletedAt": null
    }
    """

    static let itemJSON = """
    {
      "id": "3fa85f64-5717-4562-b3fc-2c963f66afa6",
      "tripId": "0f8fad5b-d9cb-469f-a165-70867728950e",
      "kind": "flight",
      "title": "TP 202 JFK → LIS",
      "startAt": "2026-10-01T22:30:00Z",
      "endAt":   "2026-10-02T09:45:00Z",
      "startTimeZone": "America/New_York",
      "endTimeZone": "Europe/Lisbon",
      "allDay": false,
      "locationName": "JFK Terminal 1",
      "address": "",
      "latitude": 40.6413,
      "longitude": -73.7781,
      "confirmationCode": "ABC123",
      "details": { "airline": "TAP", "flightNumber": "TP202", "fromCode": "JFK", "toCode": "LIS", "seat": "14A" },
      "notes": "",
      "reminderMinutes": 180,
      "sortIndex": 0,
      "updatedAt": 1727000000000,
      "updatedBy": "7c9e6679-7425-40de-944b-e07fc1f90ae7",
      "deletedAt": null
    }
    """

    static let memberJSON = """
    { "tripId": "0f8fad5b-d9cb-469f-a165-70867728950e", "userId": "7c9e6679-7425-40de-944b-e07fc1f90ae7", "displayName": "Sam", "role": "editor", "updatedAt": 1727000000000, "deletedAt": null }
    """

    static let userJSON = """
    { "id": "7c9e6679-7425-40de-944b-e07fc1f90ae7", "displayName": "Nick", "email": "x@privaterelay.appleid.com", "createdAt": 1727000000000 }
    """

    // MARK: - Decoding

    func testDecodesTrip() throws {
        let trip = try decoder.decode(TripDTO.self, from: json(Self.tripJSON))
        XCTAssertEqual(trip.id, "0f8fad5b-d9cb-469f-a165-70867728950e")
        XCTAssertEqual(trip.title, "Lisbon & Porto")
        XCTAssertEqual(trip.startDate, "2026-10-01")
        XCTAssertEqual(trip.endDate, "2026-10-09")
        XCTAssertEqual(trip.timeZone, "Europe/Lisbon")
        XCTAssertEqual(trip.coverEmoji, "🇵🇹")
        XCTAssertEqual(trip.updatedAt, 1_727_000_000_000)
        XCTAssertNil(trip.deletedAt)
    }

    func testDecodesItem() throws {
        let item = try decoder.decode(ItemDTO.self, from: json(Self.itemJSON))
        XCTAssertEqual(item.kind, "flight")
        XCTAssertEqual(item.startAt, Date(timeIntervalSince1970: 1_790_893_800)) // 2026-10-01T22:30:00Z
        XCTAssertEqual(item.endAt, Date(timeIntervalSince1970: 1_790_934_300)) // 2026-10-02T09:45:00Z
        XCTAssertEqual(item.startTimeZone, "America/New_York")
        XCTAssertEqual(item.endTimeZone, "Europe/Lisbon")
        XCTAssertEqual(item.latitude ?? 0, 40.6413, accuracy: 0.00001)
        XCTAssertEqual(item.details["flightNumber"], "TP202")
        XCTAssertEqual(item.details.count, 5)
        XCTAssertEqual(item.reminderMinutes, 180)
        XCTAssertEqual(item.updatedBy, "7c9e6679-7425-40de-944b-e07fc1f90ae7")
        XCTAssertNil(item.deletedAt)
    }

    func testDecodesMemberAndUser() throws {
        let member = try decoder.decode(MemberDTO.self, from: json(Self.memberJSON))
        XCTAssertEqual(member.role, "editor")
        XCTAssertEqual(member.displayName, "Sam")
        let user = try decoder.decode(UserDTO.self, from: json(Self.userJSON))
        XCTAssertEqual(user.displayName, "Nick")
        XCTAssertEqual(user.createdAt, 1_727_000_000_000)
    }

    func testDecodesSyncResponseWithTombstones() throws {
        let tombstone = """
        { "id": "11111111-2222-4333-8444-555555555555", "tripId": "0f8fad5b-d9cb-469f-a165-70867728950e",
          "kind": "food", "title": "Gone", "startAt": "2026-10-03T19:30:00Z", "endAt": null,
          "startTimeZone": "Europe/Lisbon", "endTimeZone": null, "allDay": false, "locationName": "",
          "address": "", "latitude": null, "longitude": null, "confirmationCode": "", "details": {},
          "notes": "", "reminderMinutes": null, "sortIndex": 1, "updatedAt": 1727000000500,
          "updatedBy": null, "deletedAt": 1727000000500 }
        """
        let body = """
        { "trips": [\(Self.tripJSON)], "items": [\(Self.itemJSON), \(tombstone)], "members": [\(Self.memberJSON)], "cursor": 1727000000999 }
        """
        let response = try decoder.decode(SyncResponseDTO.self, from: json(body))
        XCTAssertEqual(response.trips.count, 1)
        XCTAssertEqual(response.items.count, 2)
        XCTAssertEqual(response.members.count, 1)
        XCTAssertEqual(response.cursor, 1_727_000_000_999)
        XCTAssertEqual(response.items[1].deletedAt, 1_727_000_000_500)
        XCTAssertNil(response.items[1].endAt)
        XCTAssertNil(response.items[1].reminderMinutes)
    }

    func testDecodesErrorBody() throws {
        let body = json(#"{ "error": { "code": "rate_limited", "message": "Daily import limit reached" } }"#)
        let error = APIError.from(status: 429, data: body, decoder: decoder)
        XCTAssertEqual(error, .server(status: 429, code: "rate_limited", message: "Daily import limit reached"))
        XCTAssertTrue(error.isRateLimited)
        XCTAssertFalse(error.isPermanentRejection)
    }

    func testErrorWithoutBodyGetsDefaultCode() {
        let error = APIError.from(status: 403, data: Data(), decoder: decoder)
        XCTAssertEqual(error.code, "forbidden")
        XCTAssertTrue(error.isPermanentRejection)
    }

    func testUppercaseIdsAreLowercased() throws {
        let upper = Self.tripJSON.replacingOccurrences(of: "0f8fad5b-d9cb-469f-a165-70867728950e",
                                                       with: "0F8FAD5B-D9CB-469F-A165-70867728950E")
        let trip = try decoder.decode(TripDTO.self, from: json(upper))
        XCTAssertEqual(trip.id, "0f8fad5b-d9cb-469f-a165-70867728950e")
    }

    func testAcceptsFractionalSecondsLeniently() throws {
        let body = json(#"{ "code": "AB12CD34", "url": "wayfare://invite/AB12CD34", "expiresAt": "2026-10-08T12:00:00.000Z" }"#)
        let invite = try decoder.decode(InviteDTO.self, from: body)
        XCTAssertEqual(invite.expiresAt, Date(timeIntervalSince1970: 1_791_460_800))
    }

    // MARK: - Encoding

    func testEncodesItemWriteWithContractFormats() throws {
        let dto = ItemWriteDTO(
            id: "3fa85f64-5717-4562-b3fc-2c963f66afa6", tripId: "0f8fad5b-d9cb-469f-a165-70867728950e",
            kind: "flight", title: "TP 202", startAt: Date(timeIntervalSince1970: 1_790_893_800), endAt: nil,
            startTimeZone: "America/New_York", endTimeZone: nil, allDay: false, locationName: "JFK",
            address: "", latitude: nil, longitude: nil, confirmationCode: "ABC123",
            details: ["seat": "14A"], notes: "", reminderMinutes: nil, sortIndex: 0)
        let body = try object(encoder.encode(dto))

        XCTAssertEqual(body["startAt"] as? String, "2026-10-01T22:30:00Z")
        XCTAssertTrue(body["endAt"] is NSNull, "optional fields are sent as explicit null")
        XCTAssertTrue(body["endTimeZone"] is NSNull)
        XCTAssertTrue(body["reminderMinutes"] is NSNull)
        XCTAssertTrue(body["latitude"] is NSNull)
        XCTAssertEqual((body["details"] as? [String: String])?["seat"], "14A")
        XCTAssertNil(body["updatedAt"], "server-owned fields are never sent")
        XCTAssertNil(body["updatedBy"])
        XCTAssertNil(body["deletedAt"])
        XCTAssertEqual(Set(body.keys), [
            "id", "tripId", "kind", "title", "startAt", "endAt", "startTimeZone", "endTimeZone", "allDay",
            "locationName", "address", "latitude", "longitude", "confirmationCode", "details", "notes",
            "reminderMinutes", "sortIndex",
        ])
    }

    func testEncodesTripWriteWithOnlyWritableFields() throws {
        let dto = TripWriteDTO(title: "Lisbon & Porto", destination: "Portugal", startDate: "2026-10-01",
                               endDate: "2026-10-09", timeZone: "Europe/Lisbon", coverEmoji: "🇵🇹",
                               colorHex: "#2F6FEB", notes: "")
        let body = try object(encoder.encode(dto))
        XCTAssertEqual(Set(body.keys), ["title", "destination", "startDate", "endDate", "timeZone",
                                        "coverEmoji", "colorHex", "notes"])
        XCTAssertEqual(body["startDate"] as? String, "2026-10-01")
    }

    func testEncodesAuthRequestWithNulls() throws {
        let body = try object(encoder.encode(AppleAuthRequest(identityToken: "jwt", authorizationCode: nil, displayName: nil)))
        XCTAssertEqual(body["identityToken"] as? String, "jwt")
        XCTAssertTrue(body["authorizationCode"] is NSNull)
        XCTAssertTrue(body["displayName"] is NSNull)
    }

    func testEncodesDeviceAndLogout() throws {
        let device = DeviceRegistrationDTO(apnsToken: "abcd", environment: "sandbox", timeZone: "America/New_York",
                                           briefingEnabled: true, briefingHour: 7, collabAlertsEnabled: true)
        let body = try object(encoder.encode(device))
        XCTAssertEqual(Set(body.keys), ["apnsToken", "environment", "timeZone", "briefingEnabled", "briefingHour",
                                        "collabAlertsEnabled"])
        XCTAssertEqual(body["briefingHour"] as? Int, 7)

        let logout = try object(encoder.encode(LogoutRequest(apnsToken: "abcd")))
        XCTAssertEqual(logout["apnsToken"] as? String, "abcd")
    }

    func testDeviceTokenHex() {
        let token = Data([0x00, 0x0f, 0xa0, 0xff])
        XCTAssertEqual(DeviceRegistrar.hexString(from: token), "000fa0ff")
    }

    func testItemDraftDecodesLeniently() throws {
        let body = json(#"{ "items": [ { "kind": "lodging", "title": "Memmo Alfama", "startAt": "2026-10-01T14:00:00Z", "startTimeZone": "Europe/Lisbon" }, { "kind": "mystery" } ] }"#)
        let response = try decoder.decode(ImportResponseDTO.self, from: body)
        XCTAssertEqual(response.items.count, 2)
        XCTAssertNil(response.items[0].endAt)
        XCTAssertEqual(response.items[0].details, [:])
        XCTAssertNil(response.items[1].startAt)
    }

    // MARK: - Deep links

    func testInviteCodeFromURL() throws {
        XCTAssertEqual(AppRouter.inviteCode(from: try XCTUnwrap(URL(string: "wayfare://invite/AB12CD34"))), "AB12CD34")
        XCTAssertNil(AppRouter.inviteCode(from: try XCTUnwrap(URL(string: "wayfare://trip/123"))))
        XCTAssertNil(AppRouter.inviteCode(from: try XCTUnwrap(URL(string: "https://example.com/invite/AB12CD34"))))
        XCTAssertEqual(AppRouter.normalizeCode("ab12-cd 34"), "AB12CD34")
    }
}

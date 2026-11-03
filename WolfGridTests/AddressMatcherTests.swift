import XCTest
@testable import WolfGrid

final class AddressMatcherTests: XCTestCase {
    func testDirectionalVariantsShareOneIdentity() {
        let variants = ["E Belmar St", "East Belmar Street", "Belmar St E", "Belmar Street East", "Belmar East Street", "BELMAR E. ST."]
        for street in variants {
            XCTAssertEqual(AddressMatcher.identity(houseNumber: "405", streetName: street), "405|belmar street east", street)
            XCTAssertEqual(AddressMatcher.identity(houseNumber: nil, streetName: nil, formatted: "405 \(street), Windsor, ON"), "405|belmar street east", street)
        }
    }

    func testCompassDirectionsAndSuffixes() {
        for (short, full) in [("N", "North"), ("S", "South"), ("E", "East"), ("W", "West"), ("NE", "Northeast"), ("NW", "Northwest"), ("SE", "Southeast"), ("SW", "Southwest")] {
            XCTAssertEqual(AddressMatcher.streetKey("\(short) Main Rd."), AddressMatcher.streetKey("Main Road \(full)"))
        }
        XCTAssertEqual(AddressMatcher.streetKey("North East Main Avenue"), AddressMatcher.streetKey("Main Ave Northeast"))
        XCTAssertEqual(AddressMatcher.streetKey("O’Connor Cres."), AddressMatcher.streetKey("OConnor Crescent"))
        XCTAssertEqual(AddressMatcher.streetKey("St John St"), "st john street")
    }

    func testDifferentHomesAndAmbiguousNamesRemainDistinct() {
        let base = AddressMatcher.identity(houseNumber: "405", streetName: "Belmar St E")
        for (house, street) in [("403", "Belmar St E"), ("405A", "Belmar St E"), ("405-407", "Belmar St E"), ("405", "Belmar St W"), ("405", "Belmar St")] {
            XCTAssertNotEqual(base, AddressMatcher.identity(houseNumber: house, streetName: street))
        }
        XCTAssertNotEqual(AddressMatcher.streetKey("East Street"), AddressMatcher.streetKey("Street East"))
        XCTAssertNotEqual(AddressMatcher.streetKey("North Road"), AddressMatcher.streetKey("Road North"))
        XCTAssertNil(AddressMatcher.identity(houseNumber: nil, streetName: "Main St"))
        XCTAssertNil(AddressMatcher.identity(houseNumber: "51ST", streetName: "51ST"))
    }

    func testUnitsArePreservedAcrossFormattedAndStructuredAddresses() {
        let expected = AddressMatcher.identity(houseNumber: "405", streetName: "Belmar St E", unit: "2")
        for formatted in ["405 E Belmar St Unit 2", "Unit 2 405 Belmar St E", "405 East Belmar Street #2", "405 Belmar St E, Suite 2, Windsor"] {
            XCTAssertEqual(expected, AddressMatcher.identity(houseNumber: nil, streetName: nil, formatted: formatted), formatted)
        }
        XCTAssertEqual(expected, AddressMatcher.identity(houseNumber: "405", streetName: "Belmar St E", formatted: "405 E Belmar St Unit 2", unit: " "))
        XCTAssertNotEqual(expected, AddressMatcher.identity(houseNumber: "405", streetName: "Belmar St E"))
        XCTAssertNotEqual(expected, AddressMatcher.identity(houseNumber: "405", streetName: "Belmar St E", unit: "3"))
    }
}

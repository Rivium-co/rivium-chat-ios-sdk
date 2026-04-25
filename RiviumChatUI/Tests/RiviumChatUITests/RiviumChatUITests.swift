import XCTest
@testable import RiviumChatUI

final class RiviumChatUITests: XCTestCase {
    func testColorsDefaultValues() {
        let colors = RiviumChatColors()
        XCTAssertNotNil(colors.myMessageBubble)
        XCTAssertNotNil(colors.otherMessageBubble)
    }
    
    func testDimensionsDefaultValues() {
        let dimensions = RiviumChatDimensions()
        XCTAssertEqual(dimensions.messageBubbleRadius, 16)
        XCTAssertEqual(dimensions.avatarSize, 40)
    }
}

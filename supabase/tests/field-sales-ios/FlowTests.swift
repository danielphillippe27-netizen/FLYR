import XCTest
final class SalesFlowTests: XCTestCase {
 func testRecordVerifyAndCancel() throws {
  continueAfterFailure = false
  let app = XCUIApplication(); app.launch()
  XCTAssertTrue(app.staticTexts["Set a monthly sales target"].waitForExistence(timeout:15))
  XCTAssertTrue(app.buttons["Open Sales"].waitForExistence(timeout:15)); app.buttons["Open Sales"].tap()
  let record=app.buttons["Record Sale · Beta"]
  for _ in 0..<7 { if record.isHittable { break }; app.swipeUp() }
  XCTAssertTrue(record.waitForExistence(timeout:10)); record.tap()
  let picker=app.buttons.matching(NSPredicate(format:"label CONTAINS %@", "Existing lead")).firstMatch
  XCTAssertTrue(picker.waitForExistence(timeout:5)); picker.tap()
  app.buttons["Owner customer"].tap()
  let amount=app.textFields["Contract value (CAD)"]; amount.tap();amount.typeText("12345.67")
  let save=app.buttons["Save sale"];if !save.isHittable { app.swipeUp() };save.tap()
  XCTAssertTrue(app.buttons["Verify"].waitForExistence(timeout:10))
  app.buttons["Verify"].tap()
  XCTAssertTrue(app.staticTexts["Owner · Verified"].waitForExistence(timeout:10))
  app.navigationBars.buttons.firstMatch.tap()
  XCTAssertTrue(app.staticTexts["1 this month"].waitForExistence(timeout:10))
  app.buttons["Open sales leaderboard"].tap()
  XCTAssertTrue(app.staticTexts.matching(NSPredicate(format:"label CONTAINS %@", "1 sales")).firstMatch.waitForExistence(timeout:10))
  app.navigationBars.buttons.firstMatch.tap()
  app.buttons["Open Sales"].tap()
  for _ in 0..<7 { if app.buttons["Cancel"].firstMatch.isHittable { break }; app.swipeUp() }
  app.buttons["Cancel"].firstMatch.tap()
  let reason=app.alerts.textFields.firstMatch;XCTAssertTrue(reason.waitForExistence(timeout:5));reason.tap();reason.typeText("Simulator acceptance reversal")
  app.alerts.buttons["Cancel sale"].tap()
  XCTAssertTrue(app.staticTexts["Owner · Cancelled"].waitForExistence(timeout:10))
  app.navigationBars.buttons.firstMatch.tap()
  XCTAssertTrue(app.staticTexts["0 this month"].waitForExistence(timeout:10))
 }
 func testPipelineFollowUp() throws {
  continueAfterFailure = false
  let app = XCUIApplication(); app.launch()
  XCTAssertTrue(app.buttons["Open Sales"].waitForExistence(timeout:15)); app.buttons["Open Sales"].tap()
  let pipeline = app.buttons["Pipeline & follow-ups · Beta"]
  XCTAssertTrue(pipeline.waitForExistence(timeout:15)); pipeline.tap()
  let add = app.buttons["Add follow-up · Beta"]
  for _ in 0..<5 { if add.isHittable { break }; app.swipeUp() }
  XCTAssertTrue(add.waitForExistence(timeout:15)); add.tap()
  let taskTitle = "Simulator follow-up " + UUID().uuidString.prefix(6)
  let title = app.textFields["Task"]; XCTAssertTrue(title.waitForExistence(timeout:10)); title.tap(); title.typeText(taskTitle)
  app.buttons["Save follow-up"].tap()
  let task = app.staticTexts[taskTitle]
  for _ in 0..<7 { if task.isHittable { break }; app.swipeUp() }
  XCTAssertTrue(task.waitForExistence(timeout:15))
  app.cells.containing(.staticText, identifier: taskTitle).firstMatch.buttons["Complete"].tap()
  let done = app.switches["Completed in last 30 days"]; if !done.isHittable { app.swipeDown() }; let control = done.switches.firstMatch.exists ? done.switches.firstMatch : done
  if control.value as? String == "0" { control.tap() }
  for _ in 0..<5 { if task.isHittable { break }; app.swipeUp() }
  XCTAssertTrue(task.waitForExistence(timeout:15))
 }

}

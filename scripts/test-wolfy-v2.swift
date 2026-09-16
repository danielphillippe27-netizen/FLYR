import Foundation
@main struct WolfyV2Tests {
 static func main() {
  let rules = WolfyRulesV2.initial
  for (i,xp) in rules.thresholds.enumerated() {
   assert(rules.stage(xp:xp).rawValue == i+1)
   if xp > 0 { assert(rules.stage(xp:xp-1).rawValue == i) }
  }
  assert(rules.stage(xp:-1) == .pup && rules.remaining(xp:100000) == nil)
  let now = Date(timeIntervalSince1970:10000)
  func fix(_ age:Double = 0, sequence:Int64 = 1, lat:Double = 43) -> WolfyPackFixV2 {
   .init(latitude:lat,longitude:-79,accuracy:5,heading:0,speed:1,fixedAt:now.addingTimeInterval(-age),sequence:sequence)
  }
  assert(WolfyPackPresencePolicyV2.freshness(fix:fix(60),permitted:true,activeSession:true,now:now) == .stale)
  assert(WolfyPackPresencePolicyV2.freshness(fix:fix(180),permitted:true,activeSession:true,now:now) == .hidden)
  assert(WolfyPackPresencePolicyV2.freshness(fix:fix(),permitted:false,activeSession:true,now:now) == .hidden)
  assert(WolfyPackPresencePolicyV2.freshness(fix:fix(),permitted:true,activeSession:false,now:now) == .hidden)
  assert(!WolfyPackPresencePolicyV2.accepts(fix(sequence:1),previous:fix(5),now:now))
  assert(!WolfyPackPresencePolicyV2.accepts(fix(sequence:2,lat:44),previous:fix(5),now:now))
  assert(WolfyPackPresencePolicyV2.accepts(fix(sequence:2,lat:43.00001),previous:fix(5),now:now))
  assert(!WolfyPackPresencePolicyV2.nearby(fix(61),fix(),now:now))
  assert(!WolfyPackPresencePolicyV2.shouldPublish(now:now,lastSent:now.addingTimeInterval(-4),moving:true,eligibilityChanged:false))
  assert(WolfyPackPresencePolicyV2.shouldPublish(now:now,lastSent:now,moving:true,eligibilityChanged:true))
  var machine = WolfyBehaviorV2()
  func event(_ id:String,_ kind:String,_ seconds:Double = 60) -> WolfyReactionV2 {
   .init(id:id,kind:kind,occurredAt:now,expiresAt:now.addingTimeInterval(seconds),duration:3)
  }
  let priorityOrder = ["campaign_complete","evolution","verified_sale","appointment","doors_25","daily_goal","lead"]
  for pair in zip(priorityOrder, priorityOrder.dropFirst()) {
   assert(event(pair.0,pair.0).priority > event(pair.1,pair.1).priority)
  }
  assert(machine.request(event("e","evolution"),now:now))
  assert(!machine.request(event("d","door"),now:now))
  assert(!machine.request(event("p","personal_best"),now:now))
  assert(machine.pendingMajor?.id == "p")
  machine.update(speed:2,distanceBehind:0,inactiveFor:0,activity:.moving,now:now.addingTimeInterval(4))
  assert(machine.gait == .trot && machine.reaction?.id == "p")
  assert(!machine.request(event("e","evolution"),now:now.addingTimeInterval(5)))
  machine.resume(); assert(machine.reaction == nil && machine.pendingMajor == nil)
  machine.update(speed:0,distanceBehind:0,inactiveFor:600,activity:.idle,now:now)
  assert(machine.posture == .lying)
  machine.update(speed:0,distanceBehind:0,inactiveFor:600,activity:.conversation,now:now)
  assert(machine.posture == .standing)
  let first=machine.clip(pool:"lead",candidates:["a","b"],randomIndex:0)
  assert(machine.clip(pool:"lead",candidates:["a","b"],randomIndex:0) != first)
  var budget=WolfyPackPresentationBudgetV2()
  assert(budget.banner(now:now) && !budget.banner(now:now.addingTimeInterval(29)))
  assert(!budget.haptic(now:now,personalMode:.off,teamEnabled:true,foreground:true,personalFeedbackActive:false))
  assert(budget.haptic(now:now,personalMode:.subtle,teamEnabled:true,foreground:true,personalFeedbackActive:false))
  assert(!budget.haptic(now:now.addingTimeInterval(59),personalMode:.full,teamEnabled:true,foreground:true,personalFeedbackActive:false))
  print("PASS: evolution boundaries, freshness/privacy, packet ordering, teleport rejection, throttling, reaction priority, deduplication, posture, no-repeat pools and feedback budgets")
 }
}

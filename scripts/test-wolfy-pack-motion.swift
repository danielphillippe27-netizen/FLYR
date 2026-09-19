import Foundation
@main struct WolfyPackMotionTests {
 static func main() {
  let now = Date(timeIntervalSince1970:1_800_000_000), session=UUID()
  func fix(_ index: Int, age: Double = 0, sequence: Int64 = 1) -> WolfyPackFixV2 {
   .init(latitude:43+Double(index)*0.000001,longitude:-79,accuracy:5,heading:90,speed:1,fixedAt:now.addingTimeInterval(-age),sequence:sequence)
  }
  let ids=(0..<50).map { _ in UUID() }
  let input=ids.enumerated().map { i,id in WolfyPackMotionV2.Input(id:id,stage:WolfyStage(rawValue:i%5+1)!,fix:fix(i),session:session,activity:.moving,firstName:"Rep") }
  var motion=WolfyPackMotionV2();motion.replace(input,now:now)
  func poses(_ at: Date, constrained: Bool = false) -> [WolfyPackMotionV2.Pose] {
   motion.poses(now:at,center:fix(0),selected:ids[49],local:ids[48],reduceMotion:false,constrained:constrained)
  }
  let all=poses(now)
  assert(all.count==50 && all.filter{$0.detail == .full}.count==6 && all.filter{$0.detail == .simplified}.count==2)
  assert(all.first?.id==ids[49] && all[1].id==ids[48])
  assert(poses(now,constrained:true).filter{$0.detail != .marker}.count==5)
  let two=poses(now.addingTimeInterval(2)),ten=poses(now.addingTimeInterval(10))
  assert(two.map(\.longitude)==ten.map(\.longitude),"No extrapolation beyond two seconds")
  assert(poses(now.addingTimeInterval(60)).allSatisfy{$0.opacity==0.35 && $0.clip=="idle"})
  assert(poses(now.addingTimeInterval(180)).isEmpty)
  motion.replace([],now:now);assert(motion.count==0,"Revocation removes coordinates")
  motion.replace(input,now:now)
  let hidden=input.map { WolfyPackMotionV2.Input(id:$0.id,stage:$0.stage,fix:nil,session:session,activity:.idle,firstName:"Rep") }
  motion.replace(hidden,now:now);assert(motion.count==0)
  print("PASS: 50 members, detail budgets, selected/local priority, bounded extrapolation, stale/hidden states, permission clearing")
 }
}

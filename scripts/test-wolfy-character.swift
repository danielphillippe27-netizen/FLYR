import Foundation
@main struct WolfyCharacterTests {
 static func main() throws {
  assert(WolfyProgression.level(xp:0)==1)
  assert(WolfyProgression.level(xp:8100)==10)
  assert(WolfyProgression.rank(level:25)=="Territory Wolf")
  assert(WolfyProgression.rank(level:50)=="Alpha")
  assert(WolfyProgression.level(xp:980100)==100)
  assert(WolfyProgression.growthStage(xp:-1)==1)
  for (index,level) in WolfyProgression.growthLevels.enumerated() {
   let threshold=WolfyProgression.floorXP(level:level)
   assert(WolfyProgression.growthStage(xp:threshold)==index+1)
   if index>0 { assert(WolfyProgression.growthStage(xp:threshold-1)==index) }
  }
  assert(WolfyProgression.growthStage(xp:2_000_000)==5)
  var machine=WolfyCharacterStateMachine();let now=Date(timeIntervalSince1970:1000)
  assert(machine.request(.rank,eventID:"rank",now:now))
  assert(!machine.request(.play,now:now))
  assert(!machine.request(.neutral,now:now))
  assert(!machine.request(.rank,eventID:"rank",now:now.addingTimeInterval(5)))
  assert(machine.request(.focused,now:now.addingTimeInterval(5)))
  let rest=WolfyMood.resolve(hour:22,workStart:9,workEnd:18,dnd:false,active:false,doors:0,target:100,overdue:4,happiness:75)
  assert(rest.state == .resting && rest.happiness==75)
  let night=WolfyMood.resolve(hour:23,workStart:20,workEnd:4,dnd:false,active:true,doors:10,target:100,overdue:0,happiness:75)
  assert(night.state == .focused)
  let concern=WolfyMood.resolve(hour:10,workStart:9,workEnd:18,dnd:false,active:false,doors:100,target:100,overdue:2,happiness:75)
  assert(concern.state == .concerned)
  let unknown=WolfyMood.resolve(hour:10,workStart:9,workEnd:18,dnd:false,active:false,doors:nil,target:nil,overdue:nil,happiness:60)
  assert(unknown.health==nil)
  let data=try Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[1]))
  let manifest=try JSONDecoder().decode(WolfyAssetManifest.self,from:data)
  assert(manifest.compatibility=="wolfy-v1" && manifest.animations.count==28)
  assert(Set(manifest.animations.map(\.name)).count==28)
  print("PASS: level/rank, animation priority/deduplication, rest/overnight hours, mood, missing metrics and manifest decoding")
 }
}

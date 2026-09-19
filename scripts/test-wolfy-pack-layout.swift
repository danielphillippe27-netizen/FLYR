import Foundation
@main struct WolfyPackLayoutTests {
 static func main() {
  let ids=(0..<50).map{_ in UUID()}
  let stacked=ids.map{WolfyPackLayoutV2.Point(id:$0,x:100,y:100)}
  let pack=WolfyPackLayoutV2(points:stacked,local:ids[0],selected:nil,zoom:18,constrained:false)
  assert(pack.individuals == [ids[0]])
  assert(pack.groups.count == 1 && pack.groups[0].members.count == 49)
  assert(hypot(pack.groups[0].x-100,pack.groups[0].y-100)>=76)
  let spread=ids.enumerated().map{WolfyPackLayoutV2.Point(id:$0.element,x:Double($0.offset%10)*80,y:Double($0.offset/10)*80)}
  let close=WolfyPackLayoutV2(points:spread,local:ids[0],selected:ids[49],zoom:22,constrained:false)
  assert(close.individuals.count==8 && close.individuals.contains(ids[49]))
  let represented=close.individuals+close.groups.flatMap(\.members)
  assert(represented.count==50 && Set(represented)==Set(ids),"Every rep represented exactly once")
  let wide=WolfyPackLayoutV2(points:spread,local:ids[0],selected:nil,zoom:17,constrained:false)
  assert(wide.groups.count < close.groups.count,"Zooming out groups nearby reps")
  let lowPower=WolfyPackLayoutV2(points:spread,local:nil,selected:nil,zoom:22,constrained:true)
  assert(lowPower.individuals.count==5)
  let empty=WolfyPackLayoutV2(points:[],local:nil,selected:nil,zoom:22,constrained:false)
  assert(empty.groups.isEmpty && empty.individuals.isEmpty)
  print("PASS: stacking, 8/5 avatar budgets, selection, zoom grouping, no missing/duplicate reps, cleared visibility")
 }
}

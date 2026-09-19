import CoreLocation
@main struct Tests {
 static func main() {
  var coordinates:[String:CLLocation]=[:]
  let door=CLLocationCoordinate2D(latitude:43.9,longitude:-78.7)
  assert(SessionAutoCompleteCoordinatePolicy.merge(targetIDs:["DOOR-1"],incoming:["door-1":door,"foreign":door],into:&coordinates))
  assert(coordinates.count==1 && coordinates["door-1"] != nil,"Restore must repopulate saved targets only")
  assert(CLLocation(latitude:door.latitude,longitude:door.longitude).distance(from:coordinates["door-1"]!)<15,"Restored door must be reachable by proximity check")
  assert(!SessionAutoCompleteCoordinatePolicy.merge(targetIDs:["DOOR-1"],incoming:["door-1":door],into:&coordinates),"Repeated map updates must not restart dwell")
  assert(!SessionAutoCompleteCoordinatePolicy.merge(targetIDs:["bad"],incoming:["bad":.init(latitude:100,longitude:0)],into:&coordinates))
  assert(!SessionAutoCompleteCoordinatePolicy.merge(targetIDs:[],incoming:["other":door],into:&coordinates))
  print("PASS: restored coordinates, normalized IDs, nearby-door distance, repeat updates, invalid fixes and target isolation")
 }
}

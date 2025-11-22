import SwiftUI

struct GoalsCreateView: View {
  @StateObject private var vm = UseGoalsCreate()
  var body: some View {
    Form {
      Section("Goal") {
        TextField("Name", text: $vm.name)
        Picker("Type", selection: $vm.type) {
          Text("Flyers Delivered").tag("flyers")
          Text("Doors Knocked").tag("doorknock")
          Text("Conversations").tag("conversations")
          Text("Leads").tag("leads")
        }
        Stepper("Target: \(vm.target)", value: $vm.target, in: 1...10000, step: 50)
        DatePicker("Due", selection: $vm.dueDate, displayedComponents: .date)
      }
      Section {
        Button(vm.isSaving ? "Saving…" : "Create Goal") { Task { await vm.create() } }
          .disabled(vm.name.isEmpty || vm.isSaving)
      }
    }
    .navigationTitle("New Goal")
  }
}








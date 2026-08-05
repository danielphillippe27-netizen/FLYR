import SwiftUI

struct FarmCreateView: View {
  @StateObject private var vm = UseFarmCreate()
  var body: some View {
    Form {
      Section("Farm") {
        TextField("Name", text: $vm.name)
        TextField("Area (seed address or label)", text: $vm.areaLabel)
        Picker("Frequency", selection: $vm.frequency) {
          ForEach([7,14,30,60], id: \.self) { d in Text("Every \(d) days").tag(d) }
        }
      }
      Section("Phases") {
        Toggle("Include Flyer", isOn: $vm.includeFlyer)
        Toggle("Include Door Knock", isOn: $vm.includeDoorKnock)
        Toggle("Include Pop-By", isOn: $vm.includePopBy)
        Toggle("Include Survey", isOn: $vm.includeSurvey)
      }
      Section {
        Button(vm.isSaving ? "Saving…" : "Create Farm") { Task { await vm.create() } }
          .disabled(vm.isSaving || vm.name.isEmpty)
      }
    }
    .navigationTitle("New Farm")
  }
}








#!/usr/bin/env ruby

require "xcodeproj"

project_path = File.expand_path("../WolfGrid.xcodeproj", __dir__)
project = Xcodeproj::Project.open(project_path)

source_target = project.targets.find { |target| target.name == "WolfGrid" }
abort("WolfGrid target not found") unless source_target
sales_app_path = File.expand_path("../WolfGridSales/App", __dir__)
abort("WolfGridSales/App source copy not found") unless Dir.exist?(sales_app_path)

if project.targets.any? { |target| target.name == "WolfGrid Sales" }
  puts("WolfGrid Sales target already exists")
  exit(0)
end

sales_group = project.main_group.find_subpath("WolfGridSales", true)
sales_group.set_source_tree("<group>")
sales_group.new_file("WolfGridSales-Info.plist") unless sales_group.files.any? { |file| file.path == "WolfGridSales-Info.plist" }
sales_group.new_file("WolfGridSales.entitlements") unless sales_group.files.any? { |file| file.path == "WolfGridSales.entitlements" }

sales_source_group = project.new(Xcodeproj::Project::Object::PBXFileSystemSynchronizedRootGroup)
sales_source_group.name = "WolfGridSalesApp"
sales_source_group.path = "WolfGridSales/App"
sales_source_group.source_tree = "<group>"
project.main_group.children << sales_source_group

sales_target = project.new_target(
  :application,
  "WolfGrid Sales",
  :ios,
  "17.0",
  project.products_group,
  :swift,
  "WolfGridSales"
)

sales_target.file_system_synchronized_groups << sales_source_group

source_target.package_product_dependencies.each do |product_dependency|
  sales_target.package_product_dependencies << product_dependency
  build_file = project.new(Xcodeproj::Project::Object::PBXBuildFile)
  build_file.product_ref = product_dependency
  sales_target.frameworks_build_phase.files << build_file
end

source_target.build_configurations.each do |source_configuration|
  sales_configuration = sales_target.build_configurations.find do |configuration|
    configuration.name == source_configuration.name
  end
  next unless sales_configuration

  sales_configuration.base_configuration_reference = source_configuration.base_configuration_reference
  sales_configuration.build_settings.clear
  source_configuration.build_settings.each do |key, value|
    sales_configuration.build_settings[key] = value.is_a?(Array) ? value.dup : value
  end

  sales_configuration.build_settings["CODE_SIGN_ENTITLEMENTS"] = "WolfGridSales/WolfGridSales.entitlements"
  sales_configuration.build_settings["CURRENT_PROJECT_VERSION"] = "1"
  sales_configuration.build_settings["INFOPLIST_FILE"] = "WolfGridSales/WolfGridSales-Info.plist"
  sales_configuration.build_settings["MARKETING_VERSION"] = "1.0"
  sales_configuration.build_settings["PRODUCT_BUNDLE_IDENTIFIER"] = "com.danielphillippe.wolfgrid.sales"
  sales_configuration.build_settings["PRODUCT_NAME"] = "WolfGridSales"
  sales_configuration.build_settings["SWIFT_ACTIVE_COMPILATION_CONDITIONS"] = "WOLFGRID_SALES $(inherited)"
  sales_configuration.build_settings["TARGETED_DEVICE_FAMILY"] = "1"
end

project.root_object.attributes["TargetAttributes"][sales_target.uuid] = {
  "CreatedOnToolsVersion" => "26.0.1"
}

project.save

scheme = Xcodeproj::XCScheme.new
scheme.configure_with_targets(sales_target, nil, launch_target: true)
scheme.save_as(project_path, "WolfGrid Sales", true)

puts("Created WolfGrid Sales target and shared scheme")

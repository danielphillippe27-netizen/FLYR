require 'xcodeproj'
require 'fileutils'
base=ENV.fetch('SALES_IOS_TEST_DIR','/tmp/wolfgrid-sales-ios-validation')
FileUtils.mkdir_p(base)
%w[Host.swift FlowTests.swift].each { |f| FileUtils.cp(File.join(__dir__,f),File.join(base,f)) }
root=File.expand_path('../../..',__dir__)
project=Xcodeproj::Project.new("#{base}/SalesAcceptance.xcodeproj")
app=project.new_target(:application,'SalesAcceptance',:ios,'17.0')
app.build_configurations.each do |c|
 c.build_settings['PRODUCT_BUNDLE_IDENTIFIER']='local.wolfgrid.SalesAcceptance'
 c.build_settings['GENERATE_INFOPLIST_FILE']='YES'
 c.build_settings['INFOPLIST_KEY_NSAppTransportSecurity_NSAllowsArbitraryLoads']='YES'
 c.build_settings['INFOPLIST_KEY_UILaunchScreen_Generation']='YES'
 c.build_settings['SWIFT_VERSION']='5.0'
 c.build_settings['TARGETED_DEVICE_FAMILY']='1'
end
files=Dir[File.join(root,'WolfGrid/Features/FieldSales/*.swift')]+["#{base}/Host.swift"]
files.each{|path|app.source_build_phase.add_file_reference(project.main_group.new_file(path))}
pkg=project.new(Xcodeproj::Project::Object::XCLocalSwiftPackageReference)
pkg.relative_path=ENV.fetch('SUPABASE_SWIFT_CHECKOUT','/tmp/wolfgrid-sales-derived/SourcePackages/checkouts/supabase-swift')
project.root_object.package_references<<pkg
product=project.new(Xcodeproj::Project::Object::XCSwiftPackageProductDependency)
product.package=pkg;product.product_name='Supabase';app.package_product_dependencies<<product
build=project.new(Xcodeproj::Project::Object::PBXBuildFile);build.product_ref=product;app.frameworks_build_phase.files<<build
ui=project.new_target(:ui_test_bundle,'SalesFlowTests',:ios,'17.0')
ui.add_dependency(app)
ui.source_build_phase.add_file_reference(project.main_group.new_file("#{base}/FlowTests.swift"))
ui.build_configurations.each do |c|
 c.build_settings['PRODUCT_BUNDLE_IDENTIFIER']='local.wolfgrid.SalesFlowTests'
 c.build_settings['GENERATE_INFOPLIST_FILE']='YES'
 c.build_settings['SWIFT_VERSION']='5.0'
 c.build_settings['TEST_TARGET_NAME']='SalesAcceptance'
end
scheme=Xcodeproj::XCScheme.new;scheme.add_build_target(app);scheme.add_test_target(ui);scheme.set_launch_target(app);scheme.save_as(project.path,'SalesAcceptance')
project.save

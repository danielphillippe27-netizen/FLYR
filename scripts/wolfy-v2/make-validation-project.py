"""Build an isolated synthetic-map harness; excludes main-app code and business data."""
from pathlib import Path
import plistlib, re, shutil
root = Path(__file__).resolve().parents[2]
out = Path('/tmp/wolfy-pack-validation')
sources = out/'Sources'
sources.mkdir(parents=True, exist_ok=True)
for name in ('WolfyCompanionPolicy.swift','WolfyPackMotion.swift','WolfyMapPrototype.swift','WolfyPackRenderer.swift','WolfyPackMapView.swift'):
    shutil.copy2(root/'WolfGrid/Features/WolfyV2'/name, sources/name)
map_manager = (root/'WolfGrid/Config/MapboxManager.swift').read_text()
a=map_manager.index('final class DisplayLinkRecoveringMapView:'); b=map_manager.index('\nenum CampaignOfflineMapError',a)
(sources/'MapViewSupport.swift').write_text('import UIKit\nimport MapboxMaps\n'+map_manager[a:b])
shutil.copytree(root/'WolfGrid/Resources/WolfyV2', sources/'WolfyV2',dirs_exist_ok=True)
(sources/'ValidationApp.swift').write_text(r'''import SwiftUI
import MapboxMaps
@main struct WolfyValidationApp: App {
 init() { MapboxOptions.accessToken = Bundle.main.object(forInfoDictionaryKey:"MBXAccessToken") as? String ?? "" }
 @Environment(\.scenePhase) private var phase
 var body: some Scene { WindowGroup { WolfyPackPrototypeEntryView()
  .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
  .onChange(of: phase) { _, value in UIApplication.shared.isIdleTimerDisabled = value == .active }
 } }
}
''')
config=(root/'Config.local.xcconfig').read_text()
token=re.search(r'^\s*MAPBOX_ACCESS_TOKEN\s*=\s*(.*?)\s*$',config,re.M)
if not token: raise SystemExit('Mapbox token setting unavailable; no project generated')
(out/'Validation.xcconfig').write_text('MAPBOX_ACCESS_TOKEN = '+token.group(1)+'\n')
with (out/'Validation-Info.plist').open('wb') as f:
 plistlib.dump({'CFBundleIdentifier':'$(PRODUCT_BUNDLE_IDENTIFIER)','CFBundleExecutable':'$(EXECUTABLE_NAME)',
  'CFBundleName':'WolfyValidation','CFBundlePackageType':'APPL','CFBundleVersion':'1','CFBundleShortVersionString':'0.1',
  'MBXAccessToken':'$(MAPBOX_ACCESS_TOKEN)','LSRequiresIPhoneOS':True,'UILaunchScreen':{},
  'UIApplicationSceneManifest':{'UIApplicationSupportsMultipleScenes':False}},f)
objects={}
def obj(isa,**values):
    key=f'{len(objects)+1:024X}';objects[key]={'isa':isa,**values};return key
product=obj('PBXFileReference',explicitFileType='wrapper.application',path='WolfyValidation.app',sourceTree='BUILT_PRODUCTS_DIR')
sourcegroup=obj('PBXFileSystemSynchronizedRootGroup',path='Sources',sourceTree='<group>')
configfile=obj('PBXFileReference',lastKnownFileType='text.xcconfig',path='Validation.xcconfig',sourceTree='<group>')
products=obj('PBXGroup',children=[product],name='Products',sourceTree='<group>')
group=obj('PBXGroup',children=[sourcegroup,configfile,products],sourceTree='<group>')
package=obj('XCRemoteSwiftPackageReference',repositoryURL='https://github.com/mapbox/mapbox-maps-ios.git',requirement={'kind':'exactVersion','version':'11.25.0'})
dependency=obj('XCSwiftPackageProductDependency',package=package,productName='MapboxMaps')
buildfile=obj('PBXBuildFile',productRef=dependency)
frameworks=obj('PBXFrameworksBuildPhase',buildActionMask=2147483647,files=[buildfile],runOnlyForDeploymentPostprocessing=0)
compilephase=obj('PBXSourcesBuildPhase',buildActionMask=2147483647,files=[],runOnlyForDeploymentPostprocessing=0)
resourcephase=obj('PBXResourcesBuildPhase',buildActionMask=2147483647,files=[],runOnlyForDeploymentPostprocessing=0)
settings={'PRODUCT_BUNDLE_IDENTIFIER':'com.danielphillippe.WolfyPackValidation','PRODUCT_NAME':'WolfyValidation',
 'DEVELOPMENT_TEAM':'2AR5T8ZYAS','CODE_SIGN_STYLE':'Automatic','SWIFT_VERSION':'5.0','IPHONEOS_DEPLOYMENT_TARGET':'17.0',
 'LD_RUNPATH_SEARCH_PATHS':['$(inherited)','@executable_path/Frameworks'],'SDKROOT':'iphoneos','SUPPORTED_PLATFORMS':'iphoneos iphonesimulator','TARGETED_DEVICE_FAMILY':'1',
 'GENERATE_INFOPLIST_FILE':'NO','INFOPLIST_FILE':'Validation-Info.plist',
 'INFOPLIST_KEY_UILaunchScreen_Generation':'YES','INFOPLIST_KEY_UIApplicationSceneManifest_Generation':'YES',
 'SWIFT_ACTIVE_COMPILATION_CONDITIONS':'DEBUG','SWIFT_OPTIMIZATION_LEVEL':'-O','CURRENT_PROJECT_VERSION':'1','MARKETING_VERSION':'0.1'}
targetconfig=obj('XCBuildConfiguration',name='Debug',baseConfigurationReference=configfile,buildSettings=settings)
targetconfigs=obj('XCConfigurationList',buildConfigurations=[targetconfig],defaultConfigurationIsVisible=0,defaultConfigurationName='Debug')
target=obj('PBXNativeTarget',name='WolfyValidation',productName='WolfyValidation',productReference=product,
 productType='com.apple.product-type.application',buildConfigurationList=targetconfigs,buildPhases=[compilephase,frameworks,resourcephase],
 buildRules=[],dependencies=[],fileSystemSynchronizedGroups=[sourcegroup],packageProductDependencies=[dependency])
projectconfig=obj('XCBuildConfiguration',name='Debug',buildSettings={'CLANG_ENABLE_MODULES':'YES'})
projectconfigs=obj('XCConfigurationList',buildConfigurations=[projectconfig],defaultConfigurationIsVisible=0,defaultConfigurationName='Debug')
project=obj('PBXProject',attributes={'LastUpgradeCheck':'2600'},buildConfigurationList=projectconfigs,compatibilityVersion='Xcode 16.0',
 developmentRegion='en',knownRegions=['en','Base'],mainGroup=group,productRefGroup=products,projectDirPath='',projectRoot='',targets=[target],packageReferences=[package])
projectdir=out/'WolfyValidation.xcodeproj';projectdir.mkdir(exist_ok=True)
with (projectdir/'project.pbxproj').open('wb') as f:
 plistlib.dump({'archiveVersion':'1','classes':{},'objectVersion':'77','objects':objects,'rootObject':project},f)
resolved=projectdir/'project.xcworkspace/xcshareddata/swiftpm/Package.resolved';resolved.parent.mkdir(parents=True,exist_ok=True)
shutil.copy2(root/'WolfGrid.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved',resolved)
print('Generated isolated validation project at',projectdir)

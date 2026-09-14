#!/usr/bin/env python3
"""Generate a small Xcode project without installing project generators."""
import hashlib
import pathlib

root = pathlib.Path(__file__).resolve().parent.parent
project = root / 'NGAReader.xcodeproj'
project.mkdir(exist_ok=True)

def uid(name): return hashlib.sha1(name.encode()).hexdigest()[:24].upper()
def quote(value): return '"' + str(value).replace('\\', '\\\\').replace('"', '\\"') + '"'
objects = []
def obj(name, text):
    objects.append(f'{uid(name)} = {{ {text} }};')
    return uid(name)
files = sorted((root / 'App').glob('*.swift'))
refs, builds = [], []
for file in files:
    ref = obj('ref:' + file.name, f'isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {quote(file.name)}; sourceTree = "<group>";')
    refs.append(ref)
    builds.append(obj('build:' + file.name, f'isa = PBXBuildFile; fileRef = {ref};'))
resource_refs, resource_builds = [], []
resource_files = list((root / 'App' / 'Resources').glob('*.png'))
resource_files += list((root / 'App').glob('*.xcassets'))
resource_files += list((root / 'App').glob('*.storyboard'))
for file in sorted(resource_files):
    relative = file.relative_to(root / 'App')
    file_type = 'folder.assetcatalog' if file.suffix == '.xcassets' else ('file.storyboard' if file.suffix == '.storyboard' else 'image.png')
    ref = obj('ref:' + str(relative), f'isa = PBXFileReference; lastKnownFileType = {file_type}; path = {quote(relative)}; sourceTree = "<group>";')
    resource_refs.append(ref)
    resource_builds.append(obj('build:' + str(relative), f'isa = PBXBuildFile; fileRef = {ref};'))
appgroup = obj('App', f'isa = PBXGroup; children = ({",".join(refs + resource_refs)}); path = App; sourceTree = "<group>";')
product = obj('product', 'isa = PBXFileReference; explicitFileType = wrapper.application; path = NGAReader.app; sourceTree = BUILT_PRODUCTS_DIR;')
products = obj('products', f'isa = PBXGroup; children = ({product}); name = Products; sourceTree = "<group>";')
group = obj('root', f'isa = PBXGroup; children = ({appgroup},{products}); sourceTree = "<group>";')
package = obj('package', 'isa = XCLocalSwiftPackageReference; relativePath = .;')
dependency = obj('dependency', f'isa = XCSwiftPackageProductDependency; package = {package}; productName = NGAKit;')
framework = obj('framework', f'isa = PBXBuildFile; productRef = {dependency};')
sources = obj('sources', f'isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = ({",".join(builds)}); runOnlyForDeploymentPostprocessing = 0;')
frameworks = obj('frameworks', f'isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = ({framework}); runOnlyForDeploymentPostprocessing = 0;')
resources = obj('resources', f'isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = ({",".join(resource_builds)}); runOnlyForDeploymentPostprocessing = 0;')
common = {
    'SWIFT_VERSION': '6.0', 'IPHONEOS_DEPLOYMENT_TARGET': '17.0', 'SDKROOT': 'iphoneos',
    'CLANG_ENABLE_MODULES': 'YES', 'ENABLE_USER_SCRIPT_SANDBOXING': 'YES',
    'GCC_C_LANGUAGE_STANDARD': 'gnu17', 'SWIFT_STRICT_CONCURRENCY': 'complete',
}
app = {
    'PRODUCT_NAME': 'NGAReader', 'PRODUCT_BUNDLE_IDENTIFIER': 'com.kizmz.ngareader.prototype',
    'GENERATE_INFOPLIST_FILE': 'YES', 'INFOPLIST_KEY_CFBundleDisplayName': 'NGA Orbit',
    'INFOPLIST_KEY_UILaunchStoryboardName': 'LaunchScreen',
    'ASSETCATALOG_COMPILER_APPICON_NAME': 'AppIcon',
    'INFOPLIST_KEY_UIApplicationSceneManifest_Generation': 'YES',
    'INFOPLIST_KEY_UISupportedInterfaceOrientations': 'UIInterfaceOrientationPortrait UIInterfaceOrientationPortraitUpsideDown UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight',
    'TARGETED_DEVICE_FAMILY': '1,2', 'CODE_SIGN_STYLE': 'Automatic',
    'CURRENT_PROJECT_VERSION': '1', 'MARKETING_VERSION': '0.1.0',
    'SUPPORTED_PLATFORMS': 'iphoneos iphonesimulator', 'SUPPORTS_MACCATALYST': 'NO',
}
def settings(values): return ' '.join(f'{key} = {quote(value)};' for key, value in values.items())
for name, values in [('Project', common), ('App', app)]:
    configs = []
    for mode in ['Debug', 'Release']:
        extra = {'SWIFT_OPTIMIZATION_LEVEL': '-Onone' if mode == 'Debug' else '-O'}
        if mode == 'Debug': extra['SWIFT_ACTIVE_COMPILATION_CONDITIONS'] = 'DEBUG'
        configs.append(obj(name + mode, f'isa = XCBuildConfiguration; buildSettings = {{ {settings(values | extra)} }}; name = {mode};'))
    obj(name + 'Config', f'isa = XCConfigurationList; buildConfigurations = ({",".join(configs)}); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
target = obj('target', f'isa = PBXNativeTarget; buildConfigurationList = {uid("AppConfig")}; buildPhases = ({sources},{frameworks},{resources}); buildRules = (); dependencies = (); name = NGAReader; packageProductDependencies = ({dependency}); productName = NGAReader; productReference = {product}; productType = "com.apple.product-type.application";')
root_id = obj('project', f'isa = PBXProject; attributes = {{ LastUpgradeCheck = 2700; }}; buildConfigurationList = {uid("ProjectConfig")}; compatibilityVersion = "Xcode 14.0"; developmentRegion = "zh-Hans"; hasScannedForEncodings = 0; knownRegions = (en, Base, "zh-Hans"); mainGroup = {group}; packageReferences = ({package}); productRefGroup = {products}; projectDirPath = ""; projectRoot = ""; targets = ({target});')
(project / 'project.pbxproj').write_text('// !$*UTF8*$!\n{ archiveVersion = 1; classes = {}; objectVersion = 56; objects = {\n' + '\n'.join(objects) + f'\n}}; rootObject = {root_id}; }}\n')
schemes = project / 'xcshareddata' / 'xcschemes'
schemes.mkdir(parents=True, exist_ok=True)
reference = f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="NGAReader.app" BlueprintName="NGAReader" ReferencedContainer="container:NGAReader.xcodeproj"/>'
(schemes / 'NGAReader.xcscheme').write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2700" version="1.3">
<BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{reference}</BuildActionEntry></BuildActionEntries></BuildAction>
<TestAction buildConfiguration="Debug"/>
<LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{reference}</BuildableProductRunnable></LaunchAction>
<ProfileAction buildConfiguration="Release"><BuildableProductRunnable runnableDebuggingMode="0">{reference}</BuildableProductRunnable></ProfileAction>
<AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>''')
print('Generated NGAReader.xcodeproj')

#!/usr/bin/env python3
"""Regenerate the dependency-free Xcode project after adding Swift files."""
from pathlib import Path
import hashlib

root = Path(__file__).resolve().parents[1]
def uid(value):
    return hashlib.sha1(value.encode()).hexdigest()[:24].upper()

def generate():
    project, group, products, target, app = [uid(x) for x in ['project', 'root', 'products', 'target', 'app']]
    sources, frameworks, resources = [uid(x) for x in ['sources', 'frameworks', 'resources']]
    pconfigs, tconfigs = uid('pconfigs'), uid('tconfigs')
    rows = []
    def obj(key, value):
        rows.append(f'\t\t{key} = {{ {value} }};')
    paths = sorted(root.glob('MarvinApp/**/*.swift'))
    file_ids, build_ids = [], []
    for path in paths:
        rel = path.relative_to(root).as_posix()
        fid, bid = uid(rel), uid('build:' + rel)
        file_ids.append(fid); build_ids.append(bid)
        obj(fid, f'isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = "{rel}"; sourceTree = "<group>";')
        obj(bid, f'isa = PBXBuildFile; fileRef = {fid};')
    obj(app, 'isa = PBXFileReference; explicitFileType = wrapper.application; path = Marvin.app; sourceTree = BUILT_PRODUCTS_DIR;')
    obj(group, f'isa = PBXGroup; children = ({",".join(file_ids + [products])},); sourceTree = "<group>";')
    obj(products, f'isa = PBXGroup; children = ({app},); name = Products; sourceTree = "<group>";')
    obj(sources, f'isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = ({",".join(build_ids)},); runOnlyForDeploymentPostprocessing = 0;')
    for key, isa in [(frameworks, 'PBXFrameworksBuildPhase'), (resources, 'PBXResourcesBuildPhase')]:
        obj(key, f'isa = {isa}; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;')
    obj(target, f'isa = PBXNativeTarget; buildConfigurationList = {tconfigs}; buildPhases = ({sources},{frameworks},{resources},); buildRules = (); dependencies = (); name = Marvin; productName = Marvin; productReference = {app}; productType = "com.apple.product-type.application";')
    obj(project, f'isa = PBXProject; attributes = {{ BuildIndependentTargetsInParallel = YES; LastSwiftUpdateCheck = 1600; LastUpgradeCheck = 1600; }}; buildConfigurationList = {pconfigs}; compatibilityVersion = "Xcode 14.0"; developmentRegion = en; hasScannedForEncodings = 0; knownRegions = (en, Base,); mainGroup = {group}; productRefGroup = {products}; projectDirPath = ""; projectRoot = ""; targets = ({target},);')
    for owner, config_list in [('project', pconfigs), ('target', tconfigs)]:
        ids = []
        for mode in ['Debug', 'Release']:
            key = uid(owner + mode); ids.append(key)
            if owner == 'project':
                settings = 'CLANG_ENABLE_MODULES = YES; CLANG_ENABLE_OBJC_ARC = YES; SDKROOT = iphoneos; IPHONEOS_DEPLOYMENT_TARGET = 17.0; SWIFT_VERSION = 5.0;'
                settings += ' SWIFT_OPTIMIZATION_LEVEL = "-Onone"; DEBUG_INFORMATION_FORMAT = dwarf; ENABLE_TESTABILITY = YES;' if mode == 'Debug' else ' SWIFT_COMPILATION_MODE = wholemodule; SWIFT_OPTIMIZATION_LEVEL = "-O"; DEBUG_INFORMATION_FORMAT = "dwarf-with-dsym";'
            else:
                settings = 'CODE_SIGN_STYLE = Automatic; CURRENT_PROJECT_VERSION = 1; GENERATE_INFOPLIST_FILE = NO; INFOPLIST_FILE = MarvinApp/Resources/Info.plist; MARKETING_VERSION = 1.0; PRODUCT_BUNDLE_IDENTIFIER = com.mitch.marvin; PRODUCT_NAME = "$(TARGET_NAME)"; SUPPORTED_PLATFORMS = "iphoneos iphonesimulator"; SUPPORTS_MACCATALYST = NO; TARGETED_DEVICE_FAMILY = 1; SWIFT_EMIT_LOC_STRINGS = YES; LD_RUNPATH_SEARCH_PATHS = "$(inherited) @executable_path/Frameworks";'
            obj(key, f'isa = XCBuildConfiguration; buildSettings = {{ {settings} }}; name = {mode};')
        obj(config_list, f'isa = XCConfigurationList; buildConfigurations = ({",".join(ids)},); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
    (root/'Marvin.xcodeproj/project.pbxproj').write_text('// !$*UTF8*$!\n{\n\tarchiveVersion = 1;\n\tclasses = {};\n\tobjectVersion = 56;\n\tobjects = {\n' + '\n'.join(rows) + '\n\t};\n\trootObject = ' + project + ';\n}\n')
    reference = f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="Marvin.app" BlueprintName="Marvin" ReferencedContainer="container:Marvin.xcodeproj"/>'
    (root/'Marvin.xcodeproj/xcshareddata/xcschemes/Marvin.xcscheme').write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1600" version="1.3">
<BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{reference}</BuildActionEntry></BuildActionEntries></BuildAction>
<LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{reference}</BuildableProductRunnable></LaunchAction>
<ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{reference}</BuildableProductRunnable></ProfileAction>
<AnalyzeAction buildConfiguration="Debug"/>
<ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>
''')
    print(f'Generated Marvin.xcodeproj with {len(paths)} Swift files.')

if __name__ == '__main__':
    generate()

#!/usr/bin/env python3
"""Generate the dependency-free Xcode project. Requires Python 3, not XcodeGen."""
import hashlib, json
import xml.etree.ElementTree as ET
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
objects = {}
def ident(key): return hashlib.sha1(key.encode()).hexdigest()[:24].upper()
def add(key, isa, **fields):
    uid = ident(key); objects[uid] = dict(isa=isa, **fields); return uid
def q(value, depth=0):
    indent = '\t' * depth
    child_indent = indent + '\t'
    if isinstance(value, dict):
        if not value: return '{}'
        fields = '\n'.join(f'{child_indent}{q(k)} = {q(v, depth+1)};' for k,v in value.items())
        return '{\n' + fields + '\n' + indent + '}'
    if isinstance(value, list):
        if not value: return '()'
        fields = '\n'.join(f'{child_indent}{q(x, depth+1)},' for x in value)
        return '(\n' + fields + '\n' + indent + ')'
    return json.dumps(str(value))
config = add('config', 'PBXFileReference', lastKnownFileType='text.xcconfig', path='Config/App.xcconfig', sourceTree='<group>')
products=[]; groups=[]; targets=[]
def target(name, product_type, ext, folders, settings):
    product=add(name+'product','PBXFileReference',explicitFileType=product_type,path=name+'.'+ext,sourceTree='BUILT_PRODUCTS_DIR'); products.append(product)
    sync=[]
    for folder in folders:
        gid=add(folder,'PBXFileSystemSynchronizedRootGroup',explicitFileTypes={},explicitFolders=[],path=folder,sourceTree='<group>'); groups.append(gid); sync.append(gid)
    source=add(name+'sources','PBXSourcesBuildPhase',buildActionMask=2147483647,files=[],runOnlyForDeploymentPostprocessing=0)
    resource=add(name+'resources','PBXResourcesBuildPhase',buildActionMask=2147483647,files=[],runOnlyForDeploymentPostprocessing=0)
    framework=add(name+'frameworks','PBXFrameworksBuildPhase',buildActionMask=2147483647,files=[],runOnlyForDeploymentPostprocessing=0)
    configs=[]
    for mode in ['Debug','Release']:
        configs.append(add(name+mode,'XCBuildConfiguration',baseConfigurationReference=config,buildSettings={
          'SDKROOT':'iphoneos','SUPPORTED_PLATFORMS':'iphoneos iphonesimulator','PRODUCT_NAME':name,
          'SWIFT_OPTIMIZATION_LEVEL':'-Onone' if mode=='Debug' else '-O',
          'SWIFT_ACTIVE_COMPILATION_CONDITIONS':'DEBUG' if mode=='Debug' else '',
          'ENABLE_TESTABILITY':'YES' if mode=='Debug' else 'NO',
          'ONLY_ACTIVE_ARCH':'YES' if mode=='Debug' else 'NO', **settings},name=mode))
    cl=add(name+'configs','XCConfigurationList',buildConfigurations=configs,defaultConfigurationIsVisible=0,defaultConfigurationName='Release')
    tid=add(name,'PBXNativeTarget',buildConfigurationList=cl,buildPhases=[source,framework,resource],buildRules=[],dependencies=[],fileSystemSynchronizedGroups=sync,name=name,productName=name,productReference=product,productType='com.apple.product-type.'+('application' if ext=='app' else 'app-extension' if ext=='appex' else 'bundle.ui-testing' if name=='linkinUITests' else 'bundle.unit-test'))
    targets.append(tid); return tid
app=target('linkin','wrapper.application','app',['App','Sources/LinkinCore'],{'INFOPLIST_FILE':'Config/App-Info.plist','CODE_SIGN_ENTITLEMENTS':'Config/App.entitlements','ASSETCATALOG_COMPILER_APPICON_NAME':'AppIcon','ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME':'AccentColor'})
objects[app]['fileSystemSynchronizedGroups'].reverse()
unit=target('linkinTests','wrapper.cfbundle','xctest',['Tests/LinkinCoreTests'],{'GENERATE_INFOPLIST_FILE':'YES','PRODUCT_BUNDLE_IDENTIFIER':'$(LINKIN_BUNDLE_ID).tests','TEST_HOST':'$(BUILT_PRODUCTS_DIR)/linkin.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/linkin','BUNDLE_LOADER':'$(TEST_HOST)'})
ui=target('linkinUITests','wrapper.cfbundle','xctest',['UITests'],{'GENERATE_INFOPLIST_FILE':'YES','PRODUCT_BUNDLE_IDENTIFIER':'$(LINKIN_BUNDLE_ID).uitests','TEST_TARGET_NAME':'linkin'})
def dependency(a,b):
    proxy=add(a+b+'proxy','PBXContainerItemProxy',containerPortal=ident('project'),proxyType=1,remoteGlobalIDString=b,remoteInfo=objects[b]['name'])
    dep=add(a+b+'dependency','PBXTargetDependency',target=b,targetProxy=proxy); objects[a]['dependencies'].append(dep)
dependency(unit,app); dependency(ui,app)
if (ROOT/'ShareExtension/ShareViewController.swift').exists():
    extension=target('linkinShare','wrapper.app-extension','appex',['ShareExtension'],{'INFOPLIST_FILE':'Config/Share-Info.plist','CODE_SIGN_ENTITLEMENTS':'Config/Share.entitlements','PRODUCT_BUNDLE_IDENTIFIER':'$(LINKIN_BUNDLE_ID).share','APPLICATION_EXTENSION_API_ONLY':'YES','SKIP_INSTALL':'YES'})
    objects[extension]['fileSystemSynchronizedGroups'].append(ident('Sources/LinkinCore'))
    # Apple service sources are shared explicitly with the extension.
    for file in ['Configuration.swift','CloudRepository.swift','RecordCodec.swift','AttachmentReader.swift']:
        path='App/Services/'+file
        if (ROOT/path).exists():
            ref=add('extensionref'+file,'PBXFileReference',lastKnownFileType='sourcecode.swift',path=path,sourceTree='<group>'); groups.append(ref)
            build=add('extensionbuild'+file,'PBXBuildFile',fileRef=ref); objects[ident('linkinSharesources')]['files'].append(build)
    dependency(app,extension)
    embed=add('embedextension','PBXBuildFile',fileRef=ident('linkinShareproduct'),settings={'ATTRIBUTES':['RemoveHeadersOnCopy']})
    phase=add('embed','PBXCopyFilesBuildPhase',buildActionMask=2147483647,dstPath='',dstSubfolderSpec=13,files=[embed],name='Embed Foundation Extensions',runOnlyForDeploymentPostprocessing=0); objects[app]['buildPhases'].append(phase)
productgroup=add('products','PBXGroup',children=products,name='Products',sourceTree='<group>')
main=add('main','PBXGroup',children=list(dict.fromkeys(groups))+[config,productgroup],sourceTree='<group>')
projectconfigs=[]
# Keep Xcode's recommended shared settings here so regeneration preserves them.
# Personal signing settings belong in the ignored Config/Local.xcconfig.
recommended = dict.fromkeys([
    'CLANG_WARN_BLOCK_CAPTURE_AUTORELEASING', 'CLANG_WARN_BOOL_CONVERSION',
    'CLANG_WARN_COMMA', 'CLANG_WARN_CONSTANT_CONVERSION',
    'CLANG_WARN_DEPRECATED_OBJC_IMPLEMENTATIONS', 'CLANG_WARN_EMPTY_BODY',
    'CLANG_WARN_ENUM_CONVERSION', 'CLANG_WARN_INFINITE_RECURSION',
    'CLANG_WARN_INT_CONVERSION', 'CLANG_WARN_NON_LITERAL_NULL_CONVERSION',
    'CLANG_WARN_OBJC_IMPLICIT_RETAIN_SELF', 'CLANG_WARN_OBJC_LITERAL_CONVERSION',
    'CLANG_WARN_QUOTED_INCLUDE_IN_FRAMEWORK_HEADER', 'CLANG_WARN_RANGE_LOOP_ANALYSIS',
    'CLANG_WARN_STRICT_PROTOTYPES', 'CLANG_WARN_SUSPICIOUS_MOVE',
    'CLANG_WARN_UNREACHABLE_CODE', 'CLANG_WARN__DUPLICATE_METHOD_MATCH',
    'DEAD_CODE_STRIPPING', 'ENABLE_STRICT_OBJC_MSGSEND',
    'ENABLE_USER_SCRIPT_SANDBOXING', 'GCC_NO_COMMON_BLOCKS',
    'GCC_WARN_64_TO_32_BIT_CONVERSION', 'GCC_WARN_ABOUT_RETURN_TYPE',
    'GCC_WARN_UNDECLARED_SELECTOR', 'GCC_WARN_UNINITIALIZED_AUTOS',
    'GCC_WARN_UNUSED_FUNCTION', 'GCC_WARN_UNUSED_VARIABLE',
    'STRING_CATALOG_GENERATE_SYMBOLS',
], 'YES')
for mode in ['Debug','Release']:
    mode_settings = {'ENABLE_TESTABILITY':'YES','ONLY_ACTIVE_ARCH':'YES'} if mode=='Debug' else {'SWIFT_COMPILATION_MODE':'wholemodule'}
    projectconfigs.append(add('project'+mode,'XCBuildConfiguration',buildSettings={'CLANG_ENABLE_MODULES':'YES','CLANG_ENABLE_OBJC_ARC':'YES','SWIFT_VERSION':'6.0','SWIFT_STRICT_CONCURRENCY':'complete','IPHONEOS_DEPLOYMENT_TARGET':'17.0','DEBUG_INFORMATION_FORMAT':'dwarf' if mode=='Debug' else 'dwarf-with-dsym',**recommended,**mode_settings},name=mode))
pc=add('projectconfigs','XCConfigurationList',buildConfigurations=projectconfigs,defaultConfigurationIsVisible=0,defaultConfigurationName='Release')
project=add('project','PBXProject',attributes={'BuildIndependentTargetsInParallel':'YES','LastUpgradeCheck':'2660'},buildConfigurationList=pc,compatibilityVersion='Xcode 16.0',developmentRegion='en',hasScannedForEncodings=0,knownRegions=['en','Base'],mainGroup=main,productRefGroup=productgroup,projectDirPath='',projectRoot='',targets=targets)
folder=ROOT/'linkin.xcodeproj'; folder.mkdir(exist_ok=True)
(folder/'project.pbxproj').write_text('// !$*UTF8*$!\n'+q({'archiveVersion':1,'classes':{},'objectVersion':71,'objects':objects,'rootObject':project})+'\n')
def reference(t):
    name=objects[t]['name']; suffix='app' if t==app else 'xctest'
    return f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{t}" BuildableName="{name}.{suffix}" BlueprintName="{name}" ReferencedContainer="container:linkin.xcodeproj"/>'
scheme=f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2660" version="1.3">
<BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{reference(app)}</BuildActionEntry></BuildActionEntries></BuildAction>
<TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.DebuggerFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables><TestableReference skipped="NO">{reference(unit)}</TestableReference><TestableReference skipped="NO">{reference(ui)}</TestableReference></Testables></TestAction>
<LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.DebuggerFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{reference(app)}</BuildableProductRunnable></LaunchAction>
<ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{reference(app)}</BuildableProductRunnable></ProfileAction><AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>'''
schemefolder=folder/'xcshareddata/xcschemes'; schemefolder.mkdir(parents=True,exist_ok=True)
scheme_xml = ET.fromstring(scheme)
ET.indent(scheme_xml, space='   ')
(schemefolder/'linkin.xcscheme').write_text('<?xml version="1.0" encoding="UTF-8"?>\n'+ET.tostring(scheme_xml, encoding='unicode')+'\n')
print('Generated linkin.xcodeproj')

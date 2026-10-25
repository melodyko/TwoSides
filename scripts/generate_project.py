#!/usr/bin/env python3
"""Regenerate the dependency-free iOS Xcode project from local Swift files."""

from __future__ import annotations

import hashlib
import re
from pathlib import Path
import xml.etree.ElementTree as ET


ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT / "TwoSides.xcodeproj"
DEPLOYMENT_TARGET = "27.0"
objects: dict[str, dict] = {}


def identifier(key: str) -> str:
    return hashlib.sha1(key.encode("utf-8")).hexdigest()[:24].upper()


def add(key: str, isa: str, **values) -> str:
    object_id = identifier(key)
    objects[object_id] = {"isa": isa, **values}
    return object_id


def serialize(value, level: int = 0) -> str:
    indent = "\t" * level
    if isinstance(value, dict):
        lines = ["{"]
        for key, child in value.items():
            lines.append(f"{indent}\t{serialize(key)} = {serialize(child, level + 1)};")
        return "\n".join(lines) + f"\n{indent}}}"
    if isinstance(value, list):
        if not value:
            return "()"
        return "(\n" + "".join(
            f"{indent}\t{serialize(child, level + 1)},\n" for child in value
        ) + f"{indent})"
    text = str(value)
    if re.fullmatch(r"[A-Za-z0-9_./]+", text):
        return text
    return '"' + text.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n") + '"'


def reference(path: Path, file_type: str) -> str:
    relative = path.relative_to(ROOT).as_posix()
    return add(
        f"file:{relative}", "PBXFileReference", lastKnownFileType=file_type,
        name=path.name, path=relative, sourceTree="SOURCE_ROOT",
    )


def build_file(reference_id: str, target: str) -> str:
    return add(f"build:{target}:{reference_id}", "PBXBuildFile", fileRef=reference_id)


def phase(key: str, isa: str, files: list[str]) -> str:
    return add(key, isa, buildActionMask=2147483647, files=files, runOnlyForDeploymentPostprocessing=0)


def configuration_list(key: str, common: dict, debug: dict | None = None, release: dict | None = None) -> str:
    configurations = []
    for name, overrides in (("Debug", debug or {}), ("Release", release or {})):
        configurations.append(add(
            f"config:{key}:{name}", "XCBuildConfiguration", name=name,
            buildSettings={**common, **overrides},
        ))
    return add(
        f"config-list:{key}", "XCConfigurationList", buildConfigurations=configurations,
        defaultConfigurationIsVisible=0, defaultConfigurationName="Release",
    )


source_groups = []
app_sources = []
for folder in ("App", "Core", "Camera"):
    references = []
    for path in sorted((ROOT / "Sources" / folder).rglob("*.swift")):
        ref = reference(path, "sourcecode.swift")
        references.append(ref)
        app_sources.append(build_file(ref, "app"))
    source_groups.append(add(f"group:{folder}", "PBXGroup", name=folder, children=references, sourceTree="<group>"))
sources_group = add("group:Sources", "PBXGroup", name="Sources", children=source_groups, sourceTree="<group>")

resource_references = [reference(ROOT / "Resources" / "Info.plist", "text.plist.xml")]
app_resources = []
assets = ROOT / "Resources" / "Assets.xcassets"
if assets.exists():
    assets_reference = reference(assets, "folder.assetcatalog")
    resource_references.append(assets_reference)
    app_resources.append(build_file(assets_reference, "app"))
for name in ("ExpandedWords.tsv", "WordSources.txt"):
    resource_path = ROOT / "Sources" / "Core" / "Resources" / name
    if not resource_path.is_file():
        raise SystemExit(f"Required word-bank resource is missing: {resource_path}")
    resource_reference = reference(resource_path, "text")
    resource_references.append(resource_reference)
    app_resources.append(build_file(resource_reference, "app"))
resources_group = add("group:Resources", "PBXGroup", name="Resources", children=resource_references, sourceTree="<group>")

project_id = identifier("project")
app_target_id = identifier("target:app")
app_product = add("product:app", "PBXFileReference", explicitFileType="wrapper.application", includeInIndex=0, path="TwoSides.app", sourceTree="BUILT_PRODUCTS_DIR")

project_configurations = configuration_list("project", {
    "ALWAYS_SEARCH_USER_PATHS": "NO",
    "CLANG_ENABLE_MODULES": "YES",
    "CLANG_ENABLE_OBJC_ARC": "YES",
    "CLANG_WARN_DOCUMENTATION_COMMENTS": "YES",
    "CLANG_WARN_QUOTED_INCLUDE_IN_FRAMEWORK_HEADER": "YES",
    "GCC_C_LANGUAGE_STANDARD": "gnu17",
    "GCC_WARN_64_TO_32_BIT_CONVERSION": "YES",
    "GCC_WARN_ABOUT_RETURN_TYPE": "YES_ERROR",
    "GCC_WARN_UNINITIALIZED_AUTOS": "YES_AGGRESSIVE",
    "GCC_WARN_UNUSED_FUNCTION": "YES",
    "GCC_WARN_UNUSED_VARIABLE": "YES",
    "IPHONEOS_DEPLOYMENT_TARGET": DEPLOYMENT_TARGET,
    "SDKROOT": "iphoneos",
    "SWIFT_STRICT_CONCURRENCY": "complete",
    "SWIFT_VERSION": "6.0",
}, {
    "DEBUG_INFORMATION_FORMAT": "dwarf",
    "ENABLE_TESTABILITY": "YES",
    "GCC_OPTIMIZATION_LEVEL": "0",
    "GCC_PREPROCESSOR_DEFINITIONS": ["DEBUG=1", "$(inherited)"],
    "ONLY_ACTIVE_ARCH": "YES",
    "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "$(inherited) DEBUG",
    "SWIFT_OPTIMIZATION_LEVEL": "-Onone",
}, {
    "DEBUG_INFORMATION_FORMAT": "dwarf-with-dsym",
    "SWIFT_COMPILATION_MODE": "wholemodule",
    "SWIFT_OPTIMIZATION_LEVEL": "-O",
    "VALIDATE_PRODUCT": "YES",
})

app_settings = {
    "CODE_SIGN_STYLE": "Automatic",
    "CURRENT_PROJECT_VERSION": "1",
    "ENABLE_PREVIEWS": "YES",
    "GENERATE_INFOPLIST_FILE": "NO",
    "INFOPLIST_FILE": "Resources/Info.plist",
    "IPHONEOS_DEPLOYMENT_TARGET": DEPLOYMENT_TARGET,
    "LD_RUNPATH_SEARCH_PATHS": ["$(inherited)", "@executable_path/Frameworks"],
    "MARKETING_VERSION": "1.0",
    "PRODUCT_BUNDLE_IDENTIFIER": "com.uncle.twosides",
    "PRODUCT_NAME": "$(TARGET_NAME)",
    "SUPPORTED_PLATFORMS": "iphoneos iphonesimulator",
    "SUPPORTS_MACCATALYST": "NO",
    "SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD": "NO",
    "SWIFT_EMIT_LOC_STRINGS": "YES",
    "SWIFT_VERSION": "6.0",
    "TARGETED_DEVICE_FAMILY": "1,2",
}
if (assets / "AppIcon.appiconset").exists():
    app_settings["ASSETCATALOG_COMPILER_APPICON_NAME"] = "AppIcon"

add("target:app", "PBXNativeTarget",
    buildConfigurationList=configuration_list("app", app_settings),
    buildPhases=[
        phase("phase:app:sources", "PBXSourcesBuildPhase", app_sources),
        phase("phase:app:frameworks", "PBXFrameworksBuildPhase", []),
        phase("phase:app:resources", "PBXResourcesBuildPhase", app_resources),
    ],
    buildRules=[], dependencies=[], name="TwoSides", productName="TwoSides",
    productReference=app_product, productType="com.apple.product-type.application")

targets = [app_target_id]
products = [app_product]
root_children = [sources_group, resources_group]
target_attributes = {app_target_id: {"CreatedOnToolsVersion": "27.1", "ProvisioningStyle": "Automatic"}}
ui_test_paths = sorted((ROOT / "Tests" / "UITests").rglob("*.swift"))
ui_test_target_id = None
if ui_test_paths:
    test_references = [reference(path, "sourcecode.swift") for path in ui_test_paths]
    root_children.append(add("group:UITests", "PBXGroup", name="UITests", children=test_references, sourceTree="<group>"))
    test_product = add("product:uitests", "PBXFileReference", explicitFileType="wrapper.cfbundle", includeInIndex=0, path="TwoSidesUITests.xctest", sourceTree="BUILT_PRODUCTS_DIR")
    proxy = add("proxy:uitests-app", "PBXContainerItemProxy", containerPortal=project_id, proxyType=1, remoteGlobalIDString=app_target_id, remoteInfo="TwoSides")
    dependency = add("dependency:uitests-app", "PBXTargetDependency", target=app_target_id, targetProxy=proxy)
    ui_test_target_id = add("target:uitests", "PBXNativeTarget",
        buildConfigurationList=configuration_list("uitests", {
            "CODE_SIGN_STYLE": "Automatic",
            "CURRENT_PROJECT_VERSION": "1",
            "GENERATE_INFOPLIST_FILE": "YES",
            "IPHONEOS_DEPLOYMENT_TARGET": DEPLOYMENT_TARGET,
            "LD_RUNPATH_SEARCH_PATHS": ["$(inherited)", "@executable_path/Frameworks", "@loader_path/Frameworks"],
            "MARKETING_VERSION": "1.0",
            "PRODUCT_BUNDLE_IDENTIFIER": "com.uncle.twosides.uitests",
            "PRODUCT_NAME": "$(TARGET_NAME)",
            "SUPPORTED_PLATFORMS": "iphoneos iphonesimulator",
            "SWIFT_VERSION": "6.0",
            "TARGETED_DEVICE_FAMILY": "1,2",
            "TEST_TARGET_NAME": "TwoSides",
        }),
        buildPhases=[
            phase("phase:uitests:sources", "PBXSourcesBuildPhase", [build_file(ref, "uitests") for ref in test_references]),
            phase("phase:uitests:frameworks", "PBXFrameworksBuildPhase", []),
            phase("phase:uitests:resources", "PBXResourcesBuildPhase", []),
        ],
        buildRules=[], dependencies=[dependency], name="TwoSidesUITests", productName="TwoSidesUITests",
        productReference=test_product, productType="com.apple.product-type.bundle.ui-testing")
    targets.append(ui_test_target_id)
    products.append(test_product)
    target_attributes[ui_test_target_id] = {"CreatedOnToolsVersion": "27.1", "ProvisioningStyle": "Automatic", "TestTargetID": app_target_id}

products_group = add("group:Products", "PBXGroup", children=products, name="Products", sourceTree="<group>")
root_children.append(products_group)
main_group = add("group:main", "PBXGroup", children=root_children, sourceTree="<group>")
add("project", "PBXProject",
    attributes={"BuildIndependentTargetsInParallel": "YES", "LastUpgradeCheck": "2710", "TargetAttributes": target_attributes},
    buildConfigurationList=project_configurations, compatibilityVersion="Xcode 14.0",
    developmentRegion="zh-Hans", hasScannedForEncodings=0, knownRegions=["zh-Hans", "en", "Base"],
    mainGroup=main_group, productRefGroup=products_group, projectDirPath="", projectRoot="", targets=targets)

PROJECT.mkdir(parents=True, exist_ok=True)
project_contents = {"archiveVersion": "1", "classes": {}, "objectVersion": "56", "objects": objects, "rootObject": project_id}
(PROJECT / "project.pbxproj").write_text("// !$*UTF8*$!\n" + serialize(project_contents) + "\n", encoding="utf-8")


def buildable(parent, target_id: str, name: str, product: str):
    ET.SubElement(parent, "BuildableReference", BuildableIdentifier="primary", BlueprintIdentifier=target_id,
                  BuildableName=product, BlueprintName=name, ReferencedContainer="container:TwoSides.xcodeproj")


scheme = ET.Element("Scheme", LastUpgradeVersion="2710", version="1.3")
build_action = ET.SubElement(scheme, "BuildAction", parallelizeBuildables="YES", buildImplicitDependencies="YES")
entries = ET.SubElement(build_action, "BuildActionEntries")
entry = ET.SubElement(entries, "BuildActionEntry", buildForTesting="YES", buildForRunning="YES", buildForProfiling="YES", buildForArchiving="YES", buildForAnalyzing="YES")
buildable(entry, app_target_id, "TwoSides", "TwoSides.app")
if ui_test_target_id:
    test_entry = ET.SubElement(entries, "BuildActionEntry", buildForTesting="YES", buildForRunning="NO", buildForProfiling="NO", buildForArchiving="NO", buildForAnalyzing="YES")
    buildable(test_entry, ui_test_target_id, "TwoSidesUITests", "TwoSidesUITests.xctest")
test_action = ET.SubElement(scheme, "TestAction", buildConfiguration="Debug", selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB", selectedLauncherIdentifier="Xcode.DebuggerFoundation.Launcher.LLDB", shouldUseLaunchSchemeArgsEnv="YES")
testables = ET.SubElement(test_action, "Testables")
if ui_test_target_id:
    testable = ET.SubElement(testables, "TestableReference", skipped="NO", parallelizable="NO")
    buildable(testable, ui_test_target_id, "TwoSidesUITests", "TwoSidesUITests.xctest")
launch = ET.SubElement(scheme, "LaunchAction", buildConfiguration="Debug", selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB", selectedLauncherIdentifier="Xcode.DebuggerFoundation.Launcher.LLDB", launchStyle="0", useCustomWorkingDirectory="NO", ignoresPersistentStateOnLaunch="NO", debugDocumentVersioning="YES", debugServiceExtension="internal", allowLocationSimulation="YES")
buildable(ET.SubElement(launch, "BuildableProductRunnable", runnableDebuggingMode="0"), app_target_id, "TwoSides", "TwoSides.app")
profile = ET.SubElement(scheme, "ProfileAction", buildConfiguration="Release", shouldUseLaunchSchemeArgsEnv="YES", savedToolIdentifier="", useCustomWorkingDirectory="NO", debugDocumentVersioning="YES")
buildable(ET.SubElement(profile, "BuildableProductRunnable", runnableDebuggingMode="0"), app_target_id, "TwoSides", "TwoSides.app")
ET.SubElement(scheme, "AnalyzeAction", buildConfiguration="Debug")
ET.SubElement(scheme, "ArchiveAction", buildConfiguration="Release", revealArchiveInOrganizer="YES")
ET.indent(scheme, space="   ")
scheme_directory = PROJECT / "xcshareddata" / "xcschemes"
scheme_directory.mkdir(parents=True, exist_ok=True)
ET.ElementTree(scheme).write(scheme_directory / "TwoSides.xcscheme", encoding="UTF-8", xml_declaration=True)
print(f"Generated {PROJECT.name}: {len(app_sources)} app sources, {len(ui_test_paths)} UI test sources; iOS {DEPLOYMENT_TARGET}.")

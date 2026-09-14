#!/usr/bin/env python3
"""Build the complete app from source using an installed CellDock's resources.

This fallback works with CLT installations whose SwiftPM is incomplete. It does
not modify the toolchain. The resulting app is for the current CPU architecture.
"""
import argparse
import pathlib
import plistlib
import re
import shutil
import subprocess

ROOT = pathlib.Path(__file__).resolve().parents[1]


def run(args):
    subprocess.run([str(a) for a in args], check=True, cwd=ROOT)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--base-app', type=pathlib.Path, required=True)
    parser.add_argument('--identity', required=True, help='Certificate SHA1 in login Keychain')
    parser.add_argument('--swift-overlay', type=pathlib.Path)
    parser.add_argument('--library-validation-exception', action='store_true',
                        help='Required only for self-signed local certificates; opt in explicitly')
    args = parser.parse_args()
    if not re.fullmatch(r'[0-9A-Fa-f]{40}', args.identity):
        parser.error('identity must be a certificate SHA1 fingerprint')
    build = ROOT / '.build/codex-local'
    build.mkdir(parents=True, exist_ok=True)
    swift = ['swiftc', '-swift-version', '5', '-target',
             subprocess.check_output(['uname', '-m'], text=True).strip() + '-apple-macosx14.0']
    if args.swift_overlay:
        swift += ['-vfsoverlay', args.swift_overlay]
    includes = []
    objects = []
    for name, header in [('CModemBridge', 'CModemBridge.h'), ('CUACProbe', 'CUACProbe.h'), ('CEuiccCore', 'CEuiccCore.h')]:
        module = build / name
        module.mkdir(exist_ok=True)
        (module / 'module.modulemap').write_text(f'module {name} {{ header "{ROOT / "Sources" / name / "include" / header}" export * }}\n')
        includes += ['-I', module]
        for source in sorted((ROOT / 'Sources' / name).rglob('*.c')):
            # Match the maintained source list in Package.swift; exclude any
            # vendor examples or unused protocol implementations.
            if name == 'CEuiccCore' and str(source.relative_to(ROOT / 'Sources/CEuiccCore')) not in {
                'CellDockEUICCBridge.c', 'Vendor/lpac/cjson/cJSON.c', 'Vendor/lpac/cjson/cJSON_ex.c',
                *('Vendor/lpac/euicc/' + n + '.c' for n in ['base64','derutil','es8p','es9p','es9p_errors','es10a','es10b','es10c','es10c_ex','euicc','hexutil','interface','sha256','tostr'])
            }:
                continue
            obj = module / (source.stem + '.o')
            if not obj.exists() or source.stat().st_mtime > obj.stat().st_mtime:
                run(['clang', '-std=c11', '-O2', '-mmacosx-version-min=14.0', '-I', ROOT / 'Sources' / name / 'include',
                     '-I', ROOT / 'Sources/CEuiccCore/Vendor/lpac', '-c', source, '-o', obj])
            objects.append(obj)
    ipc = sorted((ROOT / 'Sources/CellDockNetworkIPC').glob('*.swift'))
    run(swift + ['-emit-library', '-static', '-emit-module', '-module-name', 'CellDockNetworkIPC',
                 '-emit-module-path', build / 'CellDockNetworkIPC.swiftmodule'] + ipc + ['-o', build / 'libCellDockNetworkIPC.a'])
    framework_dir = args.base_app / 'Contents/Frameworks'
    run(swift + ['-O', '-whole-module-optimization', '-D', 'CELLDOCK_LEGACY_GLASS_SDK', '-I', build, '-L', build, '-lCellDockNetworkIPC',
                 '-F', framework_dir, '-framework', 'Sparkle', '-framework', 'CoreAudio', '-framework', 'IOKit',
                 '-Xlinker', '-rpath', '-Xlinker', '@executable_path/../Frameworks'] + includes +
        sorted((ROOT / 'Sources/CellDock').glob('*.swift')) + objects + ['-o', build / 'CellDock'])
    output = ROOT / 'outputs/CellDock.app'
    output.parent.mkdir(exist_ok=True)
    if output.exists():
        shutil.rmtree(output)
    run(['ditto', args.base_app, output])
    shutil.copy2(build / 'CellDock', output / 'Contents/MacOS/CellDock')
    info = plistlib.loads((ROOT / 'Resources/Info.plist').read_bytes())
    info.update(CFBundleShortVersionString='0.4.4-codex', CFBundleVersion='111', CellDockCodexBridge=True,
                SUEnableAutomaticChecks=False, SUAutomaticallyUpdate=False)
    (output / 'Contents/Info.plist').write_bytes(plistlib.dumps(info))
    for localization in (ROOT / 'Resources/Localization').glob('*.lproj'):
        shutil.copytree(localization, output / 'Contents/Resources' / localization.name, dirs_exist_ok=True)
    shutil.copytree(ROOT / 'Resources/CallOpening', output / 'Contents/Resources/CallOpening', dirs_exist_ok=True)
    entitlements = plistlib.loads((ROOT / 'Resources/CellDock.entitlements').read_bytes())
    if args.library_validation_exception:
        entitlements['com.apple.security.cs.disable-library-validation'] = True
    entitlement_path = build / 'local.entitlements'
    entitlement_path.write_bytes(plistlib.dumps(entitlements))
    framework = output / 'Contents/Frameworks/Sparkle.framework'
    version = (framework / 'Versions/Current').resolve()
    components = [output / 'Contents/Library/PrivilegedHelperTools/CellDockVoWiFiRuntime',
                  version / 'XPCServices/Installer.xpc', version / 'XPCServices/Downloader.xpc',
                  version / 'Autoupdate', version / 'Updater.app', framework,
                  output / 'Contents/Library/PrivilegedHelperTools/CellDockNetworkHelper', output]
    for component in components:
        metadata = subprocess.run(['codesign', '-dv', str(component)], capture_output=True, text=True).stderr
        # swiftc embeds an ad-hoc identifier derived from the executable name.
        # It is not the application's bundle identifier or its helper identity.
        fixed_identifiers = {
            output: info['CFBundleIdentifier'],
            output / 'Contents/Library/PrivilegedHelperTools/CellDockNetworkHelper': 'app.celldock.mac.network.helper',
            output / 'Contents/Library/PrivilegedHelperTools/CellDockVoWiFiRuntime': 'app.celldock.mac.vowifi.runtime',
        }
        identifier = fixed_identifiers.get(component)
        if identifier is None:
            identifier = re.search(r'^Identifier=(.+)$', metadata, re.M).group(1)
        command = ['codesign', '--force', '--sign', args.identity, '--timestamp=none', '--options', 'runtime',
                   '--identifier', identifier, '--requirements',
                   f'=designated => identifier "{identifier}" and certificate leaf = H"{args.identity}"']
        if component == output:
            command += ['--entitlements', entitlement_path]
        elif component.name == 'Downloader.xpc':
            command += ['--preserve-metadata=entitlements']
        run(command + [component])
    run(['codesign', '--verify', '--deep', '--strict', output])
    for component, identifier in fixed_identifiers.items():
        run(['codesign', '--verify', '--strict', '--test-requirement',
             f'=identifier "{identifier}" and certificate leaf = H"{args.identity}"', component])
    print(output)


if __name__ == '__main__':
    main()

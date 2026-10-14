#!/usr/bin/env python3
"""Run the SAME authored boundary cases when CLT lacks the Swift Testing runtime.

Original Swift Testing sources are macro-expanded/type-checked first, then portable cases run.
Generated sources/binaries stay in .build. No mirrored test implementation is kept.
Full Xcode installations use swift test via script/test.sh.
"""
from pathlib import Path
import json, re, subprocess

root = Path(__file__).resolve().parent.parent
subprocess.run(['swift', 'build'], cwd=root, check=True)
binary_dir = Path(subprocess.check_output(['swift','build','--show-bin-path'], cwd=root, text=True).strip())
# Type-check the original macros before stripping them for runtime portability.
# Linking the incomplete CLT Testing runtime is unnecessary for this check.
developer = Path(subprocess.check_output(['xcode-select', '-p'], text=True).strip())
compiler = json.loads(subprocess.check_output(['swiftc', '-print-target-info'], text=True))
resources = Path(compiler['paths']['runtimeResourcePath'])
framework_candidates = [developer/'Library/Developer/Frameworks',
                        developer/'Platforms/MacOSX.platform/Developer/Library/Frameworks',
                        developer/'Library/Frameworks']
frameworks = next((p for p in framework_candidates if (p/'Testing.framework').is_dir()), None)
plugins = sorted((resources/'host/plugins').rglob('libTestingMacros.dylib'))
if frameworks is None or not plugins:
    raise SystemExit('Swift Testing framework/macro plugin unavailable. Install a complete Swift 6 toolchain or use full Xcode; original tests cannot be verified.')
original_tests = sorted((root/'Tests/UsageCoreTests').glob('*.swift'))
subprocess.run(['swiftc', '-typecheck', '-swift-version', '5', '-parse-as-library',
                '-module-name', 'UsageCoreTests', '-I', str(binary_dir/'Modules'),
                '-F', str(frameworks), '-load-plugin-library', str(plugins[0]),
                *map(str, original_tests)], cwd=root, check=True)
print('Original Swift Testing macros type-check successfully.', flush=True)

generated = root/'.build/portable-tests'; generated.mkdir(exist_ok=True)
sources=[]
for name in ['CoreTests.swift','RPCTests.swift','SecurityTests.swift','ProviderSecurityTests.swift','AntigravityTests.swift','FixtureServer.swift']:
    original = root/'Tests/UsageCoreTests'/name
    text=original.read_text().replace('import Testing\n','')
    text=re.sub(r'@Test(?:\(arguments: \[[^\]]*\]\))?\s*','',text)
    text=text.replace('#expect(', 'expect(').replace('#require(', 'requireValue(')
    if name in {'RPCTests.swift', 'ProviderSecurityTests.swift', 'AntigravityTests.swift'}:
        text=text.replace('#filePath', '"'+str(original)+'"')
    target=generated/name; target.write_text(text); sources.append(str(target))

support=generated/'Runner.swift'
support.write_text(r'''import Foundation
import Darwin

private var failureCount = 0
private let failureLock = NSLock()
func recordFailure(_ message: String) {
    failureLock.lock(); failureCount += 1; failureLock.unlock()
    fputs(message, stderr)
}
func expect(_ value: @autoclosure () throws -> Bool, file: String = #filePath, line: Int = #line) {
    do { if try !value() { recordFailure("FAIL \(file):\(line)\n") } }
    catch { recordFailure("Unexpected assertion error \(file):\(line)\n") }
}
func expect(throws type: (any Error).Type, _ work: () throws -> Void) {
    do { try work(); expect(false) } catch {}
}
func expect(throws type: (any Error).Type, _ work: () async throws -> Void) async {
    do { try await work(); expect(false) } catch {}
}
func requireValue<T>(_ value: T?) throws -> T {
    guard let value else { throw NSError(domain: "Tests", code: 1) }
    return value
}

@main struct Runner {
    static func main() async {
        setbuf(stdout, nil)
        let core=CoreTests(); let rpc=RPCTests(); let security=SecurityTests(); let providers=ProviderSecurityTests(); let antigravity=AntigravityTests()
        do {
            core.testCodexKeepsServerWindowDurationsAndMissingValuesUnknown()
            core.testPercentRejectsBooleansAndOutOfRange()
            core.testClaudeDoesNotConfuseSpendWithQuota()
            core.testGeminiUsesMostConstrainedBucketForEachModel()
            core.testMetadataUsesLastTurnRatherThanLifetimeUsage()
            core.testMissingContextIsNotZeroAndStaleReadingDoesNotRecommend()
            core.testCompactionRejectsSelectionRaceBusyAndUnverifiedSource()
            try core.testSnapshotRoundTripContainsNoCredentialFields()
            try await core.testUnixBridgeRoundTripAndSingleOwner()
            try core.testBridgeRejectsPublicDirectory()
            try await core.testScannerCachesAndRestrictsRecentDirectories()
            await rpc.rejectsRemoteEndpointWithoutConnecting()
            try security.encryptedStorageRejectsTamperingWrongKeyAndWrongFile()
            try security.migrationMinimizesChatDataAndPreservesPlaintextIfKeyFails()
            try security.privateFilesRejectSymlinksPublicPermissionsAndOversize()
            try security.bridgePrivacyRequiresExplicitChatAccess()
            try security.capturedTargetsExpireAndRejectFutureTimestamps()
            security.providerRedirectsNeverReceiveAuthorization()
            try providers.credentialsRejectUnsafeFilesWithoutChangingThem()
            providers.retryHeadersCannotCreateInfiniteOrUnboundedDelays()
            try antigravity.reportsOnlyMeasuredEnabledLimits()
            try antigravity.weeklyOnlyAndCamelCaseRemainDistinct()
            antigravity.cacheUpgradeAddsNewProviderWithoutRestoringUnverifiedAccount()
            // Match native Swift Testing's concurrent fixture execution, even on CLT-only Macs.
            try await withThrowingTaskGroup(of: Void.self) { group in
                for mode in ["after-ack", "before-ack", "busy"] {
                    group.addTask {
                        try await rpc.nativeCompactionRequiresMatchingCompletion(mode: mode)
                        print("RPC boundary checked: \(mode)")
                    }
                }
                for mode in ["small", "exact-limit", "declared-limit", "stream-limit", "redirect", "auth-error", "cancel"] {
                    group.addTask {
                        try await providers.streamedResponsesAreBoundedAndCancellable(mode: mode)
                        print("HTTP boundary checked: \(mode)")
                    }
                }
                for mode in ["success", "old", "signin", "bad-report", "environment"] {
                    group.addTask { try await antigravity.nativeReportUsesTheConfiguredExecutable(mode: mode) }
                }
                for mode in ["overflow", "timeout", "cancel", "group"] {
                    group.addTask { try await antigravity.subprocessLimitsCancellationAndGroupCleanup(mode: mode) }
                }
                try await group.waitForAll()
            }
        } catch { recordFailure("Unexpected test error: \(error)\n") }
        if failureCount > 0 { fputs("\(failureCount) failed assertions\n", stderr); exit(1) }
        print("42 boundary cases passed (portable runner; same authored tests).")
    }
}
''')
# Macro-free XCTest-independent harness uses the existing core object files.
objects=[str(p) for p in (binary_dir/'UsageCore.build').glob('*.o')]
executable=generated/'checks'
subprocess.run(['swiftc','-swift-version','5','-parse-as-library','-I',str(binary_dir/'Modules'),
                *sources,str(support),*objects,'-o',str(executable)], cwd=root, check=True)
subprocess.run([str(executable)], cwd=root, check=True, timeout=60)

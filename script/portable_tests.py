#!/usr/bin/env python3
"""Run the SAME authored boundary cases when CLT lacks the Swift Testing runtime.

Generated sources/binaries stay in .build. No mirrored test implementation is kept.
Full Xcode installations use swift test via script/test.sh.
"""
from pathlib import Path
import re, subprocess

root = Path(__file__).resolve().parent.parent
subprocess.run(['swift', 'build'], cwd=root, check=True)
binary_dir = Path(subprocess.check_output(['swift','build','--show-bin-path'], cwd=root, text=True).strip())
generated = root/'.build/portable-tests'; generated.mkdir(exist_ok=True)
sources=[]
for name in ['CoreTests.swift','RPCTests.swift','SecurityTests.swift','ProviderSecurityTests.swift']:
    original = root/'Tests/UsageCoreTests'/name
    text=original.read_text().replace('import Testing\n','')
    text=re.sub(r'@Test(?:\(arguments: \[[^\]]*\]\))?\s*','',text)
    text=text.replace('#expect(', 'expect(').replace('#require(', 'requireValue(')
    if name in {'RPCTests.swift', 'ProviderSecurityTests.swift'}:
        text=text.replace('#filePath', '"'+str(original)+'"')
    target=generated/name; target.write_text(text); sources.append(str(target))

support=generated/'Runner.swift'
support.write_text(r'''import Foundation
import Darwin

private var failureCount = 0
func expect(_ value: @autoclosure () throws -> Bool, file: String = #filePath, line: Int = #line) {
    do { if try !value() { failureCount += 1; fputs("FAIL \(file):\(line)\n", stderr) } }
    catch { failureCount += 1; fputs("Unexpected assertion error \(file):\(line)\n", stderr) }
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
        let core=CoreTests(); let rpc=RPCTests(); let security=SecurityTests(); let providers=ProviderSecurityTests()
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
            for mode in ["after-ack", "before-ack", "busy"] {
                try await rpc.nativeCompactionRequiresMatchingCompletion(mode: mode)
                print("RPC boundary checked: \(mode)")
            }
            await rpc.rejectsRemoteEndpointWithoutConnecting()
            try security.encryptedStorageRejectsTamperingWrongKeyAndWrongFile()
            try security.migrationMinimizesChatDataAndPreservesPlaintextIfKeyFails()
            try security.privateFilesRejectSymlinksPublicPermissionsAndOversize()
            try security.bridgePrivacyRequiresExplicitChatAccess()
            try security.capturedTargetsExpireAndRejectFutureTimestamps()
            security.providerRedirectsNeverReceiveAuthorization()
            try providers.credentialsRejectUnsafeFilesWithoutChangingThem()
            providers.retryHeadersCannotCreateInfiniteOrUnboundedDelays()
            for mode in ["small", "exact-limit", "declared-limit", "stream-limit", "redirect", "auth-error", "cancel"] {
                print("HTTP boundary starting: \(mode)")
                try await providers.streamedResponsesAreBoundedAndCancellable(mode: mode)
                print("HTTP boundary checked: \(mode)")
            }
        } catch { failureCount += 1; fputs("Unexpected test error: \(error)\n", stderr) }
        if failureCount > 0 { fputs("\(failureCount) failed assertions\n", stderr); exit(1) }
        print("30 boundary cases passed (portable runner; same authored tests).")
    }
}
''')
# Macro-free XCTest-independent harness uses the existing core object files.
objects=[str(p) for p in (binary_dir/'UsageCore.build').glob('*.o')]
executable=generated/'checks'
subprocess.run(['swiftc','-swift-version','5','-parse-as-library','-I',str(binary_dir/'Modules'),
                *sources,str(support),*objects,'-o',str(executable)], cwd=root, check=True)
subprocess.run([str(executable)], cwd=root, check=True, timeout=60)

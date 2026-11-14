// specs/initial_setup.fsl の各アクションを、実コードの InitialSetupFlow / InitialSetupDownloadGate の呼び出しに対応させる。
//
// InitialSetupViewModel / InitialSetupDownloads / ContentView が呼ぶのと同じ順で呼び、返ってきた書き込みを
// 偽の設定へ反映する。画面の開閉、権限・ファイル・Ollama、進行中のダウンロードの数は環境として Adapter が持つ。
// 完了した時点で録画できる設定がそろっていたか (okAtDone) は、MenuBarViewModel.canStartRecording と同じ条件で
// Adapter が偽の設定から独立に計算する。
import Foundation
@testable import SetupCore

final class InitialSetupAdapter: Adapter {
    private static let whisperModelID = "large-v3-turbo"
    private static let summaryModelID = "gemma4:e2b-it-qat"

    // 設定 (UserDefaults)
    private var savedStep = 0
    private var selectedWhisperModelID: String?
    private var selectedSummaryModelID: String?
    private var skipsSummary = false

    // 環境
    private var hasOutputDirectory = false
    private var hasScreenCapturePermission = false
    private var whisperFileExists = false
    private var ollamaReachable = false
    private var summaryModelExists = false
    private var whisperDownloads = 0
    private var summaryPulls = 0

    // 画面 (ViewModel) と、アプリで 1 つのダウンロード
    private var flow = InitialSetupAdapter.newFlow()
    private var isOpen = true
    private var gate = InitialSetupDownloadGate()

    // 履歴
    private var okAtDone = false
    private var bounced = false
    private var pickedWhileClosed = false

    init() {
        reset()
    }

    private static func newFlow() -> InitialSetupFlow {
        InitialSetupFlow(whisperModelID: whisperModelID, summaryModelID: summaryModelID)
    }

    func reset() {
        savedStep = 0
        selectedWhisperModelID = nil
        selectedSummaryModelID = nil
        skipsSummary = false
        hasOutputDirectory = false
        hasScreenCapturePermission = false
        whisperFileExists = false
        ollamaReachable = false
        summaryModelExists = false
        whisperDownloads = 0
        summaryPulls = 0
        flow = Self.newFlow()
        isOpen = true
        gate = InitialSetupDownloadGate()
        okAtDone = false
        bounced = false
        pickedWhileClosed = false
    }

    private var installedSummaryModelIDs: Set<String>? {
        ollamaReachable ? (summaryModelExists ? [Self.summaryModelID] : []) : nil
    }

    private var isScreenActive: Bool { isOpen && !flow.isFinished }

    private func write(_ effects: [InitialSetupEffect]) {
        for effect in effects {
            switch effect {
            case .saveStep(let step): savedStep = step.rawValue
            case .selectWhisperModel(let id): selectedWhisperModelID = id
            case .selectSummaryModel(let id): selectedSummaryModelID = id
            case .setSkipsSummary(let value): skipsSummary = value
            }
        }
    }

    func step(_ action: String, _ params: [String: Any]) -> StepResult? {
        switch action {
        case "env_remove_dir":
            hasOutputDirectory = false
        case "env_perm":
            hasScreenCapturePermission = params["v"] as! Bool
        case "env_wfile":
            whisperFileExists = params["v"] as! Bool
        case "env_ollama":
            ollamaReachable = params["v"] as! Bool
        case "env_smodel":
            summaryModelExists = params["v"] as! Bool

        case "set_dir":
            hasOutputDirectory = true
            flow.observeOutputDirectory(true)
        case "refresh_perm":
            flow.observeScreenCapturePermission(hasScreenCapturePermission)
        case "forward":
            write(flow.moveForward())
        case "back":
            write(flow.moveBack())
        case "skip_summary":
            write(flow.skipSummary())
        case "refresh_ollama":
            write(flow.observeSummaryModels(installedSummaryModelIDs))

        case "start_wdl":
            if gate.begin(.whisper) { whisperDownloads += 1 }
        case "finish_wdl":
            let ok = params["ok"] as! Bool
            whisperDownloads -= 1
            gate.end(.whisper)
            if ok {
                whisperFileExists = true
                write(InitialSetupFlow.whisperModelDownloaded(Self.whisperModelID))
                if !isOpen { pickedWhileClosed = true }
            }
            // 画面があれば、ダウンロードの終わりを待っていた ViewModel がファイルを読み直す
            if isScreenActive {
                write(flow.observeWhisperModel(installed: whisperFileExists))
            }
        case "start_sdl":
            if gate.begin(.summary) { summaryPulls += 1 }
        case "finish_sdl":
            let ok = params["ok"] as! Bool
            summaryPulls -= 1
            gate.end(.summary)
            if ok {
                summaryModelExists = true
                write(InitialSetupFlow.summaryModelPulled(Self.summaryModelID))
            }
            if isScreenActive {
                write(flow.observeSummaryModels(installedSummaryModelIDs))
            }

        case "close_window":
            flow = Self.newFlow()
            isOpen = false
        case "quit_app":
            flow = Self.newFlow()
            isOpen = false
            gate = InitialSetupDownloadGate()
            whisperDownloads = 0
            summaryPulls = 0
        case "reopen":
            // InitialSetupViewModel.load と同じ順
            flow = Self.newFlow()
            isOpen = true
            flow.restore(savedStepRawValue: savedStep)
            flow.observeOutputDirectory(hasOutputDirectory)
            flow.observeSkipsSummary(skipsSummary)
            flow.observeScreenCapturePermission(hasScreenCapturePermission)
            write(flow.observeWhisperModel(installed: whisperFileExists))
            write(flow.observeSummaryModels(installedSummaryModelIDs))
        case "complete":
            let snapshot = InitialSetupSnapshot(
                hasOutputDirectory: hasOutputDirectory,
                hasScreenCapturePermission: hasScreenCapturePermission,
                isWhisperModelInstalled: whisperFileExists,
                installedSummaryModelIDs: installedSummaryModelIDs,
                skipsSummary: skipsSummary
            )
            let wasFinished = flow.isFinished
            let effects = flow.complete(snapshot)
            write(effects)
            if wasFinished {
                // 完了済みなら何もしない (押せない操作の確認用)
            } else if flow.isFinished {
                // ContentView の onComplete
                savedStep = 0
                isOpen = false
                okAtDone = hasOutputDirectory
                    && hasScreenCapturePermission
                    && whisperFileExists
                    && selectedWhisperModelID == Self.whisperModelID
                    && (skipsSummary
                        || (selectedSummaryModelID == Self.summaryModelID && summaryModelExists))
            } else if !effects.isEmpty {
                // 欠けている手順へ戻すときは必ず手順を保存する。空なら完了の手順ではなかった
                bounced = true
            }
        default:
            fatalError("未知のアクション \(action)")
        }
        return nil
    }

    func observe() -> [String: Any] {
        [
            "step": flow.step.rawValue,
            "saved": savedStep,
            "done": flow.isFinished,
            "open": isOpen,
            "dir": hasOutputDirectory,
            "perm": hasScreenCapturePermission,
            "wFile": whisperFileExists,
            "oll": ollamaReachable,
            "sFile": summaryModelExists,
            "wSel": selectedWhisperModelID == Self.whisperModelID,
            "sSel": selectedSummaryModelID == Self.summaryModelID,
            "skip": skipsSummary,
            "cDir": flow.hasOutputDirectory,
            "cPerm": flow.hasScreenCapturePermission,
            "cW": flow.isWhisperModelInstalled,
            "cS": flow.isSummaryModelInstalled,
            "cSkip": flow.skipsSummary,
            "wdl": whisperDownloads,
            "sdl": summaryPulls,
            "okAtDone": okAtDone,
            "bounced": bounced,
            "pickedWhileClosed": pickedWhileClosed,
        ]
    }
}

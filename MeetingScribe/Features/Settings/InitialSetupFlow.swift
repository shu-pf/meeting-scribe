//
//  InitialSetupFlow.swift
//  MeetingScribe
//
//  初回セットアップの手順と、設定へ何を書くかの判断。
//  画面・権限・ファイル・Ollama・ダウンロードの Task は InitialSetupViewModel が持ち、
//  読み取った結果をここへ渡して、返ってきた書き込みを設定へ反映する。
//  specs/initial_setup.fsl が仕様で、specs/conformance の照合テストがこの型を直接動かす。
//

import Foundation

nonisolated enum InitialSetupStep: Int, CaseIterable, Sendable {
    case welcome
    case outputDirectory
    case permissions
    case transcriptionModel
    case summaryModel
    case complete

    var title: String {
        switch self {
        case .welcome: "ようこそ"
        case .outputDirectory: "保存先"
        case .permissions: "権限"
        case .transcriptionModel: "文字起こし"
        case .summaryModel: "要約"
        case .complete: "完了"
        }
    }

    var systemImage: String {
        switch self {
        case .welcome: "hand.wave"
        case .outputDirectory: "folder"
        case .permissions: "lock.shield"
        case .transcriptionModel: "waveform"
        case .summaryModel: "text.document"
        case .complete: "checkmark.circle"
        }
    }
}

/// 設定へ書き込む内容。返した順に反映する。
nonisolated enum InitialSetupEffect: Equatable, Sendable {
    case saveStep(InitialSetupStep)
    case selectWhisperModel(String)
    case selectSummaryModel(String)
    case setSkipsSummary(Bool)
}

/// 完了の操作のときに読み直す、その時点の設定と環境
nonisolated struct InitialSetupSnapshot: Equatable, Sendable {
    var hasOutputDirectory: Bool
    var hasScreenCapturePermission: Bool
    /// おすすめの Whisper モデルのファイルがある
    var isWhisperModelInstalled: Bool
    /// Ollama に入っているモデル。Ollama に接続できなければ nil
    var installedSummaryModelIDs: Set<String>?
    var skipsSummary: Bool
}

nonisolated struct InitialSetupFlow: Sendable {
    let whisperModelID: String
    let summaryModelID: String

    private(set) var step: InitialSetupStep = .welcome
    private(set) var hasOutputDirectory = false
    private(set) var hasScreenCapturePermission = false
    private(set) var isWhisperModelInstalled = false
    private(set) var isSummaryModelInstalled = false
    private(set) var skipsSummary = false
    private(set) var isFinished = false

    init(whisperModelID: String, summaryModelID: String) {
        self.whisperModelID = whisperModelID
        self.summaryModelID = summaryModelID
    }

    var canMoveForward: Bool {
        switch step {
        case .welcome: true
        case .outputDirectory: hasOutputDirectory
        case .permissions: hasScreenCapturePermission
        case .transcriptionModel: isWhisperModelInstalled
        case .summaryModel: isSummaryModelInstalled || skipsSummary
        case .complete: false
        }
    }

    /// 保存してある手順から再開する。前の手順の条件は、完了の操作で確かめ直す。
    mutating func restore(savedStepRawValue: Int) {
        step = InitialSetupStep(rawValue: savedStepRawValue) ?? .welcome
    }

    mutating func observeOutputDirectory(_ isSet: Bool) {
        hasOutputDirectory = isSet
    }

    mutating func observeScreenCapturePermission(_ granted: Bool) {
        hasScreenCapturePermission = granted
    }

    mutating func observeSkipsSummary(_ value: Bool) {
        skipsSummary = value
    }

    /// おすすめの Whisper モデルのファイルがあれば、それを選ぶ。
    /// ファイルだけ先にある (入れ直し、Debug 版と配布版でモデルの置き場所を共有) ときも選ばれるようにする。
    mutating func observeWhisperModel(installed: Bool) -> [InitialSetupEffect] {
        isWhisperModelInstalled = installed
        return installed ? [.selectWhisperModel(whisperModelID)] : []
    }

    /// おすすめの要約モデルが Ollama にあれば、それを選び、要約をオンに戻す。
    mutating func observeSummaryModels(_ installedIDs: Set<String>?) -> [InitialSetupEffect] {
        isSummaryModelInstalled = installedIDs?.contains(summaryModelID) ?? false
        guard isSummaryModelInstalled else { return [] }
        skipsSummary = false
        return [.selectSummaryModel(summaryModelID), .setSkipsSummary(false)]
    }

    mutating func moveForward() -> [InitialSetupEffect] {
        guard !isFinished, canMoveForward,
              let next = InitialSetupStep(rawValue: step.rawValue + 1) else {
            return []
        }
        step = next
        return [.saveStep(next)]
    }

    /// ダウンロード中の戻る操作は呼び出し側で止める
    mutating func moveBack() -> [InitialSetupEffect] {
        guard !isFinished,
              let previous = InitialSetupStep(rawValue: step.rawValue - 1) else {
            return []
        }
        step = previous
        return [.saveStep(previous)]
    }

    /// 要約モデルを用意せずに、文字起こしだけで使い始める
    mutating func skipSummary() -> [InitialSetupEffect] {
        guard !isFinished, step == .summaryModel, !isSummaryModelInstalled else {
            return []
        }
        skipsSummary = true
        step = .complete
        return [.setSkipsSummary(true), .saveStep(.complete)]
    }

    /// 完了の操作。その時点の設定と環境を読み直し、そろっていれば完了する。
    /// 欠けていれば完了せず、欠けている最初の手順へ戻す。
    mutating func complete(_ snapshot: InitialSetupSnapshot) -> [InitialSetupEffect] {
        guard !isFinished, step == .complete else { return [] }
        hasOutputDirectory = snapshot.hasOutputDirectory
        hasScreenCapturePermission = snapshot.hasScreenCapturePermission
        skipsSummary = snapshot.skipsSummary
        var effects = observeWhisperModel(installed: snapshot.isWhisperModelInstalled)
        effects += observeSummaryModels(snapshot.installedSummaryModelIDs)

        // モデルは、ファイルがあれば上の observe で選んでいる
        let missing: InitialSetupStep? =
            if !hasOutputDirectory { .outputDirectory }
            else if !hasScreenCapturePermission { .permissions }
            else if !isWhisperModelInstalled { .transcriptionModel }
            else if !(skipsSummary || isSummaryModelInstalled) { .summaryModel }
            else { nil }

        if let missing {
            step = missing
            effects.append(.saveStep(missing))
        } else {
            isFinished = true
        }
        return effects
    }

    /// Whisper モデルのダウンロードが終わったときの書き込み。画面が閉じていても反映する。
    static func whisperModelDownloaded(_ modelID: String) -> [InitialSetupEffect] {
        [.selectWhisperModel(modelID)]
    }

    /// 要約モデルの取得が終わったときの書き込み。画面が閉じていても反映し、要約をオンに戻す。
    static func summaryModelPulled(_ modelID: String) -> [InitialSetupEffect] {
        [.selectSummaryModel(modelID), .setSkipsSummary(false)]
    }
}

/// オンボーディングのダウンロードを、画面 (ViewModel) をまたいで 1 つずつに保つ。
/// 画面を閉じて開き直しても、進行中のダウンロードを 2 本目として始めない。
nonisolated struct InitialSetupDownloadGate: Sendable {
    enum Kind: Sendable { case whisper, summary }

    private(set) var isDownloadingWhisper = false
    private(set) var isDownloadingSummary = false

    var isDownloading: Bool { isDownloadingWhisper || isDownloadingSummary }

    func isDownloading(_ kind: Kind) -> Bool {
        switch kind {
        case .whisper: isDownloadingWhisper
        case .summary: isDownloadingSummary
        }
    }

    /// 始めてよければ true。同じ種類が進行中なら false。
    mutating func begin(_ kind: Kind) -> Bool {
        guard !isDownloading(kind) else { return false }
        switch kind {
        case .whisper: isDownloadingWhisper = true
        case .summary: isDownloadingSummary = true
        }
        return true
    }

    mutating func end(_ kind: Kind) {
        switch kind {
        case .whisper: isDownloadingWhisper = false
        case .summary: isDownloadingSummary = false
        }
    }
}

//
//  PipelineJobCoordinator.swift
//  MeetingScribe
//

import Foundation

/// 録画後ジョブとして調停できる記録。アプリでは `PersistedPipelineJob`、照合テストでは小さな構造体が使う。
nonisolated protocol PipelineJobRecord {
    associatedtype ID: Hashable
    var id: ID { get }
    var createdAt: Date { get }
    var state: PersistedPipelineJobState { get }
    mutating func transition(to state: PersistedPipelineJobState, detail: String?)
}

/// 録画後ジョブを起動・一時停止・再開してよいかを決める。
///
/// Swift の Task は持たず、実行 1 回分を Run ID で表す。呼び出し側は Run ID ごとに Task を持ち、
/// ここが返した Run だけを起動・キャンセルする。設計と検証は `specs/pipeline_jobs.fsl`。
/// - 同じジョブの Run は同時に 1 つまで（登録中のジョブは起動しない）
/// - スリープの前には、一時停止中でも毎回、登録中の Run をキャンセルして世代を進める
/// - 復帰処理は、渡された世代が今の世代と同じときだけ一時停止を解いて再開する
nonisolated struct PipelineJobCoordinator<Job: PipelineJobRecord> {
    typealias RunID = Int

    struct Run: Equatable {
        let jobID: Job.ID
        var isCancelled = false
        /// 新しいジョブの準備を終えてジョブを保存し、実行に入った
        var isPrepared: Bool
    }

    enum RunOutcome: Equatable {
        case succeeded(detail: String?)
        case failed(detail: String?)
    }

    struct SleepPreparation {
        /// キャンセルする Run。呼び出し側は対応する Task をキャンセルする
        var cancelledRuns: [RunID]
        /// 再開待ちに戻したジョブ。呼び出し側は保存し直す
        var waitingJobs: [Job]
    }

    private(set) var jobs: [Job.ID: Job] = [:]
    private(set) var runs: [RunID: Run] = [:]
    /// ジョブごとに登録中の Run。生きている Run は必ず登録されている
    private(set) var registrations: [Job.ID: RunID] = [:]
    private(set) var isPausedForSleep = false
    private(set) var sleepGeneration = 0
    private var nextRunID = 0

    init() {}

    /// 起動時に永続化から読み込んだジョブを入れる。
    mutating func restore(_ restored: [Job]) {
        jobs = Dictionary(uniqueKeysWithValues: restored.map { ($0.id, $0) })
    }

    /// 録画停止・要約のやり直しで新しいジョブを作るとき、準備用の Run を登録する。
    /// 一時停止中でも作り、実行するかは `jobPrepared` で決める。
    mutating func beginNewJob(id: Job.ID) -> RunID {
        precondition(jobs[id] == nil && registrations[id] == nil, "新しいジョブのIDが重複している")
        return addRun(Run(jobID: id, isPrepared: false))
    }

    /// 準備したジョブを再開待ちとして持つ。実行してよければ true を返す。
    /// キャンセル済みか一時停止中なら Run を終えて false を返し、ジョブは復帰後の再開を待つ。
    mutating func jobPrepared(_ job: Job, run runID: RunID) -> Bool {
        guard let run = runs[runID], !run.isPrepared, run.jobID == job.id else { return false }
        var waitingJob = job
        if waitingJob.state != .waiting {
            waitingJob.transition(to: .waiting, detail: nil)
        }
        jobs[job.id] = waitingJob
        if run.isCancelled || isPausedForSleep {
            endRun(runID)
            return false
        }
        runs[runID]?.isPrepared = true
        return true
    }

    /// 準備に失敗した。ジョブは保存されていない。
    mutating func preparationFailed(run runID: RunID) {
        guard let run = runs[runID], !run.isPrepared else { return }
        endRun(runID)
    }

    /// 進捗の通知でジョブの状態を上書きし、保存し直すジョブを返す。
    mutating func updateProgress(
        jobID: Job.ID,
        state: PersistedPipelineJobState
    ) -> Job? {
        guard jobs[jobID] != nil else { return nil }
        jobs[jobID]?.transition(to: state, detail: nil)
        return jobs[jobID]
    }

    /// 実行が終わった。失敗でもキャンセル済みなら再開待ちに戻す。保存し直すジョブを返す。
    mutating func runFinished(_ runID: RunID, outcome: RunOutcome) -> Job? {
        guard let run = runs[runID], run.isPrepared else { return nil }
        endRun(runID)
        guard jobs[run.jobID] != nil else { return nil }
        switch outcome {
        case .succeeded(let detail):
            jobs[run.jobID]?.transition(to: .completed, detail: detail)
        case .failed(let detail):
            if run.isCancelled {
                jobs[run.jobID]?.transition(to: .waiting, detail: nil)
            } else {
                jobs[run.jobID]?.transition(to: .failed, detail: detail)
            }
        }
        return jobs[run.jobID]
    }

    /// 失敗したジョブを再開待ちへ戻す。起動は保存のあとに `startPersistedJob` で行う。
    mutating func retry(id: Job.ID) -> Job? {
        guard jobs[id]?.state == .failed else { return nil }
        jobs[id]?.transition(to: .waiting, detail: nil)
        return jobs[id]
    }

    /// 再開待ちのジョブを起動する。一時停止中・登録中・再開待ち以外なら起動しない。
    mutating func startPersistedJob(id: Job.ID) -> RunID? {
        guard !isPausedForSleep,
              registrations[id] == nil,
              jobs[id]?.state == .waiting else {
            return nil
        }
        return addRun(Run(jobID: id, isPrepared: true))
    }

    /// willSleep を受けた。一時停止中でも毎回、登録中の Run をキャンセルし、ジョブを再開待ちに戻し、世代を進める。
    mutating func prepareForSleep() -> SleepPreparation {
        isPausedForSleep = true
        sleepGeneration += 1
        var preparation = SleepPreparation(cancelledRuns: [], waitingJobs: [])
        for (jobID, runID) in registrations {
            runs[runID]?.isCancelled = true
            preparation.cancelledRuns.append(runID)
            if jobs[jobID] != nil {
                jobs[jobID]?.transition(to: .waiting, detail: nil)
                if let job = jobs[jobID] {
                    preparation.waitingJobs.append(job)
                }
            }
        }
        return preparation
    }

    /// didWake を受けた。一時停止中なら、復帰処理に持たせる今の世代を返す。
    func wakeToken() -> Int? {
        isPausedForSleep ? sleepGeneration : nil
    }

    /// 復帰処理が終わりを待つ Run。
    func runsToAwait() -> [RunID] {
        Array(registrations.values)
    }

    /// 復帰処理が待ち終えた。世代が今と同じときだけ一時停止を解き、
    /// 再開待ちで未登録のジョブを作成順に起動する。起動したジョブと Run を返す。
    mutating func finishWake(token: Int) -> [(job: Job, run: RunID)] {
        guard isPausedForSleep, token == sleepGeneration else { return [] }
        isPausedForSleep = false
        let waitingJobs = jobs.values
            .filter { $0.state == .waiting }
            .sorted { $0.createdAt < $1.createdAt }
        return waitingJobs.compactMap { job in
            startPersistedJob(id: job.id).map { (job: job, run: $0) }
        }
    }

    private mutating func addRun(_ run: Run) -> RunID {
        let runID = nextRunID
        nextRunID += 1
        runs[runID] = run
        registrations[run.jobID] = runID
        return runID
    }

    private mutating func endRun(_ runID: RunID) {
        guard let run = runs.removeValue(forKey: runID) else { return }
        if registrations[run.jobID] == runID {
            registrations[run.jobID] = nil
        }
    }
}

extension PersistedPipelineJob: PipelineJobRecord {
    mutating func transition(to state: PersistedPipelineJobState, detail: String?) {
        self.state = state
        stateUpdatedAt = Date()
        self.detail = detail
    }
}

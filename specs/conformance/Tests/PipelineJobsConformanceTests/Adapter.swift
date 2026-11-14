// specs/pipeline_jobs.fsl の各アクションを、実コードの PipelineJobCoordinator の呼び出しに対応させる。
//
// MenuBarViewModel が Coordinator を呼ぶのと同じ順で呼ぶ。Swift の Task、スリープ・復帰の通知、
// 復帰処理が待つ Run の一覧は環境として Adapter が持つ (仕様の asleep / hs / retryPending と、
// Run の awaited0 / awaited1)。それ以外の状態は Coordinator から読み取る。
//
// 仕様の Slot (job * 2 + n) と Coordinator の Run ID の対応は Adapter が持つ。新しい Run は、
// そのジョブの 1 つ目の Slot が空いていればそこ、空いていなければ 2 つ目に置く (仕様と同じ規則)。
import Foundation
@testable import PipelineCore

struct TestJob: PipelineJobRecord {
    let id: Int
    let createdAt: Date
    var state: PersistedPipelineJobState
    var detail: String?

    mutating func transition(to state: PersistedPipelineJobState, detail: String?) {
        self.state = state
        self.detail = detail
    }
}

final class PipelineJobsAdapter: Adapter {
    private typealias Coordinator = PipelineJobCoordinator<TestJob>
    private enum Handler: String { case Idle, Pending, Awaiting }

    private static let jobCount = 2
    private static let slotCount = 4
    private static let handlerCount = 2

    private var coordinator = Coordinator()
    private var slotRuns: [Int: Coordinator.RunID] = [:]
    private var asleep = false
    private var handlers: [Handler] = []
    private var tokens: [Int?] = []
    /// 復帰処理ごとに、待っている Run ID
    private var awaitedRuns: [Set<Coordinator.RunID>] = []
    private var retryPending: [Bool] = []
    private var resumed: [Bool] = []

    init() {
        reset()
    }

    func reset() {
        coordinator = Coordinator()
        slotRuns = [:]
        asleep = false
        handlers = Array(repeating: .Idle, count: Self.handlerCount)
        tokens = Array(repeating: nil, count: Self.handlerCount)
        awaitedRuns = Array(repeating: [], count: Self.handlerCount)
        retryPending = Array(repeating: false, count: Self.jobCount)
        resumed = Array(repeating: false, count: Self.jobCount)
    }

    func step(_ action: String, _ params: [String: Any]) -> StepResult? {
        switch action {
        case "record":
            let j = params["j"] as! Int
            let runID = coordinator.beginNewJob(id: j)
            place(runID, job: j)
        case "prepare":
            let s = params["s"] as! Int
            let job = TestJob(
                id: s / 2,
                createdAt: Date(timeIntervalSinceReferenceDate: Double(s / 2)),
                state: .waiting
            )
            _ = coordinator.jobPrepared(job, run: slotRuns[s]!)
        case "prepare_failed":
            let s = params["s"] as! Int
            coordinator.preparationFailed(run: slotRuns[s]!)
        case "progress":
            let s = params["s"] as! Int
            let state: PersistedPipelineJobState = switch params["st"] as! String {
            case "Transcribing": .transcribing
            case "Summarizing": .summarizing
            case "Saving": .saving
            default: fatalError("progress の状態が想定外")
            }
            _ = coordinator.updateProgress(jobID: s / 2, state: state)
        case "finish":
            let s = params["s"] as! Int
            let ok = params["ok"] as! Bool
            _ = coordinator.runFinished(
                slotRuns[s]!,
                outcome: ok ? .succeeded(detail: "title") : .failed(detail: "error")
            )
        case "retry":
            let j = params["j"] as! Int
            if coordinator.retry(id: j) != nil {
                retryPending[j] = true
            }
        case "retry_start":
            let j = params["j"] as! Int
            retryPending[j] = false
            if let runID = coordinator.startPersistedJob(id: j) {
                place(runID, job: j)
            }
        case "os_sleep":
            asleep = true
            _ = coordinator.prepareForSleep()
        case "os_wake":
            asleep = false
            if let token = coordinator.wakeToken(),
               let w = handlers.firstIndex(of: .Idle) {
                handlers[w] = .Pending
                tokens[w] = token
            }
        case "wake_snap":
            let w = params["w"] as! Int
            handlers[w] = .Awaiting
            awaitedRuns[w] = Set(coordinator.runsToAwait())
        case "wake_finish":
            let w = params["w"] as! Int
            let started = coordinator.finishWake(token: tokens[w]!)
            handlers[w] = .Idle
            tokens[w] = nil
            awaitedRuns[w] = []
            for (job, runID) in started {
                place(runID, job: job.id)
                resumed[job.id] = true
            }
        default:
            fatalError("仕様に無いアクション \(action)")
        }
        return nil
    }

    func observe() -> [String: Any] {
        var js: [String: Any] = [:]
        var reg: [String: Any] = [:]
        var retry: [String: Any] = [:]
        var resumedState: [String: Any] = [:]
        for j in 0..<Self.jobCount {
            js["\(j)"] = Self.stateName(coordinator.jobs[j]?.state)
            if let runID = coordinator.registrations[j],
               let slot = slotRuns.first(where: { $0.value == runID })?.key {
                reg["\(j)"] = slot
            } else if coordinator.registrations[j] != nil {
                reg["\(j)"] = "登録先の Slot が無い"
            } else {
                reg["\(j)"] = FSLNull.instance
            }
            retry["\(j)"] = retryPending[j]
            resumedState["\(j)"] = resumed[j]
        }
        var run: [String: Any] = [:]
        for s in 0..<Self.slotCount {
            let runID = slotRuns[s]
            let live = runID.flatMap { coordinator.runs[$0] }
            // 終わった Run は待つ対象から外れる (Task.value の待ちが済む)
            let awaited = { (w: Int) in live != nil && runID.map { self.awaitedRuns[w].contains($0) } == true }
            run["\(s)"] = [
                "alive": live != nil,
                "cancelled": live?.isCancelled ?? false,
                "prepared": live?.isPrepared ?? false,
                "awaited0": awaited(0),
                "awaited1": awaited(1),
            ]
        }
        var hs: [String: Any] = [:]
        var stale: [String: Any] = [:]
        for w in 0..<Self.handlerCount {
            hs["\(w)"] = handlers[w].rawValue
            stale["\(w)"] = handlers[w] != .Idle && tokens[w] != coordinator.sleepGeneration
        }
        return [
            "js": js,
            "run": run,
            "reg": reg,
            "paused": coordinator.isPausedForSleep,
            "asleep": asleep,
            "hs": hs,
            "stale": stale,
            "retryPending": retry,
            "resumed": resumedState,
        ]
    }

    /// 新しい Run を仕様と同じ規則で Slot に置く
    private func place(_ runID: Coordinator.RunID, job j: Int) {
        let first = j * 2
        let firstAlive = slotRuns[first].flatMap { coordinator.runs[$0] } != nil
        slotRuns[firstAlive && slotRuns[first] != runID ? first + 1 : first] = runID
    }

    private static func stateName(_ state: PersistedPipelineJobState?) -> String {
        switch state {
        case nil: "Absent"
        case .waiting: "Waiting"
        case .transcribing: "Transcribing"
        case .summarizing: "Summarizing"
        case .saving: "Saving"
        case .completed: "Completed"
        case .failed: "Failed"
        }
    }
}

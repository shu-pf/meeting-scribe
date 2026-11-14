// 実コード側でランダムに操作列を回し、fslc replay に渡す軌跡 (replay-trace v1) を書き出す。
//
// 生成テストのランダムウォークは仕様の Monitor が選んだ 1 本だけなので、逆向きにも照合する。
// どの操作を起こせるかは仕様ではなく環境の事実から決める (生きている Task だけが進捗を報告できる、
// 失敗したジョブにだけ再実行ボタンが出る、など)。仕様が禁じる操作を実装が通したり、状態がずれたりすれば
// fslc replay が nonconformant を返す。書き出し先は環境変数 FSL_TRACE_DIR (未設定なら書き出さない)。
import Foundation
import Testing

struct SplitMix64: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

private func jsonValue(_ value: Any) -> Any {
    switch value {
    case is FSLNull: NSNull()
    case let map as [String: Any]: map.mapValues(jsonValue)
    case let list as [Any]: list.map(jsonValue)
    default: value
    }
}

/// 観測した状態から、環境が起こせる操作を列挙する
private func possibleSteps(_ state: [String: Any]) -> [(String, [String: Any])] {
    let js = state["js"] as! [String: Any]
    let run = state["run"] as! [String: [String: Bool]]
    let hs = state["hs"] as! [String: String]
    let retryPending = state["retryPending"] as! [String: Bool]
    let asleep = state["asleep"] as! Bool
    var steps: [(String, [String: Any])] = []
    for j in 0..<2 {
        let unused = (js["\(j)"] as! String) == "Absent"
            && !run["\(j * 2)"]!["alive"]! && !run["\(j * 2 + 1)"]!["alive"]!
        if unused { steps.append(("record", ["j": j])) }
        if !asleep, (js["\(j)"] as! String) == "Failed" { steps.append(("retry", ["j": j])) }
        if retryPending["\(j)"]! { steps.append(("retry_start", ["j": j])) }
    }
    for s in 0..<4 {
        let r = run["\(s)"]!
        guard r["alive"]! else { continue }
        if r["prepared"]! {
            for st in ["Transcribing", "Summarizing", "Saving"] {
                steps.append(("progress", ["s": s, "st": st]))
            }
            steps.append(("finish", ["s": s, "ok": true]))
            steps.append(("finish", ["s": s, "ok": false]))
        } else {
            steps.append(("prepare", ["s": s]))
            steps.append(("prepare_failed", ["s": s]))
        }
    }
    if asleep {
        // 同時に待てる復帰処理は 2 つまで (仕様の ASSUME-2)
        if !(state["paused"] as! Bool) || hs.values.contains("Idle") {
            steps.append(("os_wake", [:]))
        }
    } else {
        steps.append(("os_sleep", [:]))
    }
    for w in 0..<2 {
        switch hs["\(w)"]! {
        case "Pending":
            steps.append(("wake_snap", ["w": w]))
        case "Awaiting":
            // 復帰処理は、待っている Task がすべて終わるまで進まない
            let waitedRunsEnded = (0..<4).allSatisfy { s in !run["\(s)"]!["awaited\(w)"]! }
            if waitedRunsEnded { steps.append(("wake_finish", ["w": w])) }
        default:
            break
        }
    }
    return steps
}

@Test func randomWalkTracesForReplay() throws {
    let walks = Int(ProcessInfo.processInfo.environment["FSL_WALKS"] ?? "") ?? 300
    let length = 40
    let directory = ProcessInfo.processInfo.environment["FSL_TRACE_DIR"].map {
        URL(fileURLWithPath: $0, isDirectory: true)
    }
    var rng = SplitMix64(state: 20261114)
    for walk in 0..<walks {
        let adapter = PipelineJobsAdapter()
        adapter.reset()
        let initial = adapter.observe()
        var state = initial
        var events: [[String: Any]] = []
        for tick in 1...length {
            let steps = possibleSteps(state)
            guard let (action, params) = steps.randomElement(using: &rng) else { break }
            _ = adapter.step(action, params)
            state = adapter.observe()
            events.append([
                "tick": tick,
                "action": action,
                "params": params,
                "state": jsonValue(state),
            ])
        }
        #expect(!events.isEmpty)
        if let directory {
            let trace: [String: Any] = [
                "$schema": "https://fsl.dev/schemas/fslc/kernel/replay-trace.v1.schema.json",
                "schema_version": "1.0.0",
                "kernel_schema_version": "2.0.0",
                "spec": "PipelineJobs",
                "initial": jsonValue(initial),
                "events": events,
            ]
            let data = try JSONSerialization.data(withJSONObject: trace, options: [.sortedKeys])
            try data.write(to: directory.appendingPathComponent(String(format: "walk-%04d.json", walk)))
        }
    }
}

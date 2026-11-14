// 実コード側でランダムに操作列を回し、fslc replay に渡す軌跡 (replay-trace v1) を書き出す。
//
// どの操作を起こせるかは仕様ではなく、画面に出ているボタンと環境の事実から決める
// (ダウンロード中は戻るボタンが押せない、要約の手順で要約モデルが無いときだけ「要約を作らない」が出る、など)。
// 仕様が禁じる遷移を実装が通したり、状態がずれたりすれば fslc replay が nonconformant を返す。
// 書き出し先は環境変数 FSL_TRACE_DIR (未設定なら書き出さない)。
import Foundation
import Testing

private struct SplitMix64: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// 観測した状態から、利用者と環境が起こせる操作を列挙する。
/// 環境の変化 (env_*) と、画面を閉じる・アプリを終了する操作は別の列に分け、選ぶ頻度を下げる。
/// 同じ頻度だと完了まで進む軌跡がほとんど無い。
private func possibleSteps(_ s: [String: Any]) -> (
    environment: [(String, [String: Any])],
    interruption: [(String, [String: Any])],
    user: [(String, [String: Any])]
) {
    func b(_ key: String) -> Bool { s[key] as! Bool }
    func i(_ key: String) -> Int { s[key] as! Int }
    var environment: [(String, [String: Any])] = []
    var interruption: [(String, [String: Any])] = []
    var steps: [(String, [String: Any])] = []
    let done = b("done")
    let active = b("open") && !done
    let step = i("step")

    if b("dir") { environment.append(("env_remove_dir", [:])) }
    environment.append(("env_perm", ["v": !b("perm")]))
    environment.append(("env_ollama", ["v": !b("oll")]))
    if i("wdl") == 0 { environment.append(("env_wfile", ["v": !b("wFile")])) }
    if i("sdl") == 0 { environment.append(("env_smodel", ["v": !b("sFile")])) }

    if active {
        steps.append(("refresh_perm", [:]))
        steps.append(("refresh_ollama", [:]))
        interruption.append(("close_window", [:]))
        if step == 1 { steps.append(("set_dir", [:])) }
        let canForward = switch step {
        case 0: true
        case 1: b("cDir")
        case 2: b("cPerm")
        case 3: b("cW")
        case 4: b("cS") || b("cSkip")
        default: false
        }
        if canForward { steps.append(("forward", [:])) }
        if step > 0, i("wdl") == 0, i("sdl") == 0 { steps.append(("back", [:])) }
        // 2 回目のクリックが画面の更新より先に届くこともあるので、ダウンロード中でも押せる
        if step == 3, !b("cW") { steps.append(("start_wdl", [:])) }
        if step == 4, b("oll"), !b("cS") { steps.append(("start_sdl", [:])) }
        if step == 4, !b("cS"), i("sdl") == 0 { steps.append(("skip_summary", [:])) }
        if step == 5 { steps.append(("complete", [:])) }
    }
    if !done {
        interruption.append(("quit_app", [:]))
        if !b("open") { steps.append(("reopen", [:])) }
    }
    if i("wdl") > 0 {
        steps.append(("finish_wdl", ["ok": true]))
        steps.append(("finish_wdl", ["ok": false]))
    }
    if i("sdl") > 0 {
        steps.append(("finish_sdl", ["ok": true]))
        steps.append(("finish_sdl", ["ok": false]))
    }
    return (environment, interruption, steps)
}

@Test func randomWalkTracesForReplay() throws {
    let walks = Int(ProcessInfo.processInfo.environment["FSL_WALKS"] ?? "") ?? 300
    let length = 60
    let directory = ProcessInfo.processInfo.environment["FSL_TRACE_DIR"].map {
        URL(fileURLWithPath: $0, isDirectory: true)
    }
    var rng = SplitMix64(state: 20261114)
    var completedWalks = 0
    for walk in 0..<walks {
        let adapter = InitialSetupAdapter()
        adapter.reset()
        let initial = adapter.observe()
        var state = initial
        var events: [[String: Any]] = []
        for tick in 1...length {
            let (environment, interruption, user) = possibleSteps(state)
            let roll = Int.random(in: 0..<16, using: &rng)
            let candidates = if user.isEmpty || roll < 2 {
                environment
            } else if roll == 2, !interruption.isEmpty {
                interruption
            } else {
                user
            }
            guard let (action, params) = candidates.randomElement(using: &rng) else { break }
            _ = adapter.step(action, params)
            state = adapter.observe()
            events.append([
                "tick": tick,
                "action": action,
                "params": params,
                "state": state,
            ])
        }
        #expect(!events.isEmpty)
        if state["done"] as! Bool { completedWalks += 1 }
        if let directory {
            let trace: [String: Any] = [
                "$schema": "https://fsl.dev/schemas/fslc/kernel/replay-trace.v1.schema.json",
                "schema_version": "1.0.0",
                "kernel_schema_version": "2.0.0",
                "spec": "InitialSetup",
                "initial": initial,
                "events": events,
            ]
            let data = try JSONSerialization.data(withJSONObject: trace, options: [.sortedKeys])
            try data.write(to: directory.appendingPathComponent(String(format: "walk-%04d.json", walk)))
        }
    }
    // 完了まで進む軌跡が無ければ、完了の判断を照合できていない
    #expect(completedWalks > 0, "完了まで進んだ軌跡が 1 本も無い")
}

/// 画面で押せない操作を実装に直接送っても、状態が変わらないこと。
/// 画面のボタンの無効化に頼らず、InitialSetupFlow 自身が条件を確かめているかを見る。
/// 仕様はこれらの操作を有効にしないので、軌跡 (replay) には含めない。
private func disabledProbes(_ s: [String: Any]) -> [(String, [String: Any])] {
    func b(_ key: String) -> Bool { s[key] as! Bool }
    let step = s["step"] as! Int
    guard b("open") || b("done") else { return [] }
    if b("done") {
        return [("forward", [:]), ("back", [:]), ("skip_summary", [:]), ("complete", [:])]
    }
    var probes: [(String, [String: Any])] = []
    let canForward = switch step {
    case 0: true
    case 1: b("cDir")
    case 2: b("cPerm")
    case 3: b("cW")
    case 4: b("cS") || b("cSkip")
    default: false
    }
    if !canForward { probes.append(("forward", [:])) }
    if step != 4 || b("cS") { probes.append(("skip_summary", [:])) }
    if step != 5 { probes.append(("complete", [:])) }
    if step == 0 { probes.append(("back", [:])) }
    return probes
}

@Test func disabledActionsDoNotChangeState() throws {
    var rng = SplitMix64(state: 20261115)
    var probed = 0
    for _ in 0..<300 {
        let adapter = InitialSetupAdapter()
        adapter.reset()
        var state = adapter.observe()
        for _ in 1...60 {
            for (action, params) in disabledProbes(state) {
                _ = adapter.step(action, params)
                let after = adapter.observe()
                #expect(fslEqual(after, state), "押せない \(action) で状態が変わった: \(state) -> \(after)")
                probed += 1
            }
            let (environment, interruption, user) = possibleSteps(state)
            let roll = Int.random(in: 0..<16, using: &rng)
            let candidates = if user.isEmpty || roll < 2 {
                environment
            } else if roll == 2, !interruption.isEmpty {
                interruption
            } else {
                user
            }
            guard let (action, params) = candidates.randomElement(using: &rng) else { break }
            _ = adapter.step(action, params)
            state = adapter.observe()
        }
    }
    #expect(probed > 0)
}

// SPDX-License-Identifier: Apache-2.0
//
// Auto-generated FSL conformance tests (Swift Testing).
// Source: initial_setup.fsl
//
// Wire `makeAdapter()` to your implementation. Until it is wired, every test
// FAILS with "adapter not wired" (issue #1200): a suite that never calls the
// implementation is not evidence that it conforms. Generate with
// `fslc testgen --allow-unwired` to skip instead.
//
// The random-walk trace below was baked at generation time by the FSL Monitor
// (the spec's concrete interpreter) under a fixed seed, so these tests need no
// `fslc`/Python at runtime — they replay the baked oracle states and assert.
import Testing

struct StepResult {
    let ok: Bool
    let kind: String?
}

// A self-contained JSON-null sentinel so the harness depends only on `Testing`
// (no Foundation/NSNull). Project a None/absent Option state field to this.
struct FSLNull: Equatable {
    static let instance = FSLNull()
}

enum FSLNotWired: Error, CustomStringConvertible {
    case notWired
    var description: String { "adapter not wired: implement makeAdapter() to connect your implementation, or generate with `fslc testgen --allow-unwired` to skip instead" }
}

/// Connect your implementation to the spec actions/state.
///  - reset(): put the implementation in the same initial state as spec `init`
///  - step(action, params): drive one spec action; return a StepResult for
///    forbidden-rejection scenarios (nil is fine for ordinary steps)
///  - observe(): project implementation state onto the spec's logical-state shape
///    (enum = name string, Option = FSLNull.instance|value, Seq = [Any],
///     Map = [String: Any], struct = [String: Any])
protocol Adapter {
    func reset()
    func step(_ action: String, _ params: [String: Any]) -> StepResult?
    func observe() -> [String: Any]
}

// Wire your implementation here. Throwing fails every test ("adapter not wired").
func makeAdapter() throws -> any Adapter {
    InitialSetupAdapter()
}

func isAdapterWired() -> Bool {
    do {
        let a = try makeAdapter()
        a.reset()
        _ = a.observe()
        return true
    } catch {
        return false
    }
}

// Deep equality over the JSON-normal world: Bool/Int/Double/String/FSLNull,
// [Any] (ordered) and [String: Any] (by key). Int and Double do not cross-match.
func fslEqual(_ a: Any, _ b: Any) -> Bool {
    switch (a, b) {
    case (is FSLNull, is FSLNull): return true
    case let (x as Bool, y as Bool): return x == y
    case let (x as Int, y as Int): return x == y
    case let (x as Double, y as Double): return x == y
    case let (x as String, y as String): return x == y
    case let (x as [Any], y as [Any]):
        return x.count == y.count && zip(x, y).allSatisfy { fslEqual($0, $1) }
    case let (x as [String: Any], y as [String: Any]):
        return x.count == y.count && x.allSatisfy { (k, v) in
            guard let w = y[k] else { return false }
            return fslEqual(v, w)
        }
    default: return false
    }
}

// Assert only the fields the spec mentions; recurse into nested (Map/struct) shapes.
func assertPartial(_ observed: [String: Any], _ expected: [String: Any]) {
    for (key, val) in expected {
        let seen = observed[key]
        if let v = val as? [String: Any], let s = seen as? [String: Any] {
            assertPartial(s, v)
        } else {
            #expect(seen != nil, "missing state key \(key)")
            if let s = seen {
                #expect(fslEqual(s, val), "state \(key): expected \(val), got \(s)")
            }
        }
    }
}

func assertRejected(_ result: StepResult?, _ expectedKind: String?) {
    #expect(result != nil, "forbidden step must return a StepResult")
    #expect(result?.ok == false)
    if let kind = expectedKind {
        #expect(result?.kind == kind)
    }
}


@Test func scenario_cover_env_remove_dir() throws {
    let a = try makeAdapter()
    a.reset()
    _ = a.step("forward", [String: Any]())
    assertPartial(a.observe(), ["step": 1, "saved": 1, "done": false, "open": true, "dir": false, "perm": false, "wFile": false, "oll": false, "sFile": false, "wSel": false, "sSel": false, "skip": false, "cDir": false, "cPerm": false, "cW": false, "cS": false, "cSkip": false, "wdl": 0, "sdl": 0, "okAtDone": false, "bounced": false, "pickedWhileClosed": false])
    _ = a.step("set_dir", [String: Any]())
    assertPartial(a.observe(), ["step": 1, "saved": 1, "done": false, "open": true, "dir": true, "perm": false, "wFile": false, "oll": false, "sFile": false, "wSel": false, "sSel": false, "skip": false, "cDir": true, "cPerm": false, "cW": false, "cS": false, "cSkip": false, "wdl": 0, "sdl": 0, "okAtDone": false, "bounced": false, "pickedWhileClosed": false])
    _ = a.step("env_remove_dir", [String: Any]())
    assertPartial(a.observe(), ["step": 1, "saved": 1, "done": false, "open": true, "dir": false, "perm": false, "wFile": false, "oll": false, "sFile": false, "wSel": false, "sSel": false, "skip": false, "cDir": true, "cPerm": false, "cW": false, "cS": false, "cSkip": false, "wdl": 0, "sdl": 0, "okAtDone": false, "bounced": false, "pickedWhileClosed": false])
}

@Test func scenario_cover_env_perm() throws {
    let a = try makeAdapter()
    a.reset()
    _ = a.step("env_perm", ["v": false])
    assertPartial(a.observe(), ["step": 0, "saved": 0, "done": false, "open": true, "dir": false, "perm": false, "wFile": false, "oll": false, "sFile": false, "wSel": false, "sSel": false, "skip": false, "cDir": false, "cPerm": false, "cW": false, "cS": false, "cSkip": false, "wdl": 0, "sdl": 0, "okAtDone": false, "bounced": false, "pickedWhileClosed": false])
}

@Test func scenario_cover_env_wfile() throws {
    let a = try makeAdapter()
    a.reset()
    _ = a.step("env_wfile", ["v": false])
    assertPartial(a.observe(), ["step": 0, "saved": 0, "done": false, "open": true, "dir": false, "perm": false, "wFile": false, "oll": false, "sFile": false, "wSel": false, "sSel": false, "skip": false, "cDir": false, "cPerm": false, "cW": false, "cS": false, "cSkip": false, "wdl": 0, "sdl": 0, "okAtDone": false, "bounced": false, "pickedWhileClosed": false])
}

@Test func scenario_cover_env_ollama() throws {
    let a = try makeAdapter()
    a.reset()
    _ = a.step("env_ollama", ["v": false])
    assertPartial(a.observe(), ["step": 0, "saved": 0, "done": false, "open": true, "dir": false, "perm": false, "wFile": false, "oll": false, "sFile": false, "wSel": false, "sSel": false, "skip": false, "cDir": false, "cPerm": false, "cW": false, "cS": false, "cSkip": false, "wdl": 0, "sdl": 0, "okAtDone": false, "bounced": false, "pickedWhileClosed": false])
}

@Test func scenario_cover_env_smodel() throws {
    let a = try makeAdapter()
    a.reset()
    _ = a.step("env_smodel", ["v": false])
    assertPartial(a.observe(), ["step": 0, "saved": 0, "done": false, "open": true, "dir": false, "perm": false, "wFile": false, "oll": false, "sFile": false, "wSel": false, "sSel": false, "skip": false, "cDir": false, "cPerm": false, "cW": false, "cS": false, "cSkip": false, "wdl": 0, "sdl": 0, "okAtDone": false, "bounced": false, "pickedWhileClosed": false])
}

@Test func scenario_cover_set_dir() throws {
    let a = try makeAdapter()
    a.reset()
    _ = a.step("forward", [String: Any]())
    assertPartial(a.observe(), ["step": 1, "saved": 1, "done": false, "open": true, "dir": false, "perm": false, "wFile": false, "oll": false, "sFile": false, "wSel": false, "sSel": false, "skip": false, "cDir": false, "cPerm": false, "cW": false, "cS": false, "cSkip": false, "wdl": 0, "sdl": 0, "okAtDone": false, "bounced": false, "pickedWhileClosed": false])
    _ = a.step("set_dir", [String: Any]())
    assertPartial(a.observe(), ["step": 1, "saved": 1, "done": false, "open": true, "dir": true, "perm": false, "wFile": false, "oll": false, "sFile": false, "wSel": false, "sSel": false, "skip": false, "cDir": true, "cPerm": false, "cW": false, "cS": false, "cSkip": false, "wdl": 0, "sdl": 0, "okAtDone": false, "bounced": false, "pickedWhileClosed": false])
}

@Test func scenario_cover_refresh_perm() throws {
    let a = try makeAdapter()
    a.reset()
    _ = a.step("refresh_perm", [String: Any]())
    assertPartial(a.observe(), ["step": 0, "saved": 0, "done": false, "open": true, "dir": false, "perm": false, "wFile": false, "oll": false, "sFile": false, "wSel": false, "sSel": false, "skip": false, "cDir": false, "cPerm": false, "cW": false, "cS": false, "cSkip": false, "wdl": 0, "sdl": 0, "okAtDone": false, "bounced": false, "pickedWhileClosed": false])
}

@Test func scenario_cover_forward() throws {
    let a = try makeAdapter()
    a.reset()
    _ = a.step("forward", [String: Any]())
    assertPartial(a.observe(), ["step": 1, "saved": 1, "done": false, "open": true, "dir": false, "perm": false, "wFile": false, "oll": false, "sFile": false, "wSel": false, "sSel": false, "skip": false, "cDir": false, "cPerm": false, "cW": false, "cS": false, "cSkip": false, "wdl": 0, "sdl": 0, "okAtDone": false, "bounced": false, "pickedWhileClosed": false])
}

@Test func scenario_cover_back() throws {
    let a = try makeAdapter()
    a.reset()
    _ = a.step("forward", [String: Any]())
    assertPartial(a.observe(), ["step": 1, "saved": 1, "done": false, "open": true, "dir": false, "perm": false, "wFile": false, "oll": false, "sFile": false, "wSel": false, "sSel": false, "skip": false, "cDir": false, "cPerm": false, "cW": false, "cS": false, "cSkip": false, "wdl": 0, "sdl": 0, "okAtDone": false, "bounced": false, "pickedWhileClosed": false])
    _ = a.step("back", [String: Any]())
    assertPartial(a.observe(), ["step": 0, "saved": 0, "done": false, "open": true, "dir": false, "perm": false, "wFile": false, "oll": false, "sFile": false, "wSel": false, "sSel": false, "skip": false, "cDir": false, "cPerm": false, "cW": false, "cS": false, "cSkip": false, "wdl": 0, "sdl": 0, "okAtDone": false, "bounced": false, "pickedWhileClosed": false])
}

@Test func scenario_cover_skip_summary() throws {
    let a = try makeAdapter()
    a.reset()
    _ = a.step("env_perm", ["v": true])
    assertPartial(a.observe(), ["step": 0, "saved": 0, "done": false, "open": true, "dir": false, "perm": true, "wFile": false, "oll": false, "sFile": false, "wSel": false, "sSel": false, "skip": false, "cDir": false, "cPerm": false, "cW": false, "cS": false, "cSkip": false, "wdl": 0, "sdl": 0, "okAtDone": false, "bounced": false, "pickedWhileClosed": false])
    _ = a.step("env_wfile", ["v": true])
    assertPartial(a.observe(), ["step": 0, "saved": 0, "done": false, "open": true, "dir": false, "perm": true, "wFile": true, "oll": false, "sFile": false, "wSel": false, "sSel": false, "skip": false, "cDir": false, "cPerm": false, "cW": false, "cS": false, "cSkip": false, "wdl": 0, "sdl": 0, "okAtDone": false, "bounced": false, "pickedWhileClosed": false])
    _ = a.step("forward", [String: Any]())
    assertPartial(a.observe(), ["step": 1, "saved": 1, "done": false, "open": true, "dir": false, "perm": true, "wFile": true, "oll": false, "sFile": false, "wSel": false, "sSel": false, "skip": false, "cDir": false, "cPerm": false, "cW": false, "cS": false, "cSkip": false, "wdl": 0, "sdl": 0, "okAtDone": false, "bounced": false, "pickedWhileClosed": false])
    _ = a.step("set_dir", [String: Any]())
    assertPartial(a.observe(), ["step": 1, "saved": 1, "done": false, "open": true, "dir": true, "perm": true, "wFile": true, "oll": false, "sFile": false, "wSel": false, "sSel": false, "skip": false, "cDir": true, "cPerm": false, "cW": false, "cS": false, "cSkip": false, "wdl": 0, "sdl": 0, "okAtDone": false, "bounced": false, "pickedWhileClosed": false])
    _ = a.step("forward", [String: Any]())
    assertPartial(a.observe(), ["step": 2, "saved": 2, "done": false, "open": true, "dir": true, "perm": true, "wFile": true, "oll": false, "sFile": false, "wSel": false, "sSel": false, "skip": false, "cDir": true, "cPerm": false, "cW": false, "cS": false, "cSkip": false, "wdl": 0, "sdl": 0, "okAtDone": false, "bounced": false, "pickedWhileClosed": false])
    _ = a.step("close_window", [String: Any]())
    assertPartial(a.observe(), ["step": 0, "saved": 2, "done": false, "open": false, "dir": true, "perm": true, "wFile": true, "oll": false, "sFile": false, "wSel": false, "sSel": false, "skip": false, "cDir": false, "cPerm": false, "cW": false, "cS": false, "cSkip": false, "wdl": 0, "sdl": 0, "okAtDone": false, "bounced": false, "pickedWhileClosed": false])
    _ = a.step("reopen", [String: Any]())
    assertPartial(a.observe(), ["step": 2, "saved": 2, "done": false, "open": true, "dir": true, "perm": true, "wFile": true, "oll": false, "sFile": false, "wSel": true, "sSel": false, "skip": false, "cDir": true, "cPerm": true, "cW": true, "cS": false, "cSkip": false, "wdl": 0, "sdl": 0, "okAtDone": false, "bounced": false, "pickedWhileClosed": false])
    _ = a.step("forward", [String: Any]())
    assertPartial(a.observe(), ["step": 3, "saved": 3, "done": false, "open": true, "dir": true, "perm": true, "wFile": true, "oll": false, "sFile": false, "wSel": true, "sSel": false, "skip": false, "cDir": true, "cPerm": true, "cW": true, "cS": false, "cSkip": false, "wdl": 0, "sdl": 0, "okAtDone": false, "bounced": false, "pickedWhileClosed": false])
    _ = a.step("forward", [String: Any]())
    assertPartial(a.observe(), ["step": 4, "saved": 4, "done": false, "open": true, "dir": true, "perm": true, "wFile": true, "oll": false, "sFile": false, "wSel": true, "sSel": false, "skip": false, "cDir": true, "cPerm": true, "cW": true, "cS": false, "cSkip": false, "wdl": 0, "sdl": 0, "okAtDone": false, "bounced": false, "pickedWhileClosed": false])
    _ = a.step("skip_summary", [String: Any]())
    assertPartial(a.observe(), ["step": 5, "saved": 5, "done": false, "open": true, "dir": true, "perm": true, "wFile": true, "oll": false, "sFile": false, "wSel": true, "sSel": false, "skip": true, "cDir": true, "cPerm": true, "cW": true, "cS": false, "cSkip": true, "wdl": 0, "sdl": 0, "okAtDone": false, "bounced": false, "pickedWhileClosed": false])
}

@Test func scenario_cover_refresh_ollama() throws {
    let a = try makeAdapter()
    a.reset()
    _ = a.step("refresh_ollama", [String: Any]())
    assertPartial(a.observe(), ["step": 0, "saved": 0, "done": false, "open": true, "dir": false, "perm": false, "wFile": false, "oll": false, "sFile": false, "wSel": false, "sSel": false, "skip": false, "cDir": false, "cPerm": false, "cW": false, "cS": false, "cSkip": false, "wdl": 0, "sdl": 0, "okAtDone": false, "bounced": false, "pickedWhileClosed": false])
}

@Test func scenario_cover_start_wdl() throws {
    let a = try makeAdapter()
    a.reset()
    _ = a.step("env_perm", ["v": true])
    assertPartial(a.observe(), ["step": 0, "saved": 0, "done": false, "open": true, "dir": false, "perm": true, "wFile": false, "oll": false, "sFile": false, "wSel": false, "sSel": false, "skip": false, "cDir": false, "cPerm": false, "cW": false, "cS": false, "cSkip": false, "wdl": 0, "sdl": 0, "okAtDone": false, "bounced": false, "pickedWhileClosed": false])
    _ = a.step("refresh_perm", [String: Any]())
    assertPartial(a.observe(), ["step": 0, "saved": 0, "done": false, "open": true, "dir": false, "perm": true, "wFile": false, "oll": false, "sFile": false, "wSel": false, "sSel": false, "skip": false, "cDir": false, "cPerm": true, "cW": false, "cS": false, "cSkip": false, "wdl": 0, "sdl": 0, "okAtDone": false, "bounced": false, "pickedWhileClosed": false])
    _ = a.step("forward", [String: Any]())
    assertPartial(a.observe(), ["step": 1, "saved": 1, "done": false, "open": true, "dir": false, "perm": true, "wFile": false, "oll": false, "sFile": false, "wSel": false, "sSel": false, "skip": false, "cDir": false, "cPerm": true, "cW": false, "cS": false, "cSkip": false, "wdl": 0, "sdl": 0, "okAtDone": false, "bounced": false, "pickedWhileClosed": false])
    _ = a.step("set_dir", [String: Any]())
    assertPartial(a.observe(), ["step": 1, "saved": 1, "done": false, "open": true, "dir": true, "perm": true, "wFile": false, "oll": false, "sFile": false, "wSel": false, "sSel": false, "skip": false, "cDir": true, "cPerm": true, "cW": false, "cS": false, "cSkip": false, "wdl": 0, "sdl": 0, "okAtDone": false, "bounced": false, "pickedWhileClosed": false])
    _ = a.step("forward", [String: Any]())
    assertPartial(a.observe(), ["step": 2, "saved": 2, "done": false, "open": true, "dir": true, "perm": true, "wFile": false, "oll": false, "sFile": false, "wSel": false, "sSel": false, "skip": false, "cDir": true, "cPerm": true, "cW": false, "cS": false, "cSkip": false, "wdl": 0, "sdl": 0, "okAtDone": false, "bounced": false, "pickedWhileClosed": false])
    _ = a.step("forward", [String: Any]())
    assertPartial(a.observe(), ["step": 3, "saved": 3, "done": false, "open": true, "dir": true, "perm": true, "wFile": false, "oll": false, "sFile": false, "wSel": false, "sSel": false, "skip": false, "cDir": true, "cPerm": true, "cW": false, "cS": false, "cSkip": false, "wdl": 0, "sdl": 0, "okAtDone": false, "bounced": false, "pickedWhileClosed": false])
    _ = a.step("start_wdl", [String: Any]())
    assertPartial(a.observe(), ["step": 3, "saved": 3, "done": false, "open": true, "dir": true, "perm": true, "wFile": false, "oll": false, "sFile": false, "wSel": false, "sSel": false, "skip": false, "cDir": true, "cPerm": true, "cW": false, "cS": false, "cSkip": false, "wdl": 1, "sdl": 0, "okAtDone": false, "bounced": false, "pickedWhileClosed": false])
}

@Test func scenario_cover_finish_wdl() throws {
    let a = try makeAdapter()
    a.reset()
    _ = a.step("env_perm", ["v": true])
    assertPartial(a.observe(), ["step": 0, "saved": 0, "done": false, "open": true, "dir": false, "perm": true, "wFile": false, "oll": false, "sFile": false, "wSel": false, "sSel": false, "skip": false, "cDir": false, "cPerm": false, "cW": false, "cS": false, "cSkip": false, "wdl": 0, "sdl": 0, "okAtDone": false, "bounced": false, "pickedWhileClosed": false])
    _ = a.step("refresh_perm", [String: Any]())
    assertPartial(a.observe(), ["step": 0, "saved": 0, "done": false, "open": true, "dir": false, "perm": true, "wFile": false, "oll": false, "sFile": false, "wSel": false, "sSel": false, "skip": false, "cDir": false, "cPerm": true, "cW": false, "cS": false, "cSkip": false, "wdl": 0, "sdl": 0, "okAtDone": false, "bounced": false, "pickedWhileClosed": false])
    _ = a.step("forward", [String: Any]())
    assertPartial(a.observe(), ["step": 1, "saved": 1, "done": false, "open": true, "dir": false, "perm": true, "wFile": false, "oll": false, "sFile": false, "wSel": false, "sSel": false, "skip": false, "cDir": false, "cPerm": true, "cW": false, "cS": false, "cSkip": false, "wdl": 0, "sdl": 0, "okAtDone": false, "bounced": false, "pickedWhileClosed": false])
    _ = a.step("set_dir", [String: Any]())
    assertPartial(a.observe(), ["step": 1, "saved": 1, "done": false, "open": true, "dir": true, "perm": true, "wFile": false, "oll": false, "sFile": false, "wSel": false, "sSel": false, "skip": false, "cDir": true, "cPerm": true, "cW": false, "cS": false, "cSkip": false, "wdl": 0, "sdl": 0, "okAtDone": false, "bounced": false, "pickedWhileClosed": false])
    _ = a.step("forward", [String: Any]())
    assertPartial(a.observe(), ["step": 2, "saved": 2, "done": false, "open": true, "dir": true, "perm": true, "wFile": false, "oll": false, "sFile": false, "wSel": false, "sSel": false, "skip": false, "cDir": true, "cPerm": true, "cW": false, "cS": false, "cSkip": false, "wdl": 0, "sdl": 0, "okAtDone": false, "bounced": false, "pickedWhileClosed": false])
    _ = a.step("forward", [String: Any]())
    assertPartial(a.observe(), ["step": 3, "saved": 3, "done": false, "open": true, "dir": true, "perm": true, "wFile": false, "oll": false, "sFile": false, "wSel": false, "sSel": false, "skip": false, "cDir": true, "cPerm": true, "cW": false, "cS": false, "cSkip": false, "wdl": 0, "sdl": 0, "okAtDone": false, "bounced": false, "pickedWhileClosed": false])
    _ = a.step("start_wdl", [String: Any]())
    assertPartial(a.observe(), ["step": 3, "saved": 3, "done": false, "open": true, "dir": true, "perm": true, "wFile": false, "oll": false, "sFile": false, "wSel": false, "sSel": false, "skip": false, "cDir": true, "cPerm": true, "cW": false, "cS": false, "cSkip": false, "wdl": 1, "sdl": 0, "okAtDone": false, "bounced": false, "pickedWhileClosed": false])
    _ = a.step("finish_wdl", ["ok": false])
    assertPartial(a.observe(), ["step": 3, "saved": 3, "done": false, "open": true, "dir": true, "perm": true, "wFile": false, "oll": false, "sFile": false, "wSel": false, "sSel": false, "skip": false, "cDir": true, "cPerm": true, "cW": false, "cS": false, "cSkip": false, "wdl": 0, "sdl": 0, "okAtDone": false, "bounced": false, "pickedWhileClosed": false])
}

@Test func scenario_cover_start_sdl() throws {
    let a = try makeAdapter()
    a.reset()
    _ = a.step("env_perm", ["v": true])
    assertPartial(a.observe(), ["step": 0, "saved": 0, "done": false, "open": true, "dir": false, "perm": true, "wFile": false, "oll": false, "sFile": false, "wSel": false, "sSel": false, "skip": false, "cDir": false, "cPerm": false, "cW": false, "cS": false, "cSkip": false, "wdl": 0, "sdl": 0, "okAtDone": false, "bounced": false, "pickedWhileClosed": false])
    _ = a.step("env_wfile", ["v": true])
    assertPartial(a.observe(), ["step": 0, "saved": 0, "done": false, "open": true, "dir": false, "perm": true, "wFile": true, "oll": false, "sFile": false, "wSel": false, "sSel": false, "skip": false, "cDir": false, "cPerm": false, "cW": false, "cS": false, "cSkip": false, "wdl": 0, "sdl": 0, "okAtDone": false, "bounced": false, "pickedWhileClosed": false])
    _ = a.step("env_ollama", ["v": true])
    assertPartial(a.observe(), ["step": 0, "saved": 0, "done": false, "open": true, "dir": false, "perm": true, "wFile": true, "oll": true, "sFile": false, "wSel": false, "sSel": false, "skip": false, "cDir": false, "cPerm": false, "cW": false, "cS": false, "cSkip": false, "wdl": 0, "sdl": 0, "okAtDone": false, "bounced": false, "pickedWhileClosed": false])
    _ = a.step("forward", [String: Any]())
    assertPartial(a.observe(), ["step": 1, "saved": 1, "done": false, "open": true, "dir": false, "perm": true, "wFile": true, "oll": true, "sFile": false, "wSel": false, "sSel": false, "skip": false, "cDir": false, "cPerm": false, "cW": false, "cS": false, "cSkip": false, "wdl": 0, "sdl": 0, "okAtDone": false, "bounced": false, "pickedWhileClosed": false])
    _ = a.step("set_dir", [String: Any]())
    assertPartial(a.observe(), ["step": 1, "saved": 1, "done": false, "open": true, "dir": true, "perm": true, "wFile": true, "oll": true, "sFile": false, "wSel": false, "sSel": false, "skip": false, "cDir": true, "cPerm": false, "cW": false, "cS": false, "cSkip": false, "wdl": 0, "sdl": 0, "okAtDone": false, "bounced": false, "pickedWhileClosed": false])
    _ = a.step("forward", [String: Any]())
    assertPartial(a.observe(), ["step": 2, "saved": 2, "done": false, "open": true, "dir": true, "perm": true, "wFile": true, "oll": true, "sFile": false, "wSel": false, "sSel": false, "skip": false, "cDir": true, "cPerm": false, "cW": false, "cS": false, "cSkip": false, "wdl": 0, "sdl": 0, "okAtDone": false, "bounced": false, "pickedWhileClosed": false])
    _ = a.step("close_window", [String: Any]())
    assertPartial(a.observe(), ["step": 0, "saved": 2, "done": false, "open": false, "dir": true, "perm": true, "wFile": true, "oll": true, "sFile": false, "wSel": false, "sSel": false, "skip": false, "cDir": false, "cPerm": false, "cW": false, "cS": false, "cSkip": false, "wdl": 0, "sdl": 0, "okAtDone": false, "bounced": false, "pickedWhileClosed": false])
    _ = a.step("reopen", [String: Any]())
    assertPartial(a.observe(), ["step": 2, "saved": 2, "done": false, "open": true, "dir": true, "perm": true, "wFile": true, "oll": true, "sFile": false, "wSel": true, "sSel": false, "skip": false, "cDir": true, "cPerm": true, "cW": true, "cS": false, "cSkip": false, "wdl": 0, "sdl": 0, "okAtDone": false, "bounced": false, "pickedWhileClosed": false])
    _ = a.step("forward", [String: Any]())
    assertPartial(a.observe(), ["step": 3, "saved": 3, "done": false, "open": true, "dir": true, "perm": true, "wFile": true, "oll": true, "sFile": false, "wSel": true, "sSel": false, "skip": false, "cDir": true, "cPerm": true, "cW": true, "cS": false, "cSkip": false, "wdl": 0, "sdl": 0, "okAtDone": false, "bounced": false, "pickedWhileClosed": false])
    _ = a.step("forward", [String: Any]())
    assertPartial(a.observe(), ["step": 4, "saved": 4, "done": false, "open": true, "dir": true, "perm": true, "wFile": true, "oll": true, "sFile": false, "wSel": true, "sSel": false, "skip": false, "cDir": true, "cPerm": true, "cW": true, "cS": false, "cSkip": false, "wdl": 0, "sdl": 0, "okAtDone": false, "bounced": false, "pickedWhileClosed": false])
    _ = a.step("start_sdl", [String: Any]())
    assertPartial(a.observe(), ["step": 4, "saved": 4, "done": false, "open": true, "dir": true, "perm": true, "wFile": true, "oll": true, "sFile": false, "wSel": true, "sSel": false, "skip": false, "cDir": true, "cPerm": true, "cW": true, "cS": false, "cSkip": false, "wdl": 0, "sdl": 1, "okAtDone": false, "bounced": false, "pickedWhileClosed": false])
}

@Test func scenario_cover_finish_sdl() throws {
    let a = try makeAdapter()
    a.reset()
    _ = a.step("env_perm", ["v": true])
    assertPartial(a.observe(), ["step": 0, "saved": 0, "done": false, "open": true, "dir": false, "perm": true, "wFile": false, "oll": false, "sFile": false, "wSel": false, "sSel": false, "skip": false, "cDir": false, "cPerm": false, "cW": false, "cS": false, "cSkip": false, "wdl": 0, "sdl": 0, "okAtDone": false, "bounced": false, "pickedWhileClosed": false])
    _ = a.step("env_wfile", ["v": true])
    assertPartial(a.observe(), ["step": 0, "saved": 0, "done": false, "open": true, "dir": false, "perm": true, "wFile": true, "oll": false, "sFile": false, "wSel": false, "sSel": false, "skip": false, "cDir": false, "cPerm": false, "cW": false, "cS": false, "cSkip": false, "wdl": 0, "sdl": 0, "okAtDone": false, "bounced": false, "pickedWhileClosed": false])
    _ = a.step("env_ollama", ["v": true])
    assertPartial(a.observe(), ["step": 0, "saved": 0, "done": false, "open": true, "dir": false, "perm": true, "wFile": true, "oll": true, "sFile": false, "wSel": false, "sSel": false, "skip": false, "cDir": false, "cPerm": false, "cW": false, "cS": false, "cSkip": false, "wdl": 0, "sdl": 0, "okAtDone": false, "bounced": false, "pickedWhileClosed": false])
    _ = a.step("forward", [String: Any]())
    assertPartial(a.observe(), ["step": 1, "saved": 1, "done": false, "open": true, "dir": false, "perm": true, "wFile": true, "oll": true, "sFile": false, "wSel": false, "sSel": false, "skip": false, "cDir": false, "cPerm": false, "cW": false, "cS": false, "cSkip": false, "wdl": 0, "sdl": 0, "okAtDone": false, "bounced": false, "pickedWhileClosed": false])
    _ = a.step("set_dir", [String: Any]())
    assertPartial(a.observe(), ["step": 1, "saved": 1, "done": false, "open": true, "dir": true, "perm": true, "wFile": true, "oll": true, "sFile": false, "wSel": false, "sSel": false, "skip": false, "cDir": true, "cPerm": false, "cW": false, "cS": false, "cSkip": false, "wdl": 0, "sdl": 0, "okAtDone": false, "bounced": false, "pickedWhileClosed": false])
    _ = a.step("forward", [String: Any]())
    assertPartial(a.observe(), ["step": 2, "saved": 2, "done": false, "open": true, "dir": true, "perm": true, "wFile": true, "oll": true, "sFile": false, "wSel": false, "sSel": false, "skip": false, "cDir": true, "cPerm": false, "cW": false, "cS": false, "cSkip": false, "wdl": 0, "sdl": 0, "okAtDone": false, "bounced": false, "pickedWhileClosed": false])
    _ = a.step("close_window", [String: Any]())
    assertPartial(a.observe(), ["step": 0, "saved": 2, "done": false, "open": false, "dir": true, "perm": true, "wFile": true, "oll": true, "sFile": false, "wSel": false, "sSel": false, "skip": false, "cDir": false, "cPerm": false, "cW": false, "cS": false, "cSkip": false, "wdl": 0, "sdl": 0, "okAtDone": false, "bounced": false, "pickedWhileClosed": false])
    _ = a.step("reopen", [String: Any]())
    assertPartial(a.observe(), ["step": 2, "saved": 2, "done": false, "open": true, "dir": true, "perm": true, "wFile": true, "oll": true, "sFile": false, "wSel": true, "sSel": false, "skip": false, "cDir": true, "cPerm": true, "cW": true, "cS": false, "cSkip": false, "wdl": 0, "sdl": 0, "okAtDone": false, "bounced": false, "pickedWhileClosed": false])
    _ = a.step("forward", [String: Any]())
    assertPartial(a.observe(), ["step": 3, "saved": 3, "done": false, "open": true, "dir": true, "perm": true, "wFile": true, "oll": true, "sFile": false, "wSel": true, "sSel": false, "skip": false, "cDir": true, "cPerm": true, "cW": true, "cS": false, "cSkip": false, "wdl": 0, "sdl": 0, "okAtDone": false, "bounced": false, "pickedWhileClosed": false])
    _ = a.step("forward", [String: Any]())
    assertPartial(a.observe(), ["step": 4, "saved": 4, "done": false, "open": true, "dir": true, "perm": true, "wFile": true, "oll": true, "sFile": false, "wSel": true, "sSel": false, "skip": false, "cDir": true, "cPerm": true, "cW": true, "cS": false, "cSkip": false, "wdl": 0, "sdl": 0, "okAtDone": false, "bounced": false, "pickedWhileClosed": false])
    _ = a.step("start_sdl", [String: Any]())
    assertPartial(a.observe(), ["step": 4, "saved": 4, "done": false, "open": true, "dir": true, "perm": true, "wFile": true, "oll": true, "sFile": false, "wSel": true, "sSel": false, "skip": false, "cDir": true, "cPerm": true, "cW": true, "cS": false, "cSkip": false, "wdl": 0, "sdl": 1, "okAtDone": false, "bounced": false, "pickedWhileClosed": false])
    _ = a.step("finish_sdl", ["ok": false])
    assertPartial(a.observe(), ["step": 4, "saved": 4, "done": false, "open": true, "dir": true, "perm": true, "wFile": true, "oll": true, "sFile": false, "wSel": true, "sSel": false, "skip": false, "cDir": true, "cPerm": true, "cW": true, "cS": false, "cSkip": false, "wdl": 0, "sdl": 0, "okAtDone": false, "bounced": false, "pickedWhileClosed": false])
}

@Test func scenario_cover_close_window() throws {
    let a = try makeAdapter()
    a.reset()
    _ = a.step("close_window", [String: Any]())
    assertPartial(a.observe(), ["step": 0, "saved": 0, "done": false, "open": false, "dir": false, "perm": false, "wFile": false, "oll": false, "sFile": false, "wSel": false, "sSel": false, "skip": false, "cDir": false, "cPerm": false, "cW": false, "cS": false, "cSkip": false, "wdl": 0, "sdl": 0, "okAtDone": false, "bounced": false, "pickedWhileClosed": false])
}

@Test func scenario_cover_quit_app() throws {
    let a = try makeAdapter()
    a.reset()
    _ = a.step("quit_app", [String: Any]())
    assertPartial(a.observe(), ["step": 0, "saved": 0, "done": false, "open": false, "dir": false, "perm": false, "wFile": false, "oll": false, "sFile": false, "wSel": false, "sSel": false, "skip": false, "cDir": false, "cPerm": false, "cW": false, "cS": false, "cSkip": false, "wdl": 0, "sdl": 0, "okAtDone": false, "bounced": false, "pickedWhileClosed": false])
}

@Test func scenario_cover_reopen() throws {
    let a = try makeAdapter()
    a.reset()
    _ = a.step("close_window", [String: Any]())
    assertPartial(a.observe(), ["step": 0, "saved": 0, "done": false, "open": false, "dir": false, "perm": false, "wFile": false, "oll": false, "sFile": false, "wSel": false, "sSel": false, "skip": false, "cDir": false, "cPerm": false, "cW": false, "cS": false, "cSkip": false, "wdl": 0, "sdl": 0, "okAtDone": false, "bounced": false, "pickedWhileClosed": false])
    _ = a.step("reopen", [String: Any]())
    assertPartial(a.observe(), ["step": 0, "saved": 0, "done": false, "open": true, "dir": false, "perm": false, "wFile": false, "oll": false, "sFile": false, "wSel": false, "sSel": false, "skip": false, "cDir": false, "cPerm": false, "cW": false, "cS": false, "cSkip": false, "wdl": 0, "sdl": 0, "okAtDone": false, "bounced": false, "pickedWhileClosed": false])
}

@Test func scenario_cover_complete() throws {
    let a = try makeAdapter()
    a.reset()
    _ = a.step("env_perm", ["v": true])
    assertPartial(a.observe(), ["step": 0, "saved": 0, "done": false, "open": true, "dir": false, "perm": true, "wFile": false, "oll": false, "sFile": false, "wSel": false, "sSel": false, "skip": false, "cDir": false, "cPerm": false, "cW": false, "cS": false, "cSkip": false, "wdl": 0, "sdl": 0, "okAtDone": false, "bounced": false, "pickedWhileClosed": false])
    _ = a.step("env_wfile", ["v": true])
    assertPartial(a.observe(), ["step": 0, "saved": 0, "done": false, "open": true, "dir": false, "perm": true, "wFile": true, "oll": false, "sFile": false, "wSel": false, "sSel": false, "skip": false, "cDir": false, "cPerm": false, "cW": false, "cS": false, "cSkip": false, "wdl": 0, "sdl": 0, "okAtDone": false, "bounced": false, "pickedWhileClosed": false])
    _ = a.step("forward", [String: Any]())
    assertPartial(a.observe(), ["step": 1, "saved": 1, "done": false, "open": true, "dir": false, "perm": true, "wFile": true, "oll": false, "sFile": false, "wSel": false, "sSel": false, "skip": false, "cDir": false, "cPerm": false, "cW": false, "cS": false, "cSkip": false, "wdl": 0, "sdl": 0, "okAtDone": false, "bounced": false, "pickedWhileClosed": false])
    _ = a.step("set_dir", [String: Any]())
    assertPartial(a.observe(), ["step": 1, "saved": 1, "done": false, "open": true, "dir": true, "perm": true, "wFile": true, "oll": false, "sFile": false, "wSel": false, "sSel": false, "skip": false, "cDir": true, "cPerm": false, "cW": false, "cS": false, "cSkip": false, "wdl": 0, "sdl": 0, "okAtDone": false, "bounced": false, "pickedWhileClosed": false])
    _ = a.step("forward", [String: Any]())
    assertPartial(a.observe(), ["step": 2, "saved": 2, "done": false, "open": true, "dir": true, "perm": true, "wFile": true, "oll": false, "sFile": false, "wSel": false, "sSel": false, "skip": false, "cDir": true, "cPerm": false, "cW": false, "cS": false, "cSkip": false, "wdl": 0, "sdl": 0, "okAtDone": false, "bounced": false, "pickedWhileClosed": false])
    _ = a.step("close_window", [String: Any]())
    assertPartial(a.observe(), ["step": 0, "saved": 2, "done": false, "open": false, "dir": true, "perm": true, "wFile": true, "oll": false, "sFile": false, "wSel": false, "sSel": false, "skip": false, "cDir": false, "cPerm": false, "cW": false, "cS": false, "cSkip": false, "wdl": 0, "sdl": 0, "okAtDone": false, "bounced": false, "pickedWhileClosed": false])
    _ = a.step("reopen", [String: Any]())
    assertPartial(a.observe(), ["step": 2, "saved": 2, "done": false, "open": true, "dir": true, "perm": true, "wFile": true, "oll": false, "sFile": false, "wSel": true, "sSel": false, "skip": false, "cDir": true, "cPerm": true, "cW": true, "cS": false, "cSkip": false, "wdl": 0, "sdl": 0, "okAtDone": false, "bounced": false, "pickedWhileClosed": false])
    _ = a.step("forward", [String: Any]())
    assertPartial(a.observe(), ["step": 3, "saved": 3, "done": false, "open": true, "dir": true, "perm": true, "wFile": true, "oll": false, "sFile": false, "wSel": true, "sSel": false, "skip": false, "cDir": true, "cPerm": true, "cW": true, "cS": false, "cSkip": false, "wdl": 0, "sdl": 0, "okAtDone": false, "bounced": false, "pickedWhileClosed": false])
    _ = a.step("forward", [String: Any]())
    assertPartial(a.observe(), ["step": 4, "saved": 4, "done": false, "open": true, "dir": true, "perm": true, "wFile": true, "oll": false, "sFile": false, "wSel": true, "sSel": false, "skip": false, "cDir": true, "cPerm": true, "cW": true, "cS": false, "cSkip": false, "wdl": 0, "sdl": 0, "okAtDone": false, "bounced": false, "pickedWhileClosed": false])
    _ = a.step("skip_summary", [String: Any]())
    assertPartial(a.observe(), ["step": 5, "saved": 5, "done": false, "open": true, "dir": true, "perm": true, "wFile": true, "oll": false, "sFile": false, "wSel": true, "sSel": false, "skip": true, "cDir": true, "cPerm": true, "cW": true, "cS": false, "cSkip": true, "wdl": 0, "sdl": 0, "okAtDone": false, "bounced": false, "pickedWhileClosed": false])
    _ = a.step("complete", [String: Any]())
    assertPartial(a.observe(), ["step": 5, "saved": 0, "done": true, "open": false, "dir": true, "perm": true, "wFile": true, "oll": false, "sFile": false, "wSel": true, "sSel": false, "skip": true, "cDir": true, "cPerm": true, "cW": true, "cS": false, "cSkip": true, "wdl": 0, "sdl": 0, "okAtDone": true, "bounced": false, "pickedWhileClosed": false])
}

@Test func scenario_reach_BouncedToMissingStep() throws {
    let a = try makeAdapter()
    a.reset()
    _ = a.step("env_perm", ["v": true])
    assertPartial(a.observe(), ["step": 0, "saved": 0, "done": false, "open": true, "dir": false, "perm": true, "wFile": false, "oll": false, "sFile": false, "wSel": false, "sSel": false, "skip": false, "cDir": false, "cPerm": false, "cW": false, "cS": false, "cSkip": false, "wdl": 0, "sdl": 0, "okAtDone": false, "bounced": false, "pickedWhileClosed": false])
    _ = a.step("env_wfile", ["v": true])
    assertPartial(a.observe(), ["step": 0, "saved": 0, "done": false, "open": true, "dir": false, "perm": true, "wFile": true, "oll": false, "sFile": false, "wSel": false, "sSel": false, "skip": false, "cDir": false, "cPerm": false, "cW": false, "cS": false, "cSkip": false, "wdl": 0, "sdl": 0, "okAtDone": false, "bounced": false, "pickedWhileClosed": false])
    _ = a.step("forward", [String: Any]())
    assertPartial(a.observe(), ["step": 1, "saved": 1, "done": false, "open": true, "dir": false, "perm": true, "wFile": true, "oll": false, "sFile": false, "wSel": false, "sSel": false, "skip": false, "cDir": false, "cPerm": false, "cW": false, "cS": false, "cSkip": false, "wdl": 0, "sdl": 0, "okAtDone": false, "bounced": false, "pickedWhileClosed": false])
    _ = a.step("set_dir", [String: Any]())
    assertPartial(a.observe(), ["step": 1, "saved": 1, "done": false, "open": true, "dir": true, "perm": true, "wFile": true, "oll": false, "sFile": false, "wSel": false, "sSel": false, "skip": false, "cDir": true, "cPerm": false, "cW": false, "cS": false, "cSkip": false, "wdl": 0, "sdl": 0, "okAtDone": false, "bounced": false, "pickedWhileClosed": false])
    _ = a.step("env_remove_dir", [String: Any]())
    assertPartial(a.observe(), ["step": 1, "saved": 1, "done": false, "open": true, "dir": false, "perm": true, "wFile": true, "oll": false, "sFile": false, "wSel": false, "sSel": false, "skip": false, "cDir": true, "cPerm": false, "cW": false, "cS": false, "cSkip": false, "wdl": 0, "sdl": 0, "okAtDone": false, "bounced": false, "pickedWhileClosed": false])
    _ = a.step("forward", [String: Any]())
    assertPartial(a.observe(), ["step": 2, "saved": 2, "done": false, "open": true, "dir": false, "perm": true, "wFile": true, "oll": false, "sFile": false, "wSel": false, "sSel": false, "skip": false, "cDir": true, "cPerm": false, "cW": false, "cS": false, "cSkip": false, "wdl": 0, "sdl": 0, "okAtDone": false, "bounced": false, "pickedWhileClosed": false])
    _ = a.step("close_window", [String: Any]())
    assertPartial(a.observe(), ["step": 0, "saved": 2, "done": false, "open": false, "dir": false, "perm": true, "wFile": true, "oll": false, "sFile": false, "wSel": false, "sSel": false, "skip": false, "cDir": false, "cPerm": false, "cW": false, "cS": false, "cSkip": false, "wdl": 0, "sdl": 0, "okAtDone": false, "bounced": false, "pickedWhileClosed": false])
    _ = a.step("reopen", [String: Any]())
    assertPartial(a.observe(), ["step": 2, "saved": 2, "done": false, "open": true, "dir": false, "perm": true, "wFile": true, "oll": false, "sFile": false, "wSel": true, "sSel": false, "skip": false, "cDir": false, "cPerm": true, "cW": true, "cS": false, "cSkip": false, "wdl": 0, "sdl": 0, "okAtDone": false, "bounced": false, "pickedWhileClosed": false])
    _ = a.step("forward", [String: Any]())
    assertPartial(a.observe(), ["step": 3, "saved": 3, "done": false, "open": true, "dir": false, "perm": true, "wFile": true, "oll": false, "sFile": false, "wSel": true, "sSel": false, "skip": false, "cDir": false, "cPerm": true, "cW": true, "cS": false, "cSkip": false, "wdl": 0, "sdl": 0, "okAtDone": false, "bounced": false, "pickedWhileClosed": false])
    _ = a.step("forward", [String: Any]())
    assertPartial(a.observe(), ["step": 4, "saved": 4, "done": false, "open": true, "dir": false, "perm": true, "wFile": true, "oll": false, "sFile": false, "wSel": true, "sSel": false, "skip": false, "cDir": false, "cPerm": true, "cW": true, "cS": false, "cSkip": false, "wdl": 0, "sdl": 0, "okAtDone": false, "bounced": false, "pickedWhileClosed": false])
    _ = a.step("skip_summary", [String: Any]())
    assertPartial(a.observe(), ["step": 5, "saved": 5, "done": false, "open": true, "dir": false, "perm": true, "wFile": true, "oll": false, "sFile": false, "wSel": true, "sSel": false, "skip": true, "cDir": false, "cPerm": true, "cW": true, "cS": false, "cSkip": true, "wdl": 0, "sdl": 0, "okAtDone": false, "bounced": false, "pickedWhileClosed": false])
    _ = a.step("complete", [String: Any]())
    assertPartial(a.observe(), ["step": 1, "saved": 1, "done": false, "open": true, "dir": false, "perm": true, "wFile": true, "oll": false, "sFile": false, "wSel": true, "sSel": false, "skip": true, "cDir": false, "cPerm": true, "cW": true, "cS": false, "cSkip": true, "wdl": 0, "sdl": 0, "okAtDone": false, "bounced": true, "pickedWhileClosed": false])
}

@Test func scenario_reach_DoneAfterKeptDownload() throws {
    let a = try makeAdapter()
    a.reset()
    _ = a.step("forward", [String: Any]())
    assertPartial(a.observe(), ["step": 1, "saved": 1, "done": false, "open": true, "dir": false, "perm": false, "wFile": false, "oll": false, "sFile": false, "wSel": false, "sSel": false, "skip": false, "cDir": false, "cPerm": false, "cW": false, "cS": false, "cSkip": false, "wdl": 0, "sdl": 0, "okAtDone": false, "bounced": false, "pickedWhileClosed": false])
    _ = a.step("set_dir", [String: Any]())
    assertPartial(a.observe(), ["step": 1, "saved": 1, "done": false, "open": true, "dir": true, "perm": false, "wFile": false, "oll": false, "sFile": false, "wSel": false, "sSel": false, "skip": false, "cDir": true, "cPerm": false, "cW": false, "cS": false, "cSkip": false, "wdl": 0, "sdl": 0, "okAtDone": false, "bounced": false, "pickedWhileClosed": false])
    _ = a.step("env_perm", ["v": true])
    assertPartial(a.observe(), ["step": 1, "saved": 1, "done": false, "open": true, "dir": true, "perm": true, "wFile": false, "oll": false, "sFile": false, "wSel": false, "sSel": false, "skip": false, "cDir": true, "cPerm": false, "cW": false, "cS": false, "cSkip": false, "wdl": 0, "sdl": 0, "okAtDone": false, "bounced": false, "pickedWhileClosed": false])
    _ = a.step("refresh_perm", [String: Any]())
    assertPartial(a.observe(), ["step": 1, "saved": 1, "done": false, "open": true, "dir": true, "perm": true, "wFile": false, "oll": false, "sFile": false, "wSel": false, "sSel": false, "skip": false, "cDir": true, "cPerm": true, "cW": false, "cS": false, "cSkip": false, "wdl": 0, "sdl": 0, "okAtDone": false, "bounced": false, "pickedWhileClosed": false])
    _ = a.step("forward", [String: Any]())
    assertPartial(a.observe(), ["step": 2, "saved": 2, "done": false, "open": true, "dir": true, "perm": true, "wFile": false, "oll": false, "sFile": false, "wSel": false, "sSel": false, "skip": false, "cDir": true, "cPerm": true, "cW": false, "cS": false, "cSkip": false, "wdl": 0, "sdl": 0, "okAtDone": false, "bounced": false, "pickedWhileClosed": false])
    _ = a.step("forward", [String: Any]())
    assertPartial(a.observe(), ["step": 3, "saved": 3, "done": false, "open": true, "dir": true, "perm": true, "wFile": false, "oll": false, "sFile": false, "wSel": false, "sSel": false, "skip": false, "cDir": true, "cPerm": true, "cW": false, "cS": false, "cSkip": false, "wdl": 0, "sdl": 0, "okAtDone": false, "bounced": false, "pickedWhileClosed": false])
    _ = a.step("start_wdl", [String: Any]())
    assertPartial(a.observe(), ["step": 3, "saved": 3, "done": false, "open": true, "dir": true, "perm": true, "wFile": false, "oll": false, "sFile": false, "wSel": false, "sSel": false, "skip": false, "cDir": true, "cPerm": true, "cW": false, "cS": false, "cSkip": false, "wdl": 1, "sdl": 0, "okAtDone": false, "bounced": false, "pickedWhileClosed": false])
    _ = a.step("close_window", [String: Any]())
    assertPartial(a.observe(), ["step": 0, "saved": 3, "done": false, "open": false, "dir": true, "perm": true, "wFile": false, "oll": false, "sFile": false, "wSel": false, "sSel": false, "skip": false, "cDir": false, "cPerm": false, "cW": false, "cS": false, "cSkip": false, "wdl": 1, "sdl": 0, "okAtDone": false, "bounced": false, "pickedWhileClosed": false])
    _ = a.step("finish_wdl", ["ok": true])
    assertPartial(a.observe(), ["step": 0, "saved": 3, "done": false, "open": false, "dir": true, "perm": true, "wFile": true, "oll": false, "sFile": false, "wSel": true, "sSel": false, "skip": false, "cDir": false, "cPerm": false, "cW": false, "cS": false, "cSkip": false, "wdl": 0, "sdl": 0, "okAtDone": false, "bounced": false, "pickedWhileClosed": true])
    _ = a.step("reopen", [String: Any]())
    assertPartial(a.observe(), ["step": 3, "saved": 3, "done": false, "open": true, "dir": true, "perm": true, "wFile": true, "oll": false, "sFile": false, "wSel": true, "sSel": false, "skip": false, "cDir": true, "cPerm": true, "cW": true, "cS": false, "cSkip": false, "wdl": 0, "sdl": 0, "okAtDone": false, "bounced": false, "pickedWhileClosed": true])
    _ = a.step("forward", [String: Any]())
    assertPartial(a.observe(), ["step": 4, "saved": 4, "done": false, "open": true, "dir": true, "perm": true, "wFile": true, "oll": false, "sFile": false, "wSel": true, "sSel": false, "skip": false, "cDir": true, "cPerm": true, "cW": true, "cS": false, "cSkip": false, "wdl": 0, "sdl": 0, "okAtDone": false, "bounced": false, "pickedWhileClosed": true])
    _ = a.step("skip_summary", [String: Any]())
    assertPartial(a.observe(), ["step": 5, "saved": 5, "done": false, "open": true, "dir": true, "perm": true, "wFile": true, "oll": false, "sFile": false, "wSel": true, "sSel": false, "skip": true, "cDir": true, "cPerm": true, "cW": true, "cS": false, "cSkip": true, "wdl": 0, "sdl": 0, "okAtDone": false, "bounced": false, "pickedWhileClosed": true])
    _ = a.step("complete", [String: Any]())
    assertPartial(a.observe(), ["step": 5, "saved": 0, "done": true, "open": false, "dir": true, "perm": true, "wFile": true, "oll": false, "sFile": false, "wSel": true, "sSel": false, "skip": true, "cDir": true, "cPerm": true, "cW": true, "cS": false, "cSkip": true, "wdl": 0, "sdl": 0, "okAtDone": true, "bounced": false, "pickedWhileClosed": true])
}

@Test func scenario_reach_DoneWithoutSummary() throws {
    let a = try makeAdapter()
    a.reset()
    _ = a.step("forward", [String: Any]())
    assertPartial(a.observe(), ["step": 1, "saved": 1, "done": false, "open": true, "dir": false, "perm": false, "wFile": false, "oll": false, "sFile": false, "wSel": false, "sSel": false, "skip": false, "cDir": false, "cPerm": false, "cW": false, "cS": false, "cSkip": false, "wdl": 0, "sdl": 0, "okAtDone": false, "bounced": false, "pickedWhileClosed": false])
    _ = a.step("set_dir", [String: Any]())
    assertPartial(a.observe(), ["step": 1, "saved": 1, "done": false, "open": true, "dir": true, "perm": false, "wFile": false, "oll": false, "sFile": false, "wSel": false, "sSel": false, "skip": false, "cDir": true, "cPerm": false, "cW": false, "cS": false, "cSkip": false, "wdl": 0, "sdl": 0, "okAtDone": false, "bounced": false, "pickedWhileClosed": false])
    _ = a.step("forward", [String: Any]())
    assertPartial(a.observe(), ["step": 2, "saved": 2, "done": false, "open": true, "dir": true, "perm": false, "wFile": false, "oll": false, "sFile": false, "wSel": false, "sSel": false, "skip": false, "cDir": true, "cPerm": false, "cW": false, "cS": false, "cSkip": false, "wdl": 0, "sdl": 0, "okAtDone": false, "bounced": false, "pickedWhileClosed": false])
    _ = a.step("env_perm", ["v": true])
    assertPartial(a.observe(), ["step": 2, "saved": 2, "done": false, "open": true, "dir": true, "perm": true, "wFile": false, "oll": false, "sFile": false, "wSel": false, "sSel": false, "skip": false, "cDir": true, "cPerm": false, "cW": false, "cS": false, "cSkip": false, "wdl": 0, "sdl": 0, "okAtDone": false, "bounced": false, "pickedWhileClosed": false])
    _ = a.step("env_wfile", ["v": true])
    assertPartial(a.observe(), ["step": 2, "saved": 2, "done": false, "open": true, "dir": true, "perm": true, "wFile": true, "oll": false, "sFile": false, "wSel": false, "sSel": false, "skip": false, "cDir": true, "cPerm": false, "cW": false, "cS": false, "cSkip": false, "wdl": 0, "sdl": 0, "okAtDone": false, "bounced": false, "pickedWhileClosed": false])
    _ = a.step("quit_app", [String: Any]())
    assertPartial(a.observe(), ["step": 0, "saved": 2, "done": false, "open": false, "dir": true, "perm": true, "wFile": true, "oll": false, "sFile": false, "wSel": false, "sSel": false, "skip": false, "cDir": false, "cPerm": false, "cW": false, "cS": false, "cSkip": false, "wdl": 0, "sdl": 0, "okAtDone": false, "bounced": false, "pickedWhileClosed": false])
    _ = a.step("reopen", [String: Any]())
    assertPartial(a.observe(), ["step": 2, "saved": 2, "done": false, "open": true, "dir": true, "perm": true, "wFile": true, "oll": false, "sFile": false, "wSel": true, "sSel": false, "skip": false, "cDir": true, "cPerm": true, "cW": true, "cS": false, "cSkip": false, "wdl": 0, "sdl": 0, "okAtDone": false, "bounced": false, "pickedWhileClosed": false])
    _ = a.step("forward", [String: Any]())
    assertPartial(a.observe(), ["step": 3, "saved": 3, "done": false, "open": true, "dir": true, "perm": true, "wFile": true, "oll": false, "sFile": false, "wSel": true, "sSel": false, "skip": false, "cDir": true, "cPerm": true, "cW": true, "cS": false, "cSkip": false, "wdl": 0, "sdl": 0, "okAtDone": false, "bounced": false, "pickedWhileClosed": false])
    _ = a.step("forward", [String: Any]())
    assertPartial(a.observe(), ["step": 4, "saved": 4, "done": false, "open": true, "dir": true, "perm": true, "wFile": true, "oll": false, "sFile": false, "wSel": true, "sSel": false, "skip": false, "cDir": true, "cPerm": true, "cW": true, "cS": false, "cSkip": false, "wdl": 0, "sdl": 0, "okAtDone": false, "bounced": false, "pickedWhileClosed": false])
    _ = a.step("skip_summary", [String: Any]())
    assertPartial(a.observe(), ["step": 5, "saved": 5, "done": false, "open": true, "dir": true, "perm": true, "wFile": true, "oll": false, "sFile": false, "wSel": true, "sSel": false, "skip": true, "cDir": true, "cPerm": true, "cW": true, "cS": false, "cSkip": true, "wdl": 0, "sdl": 0, "okAtDone": false, "bounced": false, "pickedWhileClosed": false])
    _ = a.step("complete", [String: Any]())
    assertPartial(a.observe(), ["step": 5, "saved": 0, "done": true, "open": false, "dir": true, "perm": true, "wFile": true, "oll": false, "sFile": false, "wSel": true, "sSel": false, "skip": true, "cDir": true, "cPerm": true, "cW": true, "cS": false, "cSkip": true, "wdl": 0, "sdl": 0, "okAtDone": true, "bounced": false, "pickedWhileClosed": false])
}

@Test func randomWalkConformance() throws {
    // random-walk conformance (baked oracle trace)
    let a = try makeAdapter()
    a.reset()
    let initial: [String: Any] = ["step": 0, "saved": 0, "done": false, "open": true, "dir": false, "perm": false, "wFile": false, "oll": false, "sFile": false, "wSel": false, "sSel": false, "skip": false, "cDir": false, "cPerm": false, "cW": false, "cS": false, "cSkip": false, "wdl": 0, "sdl": 0, "okAtDone": false, "bounced": false, "pickedWhileClosed": false]
    assertPartial(a.observe(), initial)
    let walk: [(action: String, params: [String: Any], expected: [String: Any])] = [
        (action: "env_smodel", params: ["v": false], expected: ["step": 0, "saved": 0, "done": false, "open": true, "dir": false, "perm": false, "wFile": false, "oll": false, "sFile": false, "wSel": false, "sSel": false, "skip": false, "cDir": false, "cPerm": false, "cW": false, "cS": false, "cSkip": false, "wdl": 0, "sdl": 0, "okAtDone": false, "bounced": false, "pickedWhileClosed": false]),
        (action: "quit_app", params: [String: Any](), expected: ["step": 0, "saved": 0, "done": false, "open": false, "dir": false, "perm": false, "wFile": false, "oll": false, "sFile": false, "wSel": false, "sSel": false, "skip": false, "cDir": false, "cPerm": false, "cW": false, "cS": false, "cSkip": false, "wdl": 0, "sdl": 0, "okAtDone": false, "bounced": false, "pickedWhileClosed": false]),
        (action: "env_smodel", params: ["v": false], expected: ["step": 0, "saved": 0, "done": false, "open": false, "dir": false, "perm": false, "wFile": false, "oll": false, "sFile": false, "wSel": false, "sSel": false, "skip": false, "cDir": false, "cPerm": false, "cW": false, "cS": false, "cSkip": false, "wdl": 0, "sdl": 0, "okAtDone": false, "bounced": false, "pickedWhileClosed": false]),
        (action: "env_perm", params: ["v": false], expected: ["step": 0, "saved": 0, "done": false, "open": false, "dir": false, "perm": false, "wFile": false, "oll": false, "sFile": false, "wSel": false, "sSel": false, "skip": false, "cDir": false, "cPerm": false, "cW": false, "cS": false, "cSkip": false, "wdl": 0, "sdl": 0, "okAtDone": false, "bounced": false, "pickedWhileClosed": false]),
        (action: "env_ollama", params: ["v": false], expected: ["step": 0, "saved": 0, "done": false, "open": false, "dir": false, "perm": false, "wFile": false, "oll": false, "sFile": false, "wSel": false, "sSel": false, "skip": false, "cDir": false, "cPerm": false, "cW": false, "cS": false, "cSkip": false, "wdl": 0, "sdl": 0, "okAtDone": false, "bounced": false, "pickedWhileClosed": false]),
        (action: "quit_app", params: [String: Any](), expected: ["step": 0, "saved": 0, "done": false, "open": false, "dir": false, "perm": false, "wFile": false, "oll": false, "sFile": false, "wSel": false, "sSel": false, "skip": false, "cDir": false, "cPerm": false, "cW": false, "cS": false, "cSkip": false, "wdl": 0, "sdl": 0, "okAtDone": false, "bounced": false, "pickedWhileClosed": false]),
        (action: "env_smodel", params: ["v": true], expected: ["step": 0, "saved": 0, "done": false, "open": false, "dir": false, "perm": false, "wFile": false, "oll": false, "sFile": true, "wSel": false, "sSel": false, "skip": false, "cDir": false, "cPerm": false, "cW": false, "cS": false, "cSkip": false, "wdl": 0, "sdl": 0, "okAtDone": false, "bounced": false, "pickedWhileClosed": false]),
        (action: "env_smodel", params: ["v": false], expected: ["step": 0, "saved": 0, "done": false, "open": false, "dir": false, "perm": false, "wFile": false, "oll": false, "sFile": false, "wSel": false, "sSel": false, "skip": false, "cDir": false, "cPerm": false, "cW": false, "cS": false, "cSkip": false, "wdl": 0, "sdl": 0, "okAtDone": false, "bounced": false, "pickedWhileClosed": false]),
        (action: "env_ollama", params: ["v": false], expected: ["step": 0, "saved": 0, "done": false, "open": false, "dir": false, "perm": false, "wFile": false, "oll": false, "sFile": false, "wSel": false, "sSel": false, "skip": false, "cDir": false, "cPerm": false, "cW": false, "cS": false, "cSkip": false, "wdl": 0, "sdl": 0, "okAtDone": false, "bounced": false, "pickedWhileClosed": false]),
        (action: "env_smodel", params: ["v": true], expected: ["step": 0, "saved": 0, "done": false, "open": false, "dir": false, "perm": false, "wFile": false, "oll": false, "sFile": true, "wSel": false, "sSel": false, "skip": false, "cDir": false, "cPerm": false, "cW": false, "cS": false, "cSkip": false, "wdl": 0, "sdl": 0, "okAtDone": false, "bounced": false, "pickedWhileClosed": false]),
        (action: "env_ollama", params: ["v": true], expected: ["step": 0, "saved": 0, "done": false, "open": false, "dir": false, "perm": false, "wFile": false, "oll": true, "sFile": true, "wSel": false, "sSel": false, "skip": false, "cDir": false, "cPerm": false, "cW": false, "cS": false, "cSkip": false, "wdl": 0, "sdl": 0, "okAtDone": false, "bounced": false, "pickedWhileClosed": false]),
        (action: "reopen", params: [String: Any](), expected: ["step": 0, "saved": 0, "done": false, "open": true, "dir": false, "perm": false, "wFile": false, "oll": true, "sFile": true, "wSel": false, "sSel": true, "skip": false, "cDir": false, "cPerm": false, "cW": false, "cS": true, "cSkip": false, "wdl": 0, "sdl": 0, "okAtDone": false, "bounced": false, "pickedWhileClosed": false]),
        (action: "env_wfile", params: ["v": true], expected: ["step": 0, "saved": 0, "done": false, "open": true, "dir": false, "perm": false, "wFile": true, "oll": true, "sFile": true, "wSel": false, "sSel": true, "skip": false, "cDir": false, "cPerm": false, "cW": false, "cS": true, "cSkip": false, "wdl": 0, "sdl": 0, "okAtDone": false, "bounced": false, "pickedWhileClosed": false]),
        (action: "refresh_perm", params: [String: Any](), expected: ["step": 0, "saved": 0, "done": false, "open": true, "dir": false, "perm": false, "wFile": true, "oll": true, "sFile": true, "wSel": false, "sSel": true, "skip": false, "cDir": false, "cPerm": false, "cW": false, "cS": true, "cSkip": false, "wdl": 0, "sdl": 0, "okAtDone": false, "bounced": false, "pickedWhileClosed": false]),
        (action: "env_wfile", params: ["v": false], expected: ["step": 0, "saved": 0, "done": false, "open": true, "dir": false, "perm": false, "wFile": false, "oll": true, "sFile": true, "wSel": false, "sSel": true, "skip": false, "cDir": false, "cPerm": false, "cW": false, "cS": true, "cSkip": false, "wdl": 0, "sdl": 0, "okAtDone": false, "bounced": false, "pickedWhileClosed": false]),
        (action: "env_ollama", params: ["v": false], expected: ["step": 0, "saved": 0, "done": false, "open": true, "dir": false, "perm": false, "wFile": false, "oll": false, "sFile": true, "wSel": false, "sSel": true, "skip": false, "cDir": false, "cPerm": false, "cW": false, "cS": true, "cSkip": false, "wdl": 0, "sdl": 0, "okAtDone": false, "bounced": false, "pickedWhileClosed": false]),
        (action: "env_wfile", params: ["v": false], expected: ["step": 0, "saved": 0, "done": false, "open": true, "dir": false, "perm": false, "wFile": false, "oll": false, "sFile": true, "wSel": false, "sSel": true, "skip": false, "cDir": false, "cPerm": false, "cW": false, "cS": true, "cSkip": false, "wdl": 0, "sdl": 0, "okAtDone": false, "bounced": false, "pickedWhileClosed": false]),
        (action: "quit_app", params: [String: Any](), expected: ["step": 0, "saved": 0, "done": false, "open": false, "dir": false, "perm": false, "wFile": false, "oll": false, "sFile": true, "wSel": false, "sSel": true, "skip": false, "cDir": false, "cPerm": false, "cW": false, "cS": false, "cSkip": false, "wdl": 0, "sdl": 0, "okAtDone": false, "bounced": false, "pickedWhileClosed": false]),
        (action: "env_perm", params: ["v": true], expected: ["step": 0, "saved": 0, "done": false, "open": false, "dir": false, "perm": true, "wFile": false, "oll": false, "sFile": true, "wSel": false, "sSel": true, "skip": false, "cDir": false, "cPerm": false, "cW": false, "cS": false, "cSkip": false, "wdl": 0, "sdl": 0, "okAtDone": false, "bounced": false, "pickedWhileClosed": false]),
        (action: "reopen", params: [String: Any](), expected: ["step": 0, "saved": 0, "done": false, "open": true, "dir": false, "perm": true, "wFile": false, "oll": false, "sFile": true, "wSel": false, "sSel": true, "skip": false, "cDir": false, "cPerm": true, "cW": false, "cS": false, "cSkip": false, "wdl": 0, "sdl": 0, "okAtDone": false, "bounced": false, "pickedWhileClosed": false]),
        (action: "quit_app", params: [String: Any](), expected: ["step": 0, "saved": 0, "done": false, "open": false, "dir": false, "perm": true, "wFile": false, "oll": false, "sFile": true, "wSel": false, "sSel": true, "skip": false, "cDir": false, "cPerm": false, "cW": false, "cS": false, "cSkip": false, "wdl": 0, "sdl": 0, "okAtDone": false, "bounced": false, "pickedWhileClosed": false]),
        (action: "env_ollama", params: ["v": false], expected: ["step": 0, "saved": 0, "done": false, "open": false, "dir": false, "perm": true, "wFile": false, "oll": false, "sFile": true, "wSel": false, "sSel": true, "skip": false, "cDir": false, "cPerm": false, "cW": false, "cS": false, "cSkip": false, "wdl": 0, "sdl": 0, "okAtDone": false, "bounced": false, "pickedWhileClosed": false]),
        (action: "quit_app", params: [String: Any](), expected: ["step": 0, "saved": 0, "done": false, "open": false, "dir": false, "perm": true, "wFile": false, "oll": false, "sFile": true, "wSel": false, "sSel": true, "skip": false, "cDir": false, "cPerm": false, "cW": false, "cS": false, "cSkip": false, "wdl": 0, "sdl": 0, "okAtDone": false, "bounced": false, "pickedWhileClosed": false]),
        (action: "reopen", params: [String: Any](), expected: ["step": 0, "saved": 0, "done": false, "open": true, "dir": false, "perm": true, "wFile": false, "oll": false, "sFile": true, "wSel": false, "sSel": true, "skip": false, "cDir": false, "cPerm": true, "cW": false, "cS": false, "cSkip": false, "wdl": 0, "sdl": 0, "okAtDone": false, "bounced": false, "pickedWhileClosed": false]),
        (action: "env_wfile", params: ["v": false], expected: ["step": 0, "saved": 0, "done": false, "open": true, "dir": false, "perm": true, "wFile": false, "oll": false, "sFile": true, "wSel": false, "sSel": true, "skip": false, "cDir": false, "cPerm": true, "cW": false, "cS": false, "cSkip": false, "wdl": 0, "sdl": 0, "okAtDone": false, "bounced": false, "pickedWhileClosed": false]),
        (action: "env_ollama", params: ["v": false], expected: ["step": 0, "saved": 0, "done": false, "open": true, "dir": false, "perm": true, "wFile": false, "oll": false, "sFile": true, "wSel": false, "sSel": true, "skip": false, "cDir": false, "cPerm": true, "cW": false, "cS": false, "cSkip": false, "wdl": 0, "sdl": 0, "okAtDone": false, "bounced": false, "pickedWhileClosed": false]),
        (action: "env_perm", params: ["v": true], expected: ["step": 0, "saved": 0, "done": false, "open": true, "dir": false, "perm": true, "wFile": false, "oll": false, "sFile": true, "wSel": false, "sSel": true, "skip": false, "cDir": false, "cPerm": true, "cW": false, "cS": false, "cSkip": false, "wdl": 0, "sdl": 0, "okAtDone": false, "bounced": false, "pickedWhileClosed": false]),
        (action: "close_window", params: [String: Any](), expected: ["step": 0, "saved": 0, "done": false, "open": false, "dir": false, "perm": true, "wFile": false, "oll": false, "sFile": true, "wSel": false, "sSel": true, "skip": false, "cDir": false, "cPerm": false, "cW": false, "cS": false, "cSkip": false, "wdl": 0, "sdl": 0, "okAtDone": false, "bounced": false, "pickedWhileClosed": false]),
        (action: "env_perm", params: ["v": true], expected: ["step": 0, "saved": 0, "done": false, "open": false, "dir": false, "perm": true, "wFile": false, "oll": false, "sFile": true, "wSel": false, "sSel": true, "skip": false, "cDir": false, "cPerm": false, "cW": false, "cS": false, "cSkip": false, "wdl": 0, "sdl": 0, "okAtDone": false, "bounced": false, "pickedWhileClosed": false]),
        (action: "env_ollama", params: ["v": true], expected: ["step": 0, "saved": 0, "done": false, "open": false, "dir": false, "perm": true, "wFile": false, "oll": true, "sFile": true, "wSel": false, "sSel": true, "skip": false, "cDir": false, "cPerm": false, "cW": false, "cS": false, "cSkip": false, "wdl": 0, "sdl": 0, "okAtDone": false, "bounced": false, "pickedWhileClosed": false]),
        (action: "env_smodel", params: ["v": true], expected: ["step": 0, "saved": 0, "done": false, "open": false, "dir": false, "perm": true, "wFile": false, "oll": true, "sFile": true, "wSel": false, "sSel": true, "skip": false, "cDir": false, "cPerm": false, "cW": false, "cS": false, "cSkip": false, "wdl": 0, "sdl": 0, "okAtDone": false, "bounced": false, "pickedWhileClosed": false]),
        (action: "quit_app", params: [String: Any](), expected: ["step": 0, "saved": 0, "done": false, "open": false, "dir": false, "perm": true, "wFile": false, "oll": true, "sFile": true, "wSel": false, "sSel": true, "skip": false, "cDir": false, "cPerm": false, "cW": false, "cS": false, "cSkip": false, "wdl": 0, "sdl": 0, "okAtDone": false, "bounced": false, "pickedWhileClosed": false]),
        (action: "env_perm", params: ["v": true], expected: ["step": 0, "saved": 0, "done": false, "open": false, "dir": false, "perm": true, "wFile": false, "oll": true, "sFile": true, "wSel": false, "sSel": true, "skip": false, "cDir": false, "cPerm": false, "cW": false, "cS": false, "cSkip": false, "wdl": 0, "sdl": 0, "okAtDone": false, "bounced": false, "pickedWhileClosed": false]),
        (action: "env_ollama", params: ["v": true], expected: ["step": 0, "saved": 0, "done": false, "open": false, "dir": false, "perm": true, "wFile": false, "oll": true, "sFile": true, "wSel": false, "sSel": true, "skip": false, "cDir": false, "cPerm": false, "cW": false, "cS": false, "cSkip": false, "wdl": 0, "sdl": 0, "okAtDone": false, "bounced": false, "pickedWhileClosed": false]),
        (action: "env_smodel", params: ["v": false], expected: ["step": 0, "saved": 0, "done": false, "open": false, "dir": false, "perm": true, "wFile": false, "oll": true, "sFile": false, "wSel": false, "sSel": true, "skip": false, "cDir": false, "cPerm": false, "cW": false, "cS": false, "cSkip": false, "wdl": 0, "sdl": 0, "okAtDone": false, "bounced": false, "pickedWhileClosed": false]),
        (action: "env_ollama", params: ["v": true], expected: ["step": 0, "saved": 0, "done": false, "open": false, "dir": false, "perm": true, "wFile": false, "oll": true, "sFile": false, "wSel": false, "sSel": true, "skip": false, "cDir": false, "cPerm": false, "cW": false, "cS": false, "cSkip": false, "wdl": 0, "sdl": 0, "okAtDone": false, "bounced": false, "pickedWhileClosed": false]),
        (action: "reopen", params: [String: Any](), expected: ["step": 0, "saved": 0, "done": false, "open": true, "dir": false, "perm": true, "wFile": false, "oll": true, "sFile": false, "wSel": false, "sSel": true, "skip": false, "cDir": false, "cPerm": true, "cW": false, "cS": false, "cSkip": false, "wdl": 0, "sdl": 0, "okAtDone": false, "bounced": false, "pickedWhileClosed": false]),
        (action: "refresh_ollama", params: [String: Any](), expected: ["step": 0, "saved": 0, "done": false, "open": true, "dir": false, "perm": true, "wFile": false, "oll": true, "sFile": false, "wSel": false, "sSel": true, "skip": false, "cDir": false, "cPerm": true, "cW": false, "cS": false, "cSkip": false, "wdl": 0, "sdl": 0, "okAtDone": false, "bounced": false, "pickedWhileClosed": false]),
        (action: "env_wfile", params: ["v": true], expected: ["step": 0, "saved": 0, "done": false, "open": true, "dir": false, "perm": true, "wFile": true, "oll": true, "sFile": false, "wSel": false, "sSel": true, "skip": false, "cDir": false, "cPerm": true, "cW": false, "cS": false, "cSkip": false, "wdl": 0, "sdl": 0, "okAtDone": false, "bounced": false, "pickedWhileClosed": false]),
        (action: "refresh_perm", params: [String: Any](), expected: ["step": 0, "saved": 0, "done": false, "open": true, "dir": false, "perm": true, "wFile": true, "oll": true, "sFile": false, "wSel": false, "sSel": true, "skip": false, "cDir": false, "cPerm": true, "cW": false, "cS": false, "cSkip": false, "wdl": 0, "sdl": 0, "okAtDone": false, "bounced": false, "pickedWhileClosed": false]),
        (action: "env_smodel", params: ["v": true], expected: ["step": 0, "saved": 0, "done": false, "open": true, "dir": false, "perm": true, "wFile": true, "oll": true, "sFile": true, "wSel": false, "sSel": true, "skip": false, "cDir": false, "cPerm": true, "cW": false, "cS": false, "cSkip": false, "wdl": 0, "sdl": 0, "okAtDone": false, "bounced": false, "pickedWhileClosed": false]),
        (action: "env_smodel", params: ["v": true], expected: ["step": 0, "saved": 0, "done": false, "open": true, "dir": false, "perm": true, "wFile": true, "oll": true, "sFile": true, "wSel": false, "sSel": true, "skip": false, "cDir": false, "cPerm": true, "cW": false, "cS": false, "cSkip": false, "wdl": 0, "sdl": 0, "okAtDone": false, "bounced": false, "pickedWhileClosed": false]),
        (action: "refresh_perm", params: [String: Any](), expected: ["step": 0, "saved": 0, "done": false, "open": true, "dir": false, "perm": true, "wFile": true, "oll": true, "sFile": true, "wSel": false, "sSel": true, "skip": false, "cDir": false, "cPerm": true, "cW": false, "cS": false, "cSkip": false, "wdl": 0, "sdl": 0, "okAtDone": false, "bounced": false, "pickedWhileClosed": false]),
        (action: "env_ollama", params: ["v": false], expected: ["step": 0, "saved": 0, "done": false, "open": true, "dir": false, "perm": true, "wFile": true, "oll": false, "sFile": true, "wSel": false, "sSel": true, "skip": false, "cDir": false, "cPerm": true, "cW": false, "cS": false, "cSkip": false, "wdl": 0, "sdl": 0, "okAtDone": false, "bounced": false, "pickedWhileClosed": false]),
        (action: "env_perm", params: ["v": false], expected: ["step": 0, "saved": 0, "done": false, "open": true, "dir": false, "perm": false, "wFile": true, "oll": false, "sFile": true, "wSel": false, "sSel": true, "skip": false, "cDir": false, "cPerm": true, "cW": false, "cS": false, "cSkip": false, "wdl": 0, "sdl": 0, "okAtDone": false, "bounced": false, "pickedWhileClosed": false]),
        (action: "quit_app", params: [String: Any](), expected: ["step": 0, "saved": 0, "done": false, "open": false, "dir": false, "perm": false, "wFile": true, "oll": false, "sFile": true, "wSel": false, "sSel": true, "skip": false, "cDir": false, "cPerm": false, "cW": false, "cS": false, "cSkip": false, "wdl": 0, "sdl": 0, "okAtDone": false, "bounced": false, "pickedWhileClosed": false]),
        (action: "quit_app", params: [String: Any](), expected: ["step": 0, "saved": 0, "done": false, "open": false, "dir": false, "perm": false, "wFile": true, "oll": false, "sFile": true, "wSel": false, "sSel": true, "skip": false, "cDir": false, "cPerm": false, "cW": false, "cS": false, "cSkip": false, "wdl": 0, "sdl": 0, "okAtDone": false, "bounced": false, "pickedWhileClosed": false]),
        (action: "env_perm", params: ["v": false], expected: ["step": 0, "saved": 0, "done": false, "open": false, "dir": false, "perm": false, "wFile": true, "oll": false, "sFile": true, "wSel": false, "sSel": true, "skip": false, "cDir": false, "cPerm": false, "cW": false, "cS": false, "cSkip": false, "wdl": 0, "sdl": 0, "okAtDone": false, "bounced": false, "pickedWhileClosed": false]),
        (action: "env_perm", params: ["v": true], expected: ["step": 0, "saved": 0, "done": false, "open": false, "dir": false, "perm": true, "wFile": true, "oll": false, "sFile": true, "wSel": false, "sSel": true, "skip": false, "cDir": false, "cPerm": false, "cW": false, "cS": false, "cSkip": false, "wdl": 0, "sdl": 0, "okAtDone": false, "bounced": false, "pickedWhileClosed": false]),
        (action: "env_smodel", params: ["v": false], expected: ["step": 0, "saved": 0, "done": false, "open": false, "dir": false, "perm": true, "wFile": true, "oll": false, "sFile": false, "wSel": false, "sSel": true, "skip": false, "cDir": false, "cPerm": false, "cW": false, "cS": false, "cSkip": false, "wdl": 0, "sdl": 0, "okAtDone": false, "bounced": false, "pickedWhileClosed": false]),
        (action: "env_perm", params: ["v": false], expected: ["step": 0, "saved": 0, "done": false, "open": false, "dir": false, "perm": false, "wFile": true, "oll": false, "sFile": false, "wSel": false, "sSel": true, "skip": false, "cDir": false, "cPerm": false, "cW": false, "cS": false, "cSkip": false, "wdl": 0, "sdl": 0, "okAtDone": false, "bounced": false, "pickedWhileClosed": false]),
        (action: "reopen", params: [String: Any](), expected: ["step": 0, "saved": 0, "done": false, "open": true, "dir": false, "perm": false, "wFile": true, "oll": false, "sFile": false, "wSel": true, "sSel": true, "skip": false, "cDir": false, "cPerm": false, "cW": true, "cS": false, "cSkip": false, "wdl": 0, "sdl": 0, "okAtDone": false, "bounced": false, "pickedWhileClosed": false]),
        (action: "env_smodel", params: ["v": true], expected: ["step": 0, "saved": 0, "done": false, "open": true, "dir": false, "perm": false, "wFile": true, "oll": false, "sFile": true, "wSel": true, "sSel": true, "skip": false, "cDir": false, "cPerm": false, "cW": true, "cS": false, "cSkip": false, "wdl": 0, "sdl": 0, "okAtDone": false, "bounced": false, "pickedWhileClosed": false]),
        (action: "env_ollama", params: ["v": true], expected: ["step": 0, "saved": 0, "done": false, "open": true, "dir": false, "perm": false, "wFile": true, "oll": true, "sFile": true, "wSel": true, "sSel": true, "skip": false, "cDir": false, "cPerm": false, "cW": true, "cS": false, "cSkip": false, "wdl": 0, "sdl": 0, "okAtDone": false, "bounced": false, "pickedWhileClosed": false]),
        (action: "env_wfile", params: ["v": true], expected: ["step": 0, "saved": 0, "done": false, "open": true, "dir": false, "perm": false, "wFile": true, "oll": true, "sFile": true, "wSel": true, "sSel": true, "skip": false, "cDir": false, "cPerm": false, "cW": true, "cS": false, "cSkip": false, "wdl": 0, "sdl": 0, "okAtDone": false, "bounced": false, "pickedWhileClosed": false]),
        (action: "close_window", params: [String: Any](), expected: ["step": 0, "saved": 0, "done": false, "open": false, "dir": false, "perm": false, "wFile": true, "oll": true, "sFile": true, "wSel": true, "sSel": true, "skip": false, "cDir": false, "cPerm": false, "cW": false, "cS": false, "cSkip": false, "wdl": 0, "sdl": 0, "okAtDone": false, "bounced": false, "pickedWhileClosed": false]),
        (action: "env_ollama", params: ["v": true], expected: ["step": 0, "saved": 0, "done": false, "open": false, "dir": false, "perm": false, "wFile": true, "oll": true, "sFile": true, "wSel": true, "sSel": true, "skip": false, "cDir": false, "cPerm": false, "cW": false, "cS": false, "cSkip": false, "wdl": 0, "sdl": 0, "okAtDone": false, "bounced": false, "pickedWhileClosed": false]),
        (action: "env_perm", params: ["v": true], expected: ["step": 0, "saved": 0, "done": false, "open": false, "dir": false, "perm": true, "wFile": true, "oll": true, "sFile": true, "wSel": true, "sSel": true, "skip": false, "cDir": false, "cPerm": false, "cW": false, "cS": false, "cSkip": false, "wdl": 0, "sdl": 0, "okAtDone": false, "bounced": false, "pickedWhileClosed": false]),
        (action: "env_wfile", params: ["v": true], expected: ["step": 0, "saved": 0, "done": false, "open": false, "dir": false, "perm": true, "wFile": true, "oll": true, "sFile": true, "wSel": true, "sSel": true, "skip": false, "cDir": false, "cPerm": false, "cW": false, "cS": false, "cSkip": false, "wdl": 0, "sdl": 0, "okAtDone": false, "bounced": false, "pickedWhileClosed": false]),
        (action: "reopen", params: [String: Any](), expected: ["step": 0, "saved": 0, "done": false, "open": true, "dir": false, "perm": true, "wFile": true, "oll": true, "sFile": true, "wSel": true, "sSel": true, "skip": false, "cDir": false, "cPerm": true, "cW": true, "cS": true, "cSkip": false, "wdl": 0, "sdl": 0, "okAtDone": false, "bounced": false, "pickedWhileClosed": false]),
        (action: "env_wfile", params: ["v": true], expected: ["step": 0, "saved": 0, "done": false, "open": true, "dir": false, "perm": true, "wFile": true, "oll": true, "sFile": true, "wSel": true, "sSel": true, "skip": false, "cDir": false, "cPerm": true, "cW": true, "cS": true, "cSkip": false, "wdl": 0, "sdl": 0, "okAtDone": false, "bounced": false, "pickedWhileClosed": false]),
        (action: "env_wfile", params: ["v": true], expected: ["step": 0, "saved": 0, "done": false, "open": true, "dir": false, "perm": true, "wFile": true, "oll": true, "sFile": true, "wSel": true, "sSel": true, "skip": false, "cDir": false, "cPerm": true, "cW": true, "cS": true, "cSkip": false, "wdl": 0, "sdl": 0, "okAtDone": false, "bounced": false, "pickedWhileClosed": false]),
        (action: "quit_app", params: [String: Any](), expected: ["step": 0, "saved": 0, "done": false, "open": false, "dir": false, "perm": true, "wFile": true, "oll": true, "sFile": true, "wSel": true, "sSel": true, "skip": false, "cDir": false, "cPerm": false, "cW": false, "cS": false, "cSkip": false, "wdl": 0, "sdl": 0, "okAtDone": false, "bounced": false, "pickedWhileClosed": false]),
        (action: "env_wfile", params: ["v": false], expected: ["step": 0, "saved": 0, "done": false, "open": false, "dir": false, "perm": true, "wFile": false, "oll": true, "sFile": true, "wSel": true, "sSel": true, "skip": false, "cDir": false, "cPerm": false, "cW": false, "cS": false, "cSkip": false, "wdl": 0, "sdl": 0, "okAtDone": false, "bounced": false, "pickedWhileClosed": false]),
        (action: "quit_app", params: [String: Any](), expected: ["step": 0, "saved": 0, "done": false, "open": false, "dir": false, "perm": true, "wFile": false, "oll": true, "sFile": true, "wSel": true, "sSel": true, "skip": false, "cDir": false, "cPerm": false, "cW": false, "cS": false, "cSkip": false, "wdl": 0, "sdl": 0, "okAtDone": false, "bounced": false, "pickedWhileClosed": false]),
        (action: "env_smodel", params: ["v": true], expected: ["step": 0, "saved": 0, "done": false, "open": false, "dir": false, "perm": true, "wFile": false, "oll": true, "sFile": true, "wSel": true, "sSel": true, "skip": false, "cDir": false, "cPerm": false, "cW": false, "cS": false, "cSkip": false, "wdl": 0, "sdl": 0, "okAtDone": false, "bounced": false, "pickedWhileClosed": false]),
        (action: "env_perm", params: ["v": true], expected: ["step": 0, "saved": 0, "done": false, "open": false, "dir": false, "perm": true, "wFile": false, "oll": true, "sFile": true, "wSel": true, "sSel": true, "skip": false, "cDir": false, "cPerm": false, "cW": false, "cS": false, "cSkip": false, "wdl": 0, "sdl": 0, "okAtDone": false, "bounced": false, "pickedWhileClosed": false]),
        (action: "env_perm", params: ["v": true], expected: ["step": 0, "saved": 0, "done": false, "open": false, "dir": false, "perm": true, "wFile": false, "oll": true, "sFile": true, "wSel": true, "sSel": true, "skip": false, "cDir": false, "cPerm": false, "cW": false, "cS": false, "cSkip": false, "wdl": 0, "sdl": 0, "okAtDone": false, "bounced": false, "pickedWhileClosed": false]),
        (action: "env_ollama", params: ["v": true], expected: ["step": 0, "saved": 0, "done": false, "open": false, "dir": false, "perm": true, "wFile": false, "oll": true, "sFile": true, "wSel": true, "sSel": true, "skip": false, "cDir": false, "cPerm": false, "cW": false, "cS": false, "cSkip": false, "wdl": 0, "sdl": 0, "okAtDone": false, "bounced": false, "pickedWhileClosed": false]),
        (action: "quit_app", params: [String: Any](), expected: ["step": 0, "saved": 0, "done": false, "open": false, "dir": false, "perm": true, "wFile": false, "oll": true, "sFile": true, "wSel": true, "sSel": true, "skip": false, "cDir": false, "cPerm": false, "cW": false, "cS": false, "cSkip": false, "wdl": 0, "sdl": 0, "okAtDone": false, "bounced": false, "pickedWhileClosed": false]),
        (action: "env_smodel", params: ["v": true], expected: ["step": 0, "saved": 0, "done": false, "open": false, "dir": false, "perm": true, "wFile": false, "oll": true, "sFile": true, "wSel": true, "sSel": true, "skip": false, "cDir": false, "cPerm": false, "cW": false, "cS": false, "cSkip": false, "wdl": 0, "sdl": 0, "okAtDone": false, "bounced": false, "pickedWhileClosed": false]),
        (action: "env_perm", params: ["v": true], expected: ["step": 0, "saved": 0, "done": false, "open": false, "dir": false, "perm": true, "wFile": false, "oll": true, "sFile": true, "wSel": true, "sSel": true, "skip": false, "cDir": false, "cPerm": false, "cW": false, "cS": false, "cSkip": false, "wdl": 0, "sdl": 0, "okAtDone": false, "bounced": false, "pickedWhileClosed": false]),
        (action: "env_ollama", params: ["v": false], expected: ["step": 0, "saved": 0, "done": false, "open": false, "dir": false, "perm": true, "wFile": false, "oll": false, "sFile": true, "wSel": true, "sSel": true, "skip": false, "cDir": false, "cPerm": false, "cW": false, "cS": false, "cSkip": false, "wdl": 0, "sdl": 0, "okAtDone": false, "bounced": false, "pickedWhileClosed": false]),
        (action: "quit_app", params: [String: Any](), expected: ["step": 0, "saved": 0, "done": false, "open": false, "dir": false, "perm": true, "wFile": false, "oll": false, "sFile": true, "wSel": true, "sSel": true, "skip": false, "cDir": false, "cPerm": false, "cW": false, "cS": false, "cSkip": false, "wdl": 0, "sdl": 0, "okAtDone": false, "bounced": false, "pickedWhileClosed": false]),
        (action: "env_ollama", params: ["v": false], expected: ["step": 0, "saved": 0, "done": false, "open": false, "dir": false, "perm": true, "wFile": false, "oll": false, "sFile": true, "wSel": true, "sSel": true, "skip": false, "cDir": false, "cPerm": false, "cW": false, "cS": false, "cSkip": false, "wdl": 0, "sdl": 0, "okAtDone": false, "bounced": false, "pickedWhileClosed": false]),
        (action: "env_perm", params: ["v": true], expected: ["step": 0, "saved": 0, "done": false, "open": false, "dir": false, "perm": true, "wFile": false, "oll": false, "sFile": true, "wSel": true, "sSel": true, "skip": false, "cDir": false, "cPerm": false, "cW": false, "cS": false, "cSkip": false, "wdl": 0, "sdl": 0, "okAtDone": false, "bounced": false, "pickedWhileClosed": false]),
        (action: "quit_app", params: [String: Any](), expected: ["step": 0, "saved": 0, "done": false, "open": false, "dir": false, "perm": true, "wFile": false, "oll": false, "sFile": true, "wSel": true, "sSel": true, "skip": false, "cDir": false, "cPerm": false, "cW": false, "cS": false, "cSkip": false, "wdl": 0, "sdl": 0, "okAtDone": false, "bounced": false, "pickedWhileClosed": false]),
        (action: "env_ollama", params: ["v": true], expected: ["step": 0, "saved": 0, "done": false, "open": false, "dir": false, "perm": true, "wFile": false, "oll": true, "sFile": true, "wSel": true, "sSel": true, "skip": false, "cDir": false, "cPerm": false, "cW": false, "cS": false, "cSkip": false, "wdl": 0, "sdl": 0, "okAtDone": false, "bounced": false, "pickedWhileClosed": false]),
        (action: "quit_app", params: [String: Any](), expected: ["step": 0, "saved": 0, "done": false, "open": false, "dir": false, "perm": true, "wFile": false, "oll": true, "sFile": true, "wSel": true, "sSel": true, "skip": false, "cDir": false, "cPerm": false, "cW": false, "cS": false, "cSkip": false, "wdl": 0, "sdl": 0, "okAtDone": false, "bounced": false, "pickedWhileClosed": false]),
        (action: "env_wfile", params: ["v": true], expected: ["step": 0, "saved": 0, "done": false, "open": false, "dir": false, "perm": true, "wFile": true, "oll": true, "sFile": true, "wSel": true, "sSel": true, "skip": false, "cDir": false, "cPerm": false, "cW": false, "cS": false, "cSkip": false, "wdl": 0, "sdl": 0, "okAtDone": false, "bounced": false, "pickedWhileClosed": false]),
        (action: "reopen", params: [String: Any](), expected: ["step": 0, "saved": 0, "done": false, "open": true, "dir": false, "perm": true, "wFile": true, "oll": true, "sFile": true, "wSel": true, "sSel": true, "skip": false, "cDir": false, "cPerm": true, "cW": true, "cS": true, "cSkip": false, "wdl": 0, "sdl": 0, "okAtDone": false, "bounced": false, "pickedWhileClosed": false]),
        (action: "refresh_perm", params: [String: Any](), expected: ["step": 0, "saved": 0, "done": false, "open": true, "dir": false, "perm": true, "wFile": true, "oll": true, "sFile": true, "wSel": true, "sSel": true, "skip": false, "cDir": false, "cPerm": true, "cW": true, "cS": true, "cSkip": false, "wdl": 0, "sdl": 0, "okAtDone": false, "bounced": false, "pickedWhileClosed": false]),
        (action: "forward", params: [String: Any](), expected: ["step": 1, "saved": 1, "done": false, "open": true, "dir": false, "perm": true, "wFile": true, "oll": true, "sFile": true, "wSel": true, "sSel": true, "skip": false, "cDir": false, "cPerm": true, "cW": true, "cS": true, "cSkip": false, "wdl": 0, "sdl": 0, "okAtDone": false, "bounced": false, "pickedWhileClosed": false]),
        (action: "env_ollama", params: ["v": false], expected: ["step": 1, "saved": 1, "done": false, "open": true, "dir": false, "perm": true, "wFile": true, "oll": false, "sFile": true, "wSel": true, "sSel": true, "skip": false, "cDir": false, "cPerm": true, "cW": true, "cS": true, "cSkip": false, "wdl": 0, "sdl": 0, "okAtDone": false, "bounced": false, "pickedWhileClosed": false]),
        (action: "env_smodel", params: ["v": true], expected: ["step": 1, "saved": 1, "done": false, "open": true, "dir": false, "perm": true, "wFile": true, "oll": false, "sFile": true, "wSel": true, "sSel": true, "skip": false, "cDir": false, "cPerm": true, "cW": true, "cS": true, "cSkip": false, "wdl": 0, "sdl": 0, "okAtDone": false, "bounced": false, "pickedWhileClosed": false]),
        (action: "env_perm", params: ["v": true], expected: ["step": 1, "saved": 1, "done": false, "open": true, "dir": false, "perm": true, "wFile": true, "oll": false, "sFile": true, "wSel": true, "sSel": true, "skip": false, "cDir": false, "cPerm": true, "cW": true, "cS": true, "cSkip": false, "wdl": 0, "sdl": 0, "okAtDone": false, "bounced": false, "pickedWhileClosed": false]),
        (action: "refresh_perm", params: [String: Any](), expected: ["step": 1, "saved": 1, "done": false, "open": true, "dir": false, "perm": true, "wFile": true, "oll": false, "sFile": true, "wSel": true, "sSel": true, "skip": false, "cDir": false, "cPerm": true, "cW": true, "cS": true, "cSkip": false, "wdl": 0, "sdl": 0, "okAtDone": false, "bounced": false, "pickedWhileClosed": false]),
        (action: "close_window", params: [String: Any](), expected: ["step": 0, "saved": 1, "done": false, "open": false, "dir": false, "perm": true, "wFile": true, "oll": false, "sFile": true, "wSel": true, "sSel": true, "skip": false, "cDir": false, "cPerm": false, "cW": false, "cS": false, "cSkip": false, "wdl": 0, "sdl": 0, "okAtDone": false, "bounced": false, "pickedWhileClosed": false]),
        (action: "env_smodel", params: ["v": false], expected: ["step": 0, "saved": 1, "done": false, "open": false, "dir": false, "perm": true, "wFile": true, "oll": false, "sFile": false, "wSel": true, "sSel": true, "skip": false, "cDir": false, "cPerm": false, "cW": false, "cS": false, "cSkip": false, "wdl": 0, "sdl": 0, "okAtDone": false, "bounced": false, "pickedWhileClosed": false]),
        (action: "env_ollama", params: ["v": true], expected: ["step": 0, "saved": 1, "done": false, "open": false, "dir": false, "perm": true, "wFile": true, "oll": true, "sFile": false, "wSel": true, "sSel": true, "skip": false, "cDir": false, "cPerm": false, "cW": false, "cS": false, "cSkip": false, "wdl": 0, "sdl": 0, "okAtDone": false, "bounced": false, "pickedWhileClosed": false]),
        (action: "reopen", params: [String: Any](), expected: ["step": 1, "saved": 1, "done": false, "open": true, "dir": false, "perm": true, "wFile": true, "oll": true, "sFile": false, "wSel": true, "sSel": true, "skip": false, "cDir": false, "cPerm": true, "cW": true, "cS": false, "cSkip": false, "wdl": 0, "sdl": 0, "okAtDone": false, "bounced": false, "pickedWhileClosed": false]),
        (action: "env_wfile", params: ["v": true], expected: ["step": 1, "saved": 1, "done": false, "open": true, "dir": false, "perm": true, "wFile": true, "oll": true, "sFile": false, "wSel": true, "sSel": true, "skip": false, "cDir": false, "cPerm": true, "cW": true, "cS": false, "cSkip": false, "wdl": 0, "sdl": 0, "okAtDone": false, "bounced": false, "pickedWhileClosed": false]),
        (action: "env_ollama", params: ["v": false], expected: ["step": 1, "saved": 1, "done": false, "open": true, "dir": false, "perm": true, "wFile": true, "oll": false, "sFile": false, "wSel": true, "sSel": true, "skip": false, "cDir": false, "cPerm": true, "cW": true, "cS": false, "cSkip": false, "wdl": 0, "sdl": 0, "okAtDone": false, "bounced": false, "pickedWhileClosed": false]),
        (action: "env_wfile", params: ["v": false], expected: ["step": 1, "saved": 1, "done": false, "open": true, "dir": false, "perm": true, "wFile": false, "oll": false, "sFile": false, "wSel": true, "sSel": true, "skip": false, "cDir": false, "cPerm": true, "cW": true, "cS": false, "cSkip": false, "wdl": 0, "sdl": 0, "okAtDone": false, "bounced": false, "pickedWhileClosed": false]),
        (action: "env_wfile", params: ["v": true], expected: ["step": 1, "saved": 1, "done": false, "open": true, "dir": false, "perm": true, "wFile": true, "oll": false, "sFile": false, "wSel": true, "sSel": true, "skip": false, "cDir": false, "cPerm": true, "cW": true, "cS": false, "cSkip": false, "wdl": 0, "sdl": 0, "okAtDone": false, "bounced": false, "pickedWhileClosed": false]),
        (action: "quit_app", params: [String: Any](), expected: ["step": 0, "saved": 1, "done": false, "open": false, "dir": false, "perm": true, "wFile": true, "oll": false, "sFile": false, "wSel": true, "sSel": true, "skip": false, "cDir": false, "cPerm": false, "cW": false, "cS": false, "cSkip": false, "wdl": 0, "sdl": 0, "okAtDone": false, "bounced": false, "pickedWhileClosed": false]),
        (action: "env_wfile", params: ["v": false], expected: ["step": 0, "saved": 1, "done": false, "open": false, "dir": false, "perm": true, "wFile": false, "oll": false, "sFile": false, "wSel": true, "sSel": true, "skip": false, "cDir": false, "cPerm": false, "cW": false, "cS": false, "cSkip": false, "wdl": 0, "sdl": 0, "okAtDone": false, "bounced": false, "pickedWhileClosed": false]),
        (action: "env_perm", params: ["v": false], expected: ["step": 0, "saved": 1, "done": false, "open": false, "dir": false, "perm": false, "wFile": false, "oll": false, "sFile": false, "wSel": true, "sSel": true, "skip": false, "cDir": false, "cPerm": false, "cW": false, "cS": false, "cSkip": false, "wdl": 0, "sdl": 0, "okAtDone": false, "bounced": false, "pickedWhileClosed": false]),
        (action: "reopen", params: [String: Any](), expected: ["step": 1, "saved": 1, "done": false, "open": true, "dir": false, "perm": false, "wFile": false, "oll": false, "sFile": false, "wSel": true, "sSel": true, "skip": false, "cDir": false, "cPerm": false, "cW": false, "cS": false, "cSkip": false, "wdl": 0, "sdl": 0, "okAtDone": false, "bounced": false, "pickedWhileClosed": false]),
        (action: "back", params: [String: Any](), expected: ["step": 0, "saved": 0, "done": false, "open": true, "dir": false, "perm": false, "wFile": false, "oll": false, "sFile": false, "wSel": true, "sSel": true, "skip": false, "cDir": false, "cPerm": false, "cW": false, "cS": false, "cSkip": false, "wdl": 0, "sdl": 0, "okAtDone": false, "bounced": false, "pickedWhileClosed": false]),
    ]
    for step in walk {
        _ = a.step(step.action, step.params)
        assertPartial(a.observe(), step.expected)
    }
}

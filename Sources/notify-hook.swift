import Foundation

// Stop hooks read JSON from stdin and must return JSON on stdout.
// No network, transcript reads, child processes, or changes to turn decisions.
func completionID(_ data: Data) -> String? {
    guard let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          value["hook_event_name"] as? String == "Stop",
          let session = value["session_id"] as? String, !session.isEmpty,
          let turn = value["turn_id"] as? String, !turn.isEmpty else { return nil }
    let id = session + ":" + turn
    return id.count <= 512 ? id : nil
}

if CommandLine.arguments.contains("--self-test") {
    let cases: [(String, String?)] = [
        (#"{"hook_event_name":"Stop","session_id":"s","turn_id":"t"}"#, "s:t"),
        (#"{"hook_event_name":"Stop","session_id":"s","turn_id":"t","last_assistant_message":"private"}"#, "s:t"),
        (#"{"hook_event_name":"Interrupt","session_id":"s","turn_id":"t"}"#, nil),
        (#"{"hook_event_name":"SubagentStop","session_id":"s","turn_id":"t"}"#, nil),
        (#"{"hook_event_name":"Stop","session_id":"","turn_id":"t"}"#, nil),
        (#"{"hook_event_name":"Stop","session_id":"s"}"#, nil),
        ("invalid", nil),
        ("[]", nil)
    ]
    for (json, expected) in cases {
        precondition(completionID(Data(json.utf8)) == expected, "Failed event validation")
    }
    print("Passed 8 hook input checks; no notifications emitted.")
} else {
    let data = FileHandle.standardInput.readDataToEndOfFile()
    if let id = completionID(data) {
        DistributedNotificationCenter.default().postNotificationName(
            Notification.Name("local.dualsense.codexbridge.turnEnded"),
            object: id, userInfo: nil, deliverImmediately: true)
    }
    print("{}")
}

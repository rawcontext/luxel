import Foundation

struct CountdownPreset: Identifiable {
    let duration: TimeInterval
    let title: String

    var id: TimeInterval {
        duration
    }

    static let all: [CountdownPreset] = [
        CountdownPreset(duration: 3, title: "3 s"),
        CountdownPreset(duration: 5, title: "5 s"),
        CountdownPreset(duration: 10, title: "10 s")
    ]
}

struct StopAfterPreset: Identifiable {
    let duration: TimeInterval
    let title: String

    var id: TimeInterval {
        duration
    }

    static let all: [StopAfterPreset] = [
        StopAfterPreset(duration: 10, title: "10 s"),
        StopAfterPreset(duration: 30, title: "30 s"),
        StopAfterPreset(duration: 60, title: "1 min"),
        StopAfterPreset(duration: 300, title: "5 min")
    ]
}

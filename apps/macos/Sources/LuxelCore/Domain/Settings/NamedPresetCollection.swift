protocol NamedPreset {
    var name: String { get }
}

extension CaptureSizePreset: NamedPreset {}
extension ExportPreset: NamedPreset {}

extension Array where Element: NamedPreset {
    func uniquePresetName(base: String) -> String {
        let names = Set(map(\.name))
        guard names.contains(base) else {
            return base
        }

        var index = 2
        while names.contains("\(base) \(index)") {
            index += 1
        }
        return "\(base) \(index)"
    }
}

import Foundation

struct WeightedGIFColor: Equatable, Sendable {
    let color: GIFPaletteColor
    let count: Int
}

enum GIFPaletteChannel {
    case red
    case green
    case blue
}

struct MedianCutColorBox: Sendable {
    let colors: [WeightedGIFColor]

    var canSplit: Bool {
        colors.count > 1
    }

    var population: Int {
        colors.reduce(0) { $0 + $1.count }
    }

    var longestRange: Int {
        range(for: longestChannel)
    }

    var averageColor: GIFPaletteColor {
        let total = max(1, population)
        let red = colors.reduce(0) { $0 + Int($1.color.red) * $1.count }
        let green = colors.reduce(0) { $0 + Int($1.color.green) * $1.count }
        let blue = colors.reduce(0) { $0 + Int($1.color.blue) * $1.count }

        return GIFPaletteColor(
            red: UInt8((Double(red) / Double(total)).rounded()),
            green: UInt8((Double(green) / Double(total)).rounded()),
            blue: UInt8((Double(blue) / Double(total)).rounded())
        )
    }

    func split() -> (left: MedianCutColorBox, right: MedianCutColorBox)? {
        guard colors.count > 1 else {
            return nil
        }

        let sortedColors = colors.sorted { lhs, rhs in
            let channel = longestChannel
            let leftValue = lhs.color.value(for: channel)
            let rightValue = rhs.color.value(for: channel)
            if leftValue == rightValue {
                return MedianCutPaletteBuilder.sortsBefore(lhs.color, rhs.color)
            }

            return leftValue < rightValue
        }
        let halfPopulation = max(1, population / 2)
        var accumulated = 0
        var splitIndex = 1

        for index in sortedColors.indices {
            accumulated += sortedColors[index].count
            if accumulated >= halfPopulation {
                splitIndex = min(max(index + 1, 1), sortedColors.count - 1)
                break
            }
        }

        return (
            left: MedianCutColorBox(colors: Array(sortedColors[..<splitIndex])),
            right: MedianCutColorBox(colors: Array(sortedColors[splitIndex...]))
        )
    }

    private var longestChannel: GIFPaletteChannel {
        let redRange = range(for: .red)
        let greenRange = range(for: .green)
        let blueRange = range(for: .blue)

        if redRange >= greenRange, redRange >= blueRange {
            return .red
        }

        if greenRange >= blueRange {
            return .green
        }

        return .blue
    }

    private func range(for channel: GIFPaletteChannel) -> Int {
        let values = colors.map { $0.color.value(for: channel) }
        guard let minValue = values.min(), let maxValue = values.max() else {
            return 0
        }

        return Int(maxValue) - Int(minValue)
    }
}

extension Array where Element == MedianCutColorBox {
    func bestSplittableBoxIndex() -> Int? {
        var bestIndex: Int?

        for index in indices where self[index].canSplit {
            if let currentBest = bestIndex {
                if self[index].hasHigherSplitPriority(than: self[currentBest]) {
                    bestIndex = index
                }
            } else {
                bestIndex = index
            }
        }

        return bestIndex
    }
}

extension MedianCutColorBox {
    func hasHigherSplitPriority(than other: MedianCutColorBox) -> Bool {
        if longestRange != other.longestRange {
            return longestRange > other.longestRange
        }

        if population != other.population {
            return population > other.population
        }

        return colors.count > other.colors.count
    }
}

extension GIFPaletteColor {
    static let black = GIFPaletteColor(red: 0, green: 0, blue: 0)
    static let white = GIFPaletteColor(red: 255, green: 255, blue: 255)

    func value(for channel: GIFPaletteChannel) -> UInt8 {
        switch channel {
        case .red:
            red
        case .green:
            green
        case .blue:
            blue
        }
    }
}

extension Array where Element == GIFPaletteColor {
    func uniqued() -> [GIFPaletteColor] {
        var seen: Set<GIFPaletteColor> = []
        var result: [GIFPaletteColor] = []
        result.reserveCapacity(count)

        for color in self where seen.insert(color).inserted {
            result.append(color)
        }

        return result
    }
}

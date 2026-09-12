@_spi(ForToolsIntegration) import Testing

@main
enum SwiftTestingMain {
    static func main() async {
        await Testing.__swiftPMEntryPoint() as Never
    }
}

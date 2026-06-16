import Foundation

@main
private struct MPGDualModeHelper {
    static func main() {
        let arguments = Array(CommandLine.arguments.dropFirst())
        guard let command = arguments.first else {
            usage()
        }

        switch command {
        case "read":
            let status = MSIHID.readStatus()
            print("connected=\(status.connected ? "1" : "0")")
            guard status.connected else {
                exit(2)
            }
            print("\(MSIHID.modeRegister)=\(status.values[MSIHID.modeRegister] ?? "NO_RESPONSE")")
            print("\(MSIHID.confirmationRegister)=\(status.values[MSIHID.confirmationRegister] ?? "NO_RESPONSE")")
        case "set":
            guard arguments.count == 2, arguments[1] == "000" || arguments[1] == "001" else {
                usage()
            }
            guard MSIHID.setModeValue(arguments[1]) else {
                print("connected=0")
                exit(2)
            }
            print("sent=1")
        default:
            usage()
        }
    }

    private static func usage() -> Never {
        fputs("usage: mpg-dual-mode-helper read | set 000|001\n", stderr)
        exit(64)
    }
}

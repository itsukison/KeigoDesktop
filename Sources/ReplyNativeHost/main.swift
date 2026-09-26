import Foundation
import TextIO
// stdout is exclusively Chrome's framed protocol. Never print diagnostics or source text.
do { try ReplyNativeHost.run(origin: CommandLine.arguments.dropFirst().first ?? "") }
catch { exit(1) }

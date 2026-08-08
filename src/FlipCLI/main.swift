import Foundation
import FlipControl

// The `flip` command: drives the running application from a prompt or a script.
//
//   flip list                  every window, as JSON
//   flip focus <id>            bring one forward
//   flip arrange left-half     move the focused window
//   flip switch                open the grid
//   flip pause | resume        hand ⌘Tab back to macOS, or take it again
//
// It talks to the running copy over a unix socket rather than doing the work
// itself: window state lives in one place, and a second process reaching into
// accessibility would answer differently from the switcher you can see.

let usage = """
flip — drive the running Flip from the command line

USAGE
  flip list                    every window as JSON, most recently used first
  flip focus <id>              bring the window with that id forward
  flip arrange <where>         move the focused window
  flip switch                  open the switcher
  flip pause                   hand ⌘Tab back to macOS
  flip resume                  take it again

ARRANGEMENTS
  \(ControlArrangement.names.joined(separator: "  "))

EXAMPLES
  flip list | jq -r '.[] | "\\(.id)\\t\\(.app)\\t\\(.title)"'
  flip focus "$(flip list | jq '.[1].id')"
  flip arrange left-half
"""

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("flip: \(message)\n".utf8))
    exit(1)
}

var arguments = Array(CommandLine.arguments.dropFirst())
guard let verb = arguments.first else {
    print(usage)
    exit(2)
}
arguments.removeFirst()

let command: ControlCommand
switch verb {
case "list":
    command = .list

case "focus":
    guard let raw = arguments.first, let id = UInt32(raw) else {
        fail("focus needs a window id — see `flip list`")
    }
    command = .focus(id)

case "arrange":
    guard let where_ = arguments.first else {
        fail("arrange needs one of: \(ControlArrangement.names.joined(separator: ", "))")
    }
    // Checked here rather than over the socket, so a typo is answered at once
    // and with the whole list rather than a rejection from another process.
    guard ControlArrangement.names.contains(where_) else {
        fail("unknown arrangement '\(where_)' — try one of: \(ControlArrangement.names.joined(separator: ", "))")
    }
    command = .arrange(where_)

case "switch":
    command = .switcher

case "pause":
    command = .pause

case "resume":
    command = .resume

case "-h", "--help", "help":
    print(usage)
    exit(0)

case "--version":
    print(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown")
    exit(0)

default:
    fail("unknown command '\(verb)' — run `flip --help`")
}

let response: ControlResponse
do {
    response = try ControlClient.send(command)
} catch {
    fail("\(error)")
}

switch response {
case .windows(let windows):
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    guard let json = try? encoder.encode(windows) else { fail("could not render the answer") }

    print(String(decoding: json, as: UTF8.self))

case .ok:
    // Silence on success, so it composes in a script without being filtered out.
    break

case .failure(let reason):
    fail(reason)
}

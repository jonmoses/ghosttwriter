import Foundation
import GtwCore
import WorkbenchProtocol

let args = Array(CommandLine.arguments.dropFirst())
let env = ProcessInfo.processInfo.environment

// Read stdin only for `hook`, and never more than one byte past the limit.
var stdin = Data()
if Gtw.command(args) == "hook" {
    stdin = FileHandle.standardInput.readData(ofLength: Gtw.maxHookInputBytes + 1)
}

let socketPath = Gtw.socketPath(args, env: env)
    ?? SocketPaths.defaultSocket(home: env["HOME"] ?? NSHomeDirectory())

let environment = GtwEnvironment(env: env, stdin: stdin, stdoutIsTTY: isatty(1) == 1)
let output = Gtw.run(args, environment) { request, timeout in
    try SocketClient.send(request, socketPath: socketPath, timeout: timeout)
}

if !output.stdout.isEmpty { FileHandle.standardOutput.write(Data(output.stdout.utf8)) }
if !output.stderr.isEmpty { FileHandle.standardError.write(Data(output.stderr.utf8)) }
exit(output.code)

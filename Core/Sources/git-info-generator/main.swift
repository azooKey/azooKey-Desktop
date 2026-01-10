import Foundation

var tag = try? shell("git for-each-ref refs/tags --points-at HEAD --sort=-creatordate --format='%(refname:short)' | head -n 1")
var commit = try? shell("git rev-parse HEAD")
if tag?.isEmpty == true {
    tag = nil
}
if commit?.isEmpty == true {
    commit = nil
}

let outputPath = CommandLine.arguments[1]
let contents = """
// This file is auto-generated.

let gitTagFromPlugin: String? = \(tag as String?)
let gitCommitFromPlugin: String? = \(commit as String?)
"""

try contents.write(toFile: outputPath, atomically: true, encoding: .utf8)

@discardableResult
func shell(_ command: String) throws -> String {
    let process = Process()
    let pipe = Pipe()

    process.standardOutput = pipe
    process.executableURL = URL(fileURLWithPath: "/bin/bash")
    process.arguments = ["-c", command]

    try process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()

    return String(data: data, encoding: .utf8)!.trimmingCharacters(in: .whitespacesAndNewlines)
}

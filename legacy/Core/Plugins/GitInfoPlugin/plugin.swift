import Foundation
import PackagePlugin

@main
struct GitInfoPlugin: BuildToolPlugin {
    func createBuildCommands(context: PluginContext, target: Target) throws -> [Command] {
        let tool = try context.tool(named: "git-info-generator")
        let outputFile = context.pluginWorkDirectoryURL.appending(path: "GitInfo.swift")
        print(outputFile)

        return [
            .buildCommand(
                displayName: "Generate Git Info",
                executable: tool.url,
                arguments: [outputFile.path()],
                outputFiles: [outputFile]
            )
        ]
    }
}

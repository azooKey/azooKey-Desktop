public struct PackageMetadata {
    public static var gitTag: String? {
        gitTagFromPlugin
    }
    public static var gitCommit: String? {
        gitCommitFromPlugin
    }
}

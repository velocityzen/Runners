/// The version `runners --version` prints.
///
/// It stays `dev` in the repository: the release workflow overwrites this file with the tag
/// before it builds, so only release binaries carry a number.
enum Version {
    static let current = "dev"
}

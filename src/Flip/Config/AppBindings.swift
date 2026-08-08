/// A seed for a fresh install; after that `bindings.json` is the configuration.
///
/// One binding, not a set. A seed is there to show what the feature is, and
/// every key it takes is one somebody has to find and clear before it is theirs.
/// The Finder because it is the one application every Mac has, so this works on
/// a machine where nothing else is installed yet.
///
/// Bundle IDs rather than names throughout: "Google Chrome" also matches
/// "Google Chrome Dev".
enum DefaultBindings {
    static let all: [AppBinding] = [
        AppBinding(key: "f", bundleID: "com.apple.finder"),
    ]
}

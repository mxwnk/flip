/// A seed for a fresh install; after that `bindings.json` is the configuration.
/// One binding, because every key a seed takes is one somebody has to clear —
/// and the Finder, because every Mac has it.
enum DefaultBindings {
    static let all: [AppBinding] = [
        AppBinding(key: "f", bundleID: "com.apple.finder"),
    ]
}

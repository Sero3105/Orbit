import Foundation
import Security

/// Safe app uninstall: what belongs to an app is decided only from verifiable facts
/// (its own bundle ID, helpers physically inside its bundle, signed entitlements,
/// launch agents that run its code). Nothing is matched by name or open-ended prefix.
public enum Uninstaller {
    public struct Plan: Equatable {
        public var appPath: String
        public var bundleID: String
        public var ownedIDs: [String]      // bundleID + verified nested helper IDs
        public var appGroups: [String]     // verified, not shared with other installed apps
        public var leftovers: [String]
        /// Set when another installed app has the same bundle ID: its data is shared, so only the bundle goes.
        public var sharedBundleID: Bool
    }
    public struct Failure: Error, Equatable, CustomStringConvertible { public var description: String }
    public enum Outcome: Equatable { case trashed, skipped(String), failed(String) }
    public typealias Groups = (team: String?, groups: [String])

    /// ~/Library subfolders leftovers may live in (direct children only).
    static let libraryDirs = ["Application Support", "Caches", "Logs", "Containers", "Group Containers", "Application Scripts",
                              "HTTPStorages", "WebKit", "Cookies", "Preferences", "Preferences/ByHost", "LaunchAgents", "Saved Application State"]

    // MARK: Validation

    /// Reverse-DNS bundle ID: ≥2 non-empty segments of [A-Za-z0-9_-]. Rejects "/", "..", spaces, NUL…
    public static func isValidBundleID(_ id: String) -> Bool {
        guard (3...255).contains(id.utf8.count) else { return false }
        let segs = id.split(separator: ".", omittingEmptySubsequences: false)
        return segs.count >= 2 && segs.allSatisfy { s in !s.isEmpty && s.unicodeScalars.allSatisfy { CharacterSet.alphanumerics.contains($0) && $0.isASCII || $0 == "-" || $0 == "_" } }
    }
    /// A single, harmless path component (used for group container names).
    static func isSafeComponent(_ s: String) -> Bool {
        !s.isEmpty && s != "." && s != ".." && !s.contains("/") && !s.contains("\0") && s.utf8.count <= 255
    }
    static func realpath(_ p: String) -> String? {
        guard let r = Darwin.realpath(p, nil) else { return nil }
        defer { free(r) }; return String(cString: r)
    }
    static func isSymlink(_ p: String) -> Bool { var st = stat(); return lstat(p, &st) == 0 && (st.st_mode & S_IFMT) == S_IFLNK }
    static func exists(_ p: String) -> Bool { var st = stat(); return lstat(p, &st) == 0 }
    static func infoPlistID(_ bundle: String) -> String? {
        for p in [bundle + "/Contents/Info.plist", bundle + "/Info.plist"] {
            if let d = NSDictionary(contentsOfFile: p), let id = d["CFBundleIdentifier"] as? String { return id }
        }
        return nil
    }
    public static func appRoots(home: String) -> [String] { ["/Applications", home + "/Applications"] }

    /// Why this app must not be uninstalled by Orbit, or nil.
    public static func blockReason(appPath: String, home: String = NSHomeDirectory(), appRoots roots: [String]? = nil) -> String? {
        let roots = roots ?? appRoots(home: home)
        guard appPath.hasSuffix(".app"), (appPath as NSString).standardizingPath == appPath else { return "invalid application path" }
        if isSymlink(appPath) { return "application is a symbolic link" }
        guard let real = realpath(appPath) else { return "application not found" }
        if real == "/System" || real.hasPrefix("/System/") { return "protected system application" }
        let parent = (real as NSString).deletingLastPathComponent
        guard roots.compactMap(realpath).contains(parent) else { return "not in an Applications folder" }
        guard let id = infoPlistID(appPath) else { return "no bundle identifier" }
        guard isValidBundleID(id) else { return "invalid bundle identifier" }
        if id.lowercased().hasPrefix("com.apple.") { return "Apple application" }
        return nil
    }

    // MARK: Ownership

    /// Bundle IDs of helpers physically inside the app whose ID extends the app's own ("<id>.…").
    static func nestedHelperIDs(appPath: String, mainID: String) -> [String] {
        guard let en = FileManager.default.enumerator(atPath: appPath + "/Contents") else { return [] }
        var out = Set<String>()
        while let rel = en.nextObject() as? String {
            guard ["app", "appex", "xpc"].contains((rel as NSString).pathExtension) else { continue }
            let p = appPath + "/Contents/" + rel
            if isSymlink(p) { en.skipDescendants(); continue }
            if let id = infoPlistID(p), isValidBundleID(id), id.hasPrefix(mainID + ".") { out.insert(id) }
        }
        return out.sorted()
    }

    /// Team ID and app-group entitlements, trusted only when the code signature checks out.
    public static func signedGroups(appPath: String) -> Groups {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(URL(fileURLWithPath: appPath) as CFURL, [], &code) == errSecSuccess, let code,
              SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSDoNotValidateResources), nil) == errSecSuccess else { return (nil, []) }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let d = info as? [String: Any] else { return (nil, []) }
        let ent = d[kSecCodeInfoEntitlementsDict as String] as? [String: Any]
        return (d[kSecCodeInfoTeamIdentifier as String] as? String, ent?["com.apple.security.application-groups"] as? [String] ?? [])
    }

    /// Everything Orbit would move to Trash for this app. Throws when the app must not be uninstalled.
    /// `groupsOf` and `installedApps` are injectable for tests.
    public static func plan(appPath: String, home: String = NSHomeDirectory(), appRoots roots: [String]? = nil,
                            groupsOf: (String) -> Groups = signedGroups, installedApps: [String]? = nil) throws -> Plan {
        let roots = roots ?? appRoots(home: home)
        if let why = blockReason(appPath: appPath, home: home, appRoots: roots) { throw Failure(description: why) }
        let id = infoPlistID(appPath)!
        let others = (installedApps ?? roots.flatMap { r in ((try? FileManager.default.contentsOfDirectory(atPath: r)) ?? []).filter { $0.hasSuffix(".app") }.map { r + "/" + $0 } })
            .filter { realpath($0) != realpath(appPath) }
        let otherIDs = Set(others.compactMap(infoPlistID))
        if otherIDs.contains(id) { return Plan(appPath: appPath, bundleID: id, ownedIDs: [id], appGroups: [], leftovers: [], sharedBundleID: true) }
        let owned = [id] + nestedHelperIDs(appPath: appPath, mainID: id).filter { !otherIDs.contains($0) }

        // App groups: signed, team-prefixed (or group.<id>), and not also claimed by another installed app of the same team.
        let (team, groups) = groupsOf(appPath)
        var verifiedGroups = groups.filter { g in
            isSafeComponent(g) && ((team.map { g.hasPrefix($0 + ".") } ?? false) || g == "group." + id || g.hasPrefix("group." + id + "."))
        }
        if !verifiedGroups.isEmpty {
            let shared = Set(others.flatMap { o -> [String] in let og = groupsOf(o); return og.team == team ? og.groups : [] })
            verifiedGroups.removeAll { shared.contains($0) }
        }

        let L = home + "/Library/"
        var out = Set<String>()
        func add(_ p: String) { if exists(p), !isSymlink(p) { out.insert(p) } }
        for x in owned {
            for d in ["Application Support", "Caches", "Logs", "Containers", "Application Scripts", "HTTPStorages", "WebKit"] { add(L + d + "/" + x) }
            add(L + "Preferences/\(x).plist"); add(L + "Saved Application State/\(x).savedState")
            add(L + "Cookies/\(x).binarycookies"); add(L + "HTTPStorages/\(x).binarycookies")
        }
        for g in verifiedGroups { add(L + "Group Containers/" + g) }
        // Per-host prefs: "<id>.<hardware UUID>.plist" exactly.
        let uuid = "[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}"
        for k in (try? FileManager.default.contentsOfDirectory(atPath: L + "Preferences/ByHost")) ?? [] {
            if owned.contains(where: { k.range(of: "^" + NSRegularExpression.escapedPattern(for: $0) + "\\." + uuid + "\\.plist$", options: .regularExpression) != nil }) { add(L + "Preferences/ByHost/" + k) }
        }
        // Launch agents whose label is an owned ID or whose program lives inside this app.
        let realApp = realpath(appPath) ?? appPath
        for k in (try? FileManager.default.contentsOfDirectory(atPath: L + "LaunchAgents")) ?? [] where k.hasSuffix(".plist") {
            let p = L + "LaunchAgents/" + k
            guard !isSymlink(p), let d = NSDictionary(contentsOfFile: p) else { continue }
            let prog = (d["Program"] as? String) ?? (d["ProgramArguments"] as? [String])?.first
            let progReal = prog.flatMap { realpath($0) ?? ($0 as NSString).standardizingPath }
            if owned.contains(d["Label"] as? String ?? "") || progReal.map({ $0.hasPrefix(realApp + "/") || $0.hasPrefix(appPath + "/") }) == true { add(p) }
        }
        return Plan(appPath: appPath, bundleID: id, ownedIDs: owned, appGroups: verifiedGroups, leftovers: out.sorted(), sharedBundleID: false)
    }

    // MARK: Execution

    /// nil when `path` is safe to trash now: canonical, not a symlink, and a direct child of an allowed
    /// ~/Library folder with no symlink anywhere between home and the item.
    public static func leftoverProblem(_ path: String, home: String) -> String? {
        guard !path.contains("\0"), (path as NSString).standardizingPath == path else { return "invalid path" }
        guard exists(path) else { return "missing" }
        if isSymlink(path) { return "symbolic link" }
        guard let realHome = realpath(home) else { return "home not found" }
        let parent = (path as NSString).deletingLastPathComponent, name = (path as NSString).lastPathComponent
        guard let realParent = realpath(parent), isSafeComponent(name),
              libraryDirs.contains(where: { realParent == realHome + "/Library/" + $0 && parent == home + "/Library/" + $0 }) else { return "outside allowed locations" }
        guard realpath(path) == realParent + "/" + name else { return "resolves elsewhere" }
        return nil
    }

    /// Move the app, then its previewed leftovers, to Trash. Ownership and every path are rechecked
    /// right before acting; if the app itself cannot be trashed, nothing else is touched.
    public static func execute(_ preview: Plan, home: String = NSHomeDirectory(), appRoots roots: [String]? = nil,
                               groupsOf: (String) -> Groups = signedGroups, installedApps: [String]? = nil,
                               trash: (URL) throws -> Void = { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) }) -> [(String, Outcome)] {
        let rest = { (why: String) in preview.leftovers.map { ($0, Outcome.skipped(why)) } }
        guard let fresh = try? plan(appPath: preview.appPath, home: home, appRoots: roots, groupsOf: groupsOf, installedApps: installedApps),
              fresh.bundleID == preview.bundleID else {
            return [(preview.appPath, .skipped("application changed since preview"))] + rest("application changed since preview")
        }
        do { try trash(URL(fileURLWithPath: preview.appPath)) }
        catch { return [(preview.appPath, .failed(error.localizedDescription))] + rest("application could not be moved to Trash") }
        let stillOwned = Set(fresh.leftovers)
        return [(preview.appPath, .trashed)] + preview.leftovers.map { p in
            guard stillOwned.contains(p) else { return (p, .skipped("no longer verified as this app's data")) }
            if let why = leftoverProblem(p, home: home) { return (p, .skipped(why)) }
            do { try trash(URL(fileURLWithPath: p)); return (p, .trashed) } catch { return (p, .failed(error.localizedDescription)) }
        }
    }
}

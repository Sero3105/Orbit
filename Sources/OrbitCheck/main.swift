import Foundation; import OrbitCore
func check(_ c: Bool, _ n: String) { print(c ? "PASS \(n)" : "FAIL \(n)"); if !c { exit(1) } }
let tmp = NSTemporaryDirectory()+"orbit-test-\(UUID().uuidString)"
try! FileManager.default.createDirectory(atPath: tmp+"/Library/Caches/Foo", withIntermediateDirectories:true)
try! "x".write(toFile: tmp+"/Library/Caches/Foo/a.bin", atomically:true, encoding:.utf8)
let before = SafetyValidator.dirSize(URL(fileURLWithPath: tmp)).0
let scan = CleanupScanner(home: tmp).scan()
check(scan.contains{ $0.category=="App caches" }, "scan finds cache")
check(SafetyValidator.dirSize(URL(fileURLWithPath: tmp)).0 == before, "scan read-only")
let real = tmp+"/Library/Caches/Foo"; let link = tmp+"/Library/Caches/Link"
try! FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: real)
check(SafetyValidator.validate(Candidate(path:link,category:"t",reason:"t",size:1,safety:.safe,inode:SafetyValidator.inode(of:link)!), allowedRoots:[tmp]) != nil, "symlink rejected")
check(SafetyValidator.validate(Candidate(path:"/System/Library/x",category:"t",reason:"t",size:1,safety:.safe,inode:1), allowedRoots:["/"]) != nil, "protected rejected")
check(SafetyValidator.validate(Candidate(path:real,category:"t",reason:"t",size:1,safety:.safe,inode:999999), allowedRoots:[tmp]) != nil, "stale inode rejected")
check(SafetyValidator.validate(Candidate(path:real,category:"t",reason:"t",size:1,safety:.safe,inode:SafetyValidator.inode(of:real)!), allowedRoots:[tmp]) == nil, "valid accepted")
let r = TrashExecutor.run(scan, allowedRoots:[tmp], execute:false, history:nil)
check(r.allSatisfy{ $0.1.hasPrefix("Dry-run") || $0.1.hasPrefix("Skipped") } && FileManager.default.fileExists(atPath: tmp+"/Library/Caches/Foo/a.bin"), "dry-run deletes nothing")
check(!DiskScanner.scan(tmp).entries.isEmpty, "disk scan")
try? FileManager.default.removeItem(atPath: tmp); print("ALL PASS")

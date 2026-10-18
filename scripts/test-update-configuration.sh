#!/bin/bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT
cat > "$test_dir/main.swift" <<'SWIFT'
import Foundation

let key = Data(repeating: 0, count: 32).base64EncodedString()
let cases: [([String: Any], Bool)] = [
    ([:], false),
    (["SUPublicEDKey": "", "SUFeedURL": ""], false),
    (["SUPublicEDKey": key], false),
    (["SUFeedURL": "https://example.com/appcast.xml"], false),
    (["SUPublicEDKey": "invalid", "SUFeedURL": "https://example.com/appcast.xml"], false),
    (["SUPublicEDKey": Data(repeating: 0, count: 31).base64EncodedString(), "SUFeedURL": "https://example.com/appcast.xml"], false),
    (["SUPublicEDKey": key, "SUFeedURL": "http://example.com/appcast.xml"], false),
    (["SUPublicEDKey": key, "SUFeedURL": "/appcast.xml"], false),
    (["SUPublicEDKey": key, "SUFeedURL": "https:///"], false),
    (["SUPublicEDKey": key, "SUFeedURL": "https://example.com/appcast.xml"], true),
]
for (index, entry) in cases.enumerated() {
    precondition(UpdateConfiguration.isConfigured(info: entry.0) == entry.1, "Configuration case \(index) failed")
}
print("Passed \(cases.count) update configuration cases")
SWIFT
swiftc "$root/Sources/prism/UpdateConfiguration.swift" "$test_dir/main.swift" -o "$test_dir/update-config-tests"
"$test_dir/update-config-tests"

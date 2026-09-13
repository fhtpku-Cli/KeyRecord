import Foundation
import XCTest
import KeyRecordTestSupport

final class PrivacyEgressTests: XCTestCase {
    private func violations(_ source: String) throws -> [String] {
        let code = SourceInspection.codeOnly(source)
        let pattern = #"\b(?:URLSession\w*|URLRequest|NSURL\w*(?:Session|Request|Connection)\w*|NW\w+|CFNetwork\w*|CF(?:Read|Write)Stream\w*|Process|NSTask|posix_spawn\w*|execl|execlp|execle|execv|execvp|execve|popen|socket|connect|connectx|sendto|sendmsg|getaddrinfo)\b|\bimport\s+Network\b|(?<!\.)(?<!func )\bsystem\s*\("#
        let regex = try NSRegularExpression(pattern: pattern)
        var matches = regex.matches(in: code, range: NSRange(code.startIndex..., in: code)).compactMap {
            Range($0.range, in: code).map { String(code[$0]) }
        }
        // A lexer preserves strings (including raw/multiline literals) while discarding nested comments.
        let literalPattern = #"(?i)https?\s*:\s*(?:\\/|/){2}|/bin/(?:sh|bash|zsh)"#
        let literals = try NSRegularExpression(pattern: literalPattern)
        let text = commentsRemoved(source)
        matches += literals.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap {
            Range($0.range, in: text).map { String(text[$0]) }
        }
        return matches
    }

    private func commentsRemoved(_ source: String) -> String {
        let chars = Array(source)
        var output = ""
        var i = 0
        var depth = 0
        var quoted = false
        while i < chars.count {
            let next: Character? = i + 1 < chars.count ? chars[i + 1] : nil
            if depth > 0 {
                if chars[i] == "/", next == "*" { depth += 1; i += 2 }
                else if chars[i] == "*", next == "/" { depth -= 1; i += 2 }
                else { i += 1 }
            } else if quoted {
                output.append(chars[i])
                if chars[i] == "\\", let next { output.append(next); i += 2 }
                else { if chars[i] == "\"" { quoted = false }; i += 1 }
            } else if chars[i] == "/", next == "*" { depth = 1; i += 2 }
            else if chars[i] == "/", next == "/" {
                while i < chars.count, chars[i] != "\n" { i += 1 }
            } else {
                if chars[i] == "\"" { quoted = true }
                output.append(chars[i]); i += 1
            }
        }
        return output
    }

    func testProductWhenScannedHasNoNetworkShellOrEndpointCapability() throws {
        // Given / When / Then
        for path in ["Sources", "App/KeyRecordApp"] {
            for file in try SourceInspection.swiftFiles(in: SourceInspection.root.appendingPathComponent(path)) {
                XCTAssertEqual(try violations(String(contentsOf: file, encoding: .utf8)), [], file.path)
            }
        }
    }

    func testEgressFixturesWhenScannedAreRejected() throws {
        // Given
        let fixtures = ["URLSession.shared", "let request: URLRequest", "import Network",
            "NWPathMonitor()", "Darwin.connect(fd, address, length)", "socket(2, 1, 0)",
            "CFReadStreamCreateForHTTPRequest()", "Process()", "posix_spawn()", "execve()",
            #"let endpoint = "https://example.invalid""#,
            ##"let endpoint = #"http://example.invalid"#"##,
            "let endpoint = \"\"\"\nhttps://example.invalid\n\"\"\""]
        // When / Then
        for fixture in fixtures { XCTAssertFalse(try violations(fixture).isEmpty, fixture) }
    }

    func testDocumentationCommentsWhenScannedDoNotCreateFalseEndpoints() throws {
        // Given
        let source = "/* outer /* https://example.invalid */ nested */\n// http://example.invalid\nlet n = 1"
        // When / Then
        XCTAssertEqual(try violations(source), [])
    }
}

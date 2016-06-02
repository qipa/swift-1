/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

#if os(OSX)
import XCTest
import func Darwin.C.exit

/// A helper tool to get list of tests from a XCTest Bundle on OSX.
///
/// Usage: swiftpm-xctest-helper <bundle_path> <output_file_path>
/// bundle_path: Path to the XCTest bundle
/// output_file_path: File to write the result into.
///
/// Note: Output is a JSON dictionary. Tests are discovered by 
/// loading the bundle and then iterating the default Test Suite.
func run() throws {

    guard Process.arguments.count == 3 else {
        throw Error.invalidUsage
    }
    let bundlePath = Process.arguments[1].normalizedPath()
    let outputFile = Process.arguments[2].normalizedPath()

    // Note that the bundle might write to stdout while it is being loaded, but we don't try to handle that here.
    // Instead the client should decide what to do with any extra output from this tool.
    guard let bundle = NSBundle(path: bundlePath) where bundle.load() else {
        throw Error.unableToLoadBundle(bundlePath)
    }
    let suite = XCTestSuite.default()

    let splitSet: Set<Character> = ["[", " ", "]", ":"]

    // Array of test cases. Contains test cases in format:
    // { "name" : "<test_class_name>", "tests" : [ { "name" : "test_method" } ] }
    var testCases = [[String: AnyObject]]()

    for case let testCaseSuite as XCTestSuite in suite.tests {
        for case let testCaseSuite as XCTestSuite in testCaseSuite.tests {
            // Get the name of the XCTest subclass with its module name if possible.
            // If the subclass contains atleast one test get the name using reflection,
            // otherwise use the name property (which only gives subclass name).
            let name: String
            if let firstTest = testCaseSuite.tests.first {
                name = String(reflecting: firstTest.dynamicType)
            } else {
                name = testCaseSuite.name ?? "nil"
            }

            // Collect the test methods.
            let tests: [[String: String]] = testCaseSuite.tests.flatMap { test in
                guard case let test as XCTestCase = test else { return nil }
                // Split the test description into an array. Description formats:
                // `-[ClassName MethodName]`, `-[ClassName MethodNameAndReturnError:]`
                var methodName = test.description.characters.split(isSeparator: splitSet.contains).map(String.init)[2]
                // Unmangle names for Swift test cases which throw.
                if methodName.hasSuffix("AndReturnError") {
                    methodName = methodName[methodName.startIndex..<methodName.index(methodName.endIndex, offsetBy: -14)]
                }
                return ["name": methodName]
            }

            testCases.append(["name": name as NSString, "tests": tests as NSArray])
        }
    }

    // Create output file.
    NSFileManager.default().createFile(atPath: outputFile, contents: nil, attributes: nil)
    // Open output file for writing.
    guard let file = NSFileHandle(forWritingAtPath: outputFile) else {
        throw Error.couldNotOpenOutputFile(outputFile)
    }
    // Create output dictionary.
    let output = ["name": "All Tests", "tests": testCases as NSArray] as NSDictionary
    // Convert output dictionary to JSON and write to output file.
    let outputData = try NSJSONSerialization.data(withJSONObject: output, options: .prettyPrinted)
    file.write(outputData)
}

enum Error: ErrorProtocol {
    case invalidUsage
    case unableToLoadBundle(String)
    case couldNotOpenOutputFile(String)
}

extension String {
    func normalizedPath() -> String {
        var path = self
        if !(path as NSString).isAbsolutePath {
            path = NSFileManager.default().currentDirectoryPath + "/" + path
        }
        return (path as NSString).standardizingPath
    }
}

do {
    try run()
} catch Error.invalidUsage {
    print("Usage: swiftpm-xctest-helper <bundle_path> <output_file_path>")
    exit(1)
} catch {
    print("error: \(error)")
    exit(1)
}

#else

import func Glibc.exit
print("Only OSX supported.")
exit(1)

#endif

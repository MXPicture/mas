//
//  Lucky.swift
//  mas-cli
//
//  Created by Pablo Varela on 05/11/17.
//  Copyright © 2016 Andrew Naylor. All rights reserved.
//

import Commandant
import Result
import CommerceKit

/// Command which installs the first search result. This is handy as many MAS titles
/// can be long with embedded keywords.
public struct LuckyCommand: CommandProtocol {
    public typealias Options = LuckyOptions
    public let verb = "lucky"
    public let function = "Install the first result from the Mac App Store"

    private let appLibrary: AppLibrary
    private let urlSession: URLSession

    /// Designated initializer.
    ///
    /// - Parameter appLibrary: AppLibrary manager.
    /// - Parameter urlSession: URL session for network communication.
    public init(appLibrary: AppLibrary = MasAppLibrary(), urlSession: URLSession = URLSession.shared) {
        self.appLibrary = appLibrary
        self.urlSession = urlSession
    }

    public func run(_ options: Options) -> Result<(), MASError> {
        guard let searchURLString = searchURLString(options.appName),
              let searchJson = urlSession.requestSynchronousJSONWithURLString(searchURLString) as? [String: Any] else {
            return .failure(.searchFailed)
        }

        guard let resultCount = searchJson[ResultKeys.ResultCount] as? Int, resultCount > 0,
              let results = searchJson[ResultKeys.Results] as? [[String: Any]] else {
            print("No results found")
            return .failure(.noSearchResultsFound)
        }

        let appId = results[0][ResultKeys.TrackId] as! UInt64

        return install(appId, options: options)
    }

    fileprivate func install(_ appId: UInt64, options: Options) -> Result<(), MASError> {
        // Try to download applications with given identifiers and collect results
        let downloadResults = [appId].compactMap { (appId) -> MASError? in
            if let product = appLibrary.installedApp(forId: appId), !options.forceInstall {
                printWarning("\(product.appName) is already installed")
                return nil
            }

            return download(appId)
        }

        switch downloadResults.count {
        case 0:
            return .success(())
        case 1:
            return .failure(downloadResults[0])
        default:
            return .failure(.downloadFailed(error: nil))
        }
    }

    func searchURLString(_ appName: String) -> String? {
        if let urlEncodedAppName = appName.URLEncodedString {
            return "https://itunes.apple.com/search?entity=macSoftware&term=\(urlEncodedAppName)&attribute=allTrackTerm"
        }
        return nil
    }
}

public struct LuckyOptions: OptionsProtocol {
    let appName: String
    let forceInstall: Bool

    public static func create(_ appName: String) -> (_ forceInstall: Bool) -> LuckyOptions {
        return { forceInstall in
            return LuckyOptions(appName: appName, forceInstall: forceInstall)
        }
    }

    public static func evaluate(_ m: CommandMode) -> Result<LuckyOptions, CommandantError<MASError>> {
        return create
            <*> m <| Argument(usage: "the app name to install")
            <*> m <| Switch(flag: nil, key: "force", usage: "force reinstall")
    }
}

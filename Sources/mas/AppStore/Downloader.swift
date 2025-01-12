//
//  Downloader.swift
//  mas
//
//  Created by Andrew Naylor on 21/08/2015.
//  Copyright (c) 2015 Andrew Naylor. All rights reserved.
//

import PromiseKit
import StoreFoundation

/// Sequentially downloads apps, printing progress to the console.
///
/// Verifies that each supplied app ID is valid before attempting to download.
///
/// - Parameters:
///   - unverifiedAppIDs: The app IDs of the apps to be verified and downloaded.
///   - searcher: The `AppStoreSearcher` used to verify app IDs.
///   - purchasing: Flag indicating if the apps will be purchased. Only works for free apps. Defaults to false.
/// - Returns: A `Promise` that completes when the downloads are complete. If any fail,
///   the promise is rejected with the first error, after all remaining downloads are attempted.
func downloadApps(
    withAppIDs unverifiedAppIDs: [AppID],
    verifiedBy searcher: AppStoreSearcher,
    purchasing: Bool = false
) -> Promise<Void> {
    when(resolved: unverifiedAppIDs.map { searcher.lookup(appID: $0) })
        .then { results in
            downloadApps(
                withAppIDs:
                    results.compactMap { result in
                        switch result {
                        case .fulfilled(let searchResult):
                            return searchResult.trackId
                        case .rejected(let error):
                            printError(String(describing: error))
                            return nil
                        }
                    },
                purchasing: purchasing
            )
        }
}

/// Sequentially downloads apps, printing progress to the console.
///
/// - Parameters:
///   - appIDs: The app IDs of the apps to be downloaded.
///   - purchasing: Flag indicating if the apps will be purchased. Only works for free apps. Defaults to false.
/// - Returns: A promise that completes when the downloads are complete. If any fail,
///   the promise is rejected with the first error, after all remaining downloads are attempted.
func downloadApps(withAppIDs appIDs: [AppID], purchasing: Bool = false) -> Promise<Void> {
    var firstError: Error?
    return
        appIDs
        .reduce(Guarantee.value(())) { previous, appID in
            previous.then {
                downloadApp(withAppID: appID, purchasing: purchasing)
                    .recover { error in
                        if firstError == nil {
                            firstError = error
                        }
                    }
            }
        }
        .done {
            if let firstError {
                throw firstError
            }
        }
}

private func downloadApp(
    withAppID appID: AppID,
    purchasing: Bool = false,
    withAttemptCount attemptCount: UInt32 = 3
) -> Promise<Void> {
    SSPurchase()
        .perform(appID: appID, purchasing: purchasing)
        .recover { error in
            guard attemptCount > 1 else {
                throw error
            }

            // If the download failed due to network issues, try again. Otherwise, fail immediately.
            guard
                case MASError.downloadFailed(let downloadError) = error,
                case NSURLErrorDomain = downloadError?.domain
            else {
                throw error
            }

            let attemptCount = attemptCount - 1
            printWarning((downloadError ?? error).localizedDescription)
            printWarning("Trying again up to \(attemptCount) more \(attemptCount == 1 ? "time" : "times").")
            return downloadApp(withAppID: appID, purchasing: purchasing, withAttemptCount: attemptCount)
        }
}

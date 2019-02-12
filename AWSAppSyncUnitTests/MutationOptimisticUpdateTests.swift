//
// Copyright 2010-2019 Amazon.com, Inc. or its affiliates. All Rights Reserved.
//
// Licensed under the Apache License, Version 2.0 (the "License").
// You may not use this file except in compliance with the License.
// A copy of the License is located at
//
// http://aws.amazon.com/apache2.0
//
// or in the "license" file accompanying this file. This file is distributed
// on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either
// express or implied. See the License for the specific language governing
// permissions and limitations under the License.
//

import XCTest
@testable import AWSAppSync
@testable import AWSAppSyncTestCommon

class MutationOptimisticUpdateTests: XCTestCase {
    let fetchQueue = DispatchQueue(label: "MutationOptimisticUpdateTests.fetch")
    let mutationQueue = DispatchQueue(label: "MutationOptimisticUpdateTests.mutations")

    var cacheConfigRootDirectory: URL!
    let mockHTTPTransport = MockAWSNetworkTransport()

    // Set up a new DB for each test
    override func setUp() {
        let tempDir = FileManager.default.temporaryDirectory
        cacheConfigRootDirectory = tempDir.appendingPathComponent("MutationOptimisticUpdateTests-\(UUID().uuidString)")
    }

    override func tearDown() {
        MockReachabilityProvidingFactory.clearShared()
        NetworkReachabilityNotifier.clearShared()
    }

    func testMutation_WithOptimisticUpdate_UpdatesEmptyCache() throws {
        let addPost = DefaultTestPostData.defaultCreatePostWithoutFileUsingParametersMutation

        // We will set up a response block that never actually invokes the completion handler. This allows us to
        // examine the state of the local cache before any return values are processed
        let nonDispatchingResponseBlockInvoked = expectation(description: "Non dispatching response block invoked")

        let nonDispatchingResponseBlock: SendOperationResponseBlock<CreatePostWithoutFileUsingParametersMutation> = {
            _, _ in
            nonDispatchingResponseBlockInvoked.fulfill()
        }

        mockHTTPTransport.sendOperationResponseQueue.append(nonDispatchingResponseBlock)

        let appSyncClient = try makeAppSyncClient(using: mockHTTPTransport)

        let newPost = ListPostsQuery.Data.ListPost(
            id: "TEMPORARY-\(UUID().uuidString)",
            author: addPost.author,
            title: addPost.title,
            content: addPost.content,
            ups: addPost.ups ?? 0,
            downs: addPost.downs ?? 0)

        let optimisticUpdatePerformed = expectation(description: "Optimistic update performed")
        appSyncClient.perform(
            mutation: addPost,
            queue: mutationQueue,
            optimisticUpdate: { transaction in
                guard let transaction = transaction else {
                    XCTFail("Optimistic update transaction unexpectedly nil")
                    return
                }
                do {
                    try transaction.update(query: ListPostsQuery()) { data in
                        var listPosts: [ListPostsQuery.Data.ListPost?] = data.listPosts ?? []
                        listPosts.append(newPost)
                        data.listPosts = listPosts
                    }
                    // The `update` is synchronous, so we can fulfill after the block completes
                    optimisticUpdatePerformed.fulfill()
                } catch {
                    XCTFail("Unexpected error performing optimistic update: \(error)")
                }
        })

        let cacheHasOptimisticUpdateResult = expectation(description: "Cache returns optimistic update result")

        appSyncClient.fetch(
            query: ListPostsQuery(),
            cachePolicy: .returnCacheDataDontFetch,
            queue: fetchQueue
        ) { result, error in
            guard error == nil else {
                XCTFail("Unexpected error querying optimistically updated cache: \(error.debugDescription)")
                return
            }

            guard
                let listPosts = result?.data?.listPosts
                else {
                    XCTFail("Result unexpectedly nil querying optimistically updated cache")
                    return
            }

            let posts = listPosts.compactMap({$0})
            guard let firstPost = posts.first else {
                XCTFail("No posts in optimistically updated cache result")
                return
            }

            XCTAssertEqual(firstPost.id, newPost.id)
            cacheHasOptimisticUpdateResult.fulfill()
        }

        wait(
            for: [
                nonDispatchingResponseBlockInvoked,
                optimisticUpdatePerformed,
                cacheHasOptimisticUpdateResult
            ],
            timeout: 1.0)
    }

    func testMutation_WithoutOptimisticUpdate_DoesNotUpdateEmptyCache() throws {

    }

    func testMutation_WithOptimisticUpdate_UpdatesPopulatedCache() throws {

    }

    func testMutation_WithoutOptimisticUpdate_DoesNotUpdatePopulatedCache() throws {

    }

    func testMutation_WithOptimisticUpdate_UpdatesEmptyCache_WhileNetworkIsUnreachable() throws {

    }

    func testMutation_WithOptimisticUpdate_UpdatesEmptyInMemoryCache() throws {
        
    }

    // MARK - Utility methods

    func makeAddPostResponseBody(withId id: GraphQLID,
                                 forMutation mutation: CreatePostWithoutFileUsingParametersMutation) -> JSONObject {
        let createdDateMilliseconds = Date().timeIntervalSince1970 * 1000

        let response = CreatePostWithoutFileUsingParametersMutation.Data.CreatePostWithoutFileUsingParameter(
            id: id,
            author: mutation.author,
            title: mutation.title,
            content: mutation.content,
            url: mutation.url,
            ups: mutation.ups ?? 0,
            downs: mutation.downs ?? 0,
            file: nil,
            createdDate: String(describing: Int(createdDateMilliseconds)),
            awsDs: nil)

        return ["data": ["createPostWithoutFileUsingParameters": response.jsonObject]]
    }

    func makeAppSyncClient(using httpTransport: AWSNetworkTransport,
                           withBackingDatabase useBackingDatabase: Bool = true) throws -> DeinitNotifiableAppSyncClient {
        let cacheConfiguration: AWSAppSyncCacheConfiguration? = useBackingDatabase ? try AWSAppSyncCacheConfiguration(withRootDirectory: cacheConfigRootDirectory) : nil
        let helper = try AppSyncClientTestHelper(
            with: .apiKey,
            testConfiguration: AppSyncClientTestConfiguration.forUnitTests,
            cacheConfiguration: cacheConfiguration,
            httpTransport: httpTransport,
            reachabilityFactory: MockReachabilityProvidingFactory.self
        )

        if let cacheConfiguration = cacheConfiguration {
            print("AppSyncClient created with cacheConfiguration: \(cacheConfiguration)")
        } else {
            print("AppSyncClient created with in-memory caches")
        }
        return helper.appSyncClient
    }

}

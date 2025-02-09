//
// Copyright 2019, 2021, Optimizely, Inc. and contributors
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//    http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

import XCTest

class EventDispatcherTests: XCTestCase {
    
    var eventDispatcher: DefaultEventDispatcher?

    override func setUp() {
        OTUtils.createDocumentDirectoryIfNotAvailable()
    }

    override func tearDown() {
        OTUtils.clearAllEventQueues()
    }

    func testDefaultDispatcher() {
        eventDispatcher = DefaultEventDispatcher(timerInterval: 10)
        let pEventD: OPTEventDispatcher = eventDispatcher!

        pEventD.flushEvents()
        
        eventDispatcher?.queueLock.sync {}
        
        pEventD.dispatchEvent(event: EventForDispatch(body: Data()), completionHandler: nil)
        
        eventDispatcher?.queueLock.sync {}
 
        XCTAssert(eventDispatcher?.eventQueue.count == 1)
        eventDispatcher?.flushEvents()
        
        eventDispatcher?.queueLock.sync {}
        
        XCTAssert(eventDispatcher?.eventQueue.count == 0)
        
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct results.
    }
    
    func testDispatcherZeroTimeInterval() {
        class InnerEventDispatcher: DefaultEventDispatcher {
            var once = false
            var events: [EventForDispatch] = [EventForDispatch]()
            override func sendEvent(event: EventForDispatch, completionHandler: @escaping DispatchCompletionHandler) {
                events.append(event)
                if !once {
                    self.eventQueue.save(item: EventForDispatch(body: Data()))
                    once = true
                }
                completionHandler(.success(Data()))
            }
        }
        
        let dispatcher = InnerEventDispatcher(timerInterval: 0)

        // add two items.... call flush
        dispatcher.eventQueue.save(item: EventForDispatch(body: Data()))
        dispatcher.flushEvents()
        
        dispatcher.queueLock.sync {}
        
        XCTAssert(dispatcher.events.count == 2)
    }

    func testEventDispatcherFile() {
        eventDispatcher = DefaultEventDispatcher( backingStore: .file)
        let pEventD: OPTEventDispatcher = eventDispatcher!
        eventDispatcher?.timerInterval = 1
        let wait = {() in
            self.eventDispatcher?.queueLock.sync {}
        }

        pEventD.flushEvents()
        wait()
        
        pEventD.dispatchEvent(event: EventForDispatch(body: Data()), completionHandler: nil)
        wait()
        
        XCTAssert(eventDispatcher?.eventQueue.count == 1)

        eventDispatcher?.flushEvents()
        wait()
        
        XCTAssert(eventDispatcher?.eventQueue.count == 0)
        
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct results.
    }

    func testEventDispatcherUserDefaults() {
        eventDispatcher = DefaultEventDispatcher( backingStore: .userDefaults)
        let pEventD: OPTEventDispatcher = eventDispatcher!
        eventDispatcher?.timerInterval = 1
        let wait = {
            self.eventDispatcher?.queueLock.sync {}
        }

        pEventD.flushEvents()
        wait()
        
        pEventD.dispatchEvent(event: EventForDispatch(body: Data()), completionHandler: nil)
        wait()
        
        XCTAssert(eventDispatcher?.eventQueue.count == 1)

        eventDispatcher?.flushEvents()
        wait()
        
        XCTAssert(eventDispatcher?.eventQueue.count == 0)
        
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct results.
    }

    func testEventDispatcherMemory() {
        eventDispatcher = DefaultEventDispatcher( backingStore: .memory)
        let pEventD: OPTEventDispatcher = eventDispatcher!
        eventDispatcher?.timerInterval = 1
        let wait = {
            self.eventDispatcher?.queueLock.sync {}
        }

        pEventD.flushEvents()
        wait()
        
        pEventD.dispatchEvent(event: EventForDispatch(body: Data()), completionHandler: nil)
        wait()
        
        XCTAssert(eventDispatcher?.eventQueue.count == 1)

        eventDispatcher?.flushEvents()
        wait()
        
        XCTAssert(eventDispatcher?.eventQueue.count == 0)
        
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct results.
    }

    func testDispatcherCustomUrl() {
        let dispatcher = MockEventDispatcher()
        
        let originalUrl = "https://logx.optimizely.com/v1/events"
        let customUrl = "https://google.com"
        let overrideUrl = "https://apple.com"
        
        // default end-point
        
        dispatcher.dispatchEvent(event: EventForDispatch(body: Data()), completionHandler: nil)
        
        XCTAssert(dispatcher.events.count == 1)
        XCTAssert(dispatcher.events.first?.url.absoluteString == originalUrl)
        dispatcher.flushEvents()
        XCTAssert(dispatcher.events.count == 0)
        
        // customize end-point
        
        EventForDispatch.eventEndpoint = customUrl
        dispatcher.dispatchEvent(event: EventForDispatch(body: Data()), completionHandler: nil)
        
        XCTAssert(dispatcher.events.count == 1)
        XCTAssert(dispatcher.events.first?.url.absoluteString == customUrl)
        dispatcher.flushEvents()
        
        // override end-point
        
        dispatcher.dispatchEvent(event: EventForDispatch(url: URL(string: overrideUrl), body: Data()), completionHandler: nil)
        
        XCTAssert(dispatcher.events.count == 1)
        XCTAssert(dispatcher.events.first?.url.absoluteString == overrideUrl)
        dispatcher.flushEvents()
        
        // saved custom end-point
        
        dispatcher.dispatchEvent(event: EventForDispatch(body: Data()), completionHandler: nil)
        
        XCTAssert(dispatcher.events.count == 1)
        XCTAssert(dispatcher.events.first?.url.absoluteString == customUrl)
        dispatcher.flushEvents()
    }
    
    func testDispatcherMethods() {
        eventDispatcher = DefaultEventDispatcher(timerInterval: 1)
        
        eventDispatcher?.flushEvents()
        eventDispatcher?.queueLock.sync {}
        
        eventDispatcher?.dispatchEvent(event: EventForDispatch(body: Data()), completionHandler: nil)
        
        eventDispatcher?.queueLock.sync {}
        
        eventDispatcher?.applicationDidBecomeActive()
        eventDispatcher?.applicationDidEnterBackground()
        
        XCTAssert(eventDispatcher?.timer.property == nil)
        var sent = false
        
        let group = DispatchGroup()
        
        group.enter()
        
        eventDispatcher?.sendEvent(event: EventForDispatch(body: Data())) { _ in
            sent = true
            group.leave()
        }
        group.wait()
        XCTAssert(sent)
        
        group.enter()
        
        eventDispatcher?.startTimer()
        
        DispatchQueue.global(qos: .background).async {
            group.leave()
        }
        group.wait()
        
        // we are on the main thread and set timer on async main thread
        // so, must be nil here
        XCTAssert(eventDispatcher?.timer.property == nil)

    }
    
    func testDispatcherZeroBatchSize() {
        let eventDispatcher = DefaultEventDispatcher(batchSize: 0, backingStore: .userDefaults, dataStoreName: "DoNothing", timerInterval: 0)
        
        XCTAssert(eventDispatcher.batchSize > 0)
    }
    
    func testDataStoreQueue() {
        let queue = DataStoreQueueStackImpl<EventForDispatch>(queueStackName: "OPTEventQueue", dataStore: DataStoreMemory<Array<Data>>(storeName: "backingStoreName"))
        
        queue.save(item: EventForDispatch(body: "Blah".data(using: .utf8)!))
        
        let event = queue.getFirstItem()
        let str = String(data: (event?.body)!, encoding: .utf8)
        
        XCTAssert(str == "Blah")
        
        XCTAssert(queue.count == 1)
        
        let event2 = queue.getLastItem()

        let str2 = String(data: (event2?.body)!, encoding: .utf8)
        
        XCTAssert(str2 == "Blah")
        
        XCTAssert(queue.count == 1)
        
        _ = queue.removeFirstItem()
        
        XCTAssert(queue.count == 0)
        
        _ = queue.removeLastItem()
        
        XCTAssert(queue.count == 0)
    }
    
    func testEventQueueFormatCompatibilty() {
        let queueName = "OPTEventQueue"
        
        // pre-store multiple events in a queue (expected format)
        
        let bodyString = OTUtils.sampleEvent
        let bodyData = bodyString.data(using: .utf8)!
        let event = EventForDispatch(url: URL(string: "x"), body: bodyData)
        let eventData = try! JSONEncoder().encode(event)
        let events = [eventData, eventData]
        let saveFormat = try! JSONEncoder().encode(events)

        #if os(tvOS)
        var url = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        #else
        var url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        #endif
        url = url.appendingPathComponent(queueName, isDirectory: false)
        try! saveFormat.write(to: url, options: .atomic)
        
        // verify that a new dataStore can read an existing queue items
        
        let dispatcher = DumpEventDispatcher()
        
        XCTAssert(dispatcher.eventQueue.count == 2)
        dispatcher.flushEvents()
        dispatcher.queueLock.sync {}
        XCTAssert(dispatcher.eventQueue.count == 0)
    }

}

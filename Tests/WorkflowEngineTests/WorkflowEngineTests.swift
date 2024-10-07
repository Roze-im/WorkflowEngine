import XCTest
@testable import WorkflowEngine

final class WorkflowEngineTests: XCTestCase {
    
    //MARK: - Utils functions
    func executeAndBlockUntilSuccessOf(flow: AnyTestFlow, in engine: TestFlowEngine) {
        let delegate = TestFlowEngineDelegate()
        engine.delegate = delegate
        let flowCompleted = expectation(description: "flow success")
        delegate.onProgressCall = { (flowId, progress, tags) in
            guard progress.isSuccessful else { return }
            flowCompleted.fulfill()
        }
        engine.executeNewFlow(flow)
        wait(for: [flowCompleted], timeout: 2)
    }

    // MARK: - Test functions
    func testOneStepSuccess() throws {
        let flow = TestFlow1(identifier: "test_flow_1", tags: ["tag_1"])
        let delegate = TestFlowEngineDelegate()
        let engine = TestFlowEngine(
            stateStore: TestFlowStateStore(),
            logger: { print("[\($1)] \(Date()) \(String(describing: $0)) \($2)") }
        )
        engine.delegate = delegate
        let flowCompleted = expectation(description: "flow success")
        delegate.onProgressCall = { (flowId, progress, tags) in
            guard progress.isSuccessful else { return }
            XCTAssertEqual(tags, ["tag_1"])
            flowCompleted.fulfill()
        }
        engine.executeNewFlow(.flow1(flow))
        wait(for: [flowCompleted], timeout: 2)
        // pending -> completed
        XCTAssertEqual(flow.step1.output, "1")
        // two calls : in progress, success
        XCTAssertEqual(delegate.progressCalls[flow.identifier]?.count ?? 0, 2)

        guard case .success = flow.progress else {
            XCTFail("unexpected flow progress: \(String(describing: flow.progress))")
            return
        }
    }
    
    func testTwoStepsSuccess() throws {
        let flow = TestFlow2(identifier: "test_flow_2")
        let delegate = TestFlowEngineDelegate()
        let engine = TestFlowEngine(
            stateStore: TestFlowStateStore(),
            logger: { print("[\($1)] \(Date()) \(String(describing: $0)) \($2)") }
        )
        engine.delegate = delegate
        let flowCompleted = expectation(description: "flow success")
        delegate.onProgressCall = { (flowId, progress, tags) in
            guard progress.isSuccessful else { return }
            flowCompleted.fulfill()
        }
        engine.executeNewFlow(.flow2(flow))
        wait(for: [flowCompleted], timeout: 2)
        // pending -> completed
        XCTAssertEqual(flow.step1.output, "1")
        XCTAssertEqual(flow.step11.output, "1")
        // four calls : in progress, success for the two steps
        XCTAssertEqual(delegate.progressCalls[flow.identifier]?.count ?? 0, 4)

        guard case .success = flow.progress else {
            XCTFail("unexpected flow progress: \(String(describing: flow.progress))")
            return
        }
    }
    
    func testConfigureDependencies() throws {
        let flow = TestFlow1(identifier: "test_flow_1")
        executeAndBlockUntilSuccessOf(
            flow: .flow1(flow),
            in: TestFlowEngine(
                stateStore: TestFlowStateStore(),
                logger: { print("[\($1)] \(Date()) \(String(describing: $0)) \($2)") }
            )
        )

        XCTAssertNotNil(flow.logger)
        XCTAssertNotNil(flow.step1.logger)
        
        XCTAssertEqual(flow.customDependency, "42")
        XCTAssertEqual(flow.step1.customDependency, "42")
    }
    
    func testWaitFor() throws {
        let flow1 = BlockingFlow(identifier: "blocking_flow_1")
        let flow2 = TestFlow2(identifier: "test_flow_2", waitFor: .init([flow1.identifier]))
        let delegate = TestFlowEngineDelegate()
        let engine = TestFlowEngine(
            stateStore: TestFlowStateStore(),
            logger: { print("[\($1)] \(Date()) \(String(describing: $0)) \($2)") }
        )
        engine.delegate = delegate
        
        var expectNoFlowExecution: Bool = true
        let flow1Completed = expectation(description: "flow1 completed")
        let flow2Completed = expectation(description: "flow2 completed")
        
        let noFlowCompleted = expectation(description: "no flow completed")
        noFlowCompleted.isInverted = true
        delegate.onProgressCall = { (flowId, progress, tags) in
            guard progress.isSuccessful else { return }
            if expectNoFlowExecution {
                noFlowCompleted.fulfill()
                return
            }
            if flowId == flow1.identifier {
                flow1Completed.fulfill()
            }
            if flowId == flow2.identifier {
                flow2Completed.fulfill()
            }
        }
        engine.executeNewFlow(.blocking(flow1))
        engine.executeNewFlow(.flow2(flow2))
        Thread.sleep(forTimeInterval: 1) // wait one second

        wait(for: [noFlowCompleted], timeout: 2)
        
        // now unlock
        expectNoFlowExecution = false
        NotificationCenter.default.post(name: NSNotification.Name(rawValue: flow1.blockingStep.identifier), object: nil)
        
        wait(for: [flow1Completed, flow2Completed], timeout: 2)
    }
    
    func testArchive() throws {
        let store = TestFlowStateStore()
        let delegate = TestFlowEngineDelegate()
        
        var expectNoFlowExecution: Bool = true
        let flow1Identifier = "blocking_flow_1"
        let flow2Identifier = "test_flow_2"
        var flow1BlockingStepIdentifier: String = "undefined"
        let flow1Completed = expectation(description: "flow1 completed")
        let flow2Completed = expectation(description: "flow2 completed")
        
        let noFlowCompleted = expectation(description: "no flow completed")
        noFlowCompleted.isInverted = true
        
        delegate.onProgressCall = { (flowId, progress, tags) in
            guard progress.isSuccessful else { return }
            if expectNoFlowExecution {
                noFlowCompleted.fulfill()
                return
            }
            if flowId == flow1Identifier {
                flow1Completed.fulfill()
            }
            if flowId == flow2Identifier {
                flow2Completed.fulfill()
            }
        }
        
        // We need to make sure the instances are all dealloced, so we define them in the scope of a function.
        func execAndArchive() {
            let engine = TestFlowEngine(
                stateStore: store,
                logger: { print("[\($1)] \(Date()) \(String(describing: $0)) \($2)") }
            )
             engine.delegate = delegate
            // One blocking, another waiting for it. We'll start the two
            //
            let flow1 = BlockingFlow(identifier: flow1Identifier)
            flow1BlockingStepIdentifier = flow1.blockingStep.identifier
            let flow2 = TestFlow2(identifier: flow2Identifier, waitFor: .init([flow1.identifier]))
            engine.executeNewFlow(.blocking(flow1))
            engine.executeNewFlow(.flow2(flow2))
        }
        
        execAndArchive()
        Thread.sleep(forTimeInterval: 1) // wait one second making sure it's stabilized
        wait(for: [noFlowCompleted], timeout: 5)
        
        // Now we'll reuse the store and
        let engine = TestFlowEngine(
            stateStore: store,
            logger: { print("[\($1)] \(Date()) \(String(describing: $0)) \($2)") }
        )
        XCTAssertEqual(2, engine.flowIndex.flows.count)
        engine.delegate = delegate
        // Now we're going to unlock the blocking flow, and wait for the two other flows to be completed.
        expectNoFlowExecution = false
        NotificationCenter.default.post(name: NSNotification.Name(rawValue: flow1BlockingStepIdentifier), object: nil)

        wait(for: [flow1Completed, flow2Completed], timeout: 2)

    }
}

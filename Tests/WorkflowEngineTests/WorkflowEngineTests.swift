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
    
    // MARK: - Retry Tests
    
    /// Test that when delegate returns false on success, the flow is retried instead of disposed
    func testRetryWhenDelegateRejectSuccess() throws {
        let flow = ConfigurableFlow(identifier: "retry_on_delegate_reject")
        let delegate = TestFlowEngineDelegate()
        let engine = TestFlowEngine(
            stateStore: TestFlowStateStore(),
            logger: { print("[\($1)] \(Date()) \(String(describing: $0)) \($2)") }
        )
        engine.delegate = delegate
        
        // Configure very short retry delays for testing
        engine.retryBaseDelay = 0.1
        engine.retryMaxDelay = 0.5
        engine.maxRetryCount = 3
        
        var successCount = 0
        let firstSuccessRejected = expectation(description: "first success rejected")
        let secondSuccessAccepted = expectation(description: "second success accepted")
        
        // First time: reject the success (return false), second time: accept it (return true)
        delegate.shouldAcceptProgress = { flowId, progress, tags in
            guard progress.isSuccessful else { return true }
            successCount += 1
            if successCount == 1 {
                // Reject first success - should trigger retry
                firstSuccessRejected.fulfill()
                return false
            } else {
                // Accept second success
                secondSuccessAccepted.fulfill()
                return true
            }
        }
        
        engine.executeNewFlow(.configurable(flow))
        
        wait(for: [firstSuccessRejected, secondSuccessAccepted], timeout: 5, enforceOrder: true)
        
        // Verify the step was executed twice (initial + 1 retry)
        XCTAssertEqual(flow.configurableStep.executionCount, 2, "Step should have been executed twice")
        XCTAssertEqual(successCount, 2, "Should have received 2 success callbacks")
    }
    
    /// Test that flow failure triggers retry when shouldRetryOnErrorUponUnarchived returns true
    func testRetryOnFlowFailure() throws {
        let flow = ConfigurableFlow(identifier: "retry_on_failure")
        flow.configurableStep.shouldFail = true // Configure step to fail
        
        let delegate = TestFlowEngineDelegate()
        let engine = TestFlowEngine(
            stateStore: TestFlowStateStore(),
            logger: { print("[\($1)] \(Date()) \(String(describing: $0)) \($2)") }
        )
        engine.delegate = delegate
        
        // Configure very short retry delays for testing
        engine.retryBaseDelay = 0.1
        engine.retryMaxDelay = 0.5
        engine.maxRetryCount = 3
        
        var failureCount = 0
        let firstFailure = expectation(description: "first failure")
        let flowSucceeded = expectation(description: "flow succeeded after retry")
        
        delegate.onProgressCall = { flowId, progress, tags in
            switch progress {
            case .failure:
                failureCount += 1
                if failureCount == 1 {
                    firstFailure.fulfill()
                    // After first failure, configure step to succeed on next attempt
                    flow.configurableStep.shouldFail = false
                }
            case .success:
                flowSucceeded.fulfill()
            default:
                break
            }
        }
        
        engine.executeNewFlow(.configurable(flow))
        
        // Wait for first failure, then success after retry
        wait(for: [firstFailure, flowSucceeded], timeout: 5, enforceOrder: true)
        
        // Verify the step was executed twice (initial failure + successful retry)
        XCTAssertEqual(flow.configurableStep.executionCount, 2, "Step should have been executed twice")
        XCTAssertEqual(failureCount, 1, "Should have only 1 failure before success")
    }
    
    /// Test that retry count is limited by maxRetryCount
    func testMaxRetryCountLimit() throws {
        let flow = ConfigurableFlow(identifier: "max_retry_test")
        flow.configurableStep.shouldFail = true // Always fail
        
        let delegate = TestFlowEngineDelegate()
        let engine = TestFlowEngine(
            stateStore: TestFlowStateStore(),
            logger: { print("[\($1)] \(Date()) \(String(describing: $0)) \($2)") }
        )
        engine.delegate = delegate
        
        // Configure very short retry delays and low max retry count
        engine.retryBaseDelay = 0.05
        engine.retryMaxDelay = 0.1
        engine.maxRetryCount = 2
        
        var failureCount = 0
        let allRetriesExhausted = expectation(description: "all retries exhausted")
        
        delegate.onProgressCall = { flowId, progress, tags in
            if case .failure = progress {
                failureCount += 1
                // Initial execution + 2 retries = 3 failures total
                // But after maxRetryCount (2), flow should be disposed
                if failureCount >= 3 {
                    allRetriesExhausted.fulfill()
                }
            }
        }
        
        engine.executeNewFlow(.configurable(flow))
        
        wait(for: [allRetriesExhausted], timeout: 5)
        
        // Initial + 2 retries = 3 executions
        XCTAssertEqual(flow.configurableStep.executionCount, 3, "Step should have been executed 3 times (initial + 2 retries)")
        
        // Wait a bit more and verify flow was disposed (no longer in engine)
        Thread.sleep(forTimeInterval: 0.5)
        XCTAssertNil(engine.flow(flow.identifier), "Flow should be disposed after max retries")
    }
}

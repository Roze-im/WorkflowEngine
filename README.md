# WorkflowEngine

This package allows asynchronous processing of data through a series of steps.

Engine spawns flows, composed of multiple steps.

```
typealias FooFlowEngine = WorkflowEngine<AnyFooFlow, WorkflowIndex<AnyFooFlow>, FileDataStore, FooWorkflowDelegate>

enum AnyFooFlow: AnyWorkflowType {

    case downloadFoo(DownloadAndDecryptFooFlow)
    case uploadFoo(EncryptAndUploadFooFlow)

    var flow: Workflow {
        switch self {
        case .downloadFoo(let flow):
            return flow
        case .uploadFoo(let flow):
            return flow
        }
    }
}

final class FooWorkflowDelegate: WorkflowEngineDelegate {
    typealias AnyWorkflow = AnyFooFlow
    typealias Index = WorkflowIndex<AnyFooFlow>
    typealias Store = FileDataStore
    typealias OnFlowDidProgress = (WorkflowId, WorkflowProgress, Set<String>) -> Void
    var onFlowDidProgress: OnFlowDidProgress

    init(onFlowDidProgress: @escaping OnFlowDidProgress) {
        self.onFlowDidProgress = onFlowDidProgress
    }

    func workflowEngine(
        _ engine: FooFlowEngineType,
        flow: WorkflowId,
        didRegisterProgress: WorkflowProgress,
        tags: Set<String>
    ) {
        onFlowDidProgress(flow, didRegisterProgress, tags)
    }
}

class DownloadAndDecryptFooFlow: Workflow {
    enum CodingKeys: CodingKey {
        case downloadFoo
        case decryptFoo
    }

    let fooDownloading: FooDownloadingStep
    let fooDecrypting: FooDecryptingStep

    init(
        foo: Foo,
        destination: URL,
        tags: Set<String> = [], 
        waitFor: Set<WorkflowId> = []
    ) {
        let encryptedFooPath = URL(/* eg: generate a tmp path */)
        
        fooDownloading = .init(foo: foo, destination: encryptedFooPath)
        fooDecrypting = .init(foo: foo, source: encryptedFooPath, destination: destination)
        super.init(
            url: url, 
            identifier: "DownloadFooFlow_\(foo.identifier)", 
            tags: tags,
            waitFor: waitFor
        )
    }

    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        fooDownloading = try container.decode(FooDownloadingStep.self, forKey: .downloadFoo)
        fooDecrypting = try container.decode(FooDecryptingStep.self, forKey: .decryptFoo)
        try super.init(from: decoder)
    }

    override func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(fooDownloading, forKey: .downloadFoo)
        try container.encode(fooDecrypting, forKey: .decryptFoo)
        try super.encode(to: encoder)
    }
}

class FooDownloadingStep: WorkflowStep {

    let destination: URL

    override func execute() {
        super.execute()
        
        // Foo downloading logic to URL
        updateProgress(to: .inProgress(0.5))
        updateProgress(to: .success)
    }
}
class FooDecryptingStep: WorkflowStep {

    let source: URL
    let destination: URL

    override func execute() {
        super.execute()
        
        // Foo decrypting logic logic, eg: read from source, and write decrypted foo to destination
        updateProgress(to: .inProgress(0.5))
        updateProgress(to: .success)
    }
}

let fooEngine = FooFlowEngine()
let delegate = FooWorkflowDelegate()
fooEngine.delegate = delegate

delegate.onFlowDidProgress = { progress in
    switch progress {
        case pending: 
            break
        case executing(let currentStepIndex, let progress, let stepsCount):
            break
        case success:
            break
        case failure(let code, let message: String):
            break
        case cancelled:
            break
    }
}

let destination = URL(/* Generate destination URL */)
fooEngine.executeNewFlow(
    .downloadFoo(DownloadAndDecryptFooFlow(foo: foo, destination: destination))
)

```

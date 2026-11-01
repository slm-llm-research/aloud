// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "InstructFlow",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "InstructFlow", targets: ["InstructFlow"]),
    ],
    dependencies: [
        // Parakeet on the Apple Neural Engine. Pinned exactly; bump deliberately.
        .package(url: "https://github.com/FluidInference/FluidAudio.git", exact: "0.18.0"),
    ],
    targets: [
        // Trigger-key logic (pure state machine + key classification) and the CGEventTap adapter.
        .target(name: "HotkeyKit"),
        // Microphone capture and 16 kHz mono conversion.
        .target(name: "AudioKit"),
        // Speech-to-text engines behind one protocol.
        .target(name: "STTKit", dependencies: [.product(name: "FluidAudio", package: "FluidAudio")]),
        // Putting text into the focused app: pasteboard save/restore, synthesized paste, sanitizing.
        .target(name: "InsertKit"),
        // Dictation cleanup: personal dictionary, deterministic prepass, LLM clients, guardrail.
        .target(name: "CleanupKit"),
        // Client for the local agent daemon (agentd/): socket protocol, connection, process.
        .target(name: "AgentKit"),
        // The agent island: task state, plan and approval cards at the top of the screen (SwiftUI).
        .target(name: "AgentUI", dependencies: ["AgentKit"]),
        // The session flow (record -> transcribe race -> clean -> insert). Depends only on
        // protocols, so it is tested with fakes.
        .target(name: "InstructFlowCore", dependencies: ["HotkeyKit"]),
        // The menubar app: wires the real implementations into InstructFlowCore.
        .executableTarget(name: "InstructFlow",
                          dependencies: ["HotkeyKit", "AudioKit", "STTKit", "InsertKit", "CleanupKit", "AgentKit", "AgentUI", "InstructFlowCore"]),

        .testTarget(name: "HotkeyKitTests", dependencies: ["HotkeyKit"]),
        .testTarget(name: "AudioKitTests", dependencies: ["AudioKit"]),
        .testTarget(name: "InsertKitTests", dependencies: ["InsertKit"]),
        // Runs the real model; skipped unless INSTRUCTFLOW_INTEGRATION=1 (first run downloads ~600 MB).
        .testTarget(name: "STTKitTests", dependencies: ["STTKit", "AudioKit"]),
        .testTarget(name: "InstructFlowCoreTests", dependencies: ["InstructFlowCore", "HotkeyKit"]),
        // Unit tests always; live Groq/Anthropic tests only with INSTRUCTFLOW_INTEGRATION=1 and keys in env.
        .testTarget(name: "CleanupKitTests", dependencies: ["CleanupKit"]),
        // Protocol unit tests; with INSTRUCTFLOW_INTEGRATION=1, a real agentd round trip (ping only, no LLM).
        .testTarget(name: "AgentKitTests", dependencies: ["AgentKit"]),
        // Renders the island's states to PNG when INSTRUCTFLOW_RENDER_DIR is set (visual check).
        .testTarget(name: "AgentUITests", dependencies: ["AgentUI", "AgentKit"]),
    ]
)

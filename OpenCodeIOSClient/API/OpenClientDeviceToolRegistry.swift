import Foundation

struct OpenClientDeviceToolProvider: Sendable {
    typealias Handler = @Sendable (
        [String: OpenClientJSONValue],
        OpenClientRemoteToolContext
    ) async throws -> OpenClientRemoteToolResult

    let descriptor: OpenClientDeviceToolDescriptor
    private let handler: Handler

    init(descriptor: OpenClientDeviceToolDescriptor, handler: @escaping Handler) {
        self.descriptor = descriptor
        self.handler = handler
    }

    func execute(
        arguments: [String: OpenClientJSONValue],
        context: OpenClientRemoteToolContext
    ) async throws -> OpenClientRemoteToolResult {
        try await handler(arguments, context)
    }
}

actor OpenClientDeviceToolRegistry {
    private let descriptors: [OpenClientDeviceToolDescriptor]
    private let providersByID: [String: OpenClientDeviceToolProvider]

    init(
        providers: [OpenClientDeviceToolProvider]? = nil,
        browserStore: BrowserStore? = nil
    ) {
        var resolvedProviders = providers ?? [.deviceStatus, .visualChart, .visualHTML, .visualMap]
        if let browserStore {
            resolvedProviders.append(contentsOf: OpenClientDeviceToolProvider.browserTools(browserStore: browserStore))
        }
        precondition(
            Set(resolvedProviders.map(\.descriptor.id)).count == resolvedProviders.count,
            "Duplicate OpenClient device-tool ID"
        )
        descriptors = resolvedProviders.map(\.descriptor).sorted { $0.id < $1.id }
        providersByID = Dictionary(
            uniqueKeysWithValues: resolvedProviders.map { ($0.descriptor.id, $0) }
        )
    }

    func listTools() -> [OpenClientDeviceToolDescriptor] {
        descriptors
    }

    func execute(
        toolID: String,
        arguments: [String: OpenClientJSONValue],
        context: OpenClientRemoteToolContext
    ) async throws -> OpenClientRemoteToolResult {
        guard let provider = providersByID[toolID] else {
            throw OpenClientBridgeProtocolError.unknownTool(toolID)
        }
        return try await provider.execute(arguments: arguments, context: context)
    }
}

private extension OpenClientDeviceToolProvider {
    static var deviceStatus: OpenClientDeviceToolProvider {
        OpenClientDeviceToolProvider(
            descriptor: OpenClientDeviceToolDescriptor(
                id: "openclient_device_status",
                description: "Return the connected OpenClient app version, operating system, and protocol version.",
                inputSchema: [
                    "type": .string("object"),
                    "properties": .object([:]),
                    "additionalProperties": .bool(false),
                ]
            )
        ) { arguments, context in
            guard arguments.isEmpty else {
                throw OpenClientBridgeProtocolError.invalidField("arguments")
            }

            let info = Bundle.main.infoDictionary
            let status: [String: OpenClientJSONValue] = [
                "appVersion": .string(info?["CFBundleShortVersionString"] as? String ?? "unknown"),
                "build": .string(info?["CFBundleVersion"] as? String ?? "unknown"),
                "operatingSystem": .string(ProcessInfo.processInfo.operatingSystemVersionString),
                "protocolVersion": .number(Double(openClientBridgeProtocolVersion)),
                "sessionID": .string(context.sessionID),
            ]
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let output = String(
                data: try encoder.encode(OpenClientJSONValue.object(status)),
                encoding: .utf8
            ) ?? "{}"
            return OpenClientRemoteToolResult(
                title: "OpenClient device status",
                output: output,
                metadata: ["toolID": .string("openclient_device_status")]
            )
        }
    }

    static func browserTools(browserStore: BrowserStore) -> [OpenClientDeviceToolProvider] {
        [
            OpenClientDeviceToolProvider(
                descriptor: OpenClientDeviceToolDescriptor(
                    id: "openclient_browser_clear_instruction",
                    description: "Remove the user-facing instruction from the expanded OpenClient browser after the requested review or input is complete.",
                    inputSchema: objectSchema(required: [], properties: [:])
                )
            ) { arguments, _ in
                try requireKeys(arguments, allowed: [])
                let page = try await browserStore.clearAutomationInstruction()
                return try browserResult(
                    toolID: "openclient_browser_clear_instruction",
                    title: "Browser instruction cleared",
                    value: page
                )
            },
            OpenClientDeviceToolProvider(
                descriptor: OpenClientDeviceToolDescriptor(
                    id: "openclient_browser_present",
                    description: "Expand the OpenClient in-app browser when the user should view or interact with the page. Displays an instruction in the browser sheet.",
                    inputSchema: objectSchema(
                        required: ["instruction"],
                        properties: [
                            "instruction": stringSchema(
                                maximumLength: 500,
                                description: "A concise instruction explaining what the user should view or do in the browser."
                            ),
                        ]
                    )
                )
            ) { arguments, _ in
                try requireKeys(arguments, allowed: ["instruction"])
                let instruction = try requiredString(arguments, key: "instruction", maximumLength: 500)
                let page = try await browserStore.presentForAutomation(instruction: instruction)
                return try browserResult(
                    toolID: "openclient_browser_present",
                    title: "Browser presented",
                    value: page
                )
            },
            OpenClientDeviceToolProvider(
                descriptor: OpenClientDeviceToolDescriptor(
                    id: "openclient_browser_navigate",
                    description: "Navigate the OpenClient in-app browser to a URL or search query without changing its presentation and return the resulting page state.",
                    inputSchema: objectSchema(
                        required: ["address"],
                        properties: [
                            "address": stringSchema(
                                maximumLength: 2_048,
                                description: "An http/https URL, hostname, or search query."
                            ),
                        ]
                    )
                )
            ) { arguments, _ in
                try requireKeys(arguments, allowed: ["address"])
                let address = try requiredString(arguments, key: "address", maximumLength: 2_048)
                let page = try await withBrowserActivity(browserStore, status: "Navigating browser") {
                    try await browserStore.automationNavigate(to: address)
                }
                return try browserResult(
                    toolID: "openclient_browser_navigate",
                    title: "Browser navigated",
                    value: page
                )
            },
            OpenClientDeviceToolProvider(
                descriptor: OpenClientDeviceToolDescriptor(
                    id: "openclient_browser_snapshot",
                    description: "Inspect the current in-app browser page. Returns visible text and interactive elements with stable refs for click and type actions.",
                    inputSchema: objectSchema(required: [], properties: [:])
                )
            ) { arguments, _ in
                try requireKeys(arguments, allowed: [])
                let snapshot = try await withBrowserActivity(browserStore, status: "Inspecting page") {
                    try await browserStore.automationSnapshot()
                }
                return try browserResult(
                    toolID: "openclient_browser_snapshot",
                    title: "Browser snapshot",
                    value: snapshot
                )
            },
            OpenClientDeviceToolProvider(
                descriptor: OpenClientDeviceToolDescriptor(
                    id: "openclient_browser_click",
                    description: "Click an interactive element from the latest browser snapshot using its ref.",
                    inputSchema: objectSchema(
                        required: ["ref"],
                        properties: [
                            "ref": stringSchema(maximumLength: 80, description: "Element ref from openclient_browser_snapshot."),
                        ]
                    )
                )
            ) { arguments, _ in
                try requireKeys(arguments, allowed: ["ref"])
                let ref = try requiredString(arguments, key: "ref", maximumLength: 80)
                let page = try await withBrowserActivity(browserStore, status: "Interacting with page") {
                    try await browserStore.automationClick(ref: ref)
                }
                return try browserResult(
                    toolID: "openclient_browser_click",
                    title: "Browser element clicked",
                    value: page
                )
            },
            OpenClientDeviceToolProvider(
                descriptor: OpenClientDeviceToolDescriptor(
                    id: "openclient_browser_type",
                    description: "Type into an editable element from the latest browser snapshot, optionally clearing it first or submitting its form.",
                    inputSchema: objectSchema(
                        required: ["ref", "text"],
                        properties: [
                            "ref": stringSchema(maximumLength: 80, description: "Element ref from openclient_browser_snapshot."),
                            "text": stringSchema(maximumLength: 16_384, description: "Text to enter."),
                            "clear": [
                                "type": .string("boolean"),
                                "default": .bool(true),
                                "description": .string("Replace the current value when true; append when false."),
                            ],
                            "submit": [
                                "type": .string("boolean"),
                                "default": .bool(false),
                                "description": .string("Submit the enclosing form after typing."),
                            ],
                        ]
                    )
                )
            ) { arguments, _ in
                try requireKeys(arguments, allowed: ["ref", "text", "clear", "submit"])
                let ref = try requiredString(arguments, key: "ref", maximumLength: 80)
                let text = try requiredString(arguments, key: "text", maximumLength: 16_384, allowsEmpty: true)
                let clear = try optionalBool(arguments, key: "clear") ?? true
                let submit = try optionalBool(arguments, key: "submit") ?? false
                let page = try await withBrowserActivity(browserStore, status: "Entering text") {
                    try await browserStore.automationType(
                        ref: ref,
                        text: text,
                        clear: clear,
                        submit: submit
                    )
                }
                return try browserResult(
                    toolID: "openclient_browser_type",
                    title: "Browser text entered",
                    value: page
                )
            },
            OpenClientDeviceToolProvider(
                descriptor: OpenClientDeviceToolDescriptor(
                    id: "openclient_browser_history",
                    description: "Drive in-app browser history with back, forward, or reload and return the resulting page state.",
                    inputSchema: objectSchema(
                        required: ["action"],
                        properties: [
                            "action": [
                                "type": .string("string"),
                                "enum": .array([.string("back"), .string("forward"), .string("reload")]),
                            ],
                        ]
                    )
                )
            ) { arguments, _ in
                try requireKeys(arguments, allowed: ["action"])
                let action = try requiredString(arguments, key: "action", maximumLength: 16)
                let page = try await withBrowserActivity(browserStore, status: "Updating browser history") {
                    try await browserStore.automationHistory(action: action)
                }
                return try browserResult(
                    toolID: "openclient_browser_history",
                    title: "Browser \(action)",
                    value: page
                )
            },
        ]
    }

    static func withBrowserActivity<T: Sendable>(
        _ browserStore: BrowserStore,
        status: String,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        let token = try await browserStore.beginAutomationActivity(status)
        do {
            let result = try await operation()
            await browserStore.endAutomationActivity(token)
            return result
        } catch {
            await browserStore.endAutomationActivity(token)
            throw error
        }
    }

    static func browserResult<T: Encodable>(
        toolID: String,
        title: String,
        value: T
    ) throws -> OpenClientRemoteToolResult {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(value)
        let output = String(data: data, encoding: .utf8) ?? "{}"
        let jsonValue = try JSONDecoder().decode(OpenClientJSONValue.self, from: data)
        return OpenClientRemoteToolResult(
            title: title,
            output: output,
            metadata: [
                "toolID": .string(toolID),
                "result": jsonValue,
            ]
        )
    }

    static func objectSchema(
        required: [String],
        properties: [String: [String: OpenClientJSONValue]]
    ) -> [String: OpenClientJSONValue] {
        var schema: [String: OpenClientJSONValue] = [
            "type": .string("object"),
            "properties": .object(properties.mapValues(OpenClientJSONValue.object)),
            "additionalProperties": .bool(false),
        ]
        if !required.isEmpty {
            schema["required"] = .array(required.map(OpenClientJSONValue.string))
        }
        return schema
    }

    static func stringSchema(
        maximumLength: Int,
        description: String
    ) -> [String: OpenClientJSONValue] {
        [
            "type": .string("string"),
            "maxLength": .number(Double(maximumLength)),
            "description": .string(description),
        ]
    }

    static func requireKeys(
        _ arguments: [String: OpenClientJSONValue],
        allowed: Set<String>
    ) throws {
        guard Set(arguments.keys).isSubset(of: allowed) else {
            throw OpenClientBridgeProtocolError.invalidField("arguments")
        }
    }

    static func requiredString(
        _ arguments: [String: OpenClientJSONValue],
        key: String,
        maximumLength: Int,
        allowsEmpty: Bool = false
    ) throws -> String {
        guard let value = arguments[key]?.stringValue,
              value.count <= maximumLength,
              value.lengthOfBytes(using: .utf8) <= maximumLength * 4,
              allowsEmpty || !value.isEmpty else {
            throw OpenClientBridgeProtocolError.invalidField("arguments.\(key)")
        }
        return value
    }

    static func optionalBool(
        _ arguments: [String: OpenClientJSONValue],
        key: String
    ) throws -> Bool? {
        guard let value = arguments[key] else { return nil }
        guard let bool = value.boolValue else {
            throw OpenClientBridgeProtocolError.invalidField("arguments.\(key)")
        }
        return bool
    }
}

import { describe, expect, test } from "bun:test"
import { parseClientMessage, parseToolList } from "../src/protocol.js"

describe("OpenClient protocol", () => {
  test("parses registration", () => {
    expect(parseClientMessage(JSON.stringify({
      protocol: 1,
      type: "register",
      clientID: "iphone",
      displayName: "iPhone",
      appVersion: "1.0",
    }))).toEqual({
      protocol: 1,
      type: "register",
      clientID: "iphone",
      displayName: "iPhone",
      appVersion: "1.0",
    })
  })

  test("rejects duplicate tool IDs", () => {
    expect(() => parseToolList({
      tools: [
        { id: "status", description: "One", inputSchema: {} },
        { id: "status", description: "Two", inputSchema: {} },
      ],
    })).toThrow("Duplicate tool ID")
  })

  test("rejects unsupported messages", () => {
    expect(() => parseClientMessage('{"protocol":2,"type":"register"}')).toThrow("Unsupported protocol")
  })
})

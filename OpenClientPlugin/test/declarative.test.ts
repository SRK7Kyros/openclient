import { describe, expect, test } from "bun:test"
import {
  executeDeclarativeTool,
  imageDeclarativeResult,
  imageToolDescriptor,
  isDeclarativeTool,
  normalizeImageArguments,
  normalizeVideoArguments,
  videoDeclarativeResult,
  videoToolDescriptor,
} from "../src/declarative.js"

describe("declarative visual tools", () => {
  test("creates persisted HTML renderer metadata without a device response", () => {
    const arguments_ = {
      schemaVersion: 1,
      title: "Odysseus Journey",
      accessibilityLabel: "A route from Troy to Ithaca.",
      html: "<div>Homeward bound</div>",
      height: 320,
    }

    expect(executeDeclarativeTool("openclient_visual_html", arguments_)).toEqual({
      title: "Odysseus Journey",
      output: "Displayed the static HTML visual \"Odysseus Journey\".",
      metadata: {
        toolID: "openclient_visual_html",
        renderer: "openclient.html.v1",
        schemaVersion: 1,
        executionMode: "declarative",
        payload: arguments_,
      },
    })
  })

  test("recognizes only first-party declarative visuals", () => {
    expect(isDeclarativeTool("openclient_visual_map")).toBe(true)
    expect(isDeclarativeTool("openclient_visual_chart")).toBe(true)
    expect(isDeclarativeTool("openclient_visual_image")).toBe(true)
    expect(isDeclarativeTool("openclient_visual_video")).toBe(true)
    expect(isDeclarativeTool("openclient_device_status")).toBe(false)
  })

  test("publishes the lazy MP4 video contract", () => {
    expect(videoToolDescriptor).toEqual({
      id: "openclient_visual_video",
      description: expect.stringContaining("MP4"),
      inputSchema: {
        type: "object",
        required: ["schemaVersion", "filePath"],
        additionalProperties: false,
        properties: {
          schemaVersion: { type: "integer", const: 1 },
          title: { type: "string", minLength: 1, maxLength: 120, pattern: "\\S" },
          filePath: {
            type: "string",
            minLength: 1,
            description: "Absolute path to an MP4 file on the OpenCode host.",
          },
        },
      },
    })
    expect(normalizeVideoArguments({
      schemaVersion: 1,
      title: "  Launch  ",
      filePath: "/tmp/launch.MP4",
    })).toEqual({
      schemaVersion: 1,
      title: "Launch",
      filePath: "/tmp/launch.MP4",
    })

    const rendered = videoDeclarativeResult({
      schemaVersion: 1,
      resourceID: "opaque-resource",
      startPath: "/openclient/v1/video/resources/opaque-resource/stream",
      stopPath: "/openclient/v1/video/resources/opaque-resource/stream",
      expiresAt: "2026-07-27T00:00:00.000Z",
      width: 1_920,
      height: 1_080,
      rotation: 90,
      duration: 12.5,
      cover: {
        mimeType: "image/jpeg",
        dataURL: "data:image/jpeg;base64,/9j/2Q==",
        width: 96,
        height: 54,
      },
      file: {
        name: "launch.mp4",
        sizeBytes: 42,
        modifiedAt: "2026-07-27T00:00:00.000Z",
        mimeType: "video/mp4",
      },
    })
    expect(rendered.metadata).toMatchObject({
      toolID: "openclient_visual_video",
      renderer: "openclient.video.v1",
      schemaVersion: 1,
      executionMode: "declarative",
      payload: {
        resourceID: "opaque-resource",
        startPath: "/openclient/v1/video/resources/opaque-resource/stream",
        width: 1_920,
        height: 1_080,
        rotation: 90,
        duration: 12.5,
        cover: { mimeType: "image/jpeg", width: 96, height: 54 },
      },
    })
    expect(JSON.stringify(rendered)).not.toContain("hlsPath")

  })

  test("publishes and normalizes the lazy image contract", () => {
    expect(imageToolDescriptor).toEqual({
      id: "openclient_visual_image",
      description: expect.stringContaining("JPEG, PNG, or WebP"),
      inputSchema: {
        type: "object",
        required: ["schemaVersion", "filePath"],
        additionalProperties: false,
        properties: {
          schemaVersion: { type: "integer", const: 1 },
          title: { type: "string", minLength: 1, maxLength: 120, pattern: "\\S" },
          accessibilityLabel: { type: "string", minLength: 1, maxLength: 500, pattern: "\\S" },
          filePath: {
            type: "string",
            minLength: 1,
            description: "Absolute path to a JPEG, PNG, or WebP file on the OpenCode host.",
          },
        },
      },
    })
    expect(normalizeImageArguments({
      schemaVersion: 1,
      title: "  Aurora  ",
      accessibilityLabel: "  Green lights above a mountain.  ",
      filePath: "/tmp/aurora.WeBP",
    })).toEqual({
      schemaVersion: 1,
      title: "Aurora",
      accessibilityLabel: "Green lights above a mountain.",
      filePath: "/tmp/aurora.WeBP",
    })

    const rendered = imageDeclarativeResult({
      schemaVersion: 1,
      title: "Aurora",
      accessibilityLabel: "Green lights above a mountain.",
      resourceID: "opaque-resource",
      contentPath: "/openclient/v1/image/resources/opaque-resource/content",
      expiresAt: "2026-07-27T00:00:00.000Z",
      width: 1_200,
      height: 800,
      file: {
        name: "aurora.webp",
        sizeBytes: 42,
        modifiedAt: "2026-07-27T00:00:00.000Z",
        mimeType: "image/webp",
      },
      preview: {
        mimeType: "image/jpeg",
        dataURL: "data:image/jpeg;base64,/9j/2Q==",
        width: 96,
        height: 64,
      },
    })
    expect(rendered).toMatchObject({
      title: "Aurora",
      metadata: {
        toolID: "openclient_visual_image",
        renderer: "openclient.image.v1",
        executionMode: "declarative",
        payload: {
          resourceID: "opaque-resource",
          contentPath: "/openclient/v1/image/resources/opaque-resource/content",
          accessibilityLabel: "Green lights above a mountain.",
          width: 1_200,
          height: 800,
          preview: { mimeType: "image/jpeg", width: 96, height: 64 },
        },
      },
    })
  })

  test("rejects non-absolute and non-MP4 video inputs", () => {
    expect(() => normalizeVideoArguments({ schemaVersion: 1, filePath: "clip.mp4" })).toThrow("absolute path")
    expect(() => normalizeVideoArguments({ schemaVersion: 1, filePath: "/tmp/clip.mov" })).toThrow("MP4")
    expect(() => normalizeVideoArguments({ schemaVersion: 2, filePath: "/tmp/clip.mp4" })).toThrow("schemaVersion 1")
    expect(() => normalizeVideoArguments({
      schemaVersion: 1,
      filePath: "/tmp/clip.mp4",
      hlsPath: "/unsafe",
    })).toThrow("unknown field")
  })

  test("rejects invalid image inputs", () => {
    expect(() => normalizeImageArguments({ schemaVersion: 1, filePath: "photo.png" })).toThrow("absolute path")
    expect(() => normalizeImageArguments({ schemaVersion: 1, filePath: "/tmp/photo.gif" })).toThrow("JPEG, PNG, or WebP")
    expect(() => normalizeImageArguments({ schemaVersion: 1, filePath: "/tmp/photo.png", title: "  " })).toThrow("Image title")
    expect(() => normalizeImageArguments({
      schemaVersion: 1,
      filePath: "/tmp/photo.png",
      accessibilityLabel: "a".repeat(501),
    })).toThrow("500 characters")
    expect(() => normalizeImageArguments({
      schemaVersion: 1,
      filePath: "/tmp/photo.png",
      source: "private",
    })).toThrow("unknown field")
  })

  test("rejects incomplete offline payloads", () => {
    expect(() => executeDeclarativeTool("openclient_visual_html", {
      schemaVersion: 1,
      title: "Broken",
      accessibilityLabel: "Missing HTML.",
      height: 320,
    })).toThrow("HTML fragment")
    expect(() => executeDeclarativeTool("openclient_visual_map", {
      schemaVersion: 2,
      center: { latitude: 0, longitude: 0 },
    })).toThrow("schemaVersion 1")
  })

  test("matches HTML safety and payload limits offline", () => {
    const longHTML = `<div>${"journey ".repeat(100)}</div>`
    expect(executeDeclarativeTool("openclient_visual_html", {
      schemaVersion: 1,
      title: "Long Journey",
      accessibilityLabel: "A long but valid static visual.",
      html: longHTML,
      height: 320,
    })?.metadata?.payload).toEqual({
      schemaVersion: 1,
      title: "Long Journey",
      accessibilityLabel: "A long but valid static visual.",
      html: longHTML,
      height: 320,
    })

    expect(() => executeDeclarativeTool("openclient_visual_html", {
      schemaVersion: 1,
      title: "Unsafe",
      accessibilityLabel: "Unsafe script content.",
      html: "<script>alert(1)</script>",
      height: 320,
    })).toThrow("unsupported content")
  })

  test("allows long HTML pages", () => {
    expect(executeDeclarativeTool("openclient_visual_html", {
      schemaVersion: 1,
      title: "Long Page",
      accessibilityLabel: "A long static product page.",
      html: "<main>Long product page</main>",
      height: 4_800,
    })?.metadata?.payload).toMatchObject({ height: 4_800 })
  })

  test("rejects invalid map and chart payloads offline", () => {
    expect(() => executeDeclarativeTool("openclient_visual_map", {
      schemaVersion: 1,
      center: { latitude: 91, longitude: 0 },
    })).toThrow("out of range")

    expect(() => executeDeclarativeTool("openclient_visual_chart", {
      schemaVersion: 1,
      chartType: "pie",
      xAxis: { type: "category" },
      series: [{
        id: "series",
        name: "Invalid pie",
        points: [{ id: "negative", x: "Input", y: -1 }],
      }],
    })).toThrow("nonnegative")
  })
})

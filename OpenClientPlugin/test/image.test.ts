import { describe, expect, test } from "bun:test"
import { mkdtemp, readFile, rm, stat, writeFile } from "node:fs/promises"
import { join } from "node:path"
import { tmpdir } from "node:os"
import {
  ImageResourceManager,
  type ImageExecutionContext,
  type ImageMimeType,
} from "../src/image.js"
import { jpegPreview } from "./fixtures.js"

const context: ImageExecutionContext = {
  clientID: "client",
  sessionID: "session",
  messageID: "message",
  agent: "build",
  directory: "/tmp/project",
  worktree: "/tmp/project",
}

describe("lazy image resources", () => {
  test("creates canonical metadata and loads original bytes through an identity-validated descriptor", async () => {
    const temporary = await mkdtemp(join(tmpdir(), "openclient-image-test-"))
    const source = join(temporary, "private-source.PNG")
    const sourceBytes = Uint8Array.from([0x89, 0x50, 0x4e, 0x47, 1, 2, 3, 4])
    await writeFile(source, sourceBytes)
    const rootDirectory = join(temporary, "state")
    const registryPath = join(rootDirectory, "image-resources.json")
    const manager = new ImageResourceManager({
      rootDirectory,
      registryPath,
      probe: async (command, sourceFD) => {
        expect(command).toContain("ffprobe")
        expect(command).toContain("/dev/fd/3")
        expect(command).not.toContain(source)
        expect(sourceFD).toBeGreaterThan(2)
        return imageProbe("image/png", 1_200, 800)
      },
      preview: async (command, sourceFD) => {
        expect(command).toContain("ffmpeg")
        expect(command).toContain("/dev/fd/3")
        expect(command).not.toContain(source)
        expect(sourceFD).toBeGreaterThan(2)
        return jpegPreview(96, 64)
      },
    })
    try {
      const payload = await manager.createResource({
        filePath: source,
        title: "  Aurora  ",
        accessibilityLabel: "  Green lights over a mountain.  ",
        context,
      })
      const resourceID = payload.resourceID

      expect(payload).toMatchObject({
        schemaVersion: 1,
        title: "Aurora",
        accessibilityLabel: "Green lights over a mountain.",
        resourceID: expect.stringMatching(/^[A-Za-z0-9_-]{32}$/),
        contentPath: `/openclient/v1/image/resources/${resourceID}/content`,
        expiresAt: expect.any(String),
        width: 1_200,
        height: 800,
        file: {
          name: "private-source.PNG",
          sizeBytes: sourceBytes.byteLength,
          modifiedAt: expect.any(String),
          mimeType: "image/png",
        },
        preview: {
          mimeType: "image/jpeg",
          dataURL: expect.stringMatching(/^data:image\/jpeg;base64,/),
          width: 96,
          height: 64,
        },
      })
      expect(JSON.stringify(payload)).not.toContain(source)
      expect(JSON.stringify(payload)).not.toContain(Buffer.from(sourceBytes).toString("base64"))
      expect(/^[A-Za-z0-9_-]{32}$/.test(resourceID)).toBe(true)
      const content = await manager.load(resourceID)
      expect(content.contentType).toBe("image/png")
      expect(content.sizeBytes).toBe(sourceBytes.byteLength)
      expect(content.bytes).toEqual(sourceBytes)
      expect((await stat(rootDirectory)).mode & 0o777).toBe(0o700)
      expect((await stat(registryPath)).mode & 0o777).toBe(0o600)
    } finally {
      await manager.stopAll()
      await rm(temporary, { recursive: true, force: true })
    }
  })

  test("restores resources after restart and rejects changed sources", async () => {
    const temporary = await mkdtemp(join(tmpdir(), "openclient-image-test-"))
    const source = join(temporary, "durable.webp")
    const registryPath = join(temporary, "state", "image-resources.json")
    await writeFile(source, "original webp")
    const first = imageManager(temporary, registryPath)
    let second: ImageResourceManager | undefined
    try {
      const payload = await first.createResource({ filePath: source, context })
      await first.stopAll()

      second = new ImageResourceManager({ registryPath })
      expect(new TextDecoder().decode((await second.load(payload.resourceID)).bytes)).toBe("original webp")
      await writeFile(source, "changed webp source")
      await expect(second.load(payload.resourceID)).rejects.toThrow("changed after")
    } finally {
      await first.stopAll()
      await second?.stopAll()
      await rm(temporary, { recursive: true, force: true })
    }
  })

  test("enforces source formats and size, rolling expiry, and dormant LRU capacity", async () => {
    const temporary = await mkdtemp(join(tmpdir(), "openclient-image-test-"))
    const registryPath = join(temporary, "state", "image-resources.json")
    let now = 1
    const manager = new ImageResourceManager({
      registryPath,
      maximumResources: 2,
      resourceTTLMS: 10,
      now: () => now,
      probe: async () => imageProbe("image/jpeg", 100, 50),
      preview: async () => jpegPreview(96, 48),
    })
    try {
      await expect(manager.createResource({ filePath: "relative.jpg", context })).rejects.toThrow("absolute path")
      const unsupported = join(temporary, "image.gif")
      await writeFile(unsupported, "gif")
      await expect(manager.createResource({ filePath: unsupported, context })).rejects.toThrow("JPEG, PNG, or WebP")

      const oversized = join(temporary, "oversized.jpg")
      await writeFile(oversized, "12345")
      const bounded = new ImageResourceManager({
        registryPath: join(temporary, "bounded", "image-resources.json"),
        maximumSourceBytes: 4,
      })
      await expect(bounded.createResource({ filePath: oversized, context })).rejects.toThrow("size limit")
      await bounded.stopAll()

      const firstPath = join(temporary, "first.jpg")
      const secondPath = join(temporary, "second.jpeg")
      const thirdPath = join(temporary, "third.JPG")
      await Promise.all([
        writeFile(firstPath, "first"),
        writeFile(secondPath, "second"),
        writeFile(thirdPath, "third"),
      ])
      const first = await manager.createResource({ filePath: firstPath, context })
      now = 2
      const second = await manager.createResource({ filePath: secondPath, context })
      now = 3
      await manager.load(first.resourceID)
      now = 4
      const third = await manager.createResource({ filePath: thirdPath, context })
      await expect(manager.load(second.resourceID)).rejects.toMatchObject({ status: 404 })
      expect(new TextDecoder().decode((await manager.load(first.resourceID)).bytes)).toBe("first")
      expect(new TextDecoder().decode((await manager.load(third.resourceID)).bytes)).toBe("third")

      now = 15
      await expect(manager.load(first.resourceID)).rejects.toMatchObject({ status: 404 })
      expect(JSON.parse(await readFile(registryPath, "utf8"))).toMatchObject({ resources: [] })
    } finally {
      await manager.stopAll()
      await rm(temporary, { recursive: true, force: true })
    }
  })

  test("rejects invalid generated previews before persisting a resource", async () => {
    const temporary = await mkdtemp(join(tmpdir(), "openclient-image-test-"))
    const source = join(temporary, "invalid.png")
    const registryPath = join(temporary, "state", "image-resources.json")
    await writeFile(source, "png")
    const manager = new ImageResourceManager({
      registryPath,
      probe: async () => imageProbe("image/png", 10, 10),
      preview: async () => jpegPreview(97, 10),
    })
    try {
      await expect(manager.createResource({ filePath: source, context })).rejects.toThrow("dimensions")
      await expect(readFile(registryPath, "utf8")).rejects.toThrow()
    } finally {
      await manager.stopAll()
      await rm(temporary, { recursive: true, force: true })
    }
  })
})

function imageManager(temporary: string, registryPath: string): ImageResourceManager {
  return new ImageResourceManager({
    rootDirectory: join(temporary, "state"),
    registryPath,
    probe: async () => imageProbe("image/webp", 640, 480),
    preview: async () => jpegPreview(96, 72),
  })
}

function imageProbe(mimeType: ImageMimeType, width: number, height: number): string {
  const codecs: Record<ImageMimeType, string> = {
    "image/jpeg": "mjpeg",
    "image/png": "png",
    "image/webp": "webp",
  }
  return JSON.stringify({ streams: [{ codec_name: codecs[mimeType], width, height }] })
}

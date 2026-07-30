import { describe, expect, test } from "bun:test"
import { mkdtemp, mkdir, readFile, rm, stat, writeFile } from "node:fs/promises"
import { join } from "node:path"
import { platform, tmpdir } from "node:os"
import {
  VideoResourceManager,
  type VideoProcess,
  type VideoExecutionContext,
} from "../src/video.js"
import { jpegPreview } from "./fixtures.js"

const context: VideoExecutionContext = {
  clientID: "client",
  sessionID: "session",
  messageID: "message",
  agent: "build",
  directory: "/tmp/project",
  worktree: "/tmp/project",
}

const probeMetadata = async () => JSON.stringify({
  streams: [{
    width: 1_920,
    height: 1_080,
    side_data_list: [{ rotation: -90 }],
  }],
  format: { duration: "12.500000" },
})
const preview = async () => jpegPreview(96, 54)

describe("lazy video resources", () => {
  test("validates at execution without spawning and exposes no source path", async () => {
    const temporary = await mkdtemp(join(tmpdir(), "openclient-video-test-"))
    const source = join(temporary, "private-source.mp4")
    await writeFile(source, "fake mp4 for contract testing")
    let spawnCount = 0
    const manager = new VideoResourceManager({
      rootDirectory: join(temporary, "hls"),
      registryPath: join(temporary, "state", "video-resources.json"),
      probe: async (command, sourceFD) => {
        expect(command).toContain("ffprobe")
        expect(command).toContain("/dev/fd/3")
        expect(command).not.toContain(source)
        expect(sourceFD).toBeGreaterThan(2)
        return probeMetadata()
      },
      preview: async (command, sourceFD) => {
        expect(command).toContain("ffmpeg")
        expect(command).toContain("/dev/fd/3")
        expect(command).not.toContain(source)
        expect(sourceFD).toBeGreaterThan(2)
        return preview()
      },
      spawn: () => {
        spawnCount += 1
        return new FakeProcess()
      },
    })
    try {
      const payload = await manager.createResource({ filePath: source, title: "Demo", context })

      expect(spawnCount).toBe(0)
      expect(payload).toMatchObject({
        schemaVersion: 1,
        title: "Demo",
        resourceID: expect.stringMatching(/^[A-Za-z0-9_-]{32}$/),
        startPath: expect.stringContaining("/openclient/v1/video/resources/"),
        stopPath: expect.stringContaining("/openclient/v1/video/resources/"),
        width: 1_920,
        height: 1_080,
        rotation: 90,
        duration: 12.5,
        cover: {
          mimeType: "image/jpeg",
          dataURL: expect.stringMatching(/^data:image\/jpeg;base64,/),
          width: 96,
          height: 54,
        },
        file: {
          name: "private-source.mp4",
          sizeBytes: 29,
          mimeType: "video/mp4",
          modifiedAt: expect.any(String),
        },
      })
      expect(JSON.stringify(payload)).not.toContain(source)
      expect(JSON.stringify(payload)).not.toContain("hlsPath")
      expect((await stat(join(temporary, "hls"))).mode & 0o777).toBe(0o700)
      expect((await stat(join(temporary, "state", "video-resources.json"))).mode & 0o777).toBe(0o600)
    } finally {
      await manager.stopAll()
      await rm(temporary, { recursive: true, force: true })
    }
  })

  test("restores opaque resources after restart and revalidates source identity", async () => {
    const temporary = await mkdtemp(join(tmpdir(), "openclient-video-test-"))
    const source = join(temporary, "durable.mp4")
    const registryPath = join(temporary, "state", "video-resources.json")
    await writeFile(source, "mp4")
    const first = new VideoResourceManager({
      rootDirectory: join(temporary, "first-hls"),
      registryPath,
      probe: probeMetadata,
      preview,
    })
    let second: VideoResourceManager | undefined
    try {
      const resource = await first.createResource({ filePath: source, context })
      await first.stopAll()

      const olderRegistry = JSON.parse(await readFile(registryPath, "utf8")) as {
        resources: Array<{ sourceMetadata?: unknown }>
      }
      expect(olderRegistry.resources[0]?.sourceMetadata).toEqual({
        width: 1_920,
        height: 1_080,
        rotation: 90,
        duration: 12.5,
      })
      expect(olderRegistry.resources[0]).toMatchObject({
        cover: { mimeType: "image/jpeg", width: 96, height: 54 },
      })
      for (const persisted of olderRegistry.resources) delete persisted.sourceMetadata
      await writeFile(registryPath, `${JSON.stringify(olderRegistry, null, 2)}\n`)

      const commands: string[][] = []
      second = new VideoResourceManager({
        rootDirectory: join(temporary, "second-hls"),
        registryPath,
        readinessTimeoutMS: 1_000,
        readinessPollMS: 5,
        spawn: (command) => {
          commands.push(command)
          const process = new FakeProcess()
          const playlist = command.at(-1)
          const segmentPattern = command[command.indexOf("-hls_segment_filename") + 1]
          if (!playlist || !segmentPattern) throw new Error("Missing fake ffmpeg output paths")
          void Promise.resolve().then(async () => {
            await mkdir(join(playlist, ".."), { recursive: true })
            await writeFile(segmentPattern.replace("%06d", "000000"), "segment")
            await writeFile(join(playlist, "../init.mp4"), "init")
            await writeFile(playlist, "#EXTM3U\n#EXTINF:4,\nsegment-000000.m4s\n")
          })
          return process
        },
      })

      const stream = await second.start(resource.resourceID)
      expect(stream.streamID).toMatch(/^[A-Za-z0-9_-]{32}$/)
      expect(commands).toHaveLength(1)
      await second.stopStream(stream.streamID)

      await writeFile(source, "changed mp4")
      await expect(second.start(resource.resourceID)).rejects.toThrow("changed after the resource was created")
    } finally {
      await first.stopAll()
      await second?.stopAll()
      await rm(temporary, { recursive: true, force: true })
    }
  })

  test("expires persisted records across restart and evicts dormant LRU resources", async () => {
    const temporary = await mkdtemp(join(tmpdir(), "openclient-video-test-"))
    const registryPath = join(temporary, "state", "video-resources.json")
    let now = 1
    const first = new VideoResourceManager({
      rootDirectory: join(temporary, "first-hls"),
      registryPath,
      resourceTTLMS: 10,
      maximumResources: 2,
      now: () => now,
      probe: probeMetadata,
      preview,
    })
    let second: VideoResourceManager | undefined
    try {
      const firstSource = join(temporary, "first.mp4")
      const secondSource = join(temporary, "second.mp4")
      const thirdSource = join(temporary, "third.mp4")
      await Promise.all([
        writeFile(firstSource, "first"),
        writeFile(secondSource, "second"),
        writeFile(thirdSource, "third"),
      ])
      const oldest = await first.createResource({ filePath: firstSource, context })
      now = 2
      const retained = await first.createResource({ filePath: secondSource, context })
      now = 3
      expect(await first.stop(oldest.resourceID)).toBe(true)
      now = 4
      const newest = await first.createResource({ filePath: thirdSource, context })

      expect(await first.stop(retained.resourceID)).toBe(false)
      expect(await first.stop(oldest.resourceID)).toBe(true)
      expect(await first.stop(newest.resourceID)).toBe(true)
      const registry = JSON.parse(await readFile(registryPath, "utf8")) as {
        resources: Array<{ id: string }>
      }
      expect(registry.resources.map((resource) => resource.id).sort()).toEqual([
        oldest.resourceID,
        newest.resourceID,
      ].sort())

      await first.stopAll()
      now = 15
      second = new VideoResourceManager({
        rootDirectory: join(temporary, "second-hls"),
        registryPath,
        resourceTTLMS: 10,
        maximumResources: 2,
        now: () => now,
      })
      await expect(second.start(oldest.resourceID)).rejects.toMatchObject({ status: 404 })
      expect(JSON.parse(await readFile(registryPath, "utf8"))).toMatchObject({ resources: [] })
    } finally {
      await first.stopAll()
      await second?.stopAll()
      await rm(temporary, { recursive: true, force: true })
    }
  })

  test("starts once, waits for media, serves allowlisted assets, and stops", async () => {
    const temporary = await mkdtemp(join(tmpdir(), "openclient-video-test-"))
    const source = join(temporary, "demo.mp4")
    await writeFile(source, "mp4")
    const commands: string[][] = []
    const processes: FakeProcess[] = []
    const manager = new VideoResourceManager({
      rootDirectory: join(temporary, "hls"),
      registryPath: join(temporary, "state", "video-resources.json"),
      readinessTimeoutMS: 1_000,
      readinessPollMS: 5,
      probe: probeMetadata,
      preview,
      spawn: (command) => {
        commands.push(command)
        const process = new FakeProcess()
        processes.push(process)
        const playlist = command.at(-1)
        const segmentPattern = command[command.indexOf("-hls_segment_filename") + 1]
        if (!playlist || !segmentPattern) throw new Error("Missing fake ffmpeg output paths")
        const segment = segmentPattern.replace("%06d", "000000")
        void Promise.resolve().then(async () => {
          await mkdir(join(playlist, ".."), { recursive: true })
          await writeFile(segment, "segment bytes")
          await writeFile(join(playlist, "../init.mp4"), "init bytes")
          await writeFile(playlist, "#EXTM3U\n#EXT-X-MAP:URI=\"init.mp4\"\n#EXTINF:4,\nsegment-000000.m4s\n")
        })
        return process
      },
    })
    try {
      const resource = await manager.createResource({ filePath: source, context })
      const [first, second] = await Promise.all([
        manager.start(resource.resourceID),
        manager.start(resource.resourceID),
      ])

      expect(second).toEqual(first)
      expect(commands).toHaveLength(1)
      expect(commands[0]).toContain("copy")
      expect(commands[0]).toContain("fmp4")
      expect(commands[0]?.[0]).toBe("ffmpeg")
      if (platform() !== "win32") {
        expect(commands[0]).toContain("/dev/fd/3")
        expect(commands[0]).not.toContain(source)
      }
      expect(first).toEqual({
        streamID: expect.stringMatching(/^[A-Za-z0-9_-]{32}$/),
        hlsPath: `/openclient/v1/video/streams/${first.streamID}/playlist.m3u8`,
        stopPath: `/openclient/v1/video/streams/${first.streamID}`,
      })
      expect(commands[0]).toContain("temp_file")
      expect(await manager.asset(first.streamID, "playlist.m3u8")).toMatchObject({
        contentType: "application/vnd.apple.mpegurl",
      })
      expect(await manager.asset(first.streamID, "../../demo.mp4")).toBeUndefined()

      expect(await manager.stopStream(first.streamID)).toBe(true)
      expect(processes[0]?.signals).toContain("SIGTERM")
      expect(await manager.asset(first.streamID, "playlist.m3u8")).toBeUndefined()
      await expect(stat(join(temporary, "hls", first.streamID))).rejects.toThrow()
      expect(await manager.stop(resource.resourceID)).toBe(true)
    } finally {
      await manager.stopAll()
      await rm(temporary, { recursive: true, force: true })
    }
  })

  test("rejects invalid files and expires dormant resources", async () => {
    const temporary = await mkdtemp(join(tmpdir(), "openclient-video-test-"))
    const directory = join(temporary, "directory.mp4")
    const wrongType = join(temporary, "video.mov")
    await mkdir(directory)
    await writeFile(wrongType, "mov")
    let now = 0
    let spawnCount = 0
    const manager = new VideoResourceManager({
      rootDirectory: join(temporary, "hls"),
      registryPath: join(temporary, "state", "video-resources.json"),
      resourceTTLMS: 10,
      now: () => now,
      probe: probeMetadata,
      preview,
      spawn: () => {
        spawnCount += 1
        return new FakeProcess()
      },
    })
    try {
      await expect(manager.createResource({ filePath: "relative.mp4", context })).rejects.toThrow("absolute path")
      await expect(manager.createResource({ filePath: wrongType, context })).rejects.toThrow("MP4")
      await expect(manager.createResource({ filePath: directory, context })).rejects.toThrow("regular file")

      const oversized = join(temporary, "oversized.mp4")
      await writeFile(oversized, "oversized")
      const boundedManager = new VideoResourceManager({
        rootDirectory: join(temporary, "bounded-hls"),
        registryPath: join(temporary, "bounded-state", "video-resources.json"),
        maximumSourceBytes: 4,
        probe: probeMetadata,
      })
      await expect(boundedManager.createResource({ filePath: oversized, context })).rejects.toThrow("size limit")
      await boundedManager.stopAll()

      const source = join(temporary, "expires.mp4")
      await writeFile(source, "mp4")
      const resource = await manager.createResource({ filePath: source, context })
      now = 11
      await expect(manager.start(resource.resourceID)).rejects.toMatchObject({ status: 404 })
      expect(spawnCount).toBe(0)
    } finally {
      await manager.stopAll()
      await rm(temporary, { recursive: true, force: true })
    }
  })

  test("rejects a source that changes while ffprobe is reading its validated descriptor", async () => {
    const temporary = await mkdtemp(join(tmpdir(), "openclient-video-test-"))
    const source = join(temporary, "changing.mp4")
    await writeFile(source, "mp4")
    const manager = new VideoResourceManager({
      rootDirectory: join(temporary, "hls"),
      registryPath: join(temporary, "state", "video-resources.json"),
      probe: async () => {
        await writeFile(source, "changed while probing")
        return probeMetadata()
      },
    })
    try {
      await expect(manager.createResource({ filePath: source, context })).rejects.toThrow("changed while")
      await expect(readFile(join(temporary, "state", "video-resources.json"), "utf8")).rejects.toThrow()
    } finally {
      await manager.stopAll()
      await rm(temporary, { recursive: true, force: true })
    }
  })

  test("cancels an in-flight start during shutdown", async () => {
    const temporary = await mkdtemp(join(tmpdir(), "openclient-video-test-"))
    const source = join(temporary, "demo.mp4")
    await writeFile(source, "mp4")
    const process = new FakeProcess()
    const manager = new VideoResourceManager({
      rootDirectory: join(temporary, "hls"),
      registryPath: join(temporary, "state", "video-resources.json"),
      readinessTimeoutMS: 5_000,
      readinessPollMS: 5,
      probe: probeMetadata,
      preview,
      spawn: () => process,
    })
    try {
      const resource = await manager.createResource({ filePath: source, context })
      const starting = manager.start(resource.resourceID)
      const rejectedStart = starting.catch((error: unknown) => error)
      await Bun.sleep(10)
      await manager.stopAll()

      expect(await rejectedStart).toMatchObject({ message: expect.stringContaining("stopped") })
      expect(process.signals).toContain("SIGTERM")
    } finally {
      await manager.stopAll()
      await rm(temporary, { recursive: true, force: true })
    }
  })

  test("does not erase persisted resources when stop overlaps shutdown", async () => {
    const temporary = await mkdtemp(join(tmpdir(), "openclient-video-test-"))
    const source = join(temporary, "demo.mp4")
    const registryPath = join(temporary, "state", "video-resources.json")
    await writeFile(source, "mp4")
    const manager = new VideoResourceManager({
      rootDirectory: join(temporary, "hls"),
      registryPath,
      probe: probeMetadata,
      preview,
    })
    try {
      const resource = await manager.createResource({ filePath: source, context })

      await Promise.all([manager.stop(resource.resourceID), manager.stopAll()])

      const registry = JSON.parse(await readFile(registryPath, "utf8")) as {
        resources: Array<{ id: string }>
      }
      expect(registry.resources.map((item) => item.id)).toContain(resource.resourceID)
    } finally {
      await manager.stopAll()
      await rm(temporary, { recursive: true, force: true })
    }
  })
})

class FakeProcess implements VideoProcess {
  readonly signals: Array<NodeJS.Signals | number | undefined> = []
  readonly exited: Promise<number>
  private resolveExit: (code: number) => void = () => {}

  constructor() {
    this.exited = new Promise((resolve) => {
      this.resolveExit = resolve
    })
  }

  kill(signal?: NodeJS.Signals | number): void {
    this.signals.push(signal)
    this.resolveExit(0)
  }
}

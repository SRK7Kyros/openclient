import { describe, expect, test } from "bun:test"
import { maximumPreviewBytes, parseVisualPreview, previewFromJPEG } from "../src/preview.js"
import { jpegPreview } from "./fixtures.js"

describe("bounded visual previews", () => {
  test("creates and strictly restores canonical JPEG data URLs", () => {
    const preview = previewFromJPEG(jpegPreview(96, 54))
    expect(preview).toEqual({
      mimeType: "image/jpeg",
      dataURL: expect.stringMatching(/^data:image\/jpeg;base64,/),
      width: 96,
      height: 54,
    })
    expect(parseVisualPreview(preview)).toEqual(preview)
    expect(parseVisualPreview({ ...preview, width: 95 })).toBeUndefined()
    expect(parseVisualPreview({ ...preview, dataURL: `${preview.dataURL}\n` })).toBeUndefined()
  })

  test("rejects oversized, over-dimensioned, and non-JPEG previews", () => {
    expect(() => previewFromJPEG(new Uint8Array(maximumPreviewBytes + 1))).toThrow("size limit")
    expect(() => previewFromJPEG(jpegPreview(97, 54))).toThrow("dimensions")
    expect(() => previewFromJPEG(new TextEncoder().encode("not a jpeg"))).toThrow("JPEG")
  })
})

import AppKit

let url = URL(fileURLWithPath: "/Users/ragavij/.gemini/antigravity/brain/628f6a9a-74d6-4ceb-b207-f7ba2f8a8ab3/.user_uploaded/media_1794852255988_55a2e428.jpg")
guard let image = NSImage(contentsOf: url),
      let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff) else {
    exit(1)
}

let bgR = 0.094
let bgG = 0.094
let bgB = 0.102

func isBg(x: Int, y: Int) -> Bool {
    guard let c = rep.colorAt(x: x, y: y) else { return true }
    let diff = abs(c.redComponent - bgR) + abs(c.greenComponent - bgG) + abs(c.blueComponent - bgB)
    return diff < 0.05
}

var topY = 0
for y in 0..<1024 {
    if !isBg(x: 512, y: y) {
        topY = y
        break
    }
}

var bottomY = 1023
for y in stride(from: 1023, through: 0, by: -1) {
    if !isBg(x: 512, y: y) {
        bottomY = y
        break
    }
}

var leftX = 0
for x in 0..<1024 {
    if !isBg(x: x, y: 512) {
        leftX = x
        break
    }
}

var rightX = 1023
for x in stride(from: 1023, through: 0, by: -1) {
    if !isBg(x: x, y: 512) {
        rightX = x
        break
    }
}

print("Squircle bounds: left=\(leftX), right=\(rightX), top=\(topY), bottom=\(bottomY)")
print("Width: \(rightX - leftX + 1), Height: \(bottomY - topY + 1)")

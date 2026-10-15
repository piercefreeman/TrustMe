// Stands in for System Settings in tests: another process with one real
// window. Started with a Cocoa frame (x y width height), it prints
// "ready <x> <y> <width> <height>" once the window is up, then takes
// commands on stdin: "front", "hide", "show", "move x y width height".
import AppKit

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let numbers = CommandLine.arguments.dropFirst().compactMap(Double.init)
let frame = numbers.count == 4 ? CGRect(x: numbers[0], y: numbers[1], width: numbers[2], height: numbers[3])
                               : CGRect(x: 200, y: 200, width: 715, height: 600)
let window = NSWindow(contentRect: frame, styleMask: [.titled], backing: .buffered, defer: false)
window.isReleasedWhenClosed = false
window.setFrame(frame, display: true)
window.orderFrontRegardless()

func report(_ word: String) {
    let f = window.frame
    print("\(word) \(f.minX) \(f.minY) \(f.width) \(f.height)")
    fflush(stdout)
}
// Once launching is done, so the window is where it'll stay before the test looks.
DispatchQueue.main.async { report("ready") }

Thread.detachNewThread {
    while let line = readLine() {
        let parts = line.split(separator: " ")
        DispatchQueue.main.async {
            switch parts.first {
            case "front", "show": window.orderFrontRegardless()
            case "hide": window.orderOut(nil)
            case "move":
                let n = parts.dropFirst().compactMap { Double($0) }
                if n.count == 4 { window.setFrame(CGRect(x: n[0], y: n[1], width: n[2], height: n[3]), display: true) }
            default: break
            }
            report("done")
        }
    }
    exit(0)
}
app.run()

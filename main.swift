import AppKit
let app: NSApplication = .shared
let appDelegate = AppDelegate()  // Instantiates the class the @NSApplicationMain was attached to
app.delegate = appDelegate
_ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)

import Foundation

#if canImport(IOKit)
import IOKit
import IOKit.pwr_mgt
#endif

class PowerManager {

#if canImport(IOKit)
    var assertionID: IOPMAssertionID = 0
#endif
    
    func disableSleep(reason: String) {
#if canImport(IOKit)

        let reasonForActivity = reason as CFString
        IOPMAssertionCreateWithName( kIOPMAssertionTypeNoDisplaySleep as CFString,
                                                    IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                                    reasonForActivity,
                                                    &assertionID )
#endif
    }
    
    func enableSleep() {
#if canImport(IOKit)
        IOPMAssertionRelease(assertionID)
#endif
    }
}

func shell(_ launchPath: String) throws {
#if canImport(IOKit)
    let task = Process()
    task.executableURL = URL(fileURLWithPath: launchPath)

    try task.run()
#endif
}

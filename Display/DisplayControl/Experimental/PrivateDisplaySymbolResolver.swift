import Foundation
import MachO
import Darwin

/// Resolves private framework symbols at runtime using RTLD_DEFAULT and dyld inspection.
class PrivateDisplaySymbolResolver {
    static let shared = PrivateDisplaySymbolResolver()
    
    private init() {}
    
    /// Resolves a symbol using the global namespace (RTLD_DEFAULT).
    func resolveSymbol(name: String) -> UnsafeMutableRawPointer? {
        let globalHandle = UnsafeMutableRawPointer(bitPattern: -2)
        if let globalHandle, let symbol = dlsym(globalHandle, name) {
            return symbol
        }

        for path in [
            "/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics",
            "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight"
        ] {
            guard let handle = dlopen(path, RTLD_LAZY) else { continue }
            if let symbol = dlsym(handle, name) {
                return symbol
            }
        }

        return nil
    }
    
    /// Dumps loaded dyld images containing relevant keywords.
    func getLoadedDisplayImages() -> [String] {
        var relevantImages: [String] = []
        let count = _dyld_image_count()
        
        for i in 0..<count {
            if let cName = _dyld_get_image_name(i) {
                let name = String(cString: cName)
                if name.contains("SkyLight") || name.contains("CoreDisplay") || 
                   name.contains("DisplayServices") || name.contains("CoreGraphics") {
                    relevantImages.append(name)
                }
            }
        }
        return relevantImages
    }
    
    /// Discovers common private display-related symbols and returns a report.
    func runDiscovery() -> String {
        var report = "# Private Symbol Discovery Report (Global Namespace)\n\n"
        
        let images = getLoadedDisplayImages()
        report += "## Loaded Relevant Dyld Images\n"
        for img in images {
            report += "- \(img)\n"
        }
        report += "\n"
        
        let candidateSymbols = [
            "SLSMainConnectionID",
            "SLSDetectDisplays",
            "CGSMainConnectionID",
            "CGSDetectDisplays",
            "SLSBeginDisplayConfiguration",
            "CGBeginDisplayConfiguration",
            "SLSConfigureDisplayMode",
            "CGSConfigureDisplayMode",
            "SLSCompleteDisplayConfigurationWithOption",
            "SLSCompleteDisplayConfiguration",
            "CGCompleteDisplayConfiguration",
            "SLSGetDisplayList",
            "SLSGetCurrentDisplayMode",
            "CoreDisplay_DisplayCreateInfoDictionary",
            "CGSCopyDisplayInfoDictionary",
            "CGSGetCurrentDisplayMode",
            "SLSGetCurrentDisplayMode",
            "CGSGetNumberOfDisplayModes",
            "SLSGetNumberOfDisplayModes",
            "CGSGetDisplayModeDescriptionOfLength",
            "SLSGetDisplayModeDescriptionOfLength"
        ]
        
        report += "## Symbol Resolution via RTLD_DEFAULT\n"
        var foundCount = 0
        for symbol in candidateSymbols {
            if resolveSymbol(name: symbol) != nil {
                report += "- ✅ \(symbol)\n"
                foundCount += 1
            } else {
                report += "- ❌ \(symbol)\n"
            }
        }
        
        if foundCount == 0 {
            report += "\n**Warning:** No relevant symbols found in global namespace.\n"
        }
        
        return report
    }
}

extension PrivateDisplaySymbolResolver: @unchecked Sendable {}

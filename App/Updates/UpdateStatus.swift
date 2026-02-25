import Foundation

enum UpdateStatus: Equatable {
    case idle
    case checking
    case downloading(progress: Double)
    case installing
    case upToDate(remoteVersion: String)
    case needsRestart(version: String)
    case failed(message: String)
    
    var isBusy: Bool {
        switch self {
        case .checking, .downloading, .installing:
            return true
        default:
            return false
        }
    }
    
    var isClickable: Bool {
        return !isBusy
    }
    
    var progressValue: Double? {
        switch self {
        case .downloading(let value):
            return value
        default:
            return nil
        }
    }
    
    func menuTitle(currentVersion: String) -> String {
        switch self {
        case .idle, .failed, .upToDate, .needsRestart:
            return "Check for Updates..."
        case .checking:
            return "Checking for Updates..."
        case .downloading(let progress):
            let percent = Int(progress * 100)
            return "Downloading Update (\(percent)%)"
        case .installing:
            return "Installing Update..."
        }
    }
}

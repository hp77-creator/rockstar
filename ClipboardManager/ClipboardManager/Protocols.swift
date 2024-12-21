import Foundation

protocol ClipboardUpdateDelegate: AnyObject {
    func didReceiveNewClip(_ clip: ClipboardItem)
}

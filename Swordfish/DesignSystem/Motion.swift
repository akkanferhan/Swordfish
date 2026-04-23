import SwiftUI

enum Motion {
    static let fast    = Animation.easeOut(duration: 0.14)
    static let `default` = Animation.easeOut(duration: 0.22)
    static let spring  = Animation.spring(response: 0.26, dampingFraction: 0.62, blendDuration: 0)
    static let toast   = Animation.spring(response: 0.20, dampingFraction: 0.75, blendDuration: 0)
}

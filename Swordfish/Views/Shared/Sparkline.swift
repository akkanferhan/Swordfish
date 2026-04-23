import SwiftUI

struct Sparkline: View {
    let values: [Double]
    var color: Color = .accentColor

    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height
            if values.count < 2 {
                Path().stroke(Color.clear)
            } else {
                let minV = values.min() ?? 0
                let maxV = values.max() ?? 1
                let range = max(0.001, maxV - minV)
                let stepX = w / CGFloat(max(1, values.count - 1))

                Path { path in
                    for (i, v) in values.enumerated() {
                        let x = CGFloat(i) * stepX
                        let y = h - (CGFloat((v - minV) / range) * h)
                        if i == 0 {
                            path.move(to: CGPoint(x: x, y: y))
                        } else {
                            path.addLine(to: CGPoint(x: x, y: y))
                        }
                    }
                }
                .stroke(color.opacity(0.9), style: StrokeStyle(lineWidth: 1.25, lineCap: .round, lineJoin: .round))
            }
        }
    }
}

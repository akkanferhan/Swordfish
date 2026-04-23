import SwiftUI

struct BrandMonogram: View {
    var size: CGFloat = 22
    var tinted: Bool = true

    var body: some View {
        ZStack {
            if tinted {
                RoundedRectangle(cornerRadius: size * 0.25, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: 0x0A84FF), Color(hex: 0xBF5AF2)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
            }
            Canvas { ctx, canvasSize in
                let w = canvasSize.width
                let h = canvasSize.height
                let line = max(1.25, size * 0.06)
                let stroke = GraphicsContext.Shading.color(.white.opacity(0.95))

                // three horizontal lines
                for i in 0..<3 {
                    let y = h * (0.28 + 0.18 * Double(i))
                    var path = Path()
                    path.move(to: CGPoint(x: w * 0.22, y: y))
                    path.addLine(to: CGPoint(x: w * 0.62, y: y))
                    ctx.stroke(path, with: stroke, lineWidth: line)
                }
                // two circles
                let r = w * 0.07
                let cx1 = w * 0.72, cx2 = w * 0.72
                let cy1 = h * 0.36, cy2 = h * 0.60
                ctx.stroke(Path(ellipseIn: CGRect(x: cx1 - r, y: cy1 - r, width: 2*r, height: 2*r)), with: stroke, lineWidth: line)
                ctx.stroke(Path(ellipseIn: CGRect(x: cx2 - r, y: cy2 - r, width: 2*r, height: 2*r)), with: stroke, lineWidth: line)
            }
        }
        .frame(width: size, height: size)
    }
}

import SwiftUI

/// A deliberately synthetic scene, never presented as a real camera measurement.
struct DemoScene: View {
    let box: MeasuredBox?
    let unit: MeasureUnit
    private let lime = Color(red: 0.80, green: 0.98, blue: 0.40)

    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let origin = CGPoint(x: w * 0.5, y: proxy.size.height * 0.37)
            let scale = w / 390
            ZStack {
                LinearGradient(colors: [Color(red: 0.15, green: 0.19, blue: 0.18), Color(red: 0.06, green: 0.08, blue: 0.07)], startPoint: .topLeading, endPoint: .bottomTrailing)
                Canvas { context, size in
                    func p(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: origin.x + x * scale, y: origin.y + y * scale) }
                    for n in -8...8 {
                        var line = Path()
                        line.move(to: p(Double(n) * 55 - 600, 400)); line.addLine(to: p(Double(n) * 55 + 300, -90))
                        context.stroke(line, with: .color(.white.opacity(0.035)), lineWidth: 1)
                        var other = Path()
                        other.move(to: p(Double(n) * 55 - 300, -90)); other.addLine(to: p(Double(n) * 55 + 600, 400))
                        context.stroke(other, with: .color(.white.opacity(0.035)), lineWidth: 1)
                    }
                    let a = p(-103,-54), b = p(34,-95), c = p(112,-47), d = p(-24,-5)
                    let e = p(-103,62), f = p(-24,111), g = p(112,68)
                    func face(_ vertices: [CGPoint], _ color: Color) {
                        var path = Path(); path.addLines(vertices); path.closeSubpath()
                        context.fill(path, with: .color(color))
                    }
                    let shadow = CGRect(x: origin.x - 100 * scale, y: origin.y + 70 * scale, width: 240 * scale, height: 65 * scale)
                    context.drawLayer { ctx in
                        ctx.addFilter(.blur(radius: 20)); ctx.fill(Path(ellipseIn: shadow), with: .color(.black.opacity(0.45)))
                    }
                    face([a,b,c,d], Color(red: 0.69, green: 0.61, blue: 0.46))
                    face([a,d,f,e], Color(red: 0.45, green: 0.38, blue: 0.26))
                    face([d,c,g,f], Color(red: 0.57, green: 0.48, blue: 0.33))
                    face([p(-47,-71),p(-25,-78),p(53,-30),p(31,-23)], Color.white.opacity(0.12))
                    face([p(31,-23),p(53,-30),p(53,84),p(31,91)], Color.black.opacity(0.1))
                    if box != nil {
                        var outline = Path()
                        for (start, end) in [(a,b),(b,c),(c,d),(d,a),(a,e),(e,f),(f,d),(f,g),(g,c)] {
                            outline.move(to: start); outline.addLine(to: end)
                        }
                        context.stroke(outline, with: .color(lime), lineWidth: 1.4)
                        for point in [a,b,c,d,e,f,g] {
                            context.fill(Path(ellipseIn: CGRect(x: point.x - 3, y: point.y - 3, width: 6, height: 6)), with: .color(lime))
                        }
                    }
                }
                if let box {
                    tag("W", box.size.x).position(x: origin.x + 49 * scale, y: origin.y + 119 * scale)
                    tag("H", box.size.y).position(x: origin.x + 117 * scale, y: origin.y + 8 * scale)
                    tag("D", box.size.z).position(x: origin.x - 104 * scale, y: origin.y + 98 * scale)
                }
            }
        }
    }

    private func tag(_ axis: String, _ length: Float) -> some View {
        HStack(spacing: 6) {
            Text(axis).foregroundStyle(lime)
            Text("\(unit.format(length)) \(unit.rawValue)").foregroundStyle(.white)
        }.font(.system(size: 11, weight: .semibold, design: .monospaced))
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(Color.black.opacity(0.72), in: Capsule())
            .overlay(Capsule().stroke(lime.opacity(0.35), lineWidth: 0.5))
    }
}

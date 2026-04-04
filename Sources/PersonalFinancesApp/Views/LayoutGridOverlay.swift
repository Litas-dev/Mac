import SwiftUI

#if DEBUG
struct LayoutGridOverlay: View {
    var step: CGFloat = 50
    var majorStep: CGFloat = 200
    
    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack(alignment: .topLeading) {
                Canvas { ctx, _ in
                    var minor = Path()
                    var major = Path()
                    
                    let w = size.width
                    let h = size.height
                    
                    if step > 0 {
                        var x: CGFloat = 0
                        while x <= w {
                            if majorStep > 0, x.truncatingRemainder(dividingBy: majorStep) == 0 {
                                major.move(to: CGPoint(x: x, y: 0))
                                major.addLine(to: CGPoint(x: x, y: h))
                            } else {
                                minor.move(to: CGPoint(x: x, y: 0))
                                minor.addLine(to: CGPoint(x: x, y: h))
                            }
                            x += step
                        }
                        
                        var y: CGFloat = 0
                        while y <= h {
                            if majorStep > 0, y.truncatingRemainder(dividingBy: majorStep) == 0 {
                                major.move(to: CGPoint(x: 0, y: y))
                                major.addLine(to: CGPoint(x: w, y: y))
                            } else {
                                minor.move(to: CGPoint(x: 0, y: y))
                                minor.addLine(to: CGPoint(x: w, y: y))
                            }
                            y += step
                        }
                    }
                    
                    ctx.stroke(minor, with: .color(.white.opacity(0.10)), lineWidth: 1)
                    ctx.stroke(major, with: .color(.white.opacity(0.22)), lineWidth: 1)
                }
                
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(Int(size.width)) × \(Int(size.height))")
                        .font(.caption.monospacedDigit())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.black.opacity(0.45))
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    
                    ZStack(alignment: .topLeading) {
                        ForEach(xLabels(size.width), id: \.self) { x in
                            Text("\(Int(x))")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.white.opacity(0.85))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Color.black.opacity(0.35))
                                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                                .offset(x: x + 2, y: 0)
                        }
                        ForEach(yLabels(size.height), id: \.self) { y in
                            Text("\(Int(y))")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.white.opacity(0.85))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Color.black.opacity(0.35))
                                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                                .offset(x: 0, y: y + 2)
                        }
                    }
                }
                .padding(8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .allowsHitTesting(false)
    }
    
    private func xLabels(_ width: CGFloat) -> [CGFloat] {
        guard majorStep > 0 else { return [] }
        var out: [CGFloat] = []
        var x: CGFloat = 0
        while x <= width {
            out.append(x)
            x += majorStep
        }
        return out
    }
    
    private func yLabels(_ height: CGFloat) -> [CGFloat] {
        guard majorStep > 0 else { return [] }
        var out: [CGFloat] = []
        var y: CGFloat = 0
        while y <= height {
            out.append(y)
            y += majorStep
        }
        return out
    }
}
#endif


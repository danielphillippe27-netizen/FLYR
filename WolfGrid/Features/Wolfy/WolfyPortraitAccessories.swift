import SwiftUI

struct WolfyPortraitComposition: View {
    let stage: Int
    let equipment: [String:String]
    var body: some View {
        ZStack {
            Image("WolfyStage\(stage)").resizable().scaledToFit()
            WolfyPortraitAccessories(stage:stage,equipment:equipment)
        }.aspectRatio(1,contentMode:.fit)
    }
}

struct WolfyPortraitAccessory: Identifiable {
    let key: String
    let name: String
    let slot: String
    let price: Int
    var id: String { "portrait_" + key }
    static let all: [Self] = [
        .init(key:"chain_silver",name:"Silver Chain",slot:"neck",price:150),
        .init(key:"chain_gold",name:"Gold Chain",slot:"neck",price:400),
        .init(key:"chain_cuban",name:"Cuban Link",slot:"neck",price:900),
        .init(key:"chain_orange",name:"Orange Pendant",slot:"neck",price:600),
        .init(key:"glasses_classic",name:"Classic Shades",slot:"eyewear",price:100),
        .init(key:"glasses_aviator",name:"Gold Aviators",slot:"eyewear",price:300),
        .init(key:"glasses_round",name:"Round Frames",slot:"eyewear",price:250),
        .init(key:"glasses_visor",name:"Orange Visor",slot:"eyewear",price:650),
        .init(key:"collar_orange",name:"WolfGrid Collar",slot:"neck",price:75),
        .init(key:"collar_black",name:"Midnight Collar",slot:"neck",price:100),
        .init(key:"collar_teal",name:"Teal Collar",slot:"neck",price:150),
        .init(key:"collar_studded",name:"Studded Collar",slot:"neck",price:350),
        .init(key:"aura_ember",name:"Ember Glow",slot:"aura",price:100),
        .init(key:"aura_ice",name:"Arctic Glow",slot:"aura",price:250),
        .init(key:"aura_gold",name:"Golden Glow",slot:"aura",price:500),
        .init(key:"aura_prism",name:"Prism Glow",slot:"aura",price:900)
    ]
    static func find(_ id: String?) -> Self? { all.first { $0.id == id } }
}

/// Vector accessories are registered to the exact five supplied portrait poses.
/// They share the portrait's transforms, so breathing and tap motion cannot detach them.
struct WolfyPortraitAccessories: View {
    let stage: Int
    let equipment: [String:String]

    var body: some View {
        Canvas { context, size in
            let fit = Fit.all[min(4,max(0,stage-1))]
            var ctx = context
            ctx.scaleBy(x:size.width,y:size.height)
            if let item=WolfyPortraitAccessory.find(equipment["aura"]) { aura(item.key,context:&ctx) }
            if let item=WolfyPortraitAccessory.find(equipment["neck"]) { neck(item.key,fit:fit,context:&ctx) }
            if let item=WolfyPortraitAccessory.find(equipment["eyewear"]) { glasses(item.key,fit:fit,context:&ctx) }
        }.allowsHitTesting(false).accessibilityHidden(true)
    }

    private struct Fit {
        let left: CGPoint
        let right: CGPoint
        let radius: CGFloat
        let neckLeft: CGPoint
        let neckRight: CGPoint
        let drop: CGFloat
        static let all: [Self] = [
            .init(left:.init(x:0.277,y:0.310),right:.init(x:0.397,y:0.351),radius:0.051,neckLeft:.init(x:0.205,y:0.465),neckRight:.init(x:0.472,y:0.475),drop:0.115),
            .init(left:.init(x:0.261,y:0.245),right:.init(x:0.346,y:0.276),radius:0.039,neckLeft:.init(x:0.190,y:0.411),neckRight:.init(x:0.432,y:0.439),drop:0.110),
            .init(left:.init(x:0.261,y:0.218),right:.init(x:0.348,y:0.237),radius:0.037,neckLeft:.init(x:0.177,y:0.400),neckRight:.init(x:0.430,y:0.426),drop:0.112),
            .init(left:.init(x:0.260,y:0.201),right:.init(x:0.349,y:0.217),radius:0.037,neckLeft:.init(x:0.166,y:0.412),neckRight:.init(x:0.445,y:0.422),drop:0.118),
            .init(left:.init(x:0.251,y:0.208),right:.init(x:0.345,y:0.220),radius:0.038,neckLeft:.init(x:0.160,y:0.431),neckRight:.init(x:0.451,y:0.436),drop:0.112)
        ]
    }
    private func metal(_ color: Color) -> GraphicsContext.Shading {
        .linearGradient(Gradient(colors:[.white,color,color.opacity(0.8),.white.opacity(0.9),color]),startPoint:.init(x:-0.018,y:-0.012),endPoint:.init(x:0.018,y:0.012))
    }
    private func glasses(_ key:String,fit:Fit,context:inout GraphicsContext) {
        let round=key=="glasses_round", aviator=key=="glasses_aviator", visor=key=="glasses_visor"
        let color:Color = aviator ? .yellow : visor ? .orange : round ? Color(red:0.7,green:0.75,blue:0.8) : Color(white:0.07)
        let angle=atan2(fit.right.y-fit.left.y,fit.right.x-fit.left.x)
        var bridge=Path();bridge.move(to:fit.left);bridge.addLine(to:fit.right)
        context.stroke(bridge,with:.color(color),style:StrokeStyle(lineWidth:0.008,lineCap:.round))
        for (index,point) in [fit.left,fit.right].enumerated() {
            var local=context;local.translateBy(x:point.x,y:point.y);local.rotate(by:.radians(angle))
            let r=fit.radius*(index==1 ? 0.91 : 1)
            let box=CGRect(x:-r,y:-r*0.84,width:r*2,height:r*1.68)
            var lens=round ? Path(ellipseIn:box) : Path(roundedRect:box,cornerRadius:r*(visor ? 0.15 : 0.32))
            if aviator {
                lens=Path();lens.move(to:.init(x:-r,y:-r*0.3))
                lens.addCurve(to:.init(x:r,y:-r*0.3),control1:.init(x:-r,y:-r),control2:.init(x:r,y:-r))
                lens.addCurve(to:.init(x:r*0.25,y:r*0.86),control1:.init(x:r*1.05,y:r*0.5),control2:.init(x:r*0.7,y:r*0.85))
                lens.addCurve(to:.init(x:-r,y:-r*0.3),control1:.init(x:-r*0.5,y:r*0.9),control2:.init(x:-r,y:r*0.35));lens.closeSubpath()
            }
            local.fill(lens,with:.linearGradient(Gradient(colors:[Color(red:0.13,green:0.26,blue:0.35).opacity(round ? 0.12 : 0.90),Color.black.opacity(round ? 0.07 : 0.82)]),startPoint:.init(x:0,y:-r),endPoint:.init(x:0,y:r)))
            local.stroke(lens,with:metal(color),lineWidth:round || aviator ? 0.004 : 0.007)
            var shine=Path();shine.move(to:.init(x:-r*0.6,y:-r*0.32));shine.addLine(to:.init(x:r*0.2,y:-r*0.48))
            local.stroke(shine,with:.color(.white.opacity(round ? 0.3 : 0.55)),style:StrokeStyle(lineWidth:0.003,lineCap:.round))
            var arm=Path();arm.move(to:.init(x:index==0 ? -r : r,y:0));arm.addLine(to:.init(x:index==0 ? -r*1.3 : r*1.3,y:-r*0.22))
            local.stroke(arm,with:.color(color),style:StrokeStyle(lineWidth:0.004,lineCap:.round))
        }
    }
    private func neck(_ key:String,fit:Fit,context:inout GraphicsContext) {
        let collar=key.hasPrefix("collar")
        let color:Color = key.contains("silver") ? Color(white:0.65) : key.contains("black") || key.contains("studded") ? Color(white:0.11) : key.contains("teal") ? .teal : key.contains("orange") ? .orange : Color(red:0.87,green:0.60,blue:0.15)
        let drop=collar ? fit.drop*0.35 : fit.drop
        func point(_ t:CGFloat) -> CGPoint {
            .init(x:fit.neckLeft.x+(fit.neckRight.x-fit.neckLeft.x)*t,y:fit.neckLeft.y+(fit.neckRight.y-fit.neckLeft.y)*t+sin(t * .pi)*drop)
        }
        var path=Path();path.move(to:point(0));for i in 1...40 { path.addLine(to:point(CGFloat(i)/40)) }
        if collar {
            context.stroke(path,with:.color(.black.opacity(0.6)),style:StrokeStyle(lineWidth:0.026,lineCap:.round))
            context.stroke(path,with:metal(color),style:StrokeStyle(lineWidth:0.020,lineCap:.round))
            if key.contains("studded") {
                for i in 1...9 {
                    let p=point(CGFloat(i)/10);let r:CGFloat=0.006
                    var stud=Path();stud.move(to:.init(x:p.x,y:p.y-r));stud.addLine(to:.init(x:p.x+r,y:p.y));stud.addLine(to:.init(x:p.x,y:p.y+r));stud.addLine(to:.init(x:p.x-r,y:p.y));stud.closeSubpath()
                    context.fill(stud,with:metal(.gray))
                }
            }
        } else {
            let thick=key.contains("cuban")
            for i in 0...24 {
                let t=CGFloat(i)/24,p=point(t),a=point(max(0,t-0.01)),b=point(min(1,t+0.01))
                var local=context;local.translateBy(x:p.x,y:p.y);local.rotate(by:.radians(atan2(b.y-a.y,b.x-a.x)))
                let link=Path(ellipseIn:CGRect(x:-0.010,y:thick ? -0.008 : -0.006,width:0.020,height:thick ? 0.016 : 0.012))
                local.stroke(link,with:.color(.black.opacity(0.7)),lineWidth:thick ? 0.007 : 0.005)
                local.stroke(link,with:metal(color),lineWidth:thick ? 0.005 : 0.003)
            }
        }
        let p=point(0.52),radius:CGFloat=key.contains("orange") && !collar ? 0.021 : 0.013
        let tag=Path(ellipseIn:CGRect(x:p.x-radius,y:p.y+0.005,width:radius*2,height:radius*2))
        context.fill(tag,with:metal(color));context.stroke(tag,with:.color(.black.opacity(0.55)),lineWidth:0.002)
        // A small engraved paw mark stays legible without putting clothing on Wolfy.
        context.fill(Path(ellipseIn:CGRect(x:p.x-0.004,y:p.y+radius,width:0.008,height:0.007)),with:.color(.black.opacity(0.55)))
        for x in [-0.006,0,0.006] { context.fill(Path(ellipseIn:CGRect(x:p.x+x-0.002,y:p.y+radius-0.005,width:0.004,height:0.004)),with:.color(.black.opacity(0.55))) }
    }
    private func aura(_ key:String,context:inout GraphicsContext) {
        let color:Color = key.contains("ice") ? .cyan : key.contains("gold") ? .yellow : key.contains("prism") ? .purple : .orange
        let ring=Path(ellipseIn:CGRect(x:0.12,y:0.78,width:0.79,height:0.14))
        var glow=context;glow.addFilter(.blur(radius:0.012));glow.stroke(ring,with:.color(color.opacity(0.6)),lineWidth:0.018)
        context.stroke(ring,with:.color(color.opacity(0.65)),lineWidth:0.003)
        for i in 0..<12 {
            let x=0.15+CGFloat(i)*0.063,y=0.70+sin(CGFloat(i)*2.1)*0.075
            context.fill(Path(ellipseIn:CGRect(x:x,y:y,width:0.004,height:0.004)),with:.color(key.contains("prism") ? Color(hue:Double(i)/12,saturation:0.7,brightness:1) : color))
        }
    }
}

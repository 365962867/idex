#!/usr/bin/env swift
// Rebuild with: swift scripts/icon/generate_icon.swift
import AppKit
import CoreGraphics

let dimension = 1024
let output = CommandLine.arguments.dropFirst().first ?? "iDex/Assets.xcassets/AppIcon.appiconset/AppIcon.png"
let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
let context = CGContext(data: nil, width: dimension, height: dimension, bitsPerComponent: 8, bytesPerRow: dimension * 4, space: colorSpace, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
context.translateBy(x: 0, y: 1024)
context.scaleBy(x: 1, y: -1)
context.setAllowsAntialiasing(true)

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: colorSpace, components: [CGFloat((hex >> 16) & 255) / 255, CGFloat((hex >> 8) & 255) / 255, CGFloat(hex & 255) / 255, alpha])!
}
func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect { CGRect(x: x, y: y, width: w, height: h) }
func rounded(_ r: CGRect, _ radius: CGFloat) -> CGPath { CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil) }
func fill(_ path: CGPath, _ shade: CGColor) { context.addPath(path); context.setFillColor(shade); context.fillPath() }
func line(_ points: [CGPoint], _ shade: CGColor, width: CGFloat = 2) {
    guard let first = points.first else { return }
    context.beginPath();context.move(to: first)
    points.dropFirst().forEach { context.addLine(to: $0) }
    context.setStrokeColor(shade);context.setLineWidth(width);context.setLineJoin(.round);context.strokePath()
}
func stroke(_ path: CGPath, _ shade: CGColor, width: CGFloat = 2) { context.addPath(path);context.setStrokeColor(shade);context.setLineWidth(width);context.strokePath() }
func gradient(_ path: CGPath, _ colors: [CGColor], _ start: CGPoint, _ end: CGPoint, locations: [CGFloat]? = nil) {
    context.saveGState();context.addPath(path);context.clip()
    let gradient = CGGradient(colorsSpace: colorSpace, colors: colors as CFArray, locations: locations)!
    context.drawLinearGradient(gradient, start: start, end: end, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]);context.restoreGState()
}
func shadow(_ path: CGPath, _ shade: CGColor, offset: CGSize, blur: CGFloat) {
    context.saveGState();context.setShadow(offset: offset, blur: blur, color: shade);fill(path, shade);context.restoreGState()
}
func ellipse(_ r: CGRect) -> CGPath { CGPath(ellipseIn: r, transform: nil) }
func radial(_ path: CGPath, _ colors: [CGColor], center: CGPoint, radius: CGFloat) {
    context.saveGState();context.addPath(path);context.clip()
    let gradient = CGGradient(colorsSpace: colorSpace, colors: colors as CFArray, locations: nil)!
    context.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center, endRadius: radius, options: .drawsAfterEndLocation);context.restoreGState()
}

// The red injection-moulded case fills the icon; iOS supplies the outer clipping mask.
gradient(rounded(rect(0,0,1024,1024),0), [color(0xec414b),color(0xb20e24),color(0x660719)], CGPoint(x:60,y:0),CGPoint(x:970,y:1080))
let caseEdge = rounded(rect(26,24,972,976),118)
shadow(caseEdge,color(0x2d000a,0.7),offset:CGSize(width:0,height:12),blur:22)
gradient(caseEdge,[color(0xff7071),color(0xb6192d),color(0x750b1c)],CGPoint(x:80,y:24),CGPoint(x:910,y:1020))
let shell = rounded(rect(43,37,938,942),108)
gradient(shell,[color(0xe7464f),color(0xc22035),color(0xad1129)],CGPoint(x:190,y:30),CGPoint(x:870,y:970))
stroke(shell,color(0xffa1a1,0.34),width:2)
// Soft top light rolls over the slightly raised faceplate.
context.saveGState();context.addPath(shell);context.clip()
radial(ellipse(rect(-200,-360,1250,1000)),[color(0xffc6a3,0.17),color(0xffc6a3,0)],center:CGPoint(x:220,y:70),radius:720)
// A restrained, deterministic grain suggests matte plastic without stealing focus.
var randomState: UInt64 = 0x1de5
for _ in 0..<46000 {
    randomState = randomState &* 6364136223846793005 &+ 1
    let x = CGFloat((randomState >> 32) % 1024)
    randomState = randomState &* 6364136223846793005 &+ 1
    let y = CGFloat((randomState >> 32) % 1024)
    context.setFillColor(color(0x24000a,0.035));context.fill(rect(x,y,1,1))
}
context.restoreGState()

// The stepped moulding line is a familiar Pokédex detail.
let seam = [CGPoint(x:50,y:340),CGPoint(x:331,y:340),CGPoint(x:409,y:271),CGPoint(x:974,y:271)]
line(seam.map { CGPoint(x:$0.x,y:$0.y+4) },color(0xff8e8f,0.50),width:4)
line(seam,color(0x790719,0.85),width:7)
line(seam.map { CGPoint(x:$0.x,y:$0.y-4) },color(0xdb263d,0.85),width:3)

// Machined, bevelled blue optical lens.
let lensOuter = ellipse(rect(103,85,236,236))
shadow(lensOuter,color(0x480611,0.72),offset:CGSize(width:3,height:9),blur:13)
gradient(lensOuter,[color(0xffffff),color(0xc7d1cc),color(0x737f80),color(0xf1f0e3)],CGPoint(x:130,y:90),CGPoint(x:315,y:310),locations:[0,0.35,0.7,1])
stroke(lensOuter,color(0xffeee1,0.85),width:2)
let lensGasket=ellipse(rect(120,102,202,202))
gradient(lensGasket,[color(0x111c26),color(0x455763),color(0x14212b)],CGPoint(x:120,y:104),CGPoint(x:303,y:304))
let lensGlass=ellipse(rect(132,114,178,178))
radial(lensGlass,[color(0x9af8ff),color(0x1ed5f4),color(0x087ab5),color(0x062849)],center:CGPoint(x:179,y:154),radius:173)
stroke(lensGlass,color(0x8feefc,0.6),width:3)
context.saveGState();context.addPath(lensGlass);context.clip()
gradient(ellipse(rect(134,115,142,95)),[color(0xf4ffff,0.75),color(0xb7f6ff,0.05)],CGPoint(x:170,y:123),CGPoint(x:190,y:205))
fill(ellipse(rect(161,135,29,17)),color(0xffffff,0.8))
context.restoreGState()

func indicator(_ x: CGFloat, _ shade: UInt32) {
    let well=ellipse(rect(x,123,49,49))
    shadow(well,color(0x590612,0.6),offset:CGSize(width:0,height:4),blur:3)
    gradient(well,[color(0x6d0616),color(0xf0797b)],CGPoint(x:x,y:123),CGPoint(x:x+38,y:173))
    radial(ellipse(rect(x+5,128,39,39)),[color(0xffffff,0.92),color(shade),color(shade,0.95),color(0x273a18)],center:CGPoint(x:x+15,y:136),radius:43)
    fill(ellipse(rect(x+12,133,9,6)),color(0xffffff,0.7))
}
indicator(401,0xe82c38)
indicator(476,0xeed347)
indicator(551,0x9dca55)

// A pair of inset speaker slots on the upper shoulder.
for i in 0..<3 {
    let slot=rounded(rect(754,149+CGFloat(i)*23,146,9),4)
    fill(slot,color(0x7b0b20));line([CGPoint(x:760,y:159+CGFloat(i)*23),CGPoint(x:894,y:159+CGFloat(i)*23)],color(0xed6267,0.7),width:2)
}

// A deep metal bezel makes the LCD look mounted into the case.
let bezel=rounded(rect(106,390,812,459),36)
shadow(bezel,color(0x500010,0.65),offset:CGSize(width:0,height:12),blur:15)
gradient(bezel,[color(0xf1efdc),color(0xcdcfbd),color(0x969c8e)],CGPoint(x:106,y:390),CGPoint(x:850,y:850))
stroke(bezel,color(0xedeedb),width:3)
let darkInset=rounded(rect(139,423,746,379),22)
gradient(darkInset,[color(0x141e1c),color(0x515c4a)],CGPoint(x:140,y:424),CGPoint(x:870,y:795))
let screen=rounded(rect(154,438,716,349),11)
gradient(screen,[color(0xb9cc8c),color(0xa1b87a),color(0x8ea869)],CGPoint(x:155,y:438),CGPoint(x:868,y:787))
context.saveGState();context.addPath(screen);context.clip()
// Inner screen shadow and lines give the green display depth.
for i in 0..<13 {
    let alpha=CGFloat(13-i)/210
    stroke(rounded(rect(154+CGFloat(i),438+CGFloat(i),716-CGFloat(i)*2,349-CGFloat(i)*2),11),color(0x173620,alpha),width:2)
}
for y in stride(from:440,through:786,by:4) {
    context.setFillColor(color(0x294b29,0.055));context.fill(rect(155,CGFloat(y),716,1))
}
// Pixelated Poké Ball emblem: an original, simple monochrome LCD rendering.
let origin=CGPoint(x:392,y:493)
let unit:CGFloat=12
for row in 0..<20 {
    for column in 0..<20 {
        let dx=CGFloat(column)-9.5,dy=CGFloat(row)-9.5
        let d=sqrt(dx*dx+dy*dy)
        guard d<=9.65 else { continue }
        let centerRadius=sqrt(dx*dx+dy*dy)
        var shade:CGColor?
        if d>=8.0 { shade=color(0x294b31) }
        else if centerRadius<3.1 && centerRadius>=1.6 { shade=color(0x294b31) }
        else if centerRadius<1.6 { shade=color(0xc7d899) }
        else if abs(dy)<1.0 && centerRadius>=3.1 { shade=color(0x294b31) }
        else if dy < -1.0 { shade=color(0x67844a,0.42) }
        if let shade { context.setFillColor(shade);context.fill(rect(origin.x+CGFloat(column)*unit,origin.y+CGFloat(row)*unit,unit,unit)) }
    }
}
// Four scan reticles keep the app's camera purpose visible at icon scale.
let lcdInk=color(0x355936,0.85)
for (x,y,sx,sy) in [(208.0,487.0,1.0,1.0),(814.0,487.0,-1.0,1.0),(208.0,738.0,1.0,-1.0),(814.0,738.0,-1.0,-1.0)] {
    line([CGPoint(x:x,y:y+sy*25),CGPoint(x:x,y:y),CGPoint(x:x+sx*25,y:y)],lcdInk,width:7)
}
// Tiny side data ticks suggest a field instrument.
for i in 0..<5 {
    context.setFillColor(color(0x3d5c36,0.56))
    context.fill(rect(244,570+CGFloat(i)*17,CGFloat([52,35,44,25,39][i]),6))
    context.fill(rect(748,570+CGFloat(i)*17,CGFloat([30,41,26,45,34][i]),6))
}
context.restoreGState()
// A thin reflection on the display's glass.
stroke(screen,color(0xe1e9b9,0.34),width:2)

// Small recessed red screen activity lamp in the brushed bezel.
let activity=ellipse(rect(170,815,14,14));fill(activity,color(0x6b0a1b));fill(ellipse(rect(173,817,8,8)),color(0xd62e36))
for i in 0..<4 { fill(rounded(rect(762+CGFloat(i)*21,816,11,9),3),color(0x6a7563,0.75)) }

// Bottom controls: a black rubber D-pad and two small physical keys.
let cross=CGMutablePath()
let crossPoints:[CGPoint] = [CGPoint(x:177,y:882),CGPoint(x:211,y:882),CGPoint(x:211,y:859),CGPoint(x:251,y:859),CGPoint(x:251,y:882),CGPoint(x:285,y:882),CGPoint(x:285,y:922),CGPoint(x:251,y:922),CGPoint(x:251,y:946),CGPoint(x:211,y:946),CGPoint(x:211,y:922),CGPoint(x:177,y:922)]
cross.addLines(between:crossPoints);cross.closeSubpath()
shadow(cross,color(0x4e0012,0.7),offset:CGSize(width:0,height:6),blur:5)
gradient(cross,[color(0x444a49),color(0x161d20)],CGPoint(x:188,y:862),CGPoint(x:275,y:943))
stroke(cross,color(0x131719),width:2)
fill(ellipse(rect(223,894,16,16)),color(0x151b1b))
let key1=rounded(rect(349,882,152,44),19)
let key2=rounded(rect(535,882,152,44),19)
for key in [key1,key2] { shadow(key,color(0x530315,0.75),offset:CGSize(width:0,height:6),blur:4) }
gradient(key1,[color(0x36494c),color(0x122429)],CGPoint(x:349,y:882),CGPoint(x:349,y:925))
gradient(key2,[color(0x91a466),color(0x526f3c)],CGPoint(x:535,y:882),CGPoint(x:535,y:925))
line([CGPoint(x:370,y:888),CGPoint(x:477,y:888)],color(0x94a6a3,0.35),width:2)
line([CGPoint(x:556,y:888),CGPoint(x:663,y:888)],color(0xe8edba,0.45),width:2)
for i in 0..<4 {
    let slot=rounded(rect(772,873+CGFloat(i)*18,105,7),3)
    fill(slot,color(0x760a1e));line([CGPoint(x:776,y:882+CGFloat(i)*18),CGPoint(x:873,y:882+CGFloat(i)*18)],color(0xf57879,0.5),width:2)
}

// Four metal screw heads complete the manufactured object.
func screw(_ x:CGFloat,_ y:CGFloat) {
    let shape=ellipse(rect(x-9,y-9,18,18))
    shadow(shape,color(0x510413,0.8),offset:CGSize(width:0,height:2),blur:2)
    gradient(shape,[color(0xd5d6c2),color(0x6b7270),color(0xafb5a4)],CGPoint(x:x-7,y:y-8),CGPoint(x:x+7,y:y+9))
    line([CGPoint(x:x-4,y:y+4),CGPoint(x:x+4,y:y-4)],color(0x484d48),width:2)
}
screw(76,85);screw(948,85);screw(76,943);screw(948,943)

let image=context.makeImage()!
let rep=NSBitmapImageRep(cgImage:image)
rep.size=NSSize(width:1024,height:1024)
let png=rep.representation(using:.png,properties:[:])!
try png.write(to:URL(fileURLWithPath:output))
print("Wrote \(output) (\(png.count) bytes)")

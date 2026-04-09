import SwiftUI

/// The StatShot app icon rendered as a SwiftUI view.
/// Use the Xcode preview to see it at various sizes, then export
/// a 1024x1024 PNG for the asset catalog.
struct AppIconView: View {
    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let center = size / 2
            let ringRadius = size * 0.34
            let ringWidth = size * 0.06

            ZStack {
                // Background
                RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                    .fill(Color(red: 0.08, green: 0.08, blue: 0.08))

                // Orange ring
                Circle()
                    .stroke(Color.orange, lineWidth: ringWidth)
                    .frame(width: ringRadius * 2, height: ringRadius * 2)
                    .position(x: center, y: center)

                // Bell icon
                Image(systemName: "bell.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(width: size * 0.28, height: size * 0.28)
                    .foregroundStyle(.white)
                    .position(x: center, y: center)
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

#Preview("1024pt") {
    AppIconView()
        .frame(width: 1024, height: 1024)
}

#Preview("180pt") {
    AppIconView()
        .frame(width: 180, height: 180)
}

#Preview("60pt") {
    AppIconView()
        .frame(width: 60, height: 60)
}

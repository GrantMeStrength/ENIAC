//
//  AppIconGenerator.swift
//  ENIAC
//
//  Created by John Kennedy on 2/21/26.
//

import SwiftUI

/// Run this in a macOS target or Playground to generate the app icon
struct AppIconGenerator {
    
    static func generateIcon(size: CGFloat = 1024) -> some View {
        ZStack {
            // Background gradient (vintage computer terminal vibes)
            LinearGradient(
                colors: [
                    Color(red: 0.1, green: 0.15, blue: 0.2),
                    Color(red: 0.05, green: 0.1, blue: 0.15)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            
            // Circuit board pattern
            CircuitBoardPattern()
                .stroke(
                    LinearGradient(
                        colors: [
                            Color(red: 1.0, green: 0.7, blue: 0.0),  // Amber
                            Color(red: 0.3, green: 0.8, blue: 0.3)   // Green
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 3
                )
                .opacity(0.6)
            
            // Central computing core symbol
            VStack(spacing: 8) {
                Image(systemName: "cpu.fill")
                    .font(.system(size: size * 0.35, weight: .bold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [
                                Color(red: 1.0, green: 0.8, blue: 0.2),
                                Color(red: 1.0, green: 0.6, blue: 0.0)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .shadow(color: Color(red: 1.0, green: 0.7, blue: 0.0).opacity(0.5), radius: 20)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.2237, style: .continuous))
    }
    
    // Alternative design with binary code aesthetic
    static func generateBinaryIcon(size: CGFloat = 1024) -> some View {
        ZStack {
            // Deep blue-black background
            Color(red: 0.05, green: 0.08, blue: 0.15)
            
            // Binary code pattern
            BinaryCodePattern()
                .foregroundStyle(
                    Color(red: 0.2, green: 0.8, blue: 0.4).opacity(0.2)
                )
            
            // Glowing "E" for ENIAC
            Text("E")
                .font(.system(size: size * 0.6, weight: .black, design: .monospaced))
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            Color(red: 0.4, green: 1.0, blue: 0.6),
                            Color(red: 0.2, green: 0.8, blue: 0.4)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .shadow(color: Color(red: 0.2, green: 0.8, blue: 0.4), radius: 30)
                .shadow(color: Color(red: 0.2, green: 0.8, blue: 0.4), radius: 60)
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.2237, style: .continuous))
    }
}

// Circuit board pattern shape
struct CircuitBoardPattern: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let spacing = rect.width / 8
        
        // Horizontal lines
        for i in 1...7 {
            let y = CGFloat(i) * spacing
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: rect.width, y: y))
        }
        
        // Vertical lines
        for i in 1...7 {
            let x = CGFloat(i) * spacing
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x, y: rect.height))
        }
        
        // Add connection nodes (circles at intersections)
        for i in 1...7 {
            for j in 1...7 {
                let x = CGFloat(i) * spacing
                let y = CGFloat(j) * spacing
                path.addEllipse(in: CGRect(x: x - 8, y: y - 8, width: 16, height: 16))
            }
        }
        
        return path
    }
}

// Binary code pattern
struct BinaryCodePattern: View {
    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: geometry.size.height / 20) {
                ForEach(0..<20, id: \.self) { row in
                    HStack(spacing: geometry.size.width / 40) {
                        ForEach(0..<40, id: \.self) { col in
                            Text(Int.random(in: 0...1) == 0 ? "0" : "1")
                                .font(.system(size: geometry.size.width / 50, design: .monospaced))
                                .opacity(Double.random(in: 0.3...0.7))
                        }
                    }
                }
            }
        }
    }
}

// Preview for testing
#Preview("CPU Icon") {
    AppIconGenerator.generateIcon(size: 512)
}

#Preview("Binary Icon") {
    AppIconGenerator.generateBinaryIcon(size: 512)
}

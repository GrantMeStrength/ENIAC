//
//  ContentView.swift
//  ENIAC
//
//  Created by John Kennedy on 2/13/26.
//

import SwiftUI
import RealityKit

struct ContentView: View {

    var body: some View {
        VStack(spacing: 12) {
            Text("ENIAC")
                .font(.headline)
            ToggleImmersiveSpaceButton()
                .controlSize(.small)
            Text("Electronic Numerical Integrator and Computer, 1946")
                .font(.caption)
        }
        .padding(20)
        .frame(minWidth: 220, minHeight: 120)
    }
}

#Preview(windowStyle: .automatic) {
    ContentView()
        .environment(AppModel())
}

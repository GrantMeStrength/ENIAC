//
//  ImmersiveView.swift
//  ENIAC
//
//  Created by John Kennedy on 2/13/26.
//

import SwiftUI
import RealityKit
import RealityKitContent
import UIKit
import Foundation

struct ImmersiveView: View {
    @Environment(AppModel.self) var appModel
    private let eniacTargetLengthMeters: Float = 30.5
    private let eniacPaddingMeters: Float = 2.0
    private let useProceduralLayout = true
    private let roomHeightMeters: Float = 3.0
    @State private var blinkLights: [BlinkLight] = []
    @State private var blinkTask: Task<Void, Never>?
    @State private var depthDragMode = false
    @State private var dragStartPosition: SIMD3<Float>?
    @State private var activeInfoID: String?
    @State private var worldAnchor: Entity?

    private struct InfoPoint: Identifiable {
        let id: String
        let title: String
        let description: String
        let fact: String
        let position: SIMD3<Float>
        let faceNormal: SIMD3<Float>
        let viewOffset: SIMD3<Float>  // Where user stands when teleporting to this point
    }

    // ENIAC U-shaped layout (panels 1-40 from historical records):
    // Back wall: Initiating Unit (1), Cycling Unit (2), Master Programmer (3-4), Function Table 1 (5-6)
    // Left leg (panels 7-22): Accumulators 1-2 (7-8), Divider/Square Root (9), Accumulators 3-10 (10-17), Multiplier (18-20), Accumulators 11-18 (21-28 spans to right)
    // Right leg (panels 29-40): Function Table 2 (29-30), Function Table 3 (31-32), Accumulators 19-20 (33-34), Constant Transmitters (35-37), Printer (38-40)
    //
    // Layout coordinates (after scaling):
    // - Back wall at Z ≈ -7.0, X from -2.2 to +2.2
    // - Left leg at X ≈ -2.2, Z from -7.0 to -1.5
    // - Right leg at X ≈ +2.2, Z from -7.0 to -1.5
    // - Portable units in center of U, Z ≈ -4.0
    // - Photo wall (front wall behind user) at Z ≈ +3.5
    private static let infoPoints: [InfoPoint] = [
        // Left leg - Accumulators (near back of left leg)
        InfoPoint(id: "info_accumulators_back",
                  title: "Accumulators 1-2",
                  description: "The first two accumulators, positioned at the back of the left leg. Each accumulator was a self-contained arithmetic unit capable of addition, subtraction, and storing a 10-digit signed decimal number. They received data through five input channels and transmitted results through two output channels.",
                  fact: "The accumulators could add two numbers in just 200 microseconds — about 5,000 additions per second.",
                  position: SIMD3(-1.9, 1.2, -6.2),
                  faceNormal: SIMD3(1, 0, 0),
                  viewOffset: SIMD3(-0.1, 0, -5.4)),
        // Left leg - Accumulators (mid-section)
        InfoPoint(id: "info_accumulators_mid",
                  title: "Accumulators 3-10",
                  description: "Eight more accumulators lined the middle section of the left leg. Working in parallel, these units formed the computational core of ENIAC. Each contained 550 vacuum tubes arranged in decade ring counters to represent decimal digits.",
                  fact: "Each accumulator contained 550 vacuum tubes — one reason ENIAC needed 18,000 tubes total.",
                  position: SIMD3(-1.9, 1.2, -4.0),
                  faceNormal: SIMD3(1, 0, 0),
                  viewOffset: SIMD3(-0.3, 0, -4.0)),
        // Left leg - Multiplier (front of left leg)
        InfoPoint(id: "info_multiplier",
                  title: "High-Speed Multiplier",
                  description: "The multiplication unit coordinated four accumulators to perform high-speed multiplication. It could multiply two 10-digit numbers in about 2.8 milliseconds — blindingly fast for 1945. Partial products were accumulated in stages to build the final result.",
                  fact: "The multiplier was considered ENIAC's most complex subsystem, requiring precise timing across multiple accumulator units.",
                  position: SIMD3(-1.9, 1.2, -1.8),
                  faceNormal: SIMD3(1, 0, 0),
                  viewOffset: SIMD3(-0.3, 0, -1.8)),
        // Right leg - Function Tables (near back of right leg)
        InfoPoint(id: "info_function_tables",
                  title: "Function Tables",
                  description: "Specialized memory units storing pre-calculated mathematical constants and lookup tables. Instead of recomputing common values, operators could retrieve them instantly. Three function tables could each hold 104 entries of 12-digit numbers.",
                  fact: "Function tables were programmed by setting hundreds of rotary dial switches by hand — a painstaking process that could take hours.",
                  position: SIMD3(1.9, 1.2, -5.8),
                  faceNormal: SIMD3(-1, 0, 0),
                  viewOffset: SIMD3(0.3, 0, -5.8)),
        // Right leg - Constant Transmitters (mid-section)
        InfoPoint(id: "info_constants",
                  title: "Constant Transmitters",
                  description: "Three constant transmitter units allowed operators to input fixed numbers that would be used repeatedly in calculations. Each could store multiple constants set via rotary dial switches, avoiding the need to re-enter values during computation.",
                  fact: "Constant transmitters used rotary dial switches — similar to combination locks — to set each digit of a number.",
                  position: SIMD3(1.9, 1.2, -3.5),
                  faceNormal: SIMD3(-1, 0, 0),
                  viewOffset: SIMD3(0.3, 0, -3.5)),
        // Right leg - Printer (front of right leg)
        InfoPoint(id: "info_printer",
                  title: "Printer Unit",
                  description: "The IBM card punch output unit that recorded ENIAC's results. It could punch 100 cards per minute, each card holding up to 80 columns of data. This was the primary way to capture and preserve computation results for later analysis.",
                  fact: "ENIAC used IBM punched cards both for input and output — the same card technology that had been used in tabulating machines since the 1890s.",
                  position: SIMD3(1.9, 1.2, -1.2),
                  faceNormal: SIMD3(-1, 0, 0),
                  viewOffset: SIMD3(0.3, 0, -1.2)),
        // Back wall - Master Programmer (left side of back wall)
        InfoPoint(id: "info_master_programmer",
                  title: "Master Programmer",
                  description: "The sequencing unit that controlled program flow and loop counting. It directed the order of operations and could set up nested loops for iterative calculations. Programming required physically reconnecting hundreds of cables between panels.",
                  fact: "Reprogramming ENIAC could take days of rewiring. In 1948, a stored-program modification allowed instructions to be stored in the function tables instead.",
                  position: SIMD3(-1.5, 1.2, -6.9),
                  faceNormal: SIMD3(0, 0, 1),
                  viewOffset: SIMD3(-1.5, 0, -4.2)),
        // Back wall - Cycling Unit (center of back wall)
        InfoPoint(id: "info_cycling_unit",
                  title: "Cycling Unit",
                  description: "The master clock generating timing pulses that synchronized all of ENIAC's operations. Running at 100 kHz — 100,000 pulses per second — it ensured every component executed instructions in lockstep. ENIAC could perform 5,000 additions per second.",
                  fact: "ENIAC was roughly 1,000 times faster than existing electromechanical calculators, completing in seconds what previously took days.",
                  position: SIMD3(0.0, 1.2, -6.9),
                  faceNormal: SIMD3(0, 0, 1),
                  viewOffset: SIMD3(0.0, 0, -4.2)),
        // Back wall - Initiating Unit (right side of back wall)
        InfoPoint(id: "info_initiating_unit",
                  title: "Initiating Unit",
                  description: "The control panel where operators started and monitored program execution. It contained switches for launching calculations, single-stepping through operations, and reading machine status. This was the primary human interface to the computer.",
                  fact: "Six women — Kay McNulty, Betty Jennings, Betty Snyder, Marlyn Meltzer, Fran Bilas, and Ruth Lichterman — were ENIAC's first programmers, configuring it for ballistic trajectory calculations.",
                  position: SIMD3(1.5, 1.2, -6.9),
                  faceNormal: SIMD3(0, 0, 1),
                  viewOffset: SIMD3(1.5, 0, -4.2)),
        // Center of U - Portable Function Table
        InfoPoint(id: "info_portable_unit",
                  title: "Portable Function Table",
                  description: "A free-standing wheeled cabinet that could be rolled up and connected to the main ENIAC frame. It provided additional memory and function storage, and could be swapped out with different configurations for different problems.",
                  fact: "The portable design was remarkably forward-thinking — it introduced modularity to computing years before it became standard practice.",
                  position: SIMD3(-1.2, 1.1, -5.5),
                  faceNormal: SIMD3(0, 0, 1),
                  viewOffset: SIMD3(-1.2, 0, -2.8)),
        // Photo wall - The Programmers (left side)
        InfoPoint(id: "info_programmers",
                  title: "The ENIAC Programmers",
                  description: "Six women programmed ENIAC: Kay McNulty, Betty Jennings, Betty Snyder, Marlyn Meltzer, Fran Bilas, and Ruth Lichterman. They studied ENIAC's blueprints, learned its operations, and developed the techniques for programming it — all without any prior documentation or training.",
                  fact: "The ENIAC programmers were originally called 'computers' — the job title for people who performed calculations. They became the world's first electronic computer programmers.",
                  position: SIMD3(-1.8, 1.5, 1.8),
                  faceNormal: SIMD3(0, 0, -1),
                  viewOffset: SIMD3(-1.8, 0, 0.3)),
        // Photo wall - Eckert & Mauchly (right side)
        InfoPoint(id: "info_inventors",
                  title: "Eckert & Mauchly",
                  description: "J. Presper Eckert and John Mauchly designed ENIAC at the University of Pennsylvania's Moore School of Electrical Engineering. Eckert was the chief engineer responsible for the hardware, while Mauchly conceived the idea of a general-purpose electronic computer.",
                  fact: "After ENIAC, Eckert and Mauchly founded the first computer company and built UNIVAC I — the first commercial computer in the United States.",
                  position: SIMD3(1.8, 1.5, 1.8),
                  faceNormal: SIMD3(0, 0, -1),
                  viewOffset: SIMD3(1.8, 0, 0.3)),
    ]

    private struct RoomLayout {
        let center: SIMD3<Float>
        let width: Float
        let depth: Float
        let height: Float
    }

    private struct PanelTextures {
        let panelTextures: [TextureResource]
        let controlTextures: [TextureResource]
        let posterTextures: [TextureResource]
        let rowTextures: [TextureResource]
        let historyTextures: [TextureResource]
    }

    private struct BlinkLight {
        let entity: ModelEntity
        let onMaterial: UnlitMaterial
        let offMaterial: UnlitMaterial
        let column: Int      // Which column (0-9) this digit is in
        let row: Int         // Which row (0-9, where 9=top digit "9", 0=bottom digit "0")
        let panelIndex: Int  // Which panel this light belongs to
    }

    var body: some View {
        RealityView { content, attachments in
            let textures = loadPanelTextures()
            let eniacEntity: Entity
            var scaleToTargetLength = false
            var usingProceduralLayout = useProceduralLayout
            let posterTextures: [TextureResource] = textures.posterTextures
            if useProceduralLayout {
                let layout = makeENIACLayout(textures: textures)
                eniacEntity = layout.entity
                if blinkLights.isEmpty {
                    blinkLights = layout.blinkLights
                }
            } else {
                do {
                    eniacEntity = try await Entity(named: "ENIAC", in: realityKitContentBundle)
                    scaleToTargetLength = true
                    usingProceduralLayout = false
                } catch {
                    print("Failed to load ENIAC model: \(error)")
                    let layout = makeENIACLayout(textures: textures)
                    eniacEntity = layout.entity
                    if blinkLights.isEmpty {
                        blinkLights = layout.blinkLights
                    }
                    usingProceduralLayout = true
                }
            }
            if !usingProceduralLayout && !blinkLights.isEmpty {
                blinkLights = []
            }

            let eniacBounds: BoundingBox?
            if usingProceduralLayout {
                eniacBounds = eniacEntity.visualBounds(relativeTo: nil)
            } else {
                eniacBounds = placeENIAC(eniacEntity, scaleToTargetLength: scaleToTargetLength)
            }
            let anchor = AnchorEntity(world: SIMD3<Float>(repeating: 0))
            anchor.addChild(eniacEntity)
            if let bounds = eniacBounds {
                let layout = roomLayout(for: bounds)
                anchor.addChild(makeOfficeEnvironment(layout: layout,
                                                     posterTextures: posterTextures,
                                                     historyTextures: textures.historyTextures))
            }
            content.add(anchor)

            // Store anchor reference for teleportation
            worldAnchor = anchor

            // Info buttons
            for info in Self.infoPoints {
                let button = makeInfoButton(info: info)
                anchor.addChild(button)

                if let attachment = attachments.entity(for: info.id) {
                    let panelAnchor = Entity()
                    panelAnchor.name = "infopanel_\(info.id)"
                    
                    // Position panel between object and viewer to avoid clipping into cabinets
                    let normal = simd_normalize(info.faceNormal)
                    let panelOffset: Float = 0.65
                    let eyeLevelY: Float = 1.55
                    let viewerDelta = info.viewOffset - info.position
                    let displayDirection = simd_length_squared(viewerDelta) > 0.0001 ? simd_normalize(viewerDelta) : normal
                    
                    // Panel appears toward the viewing position, at eye level
                    let panelPosition = SIMD3<Float>(
                        info.position.x + displayDirection.x * panelOffset,
                        eyeLevelY,
                        info.position.z + displayDirection.z * panelOffset
                    )
                    
                    panelAnchor.position = panelPosition
                    panelAnchor.components.set(BillboardComponent())
                    panelAnchor.addChild(attachment)
                    panelAnchor.isEnabled = false
                    anchor.addChild(panelAnchor)
                }
            }
        } update: { content, attachments in
            for info in Self.infoPoints {
                let panelName = "infopanel_\(info.id)"
                for entity in content.entities {
                    if let panel = entity.findEntity(named: panelName) {
                        panel.isEnabled = (info.id == activeInfoID)
                    }
                }
            }
        } attachments: {
            ForEach(Self.infoPoints) { info in
                Attachment(id: info.id) {
                    InfoPanelView(title: info.title,
                                  description: info.description,
                                  fact: info.fact,
                                  onDismiss: { activeInfoID = nil })
                }
            }
        }
        .gesture(
            SpatialTapGesture()
                .targetedToAnyEntity()
                .onEnded { value in
                    // Check for info button tap - teleport to it and open panel
                    guard let infoName = findInfoParentName(entity: value.entity) else { return }
                    let infoID = infoName.replacingOccurrences(of: "btn_", with: "")
                    
                    // Find the info point and teleport to it
                    if let info = Self.infoPoints.first(where: { $0.id == infoID }),
                       let anchor = worldAnchor {
                        teleportToInfoPoint(info: info, anchor: anchor)
                    }
                    
                    // Open the info panel (or close if already open)
                    activeInfoID = activeInfoID == infoID ? nil : infoID
                }
        )
        .onAppear {
            startBlinking()
        }
        .onChange(of: blinkLights.count) {
            startBlinking()
        }
        .onDisappear {
            blinkTask?.cancel()
        }
    }

    private func findInfoParentName(entity: Entity) -> String? {
        var current: Entity? = entity
        while let e = current {
            if e.name.hasPrefix("btn_info_") { return e.name }
            current = e.parent
        }
        return nil
    }

    private func makeInfoButton(info: InfoPoint) -> Entity {
        let buttonRoot = Entity()
        buttonRoot.name = "btn_\(info.id)"
        buttonRoot.position = SIMD3(info.viewOffset.x, 0.005, info.viewOffset.z)

        // Subtle floor marker
        let radius: Float = 0.07
        let thickness: Float = 0.003

        let discMesh = MeshResource.generateCylinder(height: thickness, radius: radius)
        var discMaterial = SimpleMaterial(color: UIColor(white: 0.35, alpha: 0.55),
                                           roughness: 0.9,
                                           isMetallic: false)
        let disc = ModelEntity(mesh: discMesh, materials: [discMaterial])
        disc.position.y = thickness * 0.5

        // Collision and input with hover effect
        disc.components.set(InputTargetComponent(allowedInputTypes: .all))
        disc.components.set(CollisionComponent(shapes: [.generateBox(size: SIMD3(radius * 3, 0.15, radius * 3))]))
        disc.components.set(HoverEffectComponent())
        buttonRoot.addChild(disc)

        // Subtle colored ring — faint at rest, noticeable when hover highlight activates
        let ringMesh = MeshResource.generateCylinder(height: thickness * 0.5, radius: radius + 0.02)
        var ringMat = UnlitMaterial()
        ringMat.color = .init(tint: UIColor(red: 0.0, green: 0.75, blue: 1.0, alpha: 0.18))
        ringMat.blending = .transparent(opacity: 1.0)
        let ring = ModelEntity(mesh: ringMesh, materials: [ringMat])
        ring.name = "hover_ring"
        ring.position.y = thickness * 0.25
        buttonRoot.addChild(ring)

        return buttonRoot
    }

    private func teleportToInfoPoint(info: InfoPoint, anchor: Entity) {
        // Move the world so the viewOffset position is at the user's position (origin)
        let offset = -info.viewOffset
        
        // Animate the transition smoothly
        let currentPosition = anchor.position
        let targetPosition = SIMD3<Float>(offset.x, currentPosition.y, offset.z)
        
        // Create smooth animation
        var transform = anchor.transform
        transform.translation = targetPosition
        anchor.move(to: transform, relativeTo: anchor.parent, duration: 0.5, timingFunction: .easeInOut)
    }

    private func makeENIACLayout(textures: PanelTextures) -> (entity: Entity, blinkLights: [BlinkLight]) {
        let sidePanelCount = 16
        let basePanelCount = 8
        let totalPanels = sidePanelCount * 2 + basePanelCount

        let panelWidth: Float = 0.61
        let panelHeight: Float = 2.44
        let panelDepth: Float = 0.61
        let faceDepth: Float = 0.03
        let bulbRadius: Float = 0.016
        let floorClearance: Float = 0.01
        let panelGap: Float = 0.01
        let panelPitch = panelWidth + panelGap
        let layoutLength = Float(totalPanels) * panelWidth + Float(totalPanels - 1) * panelGap
        let layoutScale = eniacTargetLengthMeters / layoutLength
        let cornerGap = panelGap * 0.5

        var blinkLights: [BlinkLight] = []
        let rowTextures = textures.rowTextures
        func rowTexture(_ index: Int) -> TextureResource? {
            guard index < rowTextures.count else { return nil }
            return rowTextures[index]
        }

        func makePanel(faceSign: Float) -> Entity {
            let panel = Entity()
            let bodyMesh = MeshResource.generateBox(size: SIMD3(panelWidth, panelHeight, panelDepth))
            let bodyMaterial = SimpleMaterial(color: UIColor(white: 0.28, alpha: 1.0),
                                               roughness: 0.9,
                                               isMetallic: false)
            let body = ModelEntity(mesh: bodyMesh, materials: [bodyMaterial])
            body.components.set(ModelComponent(mesh: bodyMesh, materials: [bodyMaterial]))
            body.components.set(GroundingShadowComponent(castsShadow: true))
            panel.addChild(body)
            
            return panel
         }
        
        // Track which panel we're creating (for unique column IDs across panels)
        var currentPanelIndex = 0
        
        func makeLightPanel(position: SIMD3<Float>, faceNormal: SIMD3<Float>, name: String) -> Entity {
            let panelRoot = Entity()
            panelRoot.name = name
            let panelWidth: Float = 0.52
            let panelHeight: Float = 0.38
            let panelThickness: Float = 0.02
            let columns = 10
            let digitsPerColumn = 10  // 9 at top, 0 at bottom
            let panelIdx = currentPanelIndex
            currentPanelIndex += 1
            
            // Dark backing panel - also serves as drag target
            let backingMesh = MeshResource.generateBox(size: SIMD3(panelWidth, panelHeight, panelThickness))
            let backingMaterial = SimpleMaterial(color: UIColor(white: 0.08, alpha: 1.0),
                                                  roughness: 0.85,
                                                  isMetallic: false)
            let backing = ModelEntity(mesh: backingMesh, materials: [backingMaterial])
            backing.name = name + "_backing"
            backing.components.set(InputTargetComponent(allowedInputTypes: .all))
            backing.components.set(CollisionComponent(shapes: [.generateBox(size: SIMD3(panelWidth, panelHeight, 0.15))]))
            panelRoot.addChild(backing)
            
            // Grid spacing for 10x10 digit display
            let gridSpacingX = panelWidth * 0.88 / Float(columns - 1)
            let gridSpacingY = panelHeight * 0.88 / Float(digitsPerColumn - 1)
            let startOffsetX = -panelWidth * 0.88 * 0.5
            let startOffsetY = -panelHeight * 0.88 * 0.5
            
            // Circle ring parameters
            let circleRadius: Float = 0.012
            let circleThickness: Float = 0.001
            let ringSegments = 24
            
            // Pre-generate digit text meshes (0-9)
            var digitMeshes: [MeshResource] = []
            for digit in 0...9 {
                let mesh = MeshResource.generateText("\(digit)",
                                                      extrusionDepth: 0.002,
                                                      font: .monospacedDigitSystemFont(ofSize: 0.014, weight: .bold),
                                                      containerFrame: .zero,
                                                      alignment: .center,
                                                      lineBreakMode: .byClipping)
                digitMeshes.append(mesh)
            }
            
            // Create circle ring mesh (torus approximation using cylinder ring)
            let ringMesh = MeshResource.generateCylinder(height: circleThickness, radius: circleRadius)
            var ringMaterial = UnlitMaterial()
            ringMaterial.color = .init(tint: UIColor(white: 0.25, alpha: 0.6))
            
            for col in 0..<columns {
                for row in 0..<digitsPerColumn {
                    // Digit value: 9 at top (row 9), 0 at bottom (row 0)
                    let digitValue = 9 - row
                    let digitMesh = digitMeshes[digitValue]
                    
                    let xPos = startOffsetX + Float(col) * gridSpacingX
                    let yPos = startOffsetY + Float(row) * gridSpacingY
                    let zPos = panelThickness * 0.5 + 0.002
                    
                    // Faint circle ring around each digit
                    let ring = ModelEntity(mesh: ringMesh, materials: [ringMaterial])
                    ring.orientation = simd_quatf(angle: .pi / 2, axis: SIMD3(1, 0, 0))
                    ring.position = SIMD3(xPos, yPos, zPos - 0.001)
                    backing.addChild(ring)
                    
                    // Digit text - lights up with warm orange/yellow glow
                    // Add random variation to simulate analog vacuum tube behavior
                    let baseRed: CGFloat = 1.0
                    let baseGreen: CGFloat = 0.75 + CGFloat.random(in: -0.08...0.08)
                    let baseBlue: CGFloat = 0.35 + CGFloat.random(in: -0.1...0.1)
                    let brightness: CGFloat = 0.9 + CGFloat.random(in: 0...0.1)
                    
                    var onMaterial = UnlitMaterial()
                    onMaterial.color = .init(tint: UIColor(red: baseRed * brightness, 
                                                            green: baseGreen * brightness, 
                                                            blue: baseBlue * brightness, 
                                                            alpha: 1.0))
                    var offMaterial = UnlitMaterial()
                    offMaterial.color = .init(tint: UIColor(white: 0.12, alpha: 1.0))  // Dim when off
                    
                    let digitEntity = ModelEntity(mesh: digitMesh, materials: [offMaterial])
                    // Center the digit mesh
                    let bounds = digitMesh.bounds
                    let centerOffset = (bounds.min + bounds.max) * 0.5
                    digitEntity.position = SIMD3(xPos - centerOffset.x,
                                                  yPos - centerOffset.y,
                                                  zPos)
                    backing.addChild(digitEntity)
                    
                    // Add to blink lights for animation
                    blinkLights.append(BlinkLight(entity: digitEntity,
                                                  onMaterial: onMaterial,
                                                  offMaterial: offMaterial,
                                                  column: col,
                                                  row: row,
                                                  panelIndex: panelIdx))
                }
            }
            
            panelRoot.position = position
            // Orient the panel so the digits face the given normal direction
            let normal = simd_normalize(faceNormal)
            panelRoot.orientation = simd_quatf(from: SIMD3<Float>(0, 0, 1), to: normal)
            return panelRoot
        }

        let root = Entity()
        let panelY = panelHeight * 0.5 + floorClearance

        let baseHalfWidth = Float(basePanelCount - 1) * panelPitch * 0.5
        let _ = panelDepth * 0.5 + panelWidth * 0.5 + cornerGap  // legStartZ calculation
        let sideLength = Float(sidePanelCount - 1) * panelPitch
        let backZ = -sideLength
        for index in 0..<basePanelCount {
            let panel = makePanel(faceSign: 1)
            panel.position = SIMD3(-baseHalfWidth + Float(index) * panelPitch,
                                   panelY,
                                   backZ)
            root.addChild(panel)
        }

        let legX = baseHalfWidth + (panelWidth + panelDepth) * 0.5 + cornerGap
        let sides: [Float] = [-1, 1]
        for side in sides {
            let legRotation = simd_quatf(angle: side < 0 ? -.pi / 2 : .pi / 2,
                                         axis: SIMD3(0, 1, 0))
            let faceSign: Float = 1
            for index in 0..<sidePanelCount {
                let panel = makePanel(faceSign: faceSign)
                panel.orientation = legRotation
                panel.position = SIMD3(side * legX,
                                       panelY,
                                       backZ + Float(index) * panelPitch)
                root.addChild(panel)
            }
        }

        let centerUnits = makeCenterUnits(panelWidth: panelWidth,
                                          panelHeight: panelHeight,
                                          panelDepth: panelDepth,
                                          centerZ: backZ * 0.4,
                                          floorClearance: floorClearance)
        root.addChild(centerUnits)

        // Generate procedural normal map for panel details
        let panelNormalMap = generatePanelNormalMap()

        let rowHeight = panelHeight * 0.94
        func rowWidth(for count: Int) -> Float {
            Float(count - 1) * panelPitch + panelWidth * 0.96
        }
        func addRowOverlay(center: SIMD3<Float>, width: Float, faceNormal: SIMD3<Float>, texture: TextureResource?) {
            let mesh = MeshResource.generateBox(size: SIMD3(width, rowHeight, faceDepth))
            let material = makePanelFaceMaterial(texture: texture,
                                                  normalMap: panelNormalMap,
                                                  fallbackColor: UIColor(white: 0.35, alpha: 1.0))
            let overlay = ModelEntity(mesh: mesh, materials: [material])
            let normal = simd_normalize(faceNormal)
            overlay.orientation = simd_quatf(from: SIMD3<Float>(0, 0, 1), to: normal)
            overlay.position = center + normal * (panelDepth * 0.5 + faceDepth * 0.5 + 0.06)
            root.addChild(overlay)
        }

        addRowOverlay(center: SIMD3(0, panelY, backZ),
                      width: rowWidth(for: basePanelCount),
                      faceNormal: SIMD3(0, 0, 1),
                      texture: rowTexture(0))

        let groupCount = 8
        for groupIndex in 0..<2 {
            let startIndex = groupIndex * groupCount
            let endIndex = startIndex + groupCount - 1
            let groupCenterZ = backZ + (Float(startIndex + endIndex) * 0.5) * panelPitch
            let groupWidth = rowWidth(for: groupCount)
            addRowOverlay(center: SIMD3(-legX, panelY, groupCenterZ),
                          width: groupWidth,
                          faceNormal: SIMD3(1, 0, 0),
                          texture: rowTexture(1 + groupIndex))
            addRowOverlay(center: SIMD3(legX, panelY, groupCenterZ),
                          width: groupWidth,
                          faceNormal: SIMD3(-1, 0, 0),
                          texture: rowTexture(3 + groupIndex))
        }
        
        // Add 10x10 light panels on cabinet faces, flush against overlays
        // Overlay front face is at panelDepth*0.5 + faceDepth + 0.06 from cabinet center.
        // Place backing (thickness 0.02) so its back face just clears the overlay front.
        let panelThicknessLP: Float = 0.02
        let overlayFront = panelDepth * 0.5 + faceDepth + 0.06
        let lightPanelFaceOffset = overlayFront + panelThicknessLP * 0.5 + 0.002
        let lightPanelH: Float = 0.34
        let lightPanelY = panelY + panelHeight * 0.5 - lightPanelH * 0.25
        
        // Back row panels - facing user (positive Z)
        // Both panels on the right side of the back wall
        let backPanelZ = backZ + lightPanelFaceOffset
        let tunedY: Float = 2.05
        let lp2 = makeLightPanel(position: SIMD3(1.5449044, 2.080772, -8.898484),
                                  faceNormal: SIMD3(0, 0, 1), name: "lp_back_right")
        root.addChild(lp2)
        let lp1 = makeLightPanel(position: SIMD3(2.1449044, 2.055121, -8.898484),
                                  faceNormal: SIMD3(0, 0, 1), name: "lp_back_far_right")
        root.addChild(lp1)
        
        // Left side panels - facing right (positive X), flush with left leg cabinets
        // Cabinet numbers 1-16 from user's perspective (1 = closest to user, 16 = at back wall)
        // Panels needed at: 1, 5, 6, 7, 8, 10, 11, 12, 13, 14
        // Use the original working X position from lp3
        let leftPanelX: Float = -2.3985064
        let leftPanelY: Float = 2.0809224
        // Cabinet 1 is closest to user (highest Z), cabinet 16 is at back (lowest Z = backZ)
        // Z for cabinet number n = backZ + (16 - n) * panelPitch
        let leftPanelNumbers = [1, 5, 6, 7, 8, 10, 11, 12, 13, 14, 15]
        for cabinetNum in leftPanelNumbers {
            let z = backZ + Float(sidePanelCount - cabinetNum) * panelPitch
            let panel = makeLightPanel(position: SIMD3(leftPanelX, leftPanelY, z),
                                        faceNormal: SIMD3(1, 0, 0), 
                                        name: "lp_left_\(cabinetNum)")
            root.addChild(panel)
        }
        
        // Right side panels - facing left (negative X), flush with right leg cabinets
        // Cabinet 1 is closest to user, cabinet 16 is at back wall
        // Panels needed at: 7, 8, 13, 14, 15
        let rightPanelX: Float = 2.3982484
        let rightPanelY: Float = 2.0847638
        let rightPanelNumbers = [7, 8, 13, 14, 15]
        for cabinetNum in rightPanelNumbers {
            let z = backZ + Float(sidePanelCount - cabinetNum) * panelPitch
            let panel = makeLightPanel(position: SIMD3(rightPanelX, rightPanelY, z),
                                        faceNormal: SIMD3(-1, 0, 0), 
                                        name: "lp_right_\(cabinetNum)")
            root.addChild(panel)
        }

        root.scale = SIMD3(repeating: layoutScale)

        return (root, blinkLights)
    }

    private func loadPanelTextures() -> PanelTextures {
        let supportedExtensions = ["jpg", "jpeg", "png"]
        var urls: [URL] = []
        for fileExtension in supportedExtensions {
            if let found = realityKitContentBundle.urls(forResourcesWithExtension: fileExtension,
                                                        subdirectory: "Photographs") {
                urls.append(contentsOf: found)
            }
            if let found = realityKitContentBundle.urls(forResourcesWithExtension: fileExtension,
                                                        subdirectory: nil) {
                urls.append(contentsOf: found)
            }
        }

        // Load History photos — bundle flattens subdirectories, so load by known filenames
        let historyFileNames = [
            ("500004289-03-01", "jpg"),
            ("eckert-mauchly", "jpg"),
            ("ENIAC-1946.jpg", "png"),
            ("GettyImages-3243534-56b008303df78cf772cb3865", "jpg"),
            ("Glen_Beck_and_Betty_Snyder_program_the_ENIAC_in_building_328_at_the_Ballistic_Research_Laboratory", "jpg"),
            ("images", "jpeg"),
            ("less-than-p-greater-than-programmers-at-aberdeen-proving-grounds-configure-eniacs-function-tables-which-acted-as-a-form-of-read-only-memory-less-than-p-greater-than.jpg", "png"),
            ("presper-eckert-e1524609142180", "jpg"),
            ("Two_women_operating_ENIAC_(full_resolution)", "jpg"),
            ("Wiring-the-ENIAC-with-a-New-Program-575x375", "png"),
            ("women-computers-1024x768", "jpg"),
        ]
        var historyTextures: [TextureResource] = []
        for (name, ext) in historyFileNames {
            if let url = realityKitContentBundle.url(forResource: name, withExtension: ext) {
                if let texture = try? TextureResource.load(contentsOf: url) {
                    historyTextures.append(texture)
                    print("  Loaded history photo: \(name).\(ext)")
                }
            } else {
                print("  History photo not found: \(name).\(ext)")
            }
        }

        let deduped = Dictionary(grouping: urls, by: { $0.lastPathComponent })
            .compactMap { $0.value.first }
        let sorted = deduped.sorted { $0.lastPathComponent < $1.lastPathComponent }
        var panelTextures: [TextureResource] = []
        var controlTextures: [TextureResource] = []
        var posterTextures: [TextureResource] = []
        var rowTextureSlots: [TextureResource?] = Array(repeating: nil, count: 5)
        for url in sorted {
            do {
                let name = url.deletingPathExtension().lastPathComponent.lowercased()
                let texture = try TextureResource.load(contentsOf: url)
                if name.contains("control") {
                    controlTextures.append(texture)
                } else if name.hasPrefix("e3500s") {
                    let suffix = name.replacingOccurrences(of: "e3500s", with: "")
                    if let index = Int(suffix), (1...5).contains(index) {
                        rowTextureSlots[index - 1] = texture
                    }
                    panelTextures.append(texture)
                } else if name.hasPrefix("e") || name.hasPrefix("apilot") || name.hasPrefix("gpilot") || name.hasPrefix("orange") {
                    panelTextures.append(texture)
                } else {
                    posterTextures.append(texture)
                }
            } catch {
                print("Failed to load ENIAC photo \(url.lastPathComponent): \(error)")
            }
        }

        let fallbackRow = panelTextures.first
        let rowTextures = rowTextureSlots.compactMap { $0 ?? fallbackRow }
        if panelTextures.isEmpty {
            print("No ENIAC photo textures found in Resources/Photographs.")
        }
        if controlTextures.isEmpty {
            print("No ENIAC control panel textures found in Resources/Photographs.")
        }
        if posterTextures.isEmpty {
            print("No ENIAC poster textures found in Resources/Photographs.")
        }
        print("Loaded ENIAC textures: panels=\(panelTextures.count) controls=\(controlTextures.count) posters=\(posterTextures.count) rows=\(rowTextures.count) history=\(historyTextures.count)")
        return PanelTextures(panelTextures: panelTextures,
                             controlTextures: controlTextures,
                             posterTextures: posterTextures,
                             rowTextures: rowTextures,
                             historyTextures: historyTextures)
    }

    private func makeCenterUnits(panelWidth: Float,
                                 panelHeight: Float,
                                 panelDepth: Float,
                                 centerZ: Float,
                                 floorClearance: Float) -> Entity {
        let root = Entity()
        
        // Historical portable function table: ~1.2m wide × 1.7m tall × 0.3m deep panel
        // on an open steel frame with large caster wheels
        let tableWidth: Float = 1.2
        let tableDepth: Float = 0.25
        let panelFaceHeight: Float = 1.4
        let legHeight: Float = 0.35
        let frameThickness: Float = 0.06
        let casterRadius: Float = 0.06
        let topCapHeight: Float = 0.08
        let totalHeight = legHeight + panelFaceHeight + topCapHeight
        
        // Load free-standing unit texture
        var freestandingTexture: TextureResource?
        if let url = realityKitContentBundle.url(forResource: "free-standing-texture", withExtension: "png", subdirectory: "Photographs") {
            freestandingTexture = try? TextureResource.load(contentsOf: url)
        } else if let url = realityKitContentBundle.url(forResource: "free-standing-texture", withExtension: "png", subdirectory: nil) {
            freestandingTexture = try? TextureResource.load(contentsOf: url)
        }
        
        let darkFrame = SimpleMaterial(color: UIColor(white: 0.12, alpha: 1.0),
                                        roughness: 0.85, isMetallic: false)
        let casterMat = SimpleMaterial(color: UIColor(white: 0.08, alpha: 1.0),
                                        roughness: 0.5, isMetallic: true)
        
        func makeOneTable(position: SIMD3<Float>, angle: Float) -> Entity {
            let table = Entity()
            let baseY = floorClearance + casterRadius * 2
            
            // Base frame — horizontal bar at bottom
            let baseMesh = MeshResource.generateBox(size: SIMD3(tableWidth + frameThickness, frameThickness, tableDepth + frameThickness))
            let baseBar = ModelEntity(mesh: baseMesh, materials: [darkFrame])
            baseBar.position = SIMD3(0, baseY, 0)
            table.addChild(baseBar)
            
            // Two vertical side posts
            let postHeight = legHeight + panelFaceHeight + topCapHeight
            let postMesh = MeshResource.generateBox(size: SIMD3(frameThickness, postHeight, tableDepth))
            for side: Float in [-1, 1] {
                let post = ModelEntity(mesh: postMesh, materials: [darkFrame])
                post.position = SIMD3(side * (tableWidth * 0.5), baseY + postHeight * 0.5, 0)
                table.addChild(post)
            }
            
            // Top cap
            let topMesh = MeshResource.generateBox(size: SIMD3(tableWidth + frameThickness, topCapHeight, tableDepth + 0.02))
            let topCap = ModelEntity(mesh: topMesh, materials: [darkFrame])
            topCap.position = SIMD3(0, baseY + postHeight - topCapHeight * 0.5, 0)
            table.addChild(topCap)
            
            // Main panel face (the dial/switch area)
            let faceMesh = MeshResource.generateBox(size: SIMD3(tableWidth - frameThickness, panelFaceHeight, tableDepth - 0.02))
            let faceBody = ModelEntity(mesh: faceMesh, materials: [darkFrame])
            faceBody.position = SIMD3(0, baseY + legHeight + panelFaceHeight * 0.5, 0)
            table.addChild(faceBody)
            
            // Apply texture overlay on front face
            if let texture = freestandingTexture {
                let overlayMesh = MeshResource.generatePlane(width: tableWidth - frameThickness * 2,
                                                              height: panelFaceHeight - 0.04)
                var overlayMat = UnlitMaterial()
                overlayMat.color = .init(tint: .white, texture: MaterialParameters.Texture(texture))
                let overlay = ModelEntity(mesh: overlayMesh, materials: [overlayMat])
                overlay.position = SIMD3(0, baseY + legHeight + panelFaceHeight * 0.5,
                                          tableDepth * 0.5 + 0.005)
                table.addChild(overlay)
            }
            
            // 4 caster wheels
            let casterMesh = MeshResource.generateCylinder(height: 0.025, radius: casterRadius)
            let casterPositions: [SIMD3<Float>] = [
                SIMD3(-tableWidth * 0.45, casterRadius, -tableDepth * 0.35),
                SIMD3( tableWidth * 0.45, casterRadius, -tableDepth * 0.35),
                SIMD3(-tableWidth * 0.45, casterRadius,  tableDepth * 0.35),
                SIMD3( tableWidth * 0.45, casterRadius,  tableDepth * 0.35),
            ]
            for cp in casterPositions {
                let caster = ModelEntity(mesh: casterMesh, materials: [casterMat])
                caster.orientation = simd_quatf(angle: .pi / 2, axis: SIMD3(0, 0, 1))
                caster.position = cp
                table.addChild(caster)
            }
            
            // Fake shadow
            let shadowMesh = MeshResource.generatePlane(width: tableWidth * 1.1, depth: tableDepth * 2.0)
            var shadowMat = UnlitMaterial()
            shadowMat.color = .init(tint: UIColor(white: 0.0, alpha: 0.3))
            shadowMat.blending = .transparent(opacity: 1.0)
            let shadow = ModelEntity(mesh: shadowMesh, materials: [shadowMat])
            shadow.position = SIMD3(0, floorClearance + 0.005, 0)
            table.addChild(shadow)
            
            table.components.set(GroundingShadowComponent(castsShadow: true))
            table.position = position
            table.orientation = simd_quatf(angle: angle, axis: SIMD3(0, 1, 0))
            return table
        }
        
        // Place 2 portable function tables, parallel, rotated 35° to user, left of center
        let tableAngle: Float = 0.6109  // 35° counter-clockwise (mirrored)
        let table1 = makeOneTable(position: SIMD3(-0.6, 0, centerZ * 1.5), angle: tableAngle)
        let table2 = makeOneTable(position: SIMD3(-1.4, 0, centerZ * 1.5), angle: tableAngle)
        root.addChild(table1)
        root.addChild(table2)
        
        return root
    }

    private func makeFaceMaterial(texture: TextureResource?, fallbackColor: UIColor) -> UnlitMaterial {
        var material = UnlitMaterial()
        if let texture {
            material.color = .init(tint: .white,
                                   texture: MaterialParameters.Texture(texture))
        } else {
            material.color = .init(tint: fallbackColor)
        }
        return material
    }

    /// Creates an unlit material for panel faces to keep controls readable in simulator exposure.
    private func makePanelFaceMaterial(texture: TextureResource?, normalMap: TextureResource?, fallbackColor: UIColor) -> UnlitMaterial {
        var material = UnlitMaterial()
        if let texture {
            material.color = .init(tint: .white,
                                   texture: MaterialParameters.Texture(texture))
        } else {
            material.color = .init(tint: fallbackColor)
        }
        _ = normalMap
        return material
    }

    /// Generates a procedural normal map texture for ENIAC panel details
    /// Creates frame borders, knob bumps, and wire groove patterns
    private func generatePanelNormalMap(width: Int = 512, height: Int = 512) -> TextureResource? {
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var pixelData = [UInt8](repeating: 128, count: width * height * bytesPerPixel)
        
        // Helper to set normal at pixel (nx, ny, nz in -1 to 1 range)
        func setNormal(x: Int, y: Int, nx: Float, ny: Float, nz: Float) {
            guard x >= 0 && x < width && y >= 0 && y < height else { return }
            let index = (y * width + x) * bytesPerPixel
            // Convert from -1...1 to 0...255 (tangent space normal map)
            pixelData[index + 0] = UInt8(clamping: Int((nx * 0.5 + 0.5) * 255))  // R = X
            pixelData[index + 1] = UInt8(clamping: Int((ny * 0.5 + 0.5) * 255))  // G = Y
            pixelData[index + 2] = UInt8(clamping: Int((nz * 0.5 + 0.5) * 255))  // B = Z
            pixelData[index + 3] = 255  // A
        }
        
        // Initialize all pixels to flat normal (pointing out of surface)
        for y in 0..<height {
            for x in 0..<width {
                setNormal(x: x, y: y, nx: 0, ny: 0, nz: 1)
            }
        }
        
        // Panel frame borders (raised edges) - creates 8 panel sections
        let panelCountX = 8
        let panelCountY = 4
        let panelWidth = width / panelCountX
        let panelHeight = height / panelCountY
        let borderWidth = 4
        let borderStrength: Float = 0.6
        
        for py in 0..<panelCountY {
            for px in 0..<panelCountX {
                let startX = px * panelWidth
                let startY = py * panelHeight
                
                // Left border (normal pointing right)
                for by in 0..<panelHeight {
                    for bx in 0..<borderWidth {
                        let fade = Float(bx) / Float(borderWidth)
                        setNormal(x: startX + bx, y: startY + by,
                                 nx: borderStrength * (1 - fade), ny: 0, nz: sqrt(1 - pow(borderStrength * (1 - fade), 2)))
                    }
                }
                // Right border (normal pointing left)
                for by in 0..<panelHeight {
                    for bx in 0..<borderWidth {
                        let fade = Float(bx) / Float(borderWidth)
                        setNormal(x: startX + panelWidth - 1 - bx, y: startY + by,
                                 nx: -borderStrength * (1 - fade), ny: 0, nz: sqrt(1 - pow(borderStrength * (1 - fade), 2)))
                    }
                }
                // Top border (normal pointing down)
                for bx in 0..<panelWidth {
                    for by in 0..<borderWidth {
                        let fade = Float(by) / Float(borderWidth)
                        setNormal(x: startX + bx, y: startY + by,
                                 nx: 0, ny: -borderStrength * (1 - fade), nz: sqrt(1 - pow(borderStrength * (1 - fade), 2)))
                    }
                }
                // Bottom border (normal pointing up)
                for bx in 0..<panelWidth {
                    for by in 0..<borderWidth {
                        let fade = Float(by) / Float(borderWidth)
                        setNormal(x: startX + bx, y: startY + panelHeight - 1 - by,
                                 nx: 0, ny: borderStrength * (1 - fade), nz: sqrt(1 - pow(borderStrength * (1 - fade), 2)))
                    }
                }
            }
        }
        
        // Add knob bumps (circular raised areas)
        let knobRadius = 8
        let knobStrength: Float = 0.7
        let knobPositions: [(Int, Int)] = [
            // Distribute knobs across panel sections
            (panelWidth / 2, panelHeight / 2),
            (panelWidth + panelWidth / 2, panelHeight / 2),
            (panelWidth * 2 + panelWidth / 3, panelHeight / 2),
            (panelWidth * 3 + panelWidth / 2, panelHeight + panelHeight / 2),
            (panelWidth * 4 + panelWidth / 4, panelHeight / 2),
            (panelWidth * 5 + panelWidth / 2, panelHeight * 2 + panelHeight / 2),
            (panelWidth * 6 + panelWidth / 3, panelHeight / 2),
            (panelWidth * 7 + panelWidth / 2, panelHeight + panelHeight / 3),
            // More knobs in different rows
            (panelWidth / 3, panelHeight * 2 + panelHeight / 2),
            (panelWidth * 2 + panelWidth / 2, panelHeight * 3 + panelHeight / 3),
            (panelWidth * 4 + panelWidth / 2, panelHeight * 2 + panelHeight / 2),
            (panelWidth * 6 + panelWidth / 2, panelHeight * 3 + panelHeight / 2),
        ]
        
        for (kx, ky) in knobPositions {
            for dy in -knobRadius...knobRadius {
                for dx in -knobRadius...knobRadius {
                    let dist = sqrt(Float(dx * dx + dy * dy))
                    if dist <= Float(knobRadius) {
                        let normalizedDist = dist / Float(knobRadius)
                        // Hemisphere normal
                        let nx = Float(dx) / Float(knobRadius) * knobStrength
                        let ny = Float(dy) / Float(knobRadius) * knobStrength
                        let nz = sqrt(max(0, 1 - nx*nx - ny*ny))
                        setNormal(x: kx + dx, y: ky + dy, nx: nx, ny: ny, nz: nz)
                    }
                }
            }
        }
        
        // Add horizontal wire grooves
        let wireSpacing = height / 12
        let wireDepth: Float = 0.3
        let wireThickness = 2
        
        for wireIndex in 1..<12 {
            let wireY = wireIndex * wireSpacing
            // Skip wires that would overlap with panel borders
            if wireY % panelHeight < borderWidth * 2 || wireY % panelHeight > panelHeight - borderWidth * 2 {
                continue
            }
            for x in 0..<width {
                // Skip panel border areas
                if x % panelWidth < borderWidth || x % panelWidth > panelWidth - borderWidth {
                    continue
                }
                // Top edge of wire (normal pointing up)
                for t in 0..<wireThickness {
                    setNormal(x: x, y: wireY - wireThickness + t,
                             nx: 0, ny: wireDepth * (1 - Float(t) / Float(wireThickness)), nz: 0.95)
                }
                // Bottom edge of wire (normal pointing down)
                for t in 0..<wireThickness {
                    setNormal(x: x, y: wireY + t,
                             nx: 0, ny: -wireDepth * (1 - Float(t) / Float(wireThickness)), nz: 0.95)
                }
            }
        }
        
        // Create CGImage from pixel data
        guard let provider = CGDataProvider(data: Data(pixelData) as CFData) else { return nil }
        guard let cgImage = CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        ) else { return nil }
        
        // Convert to TextureResource
        do {
            let texture = try TextureResource.generate(from: cgImage, options: .init(semantic: .normal))
            return texture
        } catch {
            print("Failed to create normal map texture: \(error)")
            return nil
        }
    }

    private func placeENIAC(_ entity: Entity, scaleToTargetLength: Bool) -> BoundingBox? {
        if scaleToTargetLength {
            let bounds = entity.visualBounds(relativeTo: nil)
            let extents = bounds.extents
            let horizontalExtent = max(extents.x, extents.z)
            guard horizontalExtent > 0 else {
                print("ENIAC model has invalid bounds: \(extents)")
                return nil
            }

            let uniformScale = eniacTargetLengthMeters / horizontalExtent
            entity.scale = SIMD3(repeating: uniformScale)
        }

        let bounds = entity.visualBounds(relativeTo: nil)
        let centerX = (bounds.min.x + bounds.max.x) * 0.5
        let xOffset = -centerX
        let yOffset = -bounds.min.y
        let zOffset = -bounds.max.z - eniacPaddingMeters
        entity.position = SIMD3(xOffset, yOffset, zOffset)
        return entity.visualBounds(relativeTo: nil)
    }

    private func roomLayout(for bounds: BoundingBox) -> RoomLayout {
        let paddingX: Float = 4.5
        let paddingZ: Float = 3.5  // Reduced to bring photo wall closer
        let width = max(bounds.extents.x + paddingX * 2, 18.0)
        let depth = max(bounds.extents.z + paddingZ * 2, 12.0)  // Reduced minimum depth
        let center = SIMD3<Float>((bounds.min.x + bounds.max.x) * 0.5,
                                  0,
                                  (bounds.min.z + bounds.max.z) * 0.5)
        return RoomLayout(center: center, width: width, depth: depth, height: roomHeightMeters)
    }

    private func makeOfficeEnvironment(layout: RoomLayout,
                                       posterTextures: [TextureResource],
                                       historyTextures: [TextureResource]) -> Entity {
        let root = Entity()
        root.addChild(makeOfficeShell(layout: layout, posterTextures: posterTextures, historyTextures: historyTextures))
        root.addChild(makeOfficeLighting(layout: layout))
        return root
    }

    private func makeOfficeShell(layout: RoomLayout,
                                 posterTextures: [TextureResource],
                                 historyTextures: [TextureResource]) -> Entity {
        let root = Entity()
        let wallThickness: Float = 0.12
        let floorThickness: Float = 0.04
        let floorY: Float = -0.03
        let halfWidth = layout.width * 0.5
        let halfDepth = layout.depth * 0.5

        let wallMaterial = makeWallMaterial()
        let ceilingMaterial = makeCeilingMaterial()
        let floorMaterial = makeFloorMaterial()

        let backWall = ModelEntity(mesh: .generateBox(size: SIMD3(layout.width, layout.height, wallThickness)),
                                   materials: [wallMaterial])
        backWall.position = SIMD3(layout.center.x, layout.height * 0.5, layout.center.z - halfDepth)
        root.addChild(backWall)

        let leftWall = ModelEntity(mesh: .generateBox(size: SIMD3(wallThickness, layout.height, layout.depth)),
                                   materials: [wallMaterial])
        leftWall.position = SIMD3(layout.center.x - halfWidth, layout.height * 0.5, layout.center.z)
        root.addChild(leftWall)

        let rightWall = ModelEntity(mesh: .generateBox(size: SIMD3(wallThickness, layout.height, layout.depth)),
                                    materials: [wallMaterial])
        rightWall.position = SIMD3(layout.center.x + halfWidth, layout.height * 0.5, layout.center.z)
        root.addChild(rightWall)

        // Front wall (behind user) with history photos
        let frontWall = ModelEntity(mesh: .generateBox(size: SIMD3(layout.width, layout.height, wallThickness)),
                                    materials: [wallMaterial])
        frontWall.position = SIMD3(layout.center.x, layout.height * 0.5, layout.center.z + halfDepth)
        root.addChild(frontWall)

        // Hang history photographs on front wall — doubled to 20" x 16" (0.508m x 0.406m)
        // Captions match the order in historyFileNames array
        let historyCaptions = [
            "ENIAC at the Moore School, 1946",
            "J. Presper Eckert, Leslie R. Groves and John Mauchly",
            "ENIAC's First Public Demonstration, 1946",
            "J. Presper Eckert and John Mauchly",
            "Glen Beck and Betty Snyder Programming ENIAC",
            "John Mauchly.",
            "Configuring Function Tables at Aberdeen",
            "J. Presper Eckert",
            "Two Women Operating ENIAC",
            "Wiring ENIAC with a New Program",
            "The ENIAC Programmers"
        ]
        if !historyTextures.isEmpty {
            let photoWidth: Float = 0.508
            let photoHeight: Float = 0.406
            let frameInset: Float = 0.03
            let frameDepth: Float = 0.02
           // let captionHeight: Float = 0.06
            let captionGap: Float = 0.02
            let photoY: Float = 1.6
            let photoZ = layout.center.z + halfDepth - wallThickness * 0.5 - 0.005
            let count = historyTextures.count
            let spacing: Float = 0.85
            let totalSpan = Float(count - 1) * spacing
            let startX = layout.center.x - totalSpan * 0.5

            let frameMat = SimpleMaterial(color: UIColor(white: 0.15, alpha: 1.0),
                                          roughness: 0.4, isMetallic: false)
            let captionBackMat = SimpleMaterial(color: UIColor(white: 0.12, alpha: 1.0),
                                                roughness: 0.5, isMetallic: false)

            for (i, texture) in historyTextures.enumerated() {
                let x = startX + Float(i) * spacing

                // Dark frame
                let frameMesh = MeshResource.generateBox(size: SIMD3(photoWidth + frameInset * 2,
                                                                      photoHeight + frameInset * 2,
                                                                      frameDepth))
                let frame = ModelEntity(mesh: frameMesh, materials: [frameMat])
                frame.position = SIMD3(x, photoY, photoZ)
                root.addChild(frame)

                // Photo face
                let faceMesh = MeshResource.generatePlane(width: photoWidth, height: photoHeight)
                var faceMat = UnlitMaterial()
                faceMat.color = .init(tint: .white, texture: MaterialParameters.Texture(texture))
                let face = ModelEntity(mesh: faceMesh, materials: [faceMat])
                face.orientation = simd_quatf(angle: .pi, axis: SIMD3(0, 1, 0))
                face.position = SIMD3(x, photoY, photoZ - frameDepth * 0.5 - 0.001)
                root.addChild(face)

                // Generate text mesh for caption first to measure its size
                let captionText = i < historyCaptions.count ? historyCaptions[i] : "Historic ENIAC Photo"
                // Use a classic 1950s-era serif typeface
                let serifFont = UIFont(name: "Times New Roman", size: 0.025) ?? UIFont.systemFont(ofSize: 0.025)
                let textMesh = MeshResource.generateText(captionText,
                                                         extrusionDepth: 0.002,
                                                         font: serifFont,
                                                         containerFrame: .zero,
                                                         alignment: .center,
                                                         lineBreakMode: .byTruncatingTail)
                let textBounds = textMesh.bounds
                let textWidth = textBounds.max.x - textBounds.min.x
                let textHeight = textBounds.max.y - textBounds.min.y

                // Caption sign below photo - sized to fit text with padding
                let captionPaddingX: Float = 0.025
                let captionPaddingY: Float = 0.015
                let captionBackWidth = textWidth + captionPaddingX * 2
                let captionBackHeight = textHeight + captionPaddingY * 2
                let captionY = photoY - photoHeight * 0.5 - frameInset - captionGap - captionBackHeight * 0.5
                let captionBackMesh = MeshResource.generateBox(size: SIMD3(captionBackWidth, captionBackHeight, 0.01))
                let captionBack = ModelEntity(mesh: captionBackMesh, materials: [captionBackMat])
                captionBack.position = SIMD3(x, captionY, photoZ - frameDepth * 0.5)
                root.addChild(captionBack)

                // Add the text
                var textMat = UnlitMaterial()
                textMat.color = .init(tint: UIColor(white: 0.9, alpha: 1.0))
                let textEntity = ModelEntity(mesh: textMesh, materials: [textMat])
                // Rotate text to face the user (towards -Z)
                textEntity.orientation = simd_quatf(angle: .pi, axis: SIMD3(0, 1, 0))
                // Center text on caption backing
                let textCenterOffset = (textBounds.min + textBounds.max) * 0.5
                textEntity.position = SIMD3(x + textCenterOffset.x,
                                            captionY - textCenterOffset.y,
                                            photoZ - frameDepth * 0.5 - 0.006)
                root.addChild(textEntity)
            }
        }

        let ceiling = ModelEntity(mesh: .generateBox(size: SIMD3(layout.width, wallThickness, layout.depth)),
                                  materials: [ceilingMaterial])
        ceiling.position = SIMD3(layout.center.x, layout.height, layout.center.z)
        root.addChild(ceiling)

        let floor = ModelEntity(mesh: .generateBox(size: SIMD3(layout.width, floorThickness, layout.depth)),
                                materials: [floorMaterial])
        floor.position = SIMD3(layout.center.x, floorY, layout.center.z)
        floor.components.set(GroundingShadowComponent(castsShadow: false))
        root.addChild(floor)

        let posterMesh = MeshResource.generatePlane(width: 2.0, depth: 1.4)
        let posterRotation = simd_quatf(angle: -.pi / 2, axis: SIMD3(1, 0, 0))
        let posterY = layout.height * 0.6
        let posterZ = layout.center.z - halfDepth + wallThickness * 0.5 + 0.03
        let posterXOffset = layout.width * 0.28
        let posters: [SIMD3<Float>] = [
            SIMD3(layout.center.x - posterXOffset, posterY, posterZ),
            SIMD3(layout.center.x + posterXOffset, posterY, posterZ)
        ]
        for (index, position) in posters.enumerated() {
            let texture = posterTextures.isEmpty ? nil : posterTextures[index % posterTextures.count]
            let posterMaterial = makeFaceMaterial(texture: texture,
                                                   fallbackColor: UIColor(white: 0.95, alpha: 1.0))
            let poster = ModelEntity(mesh: posterMesh, materials: [posterMaterial])
            poster.orientation = posterRotation
            poster.position = position
            root.addChild(poster)
        }

        return root
    }

    private func makeFloorMaterial() -> PhysicallyBasedMaterial {
        var material = PhysicallyBasedMaterial()
        
        if let url = realityKitContentBundle.url(forResource: "floor_concrete",
                                                  withExtension: "png",
                                                  subdirectory: "Textures"),
           let floorTex = try? TextureResource.load(contentsOf: url) {
            material.baseColor = .init(tint: UIColor(white: 0.65, alpha: 1.0),
                                       texture: MaterialParameters.Texture(floorTex))
        } else if let url = realityKitContentBundle.url(forResource: "floor_concrete",
                                                         withExtension: "png",
                                                         subdirectory: nil),
                  let floorTex = try? TextureResource.load(contentsOf: url) {
            material.baseColor = .init(tint: UIColor(white: 0.65, alpha: 1.0),
                                       texture: MaterialParameters.Texture(floorTex))
        } else {
            material.baseColor = .init(tint: UIColor(red: 0.32, green: 0.30, blue: 0.28, alpha: 1.0))
        }
        
        // Keep texture frequency low to reduce shimmer in simulator.
        material.textureCoordinateTransform = .init(scale: SIMD2<Float>(1.5, 1.5))
        material.roughness = .init(floatLiteral: 1.0)
        material.metallic = .init(floatLiteral: 0.0)

        return material
    }
    
    private func makeWallMaterial() -> PhysicallyBasedMaterial {
        var material = PhysicallyBasedMaterial()
        
        // Generate subtle wall texture with paint imperfections
        let wallTexture = generateWallTexture()
        
        material.baseColor = .init(tint: UIColor(red: 0.88, green: 0.85, blue: 0.80, alpha: 1.0),
                                   texture: wallTexture.map { MaterialParameters.Texture($0) })
        material.roughness = .init(floatLiteral: 0.92)
        material.metallic = .init(floatLiteral: 0.0)
        
        return material
    }
    
    private func makeCeilingMaterial() -> PhysicallyBasedMaterial {
        var material = PhysicallyBasedMaterial()
        
        // Try to load ceiling tile texture, else generate procedural
        if let url = realityKitContentBundle.url(forResource: "ceiling_tiles",
                                                  withExtension: "png",
                                                  subdirectory: "Textures"),
           let ceilTex = try? TextureResource.load(contentsOf: url) {
            material.baseColor = .init(tint: UIColor(white: 0.95, alpha: 1.0),
                                       texture: MaterialParameters.Texture(ceilTex))
        } else {
            // Generate procedural ceiling tile texture with many tiles
            let ceilingTexture = generateCeilingTexture()
            if let tex = ceilingTexture {
                material.baseColor = .init(tint: UIColor(white: 0.92, alpha: 1.0),
                                           texture: MaterialParameters.Texture(tex))
            } else {
                material.baseColor = .init(tint: UIColor(white: 0.92, alpha: 1.0))
            }
        }
        
        // Scale UVs to tile the texture across the ceiling
        material.textureCoordinateTransform = .init(scale: SIMD2<Float>(4, 4))
        
        material.roughness = .init(floatLiteral: 0.95)
        material.metallic = .init(floatLiteral: 0.0)
        
        return material
    }
    
    private func generateFloorTexture() -> TextureResource? {
        let size = 512
        var pixels = [UInt8](repeating: 0, count: size * size * 4)
        
        for y in 0..<size {
            for x in 0..<size {
                let i = (y * size + x) * 4
                
                // Base concrete gray with subtle variation
                let baseGray: UInt8 = 140
                let noise1 = Int.random(in: -15...15)
                let noise2 = Int.random(in: -8...8)
                
                // Add subtle stains and wear patterns
                let stainChance = Double.random(in: 0...1)
                let stain: Int = stainChance < 0.02 ? Int.random(in: -25...0) : 0
                
                // Subtle tile grid lines (4 tiles across)
                let tileSize = size / 4
                let onGridX = (x % tileSize) < 2 || (x % tileSize) > tileSize - 3
                let onGridY = (y % tileSize) < 2 || (y % tileSize) > tileSize - 3
                let gridDarken: Int = (onGridX || onGridY) ? -12 : 0
                
                let gray = UInt8(clamping: Int(baseGray) + noise1 + noise2 + stain + gridDarken)
                pixels[i] = gray
                pixels[i + 1] = gray
                pixels[i + 2] = UInt8(clamping: Int(gray) - 3)  // Slightly warmer
                pixels[i + 3] = 255
            }
        }
        
        return createTextureFromPixels(pixels, size: size)
    }
    
    private func generateFloorNormalMap() -> TextureResource? {
        let size = 512
        var pixels = [UInt8](repeating: 0, count: size * size * 4)
        
        for y in 0..<size {
            for x in 0..<size {
                let i = (y * size + x) * 4
                
                // Subtle surface bumps
                let bumpX = Double.random(in: -0.03...0.03)
                let bumpY = Double.random(in: -0.03...0.03)
                
                // Tile grid creates slight height variation
                let tileSize = size / 4
                let nearEdgeX = abs((x % tileSize) - tileSize/2) > tileSize/2 - 4
                let nearEdgeY = abs((y % tileSize) - tileSize/2) > tileSize/2 - 4
                let edgeBump = (nearEdgeX || nearEdgeY) ? 0.08 : 0.0
                
                let nx = bumpX
                let ny = bumpY + edgeBump
                let nz = sqrt(max(0, 1.0 - nx*nx - ny*ny))
                
                pixels[i] = UInt8(clamping: Int((nx + 1.0) * 127.5))
                pixels[i + 1] = UInt8(clamping: Int((ny + 1.0) * 127.5))
                pixels[i + 2] = UInt8(clamping: Int(nz * 255))
                pixels[i + 3] = 255
            }
        }
        
        return createTextureFromPixels(pixels, size: size, isNormal: true)
    }
    
    private func generateWallTexture() -> TextureResource? {
        let size = 256
        var pixels = [UInt8](repeating: 0, count: size * size * 4)
        
        for y in 0..<size {
            for x in 0..<size {
                let i = (y * size + x) * 4
                
                // Warm off-white base with subtle paint texture
                let baseR: UInt8 = 225
                let baseG: UInt8 = 218
                let baseB: UInt8 = 205
                
                // Subtle variation for paint texture
                let noise = Int.random(in: -6...6)
                
                // Occasional subtle marks/scuffs
                let scuffChance = Double.random(in: 0...1)
                let scuff: Int = scuffChance < 0.005 ? Int.random(in: -15...0) : 0
                
                pixels[i] = UInt8(clamping: Int(baseR) + noise + scuff)
                pixels[i + 1] = UInt8(clamping: Int(baseG) + noise + scuff)
                pixels[i + 2] = UInt8(clamping: Int(baseB) + noise + scuff)
                pixels[i + 3] = 255
            }
        }
        
        return createTextureFromPixels(pixels, size: size)
    }
    
    private func generateCeilingTexture() -> TextureResource? {
        let size = 512
        var pixels = [UInt8](repeating: 0, count: size * size * 4)
        
        // Create 8x8 tile grid within the texture
        let tilesPerSide = 8
        let tileSize = size / tilesPerSide
        
        for y in 0..<size {
            for x in 0..<size {
                let i = (y * size + x) * 4
                
                // Tile grid lines (darker edges)
                let localX = x % tileSize
                let localY = y % tileSize
                let onGridX = localX < 2 || localX > tileSize - 3
                let onGridY = localY < 2 || localY > tileSize - 3
                
                let baseGray: UInt8 = (onGridX || onGridY) ? 175 : 232
                let noise = Int.random(in: -3...3)
                
                // Subtle perforation pattern for acoustic tiles (small dots)
                let dotSpacing = 6
                let dotPattern = ((localX % dotSpacing) < 1 && (localY % dotSpacing) < 1) ? -6 : 0
                
                // Slight variation between tiles
                let tileX = x / tileSize
                let tileY = y / tileSize
                let tileVariation = ((tileX + tileY) % 3 - 1) * 3
                
                let gray = UInt8(clamping: Int(baseGray) + noise + dotPattern + tileVariation)
                pixels[i] = gray
                pixels[i + 1] = gray
                pixels[i + 2] = UInt8(clamping: Int(gray) + 2)  // Slightly cooler
                pixels[i + 3] = 255
            }
        }
        
        return createTextureFromPixels(pixels, size: size)
    }
    
    private func createTextureFromPixels(_ pixels: [UInt8], size: Int, isNormal: Bool = false) -> TextureResource? {
        let data = Data(pixels)
        guard let cgProvider = CGDataProvider(data: data as CFData) else { return nil }
        guard let cgImage = CGImage(width: size,
                                     height: size,
                                     bitsPerComponent: 8,
                                     bitsPerPixel: 32,
                                     bytesPerRow: size * 4,
                                     space: CGColorSpaceCreateDeviceRGB(),
                                     bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                                     provider: cgProvider,
                                     decode: nil,
                                     shouldInterpolate: true,
                                     intent: .defaultIntent) else { return nil }
        
        let semantic: TextureResource.Semantic = isNormal ? .normal : .color
        return try? TextureResource.generate(from: cgImage, options: .init(semantic: semantic))
    }

    private func makeOfficeLighting(layout: RoomLayout) -> Entity {
        let root = Entity()
        let warmLight = UIColor(red: 1.0, green: 0.97, blue: 0.9, alpha: 1.0)

        // Main overhead directional light
        let directional = DirectionalLight()
        directional.light.color = warmLight
        directional.light.intensity = 6500
        directional.position = SIMD3(layout.center.x,
                                     layout.height,
                                     layout.center.z)
        directional.look(at: SIMD3(layout.center.x, 0, layout.center.z),
                         from: directional.position,
                         relativeTo: nil)
        root.addChild(directional)

        // Multiple fill lights distributed around the room for better ambient coverage
        let fillLightIntensity: Float = 22000
        let fillLightRadius: Float = 30.0
        let fillPositions: [SIMD3<Float>] = [
            SIMD3(layout.center.x - layout.width * 0.42, layout.height * 0.45, layout.center.z - layout.depth * 0.42),
            SIMD3(layout.center.x + layout.width * 0.42, layout.height * 0.45, layout.center.z - layout.depth * 0.42),
            SIMD3(layout.center.x - layout.width * 0.42, layout.height * 0.45, layout.center.z + layout.depth * 0.42),
            SIMD3(layout.center.x + layout.width * 0.42, layout.height * 0.45, layout.center.z + layout.depth * 0.42),
            SIMD3(layout.center.x, layout.height * 0.35, layout.center.z),
        ]
        for pos in fillPositions {
            let fill = PointLight()
            fill.light.color = warmLight
            fill.light.intensity = fillLightIntensity
            fill.light.attenuationRadius = fillLightRadius
            fill.position = pos
            root.addChild(fill)
        }

        let ambientLift = PointLight()
        ambientLift.light.color = warmLight
        ambientLift.light.intensity = 12000
        ambientLift.light.attenuationRadius = 48.0
        ambientLift.position = SIMD3(layout.center.x, layout.height * 0.45, layout.center.z)
        root.addChild(ambientLift)

        // Circular ceiling lights (period-appropriate)
        let lightRadius: Float = 0.2
        let lightThickness: Float = 0.04
        let fixtureY = layout.height - 0.06
        
        let lightMesh = MeshResource.generateCylinder(height: lightThickness, radius: lightRadius)
        let emissiveMaterial = UnlitMaterial(color: UIColor(white: 0.74, alpha: 1.0))
        
        // Grid: lights in a 5x4 pattern
        let lightRows = 5
        let lightCols = 4
        let spacingX = layout.width / Float(lightCols + 1)
        let spacingZ = layout.depth / Float(lightRows + 1)
        
        for row in 0..<lightRows {
            for col in 0..<lightCols {
                let x = layout.center.x - layout.width * 0.5 + spacingX * Float(col + 1)
                let z = layout.center.z - layout.depth * 0.5 + spacingZ * Float(row + 1)
                
                let light = ModelEntity(mesh: lightMesh, materials: [emissiveMaterial])
                light.position = SIMD3(x, fixtureY, z)
                root.addChild(light)
                
                // Subtle ring around the light
                let ringMesh = MeshResource.generateCylinder(height: lightThickness * 0.5,
                                                              radius: lightRadius + 0.02)
                let ringMat = SimpleMaterial(color: UIColor(white: 0.75, alpha: 1.0),
                                             roughness: 0.5, isMetallic: true)
                let ring = ModelEntity(mesh: ringMesh, materials: [ringMat])
                ring.position = SIMD3(x, fixtureY + 0.001, z)
                root.addChild(ring)
            }
        }
        
        return root
    }

    private func startBlinking() {
        blinkTask?.cancel()
        guard !blinkLights.isEmpty else { return }
        blinkTask = Task { @MainActor in
            // Determine number of panels and columns
            let maxPanel = blinkLights.map { $0.panelIndex }.max() ?? 0
            let columns = 10
            
            // Track which digit (row 0-9) is currently lit for each column on each panel
            // Row corresponds to digit value: row 0 = digit "0", row 9 = digit "9"
            var activeDigits: [[Int]] = Array(repeating: Array(repeating: 0, count: columns), count: maxPanel + 1)
            
            // Initialize with random starting values
            for panel in 0...maxPanel {
                for col in 0..<columns {
                    activeDigits[panel][col] = Int.random(in: 0...9)
                }
            }
            
            // Set initial state - only one digit per column is on
            for light in blinkLights {
                let isOn = light.row == activeDigits[light.panelIndex][light.column]
                light.entity.model?.materials = [isOn ? light.onMaterial : light.offMaterial]
                light.entity.isEnabled = true
            }
            
            // Track per-column update timing for less predictable animation
            var columnTimers: [[Double]] = Array(repeating: Array(repeating: 0, count: columns), count: maxPanel + 1)
            for panel in 0...maxPanel {
                for col in 0..<columns {
                    // Stagger initial timers so columns don't all update at once
                    columnTimers[panel][col] = Double.random(in: 0.5...2.5)
                }
            }
            
            let tickInterval: UInt64 = 100_000_000  // 100ms tick
            
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: tickInterval)
                
                // Decrement timers and update columns that are ready
                for panel in 0...maxPanel {
                    for col in 0..<columns {
                        columnTimers[panel][col] -= 0.1
                        
                        if columnTimers[panel][col] <= 0 {
                            // Change the active digit for this column
                            let oldDigit = activeDigits[panel][col]
                            
                            // Usually increment/decrement, occasionally jump
                            let change: Int
                            let r = Double.random(in: 0...1)
                            if r < 0.4 {
                                change = 1  // Increment
                            } else if r < 0.7 {
                                change = -1  // Decrement
                            } else if r < 0.85 {
                                change = Int.random(in: -3...3)  // Small jump
                            } else {
                                change = Int.random(in: 0...9) - oldDigit  // Random position
                            }
                            
                            var newDigit = oldDigit + change
                            // Wrap around 0-9
                            newDigit = ((newDigit % 10) + 10) % 10
                            activeDigits[panel][col] = newDigit
                            
                            // Update the entities for this column
                            for light in blinkLights where light.panelIndex == panel && light.column == col {
                                let isOn = light.row == newDigit
                                light.entity.model?.materials = [isOn ? light.onMaterial : light.offMaterial]
                            }
                            
                            // Reset timer with varied delay (slower, less predictable)
                            columnTimers[panel][col] = Double.random(in: 0.8...3.5)
                        }
                    }
                }
            }
        }
    }

    private func makeOfficeFurniture(layout: RoomLayout) -> Entity {
        let root = Entity()
        let deskMaterial = SimpleMaterial(color: UIColor(red: 0.4, green: 0.26, blue: 0.16, alpha: 1.0),
                                           roughness: 0.6,
                                           isMetallic: false)
        let chairMaterial = SimpleMaterial(color: UIColor(white: 0.25, alpha: 1.0),
                                            roughness: 0.8,
                                            isMetallic: false)

        let deskSize = SIMD3<Float>(1.6, 0.75, 0.8)
        let deskZ = layout.center.z - layout.depth * 0.35
        let deskXOffset = layout.width * 0.3
        let deskY = deskSize.y * 0.5

        let deskMesh = MeshResource.generateBox(size: deskSize)
        let deskPositions = [
            SIMD3(layout.center.x - deskXOffset, deskY, deskZ),
            SIMD3(layout.center.x + deskXOffset, deskY, deskZ)
        ]
        for position in deskPositions {
            let desk = ModelEntity(mesh: deskMesh, materials: [deskMaterial])
            desk.position = position
            root.addChild(desk)
        }

        let chairMeshSeat = MeshResource.generateBox(size: SIMD3<Float>(0.5, 0.12, 0.5))
        let chairMeshBack = MeshResource.generateBox(size: SIMD3<Float>(0.5, 0.5, 0.08))
        func makeChair() -> Entity {
            let chair = Entity()
            let seat = ModelEntity(mesh: chairMeshSeat, materials: [chairMaterial])
            seat.position = SIMD3(0, 0.06, 0)
            chair.addChild(seat)

            let back = ModelEntity(mesh: chairMeshBack, materials: [chairMaterial])
            back.position = SIMD3(0, 0.06 + 0.25, -0.21)
            chair.addChild(back)
            return chair
        }

        let chairZOffset: Float = 0.75
        for position in deskPositions {
            let chair = makeChair()
            chair.position = SIMD3(position.x, 0, position.z + chairZOffset)
            chair.orientation = simd_quatf(angle: .pi, axis: SIMD3(0, 1, 0))
            root.addChild(chair)
        }

        return root
    }
}

// MARK: - Info Panel View
struct InfoPanelView: View {
    let title: String
    let description: String
    let fact: String
    let onDismiss: () -> Void

    // Classic 1950s-era serif typeface
    private let serifFont = Font.custom("Times New Roman", size: 19)
    private let serifTitleFont = Font.custom("Times New Roman", size: 26)
    private let serifCalloutFont = Font.custom("Times New Roman", size: 16)
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title)
                    .font(serifTitleFont)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundColor(.gray)
                }
                .buttonStyle(.plain)
            }

            Divider()
                .background(Color.white.opacity(0.3))

            Text(description)
                .font(serifFont)
                .foregroundColor(.white.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)

            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "lightbulb.fill")
                    .foregroundColor(.yellow)
                    .font(.callout)
                Text(fact)
                    .font(serifCalloutFont)
                    .foregroundColor(.yellow.opacity(0.9))
                    .italic()
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 4)
        }
        .padding(24)
        .frame(width: 460)
        .background(.ultraThinMaterial)
        .cornerRadius(16)
    }
}

#Preview(immersionStyle: .full) {
    ImmersiveView()
        .environment(AppModel())
}

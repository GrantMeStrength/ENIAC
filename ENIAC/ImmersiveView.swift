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
    private let roomHeightMeters: Float = 3.2
    @State private var blinkLights: [BlinkLight] = []
    @State private var blinkTask: Task<Void, Never>?
    @State private var depthDragMode = false
    @State private var dragStartPosition: SIMD3<Float>?
    @State private var activeInfoID: String?

    private struct InfoPoint: Identifiable {
        let id: String
        let title: String
        let description: String
        let fact: String
        let position: SIMD3<Float>
        let faceNormal: SIMD3<Float>
    }

    private static let infoPoints: [InfoPoint] = [
        InfoPoint(id: "info_accumulators_left",
                  title: "Accumulators",
                  description: "The main arithmetic units of ENIAC, capable of addition, subtraction, and number storage. Twenty accumulators worked in parallel, each storing a 10-digit decimal number using vacuum tubes. They formed the computational heart of the machine.",
                  fact: "Each accumulator contained 550 vacuum tubes — one reason ENIAC needed 18,000 tubes total.",
                  position: SIMD3(-2.35, 1.2, -4.5),
                  faceNormal: SIMD3(1, 0, 0)),
        InfoPoint(id: "info_function_tables",
                  title: "Function Tables",
                  description: "Specialized memory units storing pre-calculated mathematical constants and lookup tables. Instead of recomputing common values, operators could retrieve them instantly. Three portable function tables could each hold 104 entries of 12-digit numbers.",
                  fact: "Function tables were programmed by setting hundreds of rotary dial switches by hand — a painstaking process that could take hours.",
                  position: SIMD3(2.35, 1.2, -4.5),
                  faceNormal: SIMD3(-1, 0, 0)),
        InfoPoint(id: "info_master_programmer",
                  title: "Master Programmer",
                  description: "The sequencing unit that controlled program flow and loop counting. It directed the order of operations and could set up nested loops for iterative calculations. Programming required physically reconnecting hundreds of cables between panels.",
                  fact: "Reprogramming ENIAC could take days of rewiring. In 1948, a stored-program modification allowed instructions to be stored in the function tables instead.",
                  position: SIMD3(-2.35, 1.2, -7.5),
                  faceNormal: SIMD3(1, 0, 0)),
        InfoPoint(id: "info_cycling_unit",
                  title: "Cycling Unit",
                  description: "The master clock generating timing pulses that synchronized all of ENIAC's operations. Running at 100 kHz — 100,000 pulses per second — it ensured every component executed instructions in lockstep. ENIAC could perform 5,000 additions per second.",
                  fact: "ENIAC was roughly 1,000 times faster than existing electromechanical calculators, completing in seconds what previously took days.",
                  position: SIMD3(0, 1.2, -8.6),
                  faceNormal: SIMD3(0, 0, 1)),
        InfoPoint(id: "info_initiating_unit",
                  title: "Initiating Unit",
                  description: "The control panel where operators started and monitored program execution. It contained switches for launching calculations, single-stepping through operations, and reading machine status. This was the primary human interface to the computer.",
                  fact: "Six women — Kay McNulty, Betty Jennings, Betty Snyder, Marlyn Meltzer, Fran Bilas, and Ruth Lichterman — were ENIAC's first programmers, configuring it for ballistic trajectory calculations.",
                  position: SIMD3(1.5, 1.2, -8.6),
                  faceNormal: SIMD3(0, 0, 1)),
        InfoPoint(id: "info_portable_unit",
                  title: "Portable Function Table",
                  description: "A free-standing wheeled cabinet that could be rolled up and connected to the main ENIAC frame. It provided additional memory and function storage, and could be swapped out with different configurations for different problems.",
                  fact: "The portable design was remarkably forward-thinking — it introduced modularity to computing years before it became standard practice.",
                  position: SIMD3(0, 0.9, -3.7),
                  faceNormal: SIMD3(0, 0, 1)),
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
    }

    private struct BlinkLight {
        let entity: ModelEntity
        let onMaterial: UnlitMaterial
        let offMaterial: UnlitMaterial
        let phaseOffset: Int
    }

    var body: some View {
        RealityView { content, attachments in
            do {
                let immersiveContentEntity = try await Entity(named: "Immersive", in: realityKitContentBundle)
                if let videoDock = immersiveContentEntity.findEntity(named: "Video_Dock") {
                    videoDock.removeFromParent()
                }
                content.add(immersiveContentEntity)
            } catch {
                print("Failed to load immersive environment: \(error)")
            }

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
                                                     posterTextures: posterTextures))
            }
            content.add(anchor)

            // Add info buttons and pre-create hidden panel anchors
            for info in Self.infoPoints {
                let button = makeInfoButton(info: info)
                anchor.addChild(button)

                if let attachment = attachments.entity(for: info.id) {
                    let panelAnchor = Entity()
                    panelAnchor.name = "infopanel_\(info.id)"
                    let normal = simd_normalize(info.faceNormal)
                    panelAnchor.position = info.position + normal * 0.6 + SIMD3(0, 0.5, 0)
                    panelAnchor.components.set(BillboardComponent())
                    panelAnchor.addChild(attachment)
                    panelAnchor.isEnabled = false
                    anchor.addChild(panelAnchor)
                }
            }
        } update: { content, attachments in
            // Show/hide info panels based on activeInfoID
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
                    guard let name = findInfoParentName(entity: value.entity) else { return }
                    let infoID = name.replacingOccurrences(of: "btn_", with: "")
                    if activeInfoID == infoID {
                        activeInfoID = nil
                    } else {
                        activeInfoID = infoID
                    }
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
        buttonRoot.position = info.position

        // Subtle disc with "ⓘ" style
        let radius: Float = 0.03
        let discThickness: Float = 0.004
        let discMesh = MeshResource.generateCylinder(height: discThickness, radius: radius)
        var discMaterial = PhysicallyBasedMaterial()
        discMaterial.baseColor = .init(tint: UIColor(white: 0.15, alpha: 0.85))
        discMaterial.roughness = .init(floatLiteral: 0.4)
        discMaterial.metallic = .init(floatLiteral: 0.8)
        let disc = ModelEntity(mesh: discMesh, materials: [discMaterial])
        // Orient disc to face the info normal
        let normal = simd_normalize(info.faceNormal)
        disc.orientation = simd_quatf(from: SIMD3<Float>(0, 1, 0), to: normal)
        disc.components.set(InputTargetComponent(allowedInputTypes: .all))
        disc.components.set(CollisionComponent(shapes: [.generateSphere(radius: radius * 3.0)]))
        disc.components.set(HoverEffectComponent())
        buttonRoot.addChild(disc)

        // Thin glowing ring around the edge
        let ringRadius: Float = radius + 0.003
        let ringMesh = MeshResource.generateCylinder(height: discThickness * 0.5, radius: ringRadius)
        var ringMaterial = UnlitMaterial()
        ringMaterial.color = .init(tint: UIColor(red: 0.5, green: 0.7, blue: 1.0, alpha: 0.4))
        let ring = ModelEntity(mesh: ringMesh, materials: [ringMaterial])
        ring.orientation = disc.orientation
        buttonRoot.addChild(ring)

        return buttonRoot
    }

    private func makeENIACLayout(textures: PanelTextures) -> (entity: Entity, blinkLights: [BlinkLight]) {
        let sidePanelCount = 16
        let basePanelCount = 8
        let totalPanels = sidePanelCount * 2 + basePanelCount

        let panelWidth: Float = 0.6
        let panelHeight: Float = 2.4
        let panelDepth: Float = 0.9
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
            let bodyMaterial = SimpleMaterial(color: UIColor(white: 0.18, alpha: 1.0),
                                               roughness: 0.9,
                                               isMetallic: false)
            let body = ModelEntity(mesh: bodyMesh, materials: [bodyMaterial])
            body.components.set(ModelComponent(mesh: bodyMesh, materials: [bodyMaterial]))
            body.components.set(GroundingShadowComponent(castsShadow: true))
            panel.addChild(body)
            
            return panel
        }
        
        func makeLightPanel(position: SIMD3<Float>, faceNormal: SIMD3<Float>, name: String) -> Entity {
            let panelRoot = Entity()
            panelRoot.name = name
            let panelWidth: Float = 0.48
            let panelHeight: Float = 0.34
            let panelThickness: Float = 0.02
            let lightsPerRow = 10
            let lightRows = 10
            let smallerBulbRadius: Float = 0.006
            
            // Dark backing panel - also serves as drag target
            let backingMesh = MeshResource.generateBox(size: SIMD3(panelWidth, panelHeight, panelThickness))
            let backingMaterial = SimpleMaterial(color: UIColor(white: 0.1, alpha: 1.0),
                                                  roughness: 0.8,
                                                  isMetallic: false)
            let backing = ModelEntity(mesh: backingMesh, materials: [backingMaterial])
            backing.name = name + "_backing"
            backing.components.set(InputTargetComponent(allowedInputTypes: .all))
            // Thicker collision box for reliable targeting at distance
            backing.components.set(CollisionComponent(shapes: [.generateBox(size: SIMD3(panelWidth, panelHeight, 0.15))]))
            panelRoot.addChild(backing)
            
            // Grid of 10x10 lights
            let bulbMesh = MeshResource.generateSphere(radius: smallerBulbRadius)
            let lightColor = UIColor(white: 1.0, alpha: 1.0)
            let gridSpacingX = panelWidth * 0.85 / Float(lightsPerRow - 1)
            let gridSpacingY = panelHeight * 0.85 / Float(lightRows - 1)
            let startOffsetX = -panelWidth * 0.85 * 0.5
            let startOffsetY = -panelHeight * 0.85 * 0.5
            let phaseOffsetBase = blinkLights.count
            
            for row in 0..<lightRows {
                for col in 0..<lightsPerRow {
                    var onMaterial = UnlitMaterial()
                    onMaterial.color = .init(tint: lightColor)
                    var offMaterial = UnlitMaterial()
                    offMaterial.color = .init(tint: UIColor(white: 0.15, alpha: 1.0))
                    let bulb = ModelEntity(mesh: bulbMesh, materials: [offMaterial])
                    bulb.position = SIMD3(startOffsetX + Float(col) * gridSpacingX,
                                          startOffsetY + Float(row) * gridSpacingY,
                                          panelThickness * 0.5 + smallerBulbRadius)
                    backing.addChild(bulb)
                    blinkLights.append(BlinkLight(entity: bulb,
                                                  onMaterial: onMaterial,
                                                  offMaterial: offMaterial,
                                                  phaseOffset: phaseOffsetBase + row * lightsPerRow + col))
                }
            }
            
            panelRoot.position = position
            // Orient the panel so the lights face the given normal direction
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

        let rowHeight = panelHeight * 0.94
        func rowWidth(for count: Int) -> Float {
            Float(count - 1) * panelPitch + panelWidth * 0.96
        }
        func addRowOverlay(center: SIMD3<Float>, width: Float, faceNormal: SIMD3<Float>, texture: TextureResource?) {
            let mesh = MeshResource.generateBox(size: SIMD3(width, rowHeight, faceDepth))
            let material = makeFaceMaterial(texture: texture,
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
        // Use same Y as the tuned side panels
        let backPanelZ = backZ + lightPanelFaceOffset
        let tunedY: Float = 2.05
        let lp1 = makeLightPanel(position: SIMD3(1.4943672, 2.0489478, -8.615842),
                                  faceNormal: SIMD3(0, 0, 1), name: "lp_back_left")
        root.addChild(lp1)
        let lp2 = makeLightPanel(position: SIMD3(2.1103811, 2.0489266, -8.617195),
                                  faceNormal: SIMD3(0, 0, 1), name: "lp_back_right")
        root.addChild(lp2)
        
        // Left side panel - facing right (positive X), flush with left leg cabinets
        let sidePanelZ = backZ + 3.0 * panelPitch
        let lp3 = makeLightPanel(position: SIMD3(-2.3509514, 2.0560832, -7.3134885),
                                  faceNormal: SIMD3(1, 0, 0), name: "lp_left")
        root.addChild(lp3)
        
        // Right side panel - facing left (negative X), flush with right leg cabinets
        let lp4 = makeLightPanel(position: SIMD3(2.3459857, 2.045791, -7.3094997),
                                  faceNormal: SIMD3(-1, 0, 0), name: "lp_right")
        root.addChild(lp4)

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
        print("Loaded ENIAC textures: panels=\(panelTextures.count) controls=\(controlTextures.count) posters=\(posterTextures.count) rows=\(rowTextures.count)")
        return PanelTextures(panelTextures: panelTextures,
                             controlTextures: controlTextures,
                             posterTextures: posterTextures,
                             rowTextures: rowTextures)
    }

    private func makeCenterUnits(panelWidth: Float,
                                 panelHeight: Float,
                                 panelDepth: Float,
                                 centerZ: Float,
                                 floorClearance: Float) -> Entity {
        let root = Entity()
        let unitWidth: Float = 1.2  // 60% of 2.0
        let unitDepth: Float = 0.3  // 60% of 0.5
        let unitHeight: Float = 1.2  // 60% of 2.0
        let wheelRadius: Float = 0.03  // 60% of 0.05
        let wheelOffsetX = unitWidth * 0.45
        let wheelOffsetZ = unitDepth * 0.45
        let baseY = unitHeight * 0.5 + floorClearance + wheelRadius * 2
        
        // Load free-standing unit texture
        var freestandingTexture: TextureResource?
        // Try both search methods like loadPanelTextures does
        if let url = realityKitContentBundle.url(forResource: "free-standing-texture", withExtension: "png", subdirectory: "Photographs") {
            freestandingTexture = try? TextureResource.load(contentsOf: url)
            print("Loaded free-standing texture from Photographs: \(url.lastPathComponent)")
        } else if let url = realityKitContentBundle.url(forResource: "free-standing-texture", withExtension: "png", subdirectory: nil) {
            freestandingTexture = try? TextureResource.load(contentsOf: url)
            print("Loaded free-standing texture from root: \(url.lastPathComponent)")
        } else {
            print("Failed to find free-standing-texture.png in bundle")
        }
        
        let frameMaterial = SimpleMaterial(color: UIColor(white: 0.2, alpha: 1.0),
                                           roughness: 0.85,
                                           isMetallic: false)
        let mesh = MeshResource.generateBox(size: SIMD3(unitWidth, unitHeight, unitDepth))
        
        let wheelMaterial = SimpleMaterial(color: UIColor(white: 0.1, alpha: 1.0),
                                            roughness: 0.7,
                                            isMetallic: false)
        let wheelMesh = MeshResource.generateCylinder(height: 0.02, radius: wheelRadius)
        let wheelOffsets = [
            SIMD3(-wheelOffsetX, -unitHeight * 0.5 - wheelRadius, -wheelOffsetZ),
            SIMD3(wheelOffsetX, -unitHeight * 0.5 - wheelRadius, -wheelOffsetZ),
            SIMD3(-wheelOffsetX, -unitHeight * 0.5 - wheelRadius, wheelOffsetZ),
            SIMD3(wheelOffsetX, -unitHeight * 0.5 - wheelRadius, wheelOffsetZ)
        ]
        
        // Single unit in center of U, angled towards user, positioned near back wall
        let unit = ModelEntity(mesh: mesh, materials: [frameMaterial])
        unit.position = SIMD3(0, baseY, centerZ * 2.0)
        unit.orientation = simd_quatf(angle: 0.6, axis: SIMD3(0, 1, 0))
        unit.components.set(GroundingShadowComponent(castsShadow: true))
        
        // Add textured front face (largest face: width x height)
        if let texture = freestandingTexture {
            let faceMesh = MeshResource.generatePlane(width: unitWidth, height: unitHeight)
            var faceMaterial = UnlitMaterial()
            faceMaterial.color = .init(tint: .white, texture: MaterialParameters.Texture(texture))
            let face = ModelEntity(mesh: faceMesh, materials: [faceMaterial])
            face.position = SIMD3(0, 0, unitDepth * 0.5 + 0.01)
            unit.addChild(face)
        }
        
        // Fake shadow on floor under unit
        let shadowMesh = MeshResource.generatePlane(width: unitWidth * 1.1, depth: unitDepth * 1.5)
        var shadowMaterial = UnlitMaterial()
        shadowMaterial.color = .init(tint: UIColor(white: 0.0, alpha: 0.35))
        shadowMaterial.blending = .transparent(opacity: 1.0)
        let shadow = ModelEntity(mesh: shadowMesh, materials: [shadowMaterial])
        shadow.position = SIMD3(0, -baseY + floorClearance + 0.005, 0)
        unit.addChild(shadow)
        
        for offset in wheelOffsets {
            let wheel = ModelEntity(mesh: wheelMesh, materials: [wheelMaterial])
            wheel.orientation = simd_quatf(angle: .pi / 2, axis: SIMD3(1, 0, 0))
            wheel.position = offset
            unit.addChild(wheel)
        }
        root.addChild(unit)
        
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
        let paddingZ: Float = 6.0
        let width = max(bounds.extents.x + paddingX * 2, 18.0)
        let depth = max(bounds.extents.z + paddingZ * 2, 16.0)
        let center = SIMD3<Float>((bounds.min.x + bounds.max.x) * 0.5,
                                  0,
                                  (bounds.min.z + bounds.max.z) * 0.5)
        return RoomLayout(center: center, width: width, depth: depth, height: roomHeightMeters)
    }

    private func makeOfficeEnvironment(layout: RoomLayout,
                                       posterTextures: [TextureResource]) -> Entity {
        let root = Entity()
        root.addChild(makeOfficeShell(layout: layout, posterTextures: posterTextures))
        root.addChild(makeOfficeLighting(layout: layout))
        root.addChild(makeOfficeFurniture(layout: layout))
        return root
    }

    private func makeOfficeShell(layout: RoomLayout,
                                 posterTextures: [TextureResource]) -> Entity {
        let root = Entity()
        let wallThickness: Float = 0.12
        let floorThickness: Float = 0.002
        let floorY: Float = 0.0  // Floor at ground level
        let halfWidth = layout.width * 0.5
        let halfDepth = layout.depth * 0.5

        let wallMaterial = SimpleMaterial(color: UIColor(white: 0.94, alpha: 1.0),
                                           roughness: 0.9,
                                           isMetallic: false)
        let ceilingMaterial = SimpleMaterial(color: UIColor(white: 0.98, alpha: 1.0),
                                              roughness: 0.95,
                                              isMetallic: false)
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

        let ceiling = ModelEntity(mesh: .generateBox(size: SIMD3(layout.width, wallThickness, layout.depth)),
                                  materials: [ceilingMaterial])
        ceiling.position = SIMD3(layout.center.x, layout.height, layout.center.z)
        root.addChild(ceiling)

        let floor = ModelEntity(mesh: .generateBox(size: SIMD3(layout.width, floorThickness, layout.depth)),
                                materials: [floorMaterial])
        floor.position = SIMD3(layout.center.x, floorY, layout.center.z)
        floor.components.set(GroundingShadowComponent(castsShadow: false))
        root.addChild(floor)

        var windowMaterial = UnlitMaterial()
        windowMaterial.color = .init(tint: UIColor(red: 0.72, green: 0.86, blue: 1.0, alpha: 1.0))
        let windowMesh = MeshResource.generateBox(size: SIMD3<Float>(2.4, 1.3, 0.02))
        let windowZ = layout.center.z - halfDepth + wallThickness * 0.5 + 0.02
        let windowY = layout.height * 0.65
        let windowXOffset = layout.width * 0.2
        let windowPositions = [
            SIMD3(layout.center.x - windowXOffset, windowY, windowZ),
            SIMD3(layout.center.x + windowXOffset, windowY, windowZ)
        ]
        for position in windowPositions {
            let window = ModelEntity(mesh: windowMesh, materials: [windowMaterial])
            window.position = position
            root.addChild(window)
        }

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

    private func makeFloorMaterial() -> SimpleMaterial {
        var material = SimpleMaterial(color: .white, roughness: 0.7, isMetallic: false)
        
        if let url = realityKitContentBundle.url(forResource: "floor_checker",
                                                  withExtension: "png",
                                                  subdirectory: "Textures"),
           let texture = try? TextureResource.load(contentsOf: url) {
            material.color = .init(tint: UIColor(white: 0.95, alpha: 1.0),
                                   texture: MaterialParameters.Texture(texture))
            print("Loaded floor checker texture")
        } else if let url = realityKitContentBundle.url(forResource: "floor_checker",
                                                         withExtension: "png",
                                                         subdirectory: nil),
                  let texture = try? TextureResource.load(contentsOf: url) {
            material.color = .init(tint: UIColor(white: 0.95, alpha: 1.0),
                                   texture: MaterialParameters.Texture(texture))
            print("Loaded floor checker texture from root")
        } else {
            material.color = .init(tint: UIColor(white: 0.92, alpha: 1.0))
            print("Failed to load floor checker texture, using fallback")
        }
        
        return material
    }

    private func makeOfficeLighting(layout: RoomLayout) -> Entity {
        let root = Entity()
        let warmLight = UIColor(red: 1.0, green: 0.97, blue: 0.9, alpha: 1.0)

        // Main overhead directional light with shadows
        let directional = DirectionalLight()
        directional.light.color = warmLight
        directional.light.intensity = 2000
        directional.shadow = DirectionalLightComponent.Shadow(maximumDistance: 35.0, depthBias: 0.5)
        directional.position = SIMD3(layout.center.x,
                                     layout.height,
                                     layout.center.z)
        directional.look(at: SIMD3(layout.center.x, 0, layout.center.z),
                         from: directional.position,
                         relativeTo: nil)
        root.addChild(directional)

        // Add fluorescent ceiling lights - visual fixtures only, directional provides illumination
        let fixtureWidth: Float = 1.2
        let fixtureDepth: Float = 0.3
        let fixtureHeight: Float = 0.08
        let fixtureY = layout.height - fixtureHeight * 0.5 - 0.05
        
        let fixtureMaterial = SimpleMaterial(color: UIColor(white: 0.95, alpha: 1.0),
                                              roughness: 0.3,
                                              isMetallic: false)
        let emissiveMaterial = UnlitMaterial(color: UIColor(white: 0.98, alpha: 1.0))
        
        // Grid of fluorescent fixtures (4 rows x 3 columns)
        let rows = 4
        let cols = 3
        let spacingX = layout.width / Float(cols + 1)
        let spacingZ = layout.depth / Float(rows + 1)
        
        for row in 0..<rows {
            for col in 0..<cols {
                let x = layout.center.x - layout.width * 0.5 + spacingX * Float(col + 1)
                let z = layout.center.z - layout.depth * 0.5 + spacingZ * Float(row + 1)
                
                // Fixture housing
                let fixtureMesh = MeshResource.generateBox(size: SIMD3(fixtureWidth, fixtureHeight, fixtureDepth))
                let fixture = ModelEntity(mesh: fixtureMesh, materials: [fixtureMaterial])
                fixture.position = SIMD3(x, fixtureY, z)
                root.addChild(fixture)
                
                // Emissive panel below fixture
                let panelThickness: Float = 0.01
                let panelMesh = MeshResource.generateBox(size: SIMD3(fixtureWidth * 0.95, panelThickness, fixtureDepth * 0.95))
                let panel = ModelEntity(mesh: panelMesh, materials: [emissiveMaterial])
                panel.position = SIMD3(0, -fixtureHeight * 0.5 - panelThickness * 0.5 - 0.005, 0)
                fixture.addChild(panel)
            }
        }
        return root
    }

    private func startBlinking() {
        blinkTask?.cancel()
        guard !blinkLights.isEmpty else { return }
        blinkTask = Task { @MainActor in
            var phase = 0
            while !Task.isCancelled {
                phase += 1
                for light in blinkLights {
                    let isOn = (phase + light.phaseOffset) % 3 != 0
                    light.entity.model?.materials = [isOn ? light.onMaterial : light.offMaterial]
                    light.entity.isEnabled = true
                }
                try? await Task.sleep(nanoseconds: 320_000_000)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title)
                    .font(.title2)
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
                .font(.body)
                .foregroundColor(.white.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)

            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "lightbulb.fill")
                    .foregroundColor(.yellow)
                    .font(.callout)
                Text(fact)
                    .font(.callout)
                    .foregroundColor(.yellow.opacity(0.9))
                    .italic()
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 4)
        }
        .padding(20)
        .frame(width: 380)
        .background(.ultraThinMaterial)
        .cornerRadius(16)
    }
}

#Preview(immersionStyle: .full) {
    ImmersiveView()
        .environment(AppModel())
}

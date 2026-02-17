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
        RealityView { content in
            do {
                let immersiveContentEntity = try await Entity(named: "Immersive", in: realityKitContentBundle)
                if let ground = immersiveContentEntity.findEntity(named: "Ground") {
                    ground.removeFromParent()
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
        }
        .onAppear {
            startBlinking()
        }
        .onChange(of: blinkLights.count) { _ in
            startBlinking()
        }
        .onDisappear {
            blinkTask?.cancel()
        }
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
            panel.addChild(body)

            let lightOffset = panelDepth * 0.5 + faceDepth + 0.05

            let bulbMesh = MeshResource.generateSphere(radius: bulbRadius)
            let lightColor = UIColor(white: 1.0, alpha: 1.0)
            let lightsPerRow = 6
            let rowCount = 2
            let lightRowY = panelHeight * 0.32
            let rowSpacing = panelHeight * 0.12
            let lightRowWidth = panelWidth * 0.7
            let startX = -lightRowWidth * 0.5
            let spacing = lightRowWidth / Float(lightsPerRow - 1)
            let phaseOffsetBase = blinkLights.count
            var lightIndex = 0
            for row in 0..<rowCount {
                let rowY = lightRowY - Float(row) * rowSpacing
                for index in 0..<lightsPerRow {
                    var onMaterial = UnlitMaterial()
                    onMaterial.color = .init(tint: lightColor)
                    var offMaterial = UnlitMaterial()
                    offMaterial.color = .init(tint: UIColor(white: 0.2, alpha: 1.0))
                    let bulb = ModelEntity(mesh: bulbMesh, materials: [offMaterial])
                    bulb.position = SIMD3(startX + Float(index) * spacing,
                                          rowY,
                                          faceSign * lightOffset)
                    panel.addChild(bulb)
                    blinkLights.append(BlinkLight(entity: bulb,
                                                  onMaterial: onMaterial,
                                                  offMaterial: offMaterial,
                                                  phaseOffset: phaseOffsetBase + lightIndex))
                    lightIndex += 1
                }
            }
            return panel
        }

        let root = Entity()
        let panelY = panelHeight * 0.5 + floorClearance

        let baseHalfWidth = Float(basePanelCount - 1) * panelPitch * 0.5
        let legStartZ = panelDepth * 0.5 + panelWidth * 0.5 + cornerGap
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
                } else if name.hasPrefix("e480s") {
                    let suffix = name.replacingOccurrences(of: "e480s", with: "")
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
        let unitWidth: Float = 2.0
        let unitDepth: Float = 0.5
        let unitHeight: Float = 2.0
        let wheelRadius: Float = 0.05
        let wheelOffsetX = unitWidth * 0.45
        let wheelOffsetZ = unitDepth * 0.45
        let baseY = unitHeight * 0.5 + floorClearance + wheelRadius * 2
        let material = SimpleMaterial(color: UIColor(white: 0.2, alpha: 1.0),
                                       roughness: 0.85,
                                       isMetallic: false)
        let mesh = MeshResource.generateBox(size: SIMD3(unitWidth, unitHeight, unitDepth))
        let spacing: Float = unitWidth * 1.4
        let positions = [
            SIMD3(-spacing, baseY, centerZ),
            SIMD3(0, baseY, centerZ),
            SIMD3(spacing, baseY, centerZ)
        ]
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
        let orientations: [Float] = [-0.2, 0.1, 0.3]
        for (index, position) in positions.enumerated() {
            let unit = ModelEntity(mesh: mesh, materials: [material])
            unit.position = position
            unit.orientation = simd_quatf(angle: orientations[index % orientations.count],
                                          axis: SIMD3(0, 1, 0))
            for offset in wheelOffsets {
                let wheel = ModelEntity(mesh: wheelMesh, materials: [wheelMaterial])
                wheel.orientation = simd_quatf(angle: .pi / 2, axis: SIMD3(1, 0, 0))
                wheel.position = offset
                unit.addChild(wheel)
            }
            root.addChild(unit)
        }
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
        floor.position = SIMD3(layout.center.x, -floorThickness * 0.5, layout.center.z)
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
        if let url = realityKitContentBundle.url(forResource: "floor_checker",
                                                  withExtension: "png",
                                                  subdirectory: "Textures"),
           let texture = try? TextureResource.load(contentsOf: url) {
            var material = SimpleMaterial(color: .white, roughness: 0.85, isMetallic: false)
            material.color = .init(tint: UIColor(white: 0.95, alpha: 1.0),
                                   texture: MaterialParameters.Texture(texture))
            return material
        }
        return SimpleMaterial(color: UIColor(white: 0.92, alpha: 1.0),
                              roughness: 0.85,
                              isMetallic: false)
    }

    private func makeOfficeLighting(layout: RoomLayout) -> Entity {
        let root = Entity()
        let warmLight = UIColor(red: 1.0, green: 0.97, blue: 0.9, alpha: 1.0)

        let directional = DirectionalLight()
        directional.light.color = warmLight
        directional.light.intensity = 120000
        directional.position = SIMD3(layout.center.x,
                                     layout.height,
                                     layout.center.z + layout.depth * 0.45)
        directional.look(at: SIMD3(layout.center.x, layout.height * 0.4, layout.center.z),
                         from: directional.position,
                         relativeTo: nil)
        root.addChild(directional)

        let fillDirectional = DirectionalLight()
        fillDirectional.light.color = warmLight
        fillDirectional.light.intensity = 80000
        fillDirectional.position = SIMD3(layout.center.x,
                                         layout.height,
                                         layout.center.z - layout.depth * 0.45)
        fillDirectional.look(at: SIMD3(layout.center.x, layout.height * 0.4, layout.center.z),
                             from: fillDirectional.position,
                             relativeTo: nil)
        root.addChild(fillDirectional)

        let attenuation = max(layout.width, layout.depth) * 2.0
        let pointPositions = [
            SIMD3(layout.center.x, layout.height - 0.25, layout.center.z),
            SIMD3(layout.center.x, layout.height - 0.25, layout.center.z - layout.depth * 0.3),
            SIMD3(layout.center.x, layout.height - 0.25, layout.center.z + layout.depth * 0.3),
            SIMD3(layout.center.x - layout.width * 0.35, layout.height - 0.25, layout.center.z),
            SIMD3(layout.center.x + layout.width * 0.35, layout.height - 0.25, layout.center.z),
            SIMD3(layout.center.x - layout.width * 0.35, layout.height - 0.25, layout.center.z + layout.depth * 0.3),
            SIMD3(layout.center.x + layout.width * 0.35, layout.height - 0.25, layout.center.z + layout.depth * 0.3)
        ]
        for position in pointPositions {
            let light = PointLight()
            light.light.color = warmLight
            light.light.intensity = 45000
            light.light.attenuationRadius = attenuation
            light.position = position
            root.addChild(light)
        }

        let ambientFill = PointLight()
        ambientFill.light.color = warmLight
        ambientFill.light.intensity = 65000
        ambientFill.light.attenuationRadius = attenuation
        ambientFill.position = SIMD3(layout.center.x, layout.height * 0.7, layout.center.z)
        root.addChild(ambientFill)
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

#Preview(immersionStyle: .full) {
    ImmersiveView()
        .environment(AppModel())
}

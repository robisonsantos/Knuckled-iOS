import SwiftUI
import SceneKit

/// 3D die (120pt). Same contract as the temporary 2D DieView it replaces:
/// fixed size, tap only when enabled && !rolling, spinning cue while rolling.
struct DiceSceneView: View {
    let value: Int?
    let rolling: Bool
    let enabled: Bool
    let onTap: () -> Void
    var metrics: LayoutMetrics = .compact

    var body: some View {
        // The visible die lives OUTSIDE the Button: SwiftUI dims the content
        // of a disabled Button (~50%), which made the die look faded whenever
        // it wasn't tappable (incl. while rolling). The transparent overlay
        // Button keeps the exact buttons["dice"] contract (taps, isEnabled,
        // identifiers, labels) while the die always renders full-opacity.
        ZStack {
            DiceSceneRepresentable(value: value, rolling: rolling)
                .frame(width: metrics.die, height: metrics.die)
                .allowsHitTesting(false)
            Button(action: {
                if enabled && !rolling { onTap() }
            }) {
                Color.clear
                    .frame(width: metrics.die, height: metrics.die)
                    .contentShape(Rectangle()) // Color.clear is not hittable without this
            }
            .buttonStyle(.plain)
            .disabled(!(enabled && !rolling))
            .accessibilityIdentifier("dice")
            .accessibilityLabel(rolling ? "Dice rolling" : value.map { "Dice showing \($0)" } ?? "Dice tap to roll")
        }
        .frame(width: metrics.die, height: metrics.die)
    }
}

private struct DiceSceneRepresentable: UIViewRepresentable {
    let value: Int?
    let rolling: Bool

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.backgroundColor = .clear
        view.scene = makeScene()
        view.autoenablesDefaultLighting = true
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        context.coordinator.sync(scene: view.scene, value: value, rolling: rolling)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    private func makeScene() -> SCNScene {
        let scene = SCNScene()
        let camera = SCNCamera()
        let cameraNode = SCNNode()
        cameraNode.camera = camera
        cameraNode.position = SCNVector3(0, 0, 3)
        scene.rootNode.addChildNode(cameraNode)
        scene.rootNode.addChildNode(Coordinator.makePivot())
        return scene
    }

    final class Coordinator {
        private var pivot: SCNNode?
        private var displayLink: CADisplayLink?
        private var velocity = SCNVector3Zero
        private var lastTick = CFTimeInterval(0)

        static func makePivot() -> SCNNode {
            let pivot = SCNNode()
            pivot.name = "pivot"
            if let model = loadModel() {
                pivot.addChildNode(model)
            }
            return pivot
        }

        /// dice.usdz when conversion won (Task 6A), else the procedural box.
        static func loadModel() -> SCNNode? {
            if let url = Bundle.main.url(forResource: "dice", withExtension: "usdz"),
               let scene = try? SCNScene(url: url, options: nil),
               let node = scene.rootNode.childNodes.first {
                // Re-center off-center geometry (Android parity: separate pivot
                // node at the origin + centered child, so spin never orbits).
                let (bbMin, bbMax) = node.boundingBox
                node.position = SCNVector3(
                    -(bbMin.x + bbMax.x) / 2,
                    -(bbMin.y + bbMax.y) / 2,
                    -(bbMin.z + bbMax.z) / 2
                )
                let longest = max(bbMax.x - bbMin.x, max(bbMax.y - bbMin.y, bbMax.z - bbMin.z))
                if longest > 0 {
                    let s = Float(1.5) / longest
                    node.scale = SCNVector3(s, s, s)
                }
                return node
            }
            return makeProceduralDie()
        }

        /// Fallback box: 6 pip-face materials on SCNBox order
        /// [front, right, back, left, top, bottom] = [+z,+x,-z,-x,+y,-y].
        static func makeProceduralDie() -> SCNNode? {
            var materials: [SCNMaterial] = []
            for face in DiceOrientation.proceduralFaces {
                let material = SCNMaterial()
                material.diffuse.contents = UIImage(named: "\(face)")
                materials.append(material)
            }
            guard materials.count == 6 else { return nil }
            let box = SCNBox(width: 1.5, height: 1.5, length: 1.5, chamferRadius: 0.12)
            box.materials = materials
            return SCNNode(geometry: box)
        }

        func sync(scene: SCNScene?, value: Int?, rolling: Bool) {
            if pivot == nil { pivot = scene?.rootNode.childNode(withName: "pivot", recursively: false) }
            guard let pivot else { return }
            let reduceMotion = UIAccessibility.isReduceMotionEnabled
            if rolling, !reduceMotion {
                if displayLink == nil {
                    velocity = SCNVector3(
                        x: Float(720).degreesToRadians * (Bool.random() ? 1 : -1),
                        y: Float(540).degreesToRadians * (Bool.random() ? 1 : -1),
                        z: 0
                    )
                    lastTick = CACurrentMediaTime()
                    let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
                    link.add(to: .main, forMode: .common)
                    displayLink = link
                }
            } else {
                displayLink?.invalidate()
                displayLink = nil
                snap(pivot, to: value ?? Int.random(in: 1...6))
            }
        }

        private func snap(_ pivot: SCNNode, to value: Int) {
            let e = DiceOrientation.eulerForFace(value)
            pivot.eulerAngles = SCNVector3(
                Float(e.x).degreesToRadians,
                Float(e.y).degreesToRadians,
                Float(e.z).degreesToRadians
            )
        }

        @objc private func tick(_ link: CADisplayLink) {
            guard let pivot else { return }
            let now = link.timestamp
            let dt = min(now - lastTick, 0.05)
            lastTick = now
            pivot.eulerAngles.x += velocity.x * Float(dt)
            pivot.eulerAngles.y += velocity.y * Float(dt)
        }
    }
}

private extension Float {
    var degreesToRadians: Float { self * .pi / 180 }
}

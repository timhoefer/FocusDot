import AppKit
import SceneKit
import Combine

final class SceneBallView: NSView {
    private let scnView: SCNView
    private let scene: SCNScene
    private let sphereNode: SCNNode
    private let cameraNode: SCNNode

    private let preferences: PreferencesManager
    private let animator: BounceAnimator
    private let interaction: InteractionManager
    private var cancellables = Set<AnyCancellable>()
    private var sphereRadius: CGFloat

    // Base geometry for CPU deformation during drag
    private var baseVertices: [SCNVector3] = []
    private var baseNormals: [SCNVector3] = []
    private var geometryElements: [SCNGeometryElement] = []
    private var baseSphere: SCNSphere!
    private var isDragging = false

    init(frame: NSRect, preferences: PreferencesManager, animator: BounceAnimator, interaction: InteractionManager) {
        self.preferences = preferences
        self.animator = animator
        self.interaction = interaction
        self.sphereRadius = preferences.dotSize / 2

        scene = SCNScene()
        scene.background.contents = NSColor.clear

        let camera = SCNCamera()
        camera.usesOrthographicProjection = true
        // orthographicScale = half visible height in scene units
        // View is 200pt. For sphere to appear as dotSize pt:
        // dotSize/200 = (2*sphereRadius) / (2*orthoScale)
        // orthoScale = sphereRadius * 200 / dotSize = sphereRadius * 200 / (2*sphereRadius) = 100
        camera.orthographicScale = 100
        cameraNode = SCNNode()
        cameraNode.camera = camera
        cameraNode.position = SCNVector3(0, 0, 50)
        scene.rootNode.addChildNode(cameraNode)

        // Sphere
        baseSphere = SCNSphere(radius: 1)
        baseSphere.segmentCount = 48

        let material = SCNMaterial()
        material.lightingModel = .physicallyBased
        material.diffuse.contents = NSColor(preferences.dotColor.color)
        material.roughness.contents = NSColor(white: 0.85, alpha: 1)
        material.metalness.contents = NSColor(white: 0.0, alpha: 1)
        material.blendMode = .alpha
        material.shaderModifiers = [
            .fragment: """
            float fresnel = 1.0 - abs(dot(normalize(_surface.normal), normalize(_surface.view)));
            float edgeFade = pow(fresnel, 3.0) * 0.25;
            _output.color.a *= (1.0 - edgeFade);
            """
        ]
        baseSphere.materials = [material]

        // Extract base vertices for CPU deformation during drag
        if let src = baseSphere.sources(for: .vertex).first {
            baseVertices = SceneBallView.extractVectors(from: src)
        }
        if let src = baseSphere.sources(for: .normal).first {
            baseNormals = SceneBallView.extractVectors(from: src)
        }
        geometryElements = baseSphere.elements

        sphereNode = SCNNode(geometry: baseSphere)
        sphereNode.scale = SCNVector3(sphereRadius, sphereRadius, sphereRadius)
        scene.rootNode.addChildNode(sphereNode)

        // Lights
        let dirLight = SCNLight()
        dirLight.type = .directional
        dirLight.intensity = 800
        dirLight.color = NSColor.white
        let dirNode = SCNNode()
        dirNode.light = dirLight
        dirNode.eulerAngles = SCNVector3(-CGFloat.pi / 4, -CGFloat.pi / 4, 0)
        scene.rootNode.addChildNode(dirNode)

        let ambLight = SCNLight()
        ambLight.type = .ambient
        ambLight.intensity = 400
        ambLight.color = NSColor(white: 0.9, alpha: 1)
        let ambNode = SCNNode()
        ambNode.light = ambLight
        scene.rootNode.addChildNode(ambNode)

        // SCNView
        scnView = SCNView(frame: NSRect(origin: .zero, size: frame.size))
        scnView.wantsLayer = true
        scnView.scene = scene
        scnView.backgroundColor = .clear
        scnView.allowsCameraControl = false
        scnView.autoenablesDefaultLighting = false
        scnView.isPlaying = true
        scnView.preferredFramesPerSecond = 60
        scnView.antialiasingMode = .multisampling4X
        scnView.layer?.isOpaque = false
        scnView.layer?.backgroundColor = CGColor.clear

        super.init(frame: frame)
        wantsLayer = true
        layer?.isOpaque = false
        layer?.backgroundColor = CGColor.clear
        addSubview(scnView)

        DispatchQueue.main.async { [weak self] in
            self?.setupObservers()
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        scnView.frame = bounds
    }

    private func setupObservers() {
        preferences.$dotColor
            .sink { [weak self] color in
                self?.sphereNode.geometry?.firstMaterial?.diffuse.contents = NSColor(color.color)
            }
            .store(in: &cancellables)

        preferences.$dotSize
            .sink { [weak self] size in
                guard let self else { return }
                self.sphereRadius = size / 2
                self.sphereNode.scale = SCNVector3(sphereRadius, sphereRadius, sphereRadius)
            }
            .store(in: &cancellables)

        preferences.$dotOpacity
            .sink { [weak self] opacity in
                self?.sphereNode.opacity = CGFloat(opacity)
            }
            .store(in: &cancellables)

        Publishers.CombineLatest3(
            animator.$pull,
            interaction.$deformation,
            animator.$offset
        )
        .sink { [weak self] animPull, deformation, offset in
            guard let self else { return }

            // Physics in BounceAnimator is the single source of truth for stretch.
            let pull = animPull
            let rawMag = sqrt(pull.width * pull.width + pull.height * pull.height)
            let pullMag = rawMag / self.sphereRadius
            let nowDragging = deformation.isGrabbed && pullMag > 0.4

            if nowDragging {
                self.applyNeckDeformation(pull: pull, pullMag: pullMag)
            } else {
                self.applyEllipsoidalDeformation(pull: pull, pullMag: pullMag)
            }

            // Position offset: 1 scene unit = 1 screen point (orthoScale=100, viewHalf=100)
            let scenePerPt: CGFloat = 100.0 / 100.0
            self.sphereNode.position = SCNVector3(offset.width * scenePerPt, -offset.height * scenePerPt, 0)
        }
        .store(in: &cancellables)
    }

    // MARK: - Ellipsoidal deformation (GPU via node transform — smooth for idle animations)

    private func applyEllipsoidalDeformation(pull: CGSize, pullMag: CGFloat) {
        // Restore SCNSphere if we were doing neck deformation
        if isDragging {
            isDragging = false
            let materials = sphereNode.geometry?.materials ?? []
            baseSphere.materials = materials
            sphereNode.geometry = baseSphere
        }

        guard pullMag > 0.01 else {
            // No deformation — uniform scale
            sphereNode.scale = SCNVector3(sphereRadius, sphereRadius, sphereRadius)
            sphereNode.rotation = SCNVector4(0, 0, 1, 0)
            return
        }

        let pullAngle = atan2(-pull.height, pull.width)
        let stretch = min(pullMag, 0.7)

        // Elongate along pull axis, contract perpendicular (volume conserving)
        let elongation: CGFloat = 1.0 + stretch * 0.5
        let contraction: CGFloat = 1.0 / sqrt(elongation)

        let sx = elongation * sphereRadius
        let sy = contraction * sphereRadius
        let sz = contraction * sphereRadius

        // Apply as: rotate to pull axis → scale → rotate back
        // SCNNode: set scale in local space, rotate node to align X with pull direction
        sphereNode.scale = SCNVector3(sx, sy, sz)
        sphereNode.rotation = SCNVector4(0, 0, 1, pullAngle)
    }

    // MARK: - Neck deformation (CPU geometry — only during active drag)

    private func applyNeckDeformation(pull: CGSize, pullMag: CGFloat) {
        isDragging = true

        let stretch = pullMag
        let r: CGFloat = 1.0

        let px = pull.width
        let py = -pull.height
        let pLen = sqrt(px * px + py * py)
        guard pLen > 0.001 else { return }
        let dirX = px / pLen
        let dirY = py / pLen

        let bodyR = r / (1.0 + stretch * 0.08)
        let neckLen = min(stretch * r * 0.4, r * 2.5)
        let tipScale = max(CGFloat(0.1), 0.35 - stretch * 0.04)

        var newVertices = [SCNVector3](repeating: SCNVector3Zero, count: baseVertices.count)

        for i in 0..<baseVertices.count {
            let vx = baseVertices[i].x
            let vy = baseVertices[i].y
            let vz = baseVertices[i].z
            let axial = vx * dirX + vy * dirY
            let alignment = axial / r
            let epx = vx - axial * dirX
            let epy = vy - axial * dirY

            if alignment > 0 {
                let t = alignment
                let ext = neckLen * t * t
                let thinning: CGFloat = 1.0 - t * (1.0 - tipScale)
                let sp = bodyR * thinning
                let na = axial + ext
                newVertices[i] = SCNVector3(epx * sp + na * dirX, epy * sp + na * dirY, vz * sp)
            } else {
                newVertices[i] = SCNVector3(vx * bodyR, vy * bodyR, vz * bodyR)
            }
        }

        var newNormals = [SCNVector3](repeating: SCNVector3Zero, count: newVertices.count)
        for i in 0..<newVertices.count {
            let v = newVertices[i]
            let len = sqrt(v.x * v.x + v.y * v.y + v.z * v.z)
            if len > 0.001 {
                newNormals[i] = SCNVector3(v.x / len, v.y / len, v.z / len)
            }
        }

        let vertexSource = SCNGeometrySource(vertices: newVertices)
        let normalSource = SCNGeometrySource(normals: newNormals)
        let materials = sphereNode.geometry?.materials ?? []
        let geo = SCNGeometry(sources: [vertexSource, normalSource], elements: geometryElements)
        geo.materials = materials

        // Reset transform — deformation is in the geometry itself
        sphereNode.scale = SCNVector3(sphereRadius, sphereRadius, sphereRadius)
        sphereNode.rotation = SCNVector4(0, 0, 1, 0)
        sphereNode.geometry = geo
    }

    // MARK: - Helpers

    private static func extractVectors(from source: SCNGeometrySource) -> [SCNVector3] {
        let count = source.vectorCount
        let stride = source.dataStride
        let offset = source.dataOffset
        let bpc = source.bytesPerComponent
        let data = source.data

        var vectors = [SCNVector3]()
        vectors.reserveCapacity(count)

        data.withUnsafeBytes { raw in
            let bytes = raw.baseAddress!
            for i in 0..<count {
                let ptr = bytes.advanced(by: i * stride + offset)
                if bpc == 4 {
                    let x = CGFloat(ptr.load(fromByteOffset: 0, as: Float.self))
                    let y = CGFloat(ptr.load(fromByteOffset: 4, as: Float.self))
                    let z = CGFloat(ptr.load(fromByteOffset: 8, as: Float.self))
                    vectors.append(SCNVector3(x, y, z))
                } else {
                    let x = CGFloat(ptr.load(fromByteOffset: 0, as: Double.self))
                    let y = CGFloat(ptr.load(fromByteOffset: 8, as: Double.self))
                    let z = CGFloat(ptr.load(fromByteOffset: 16, as: Double.self))
                    vectors.append(SCNVector3(x, y, z))
                }
            }
        }

        return vectors
    }
}

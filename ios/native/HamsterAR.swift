import ARKit
import AVFoundation
import OSLog
import RealityKit
import UIKit
import simd

private let bridge = HamsterARBridge()
private let arLog = Logger(subsystem: "com.yinzon.hamstercage", category: "AR")

@_cdecl("hamster_ar_supported")
func hamsterARSupported() -> Int32 {
    ARWorldTrackingConfiguration.isSupported ? 1 : 0
}

@_cdecl("hamster_ar_open")
func hamsterAROpen(_ mask: Int32) -> Int32 {
    guard mask != 0, ARWorldTrackingConfiguration.isSupported else { return 0 }
    DispatchQueue.main.async { bridge.open(mask) }
    return 1
}

@_cdecl("hamster_ar_take_event")
func hamsterARTakeEvent() -> Int32 {
    bridge.takeEvent()
}

@_cdecl("hamster_ar_close")
func hamsterARClose() {
    DispatchQueue.main.async { bridge.close() }
}

private final class HamsterARBridge {
    private let lock = NSLock()
    private var event: Int32 = 0
    private var generation = 0
    private var controller: TableController?

    func takeEvent() -> Int32 {
        lock.lock()
        defer { lock.unlock() }
        let result = event
        event = 0
        return result
    }

    private func publish(_ result: Int32) {
        lock.lock()
        event = result
        lock.unlock()
    }

    @MainActor func open(_ mask: Int32) {
        generation += 1
        let ticket = generation
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            present(mask)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { allowed in
                DispatchQueue.main.async {
                    guard self.generation == ticket else { return }
                    if allowed { self.present(mask) } else { self.publish(2) }
                }
            }
        default:
            publish(2)
        }
    }

    @MainActor private func present(_ mask: Int32) {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive || $0.activationState == .foregroundInactive }
        let window = scene?.keyWindow
        guard let host = window?.rootViewController,
              host.presentedViewController == nil else {
            publish(2)
            return
        }
        let models: [(index: Int, entity: Entity)]
        do {
            models = try (0..<2).filter { mask & (Int32(1) << $0) != 0 }.map {
                ($0, try TableHamster.load(index: $0))
            }
        } catch {
            arLog.error("仓鼠模型加载失败：\(error.localizedDescription, privacy: .public)")
            publish(3)
            return
        }
        let table = TableController(models: models)
        controller = table
        table.modalPresentationStyle = .fullScreen
        table.onClose = { [weak self] result in
            self?.controller = nil
            self?.publish(result)
        }
        host.present(table, animated: true)
    }

    func close() {
        generation += 1
        if let controller {
            controller.finish()
        } else {
            publish(1)
        }
    }
}

private final class TableController: UIViewController, ARSessionDelegate {
    var onClose: ((Int32) -> Void)?
    private let models: [(index: Int, entity: Entity)]
    private let camera = ARView(frame: .zero, cameraMode: .ar, automaticallyConfigureSession: false)
    private let hint = UILabel()
    private let reset = UIButton(type: .system)
    private let reticle = AnchorEntity(world: SIMD3<Float>.zero)
    private let ring = ModelEntity(
        mesh: .generatePlane(width: 0.12, depth: 0.12, cornerRadius: 0.055),
        materials: [UnlitMaterial(color: UIColor(red: 0.93, green: 0.85, blue: 0.65, alpha: 0.78))]
    )
    private var playground: AnchorEntity?
    private var pets: [TableHamster] = []
    private var displayLink: CADisplayLink?
    private var elapsed: Double = 0
    private var previousFrame: Double = 0
    private var finishing = false
    private var tracking = false

    init(models: [(index: Int, entity: Entity)]) {
        self.models = models
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { nil }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .landscape }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        camera.frame = view.bounds
        camera.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(camera)
        camera.session.delegate = self
        camera.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tap(_:))))

        let back = UIButton(type: .system)
        configure(back, "回到笼子")
        configure(reset, "重新摆放")
        back.addTarget(self, action: #selector(goBack), for: .touchUpInside)
        reset.addTarget(self, action: #selector(reposition), for: .touchUpInside)
        reset.isHidden = true

        hint.translatesAutoresizingMaskIntoConstraints = false
        hint.textColor = .white
        hint.font = .systemFont(ofSize: 18, weight: .semibold)
        hint.textAlignment = .center
        hint.numberOfLines = 2
        hint.text = "慢慢移动相机，寻找桌面"
        view.addSubview(hint)
        let safe = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            back.leadingAnchor.constraint(equalTo: safe.leadingAnchor, constant: 16),
            back.topAnchor.constraint(equalTo: safe.topAnchor, constant: 10),
            reset.trailingAnchor.constraint(equalTo: safe.trailingAnchor, constant: -16),
            reset.topAnchor.constraint(equalTo: back.topAnchor),
            hint.leadingAnchor.constraint(equalTo: safe.leadingAnchor, constant: 16),
            hint.trailingAnchor.constraint(equalTo: safe.trailingAnchor, constant: -16),
            hint.bottomAnchor.constraint(equalTo: safe.bottomAnchor, constant: -18)
        ])

        ring.position.y = 0.002
        reticle.addChild(ring)
        reticle.isEnabled = false
        camera.scene.addAnchor(reticle)
        NotificationCenter.default.addObserver(self, selector: #selector(interrupted),
            name: UIApplication.willResignActiveNotification, object: nil)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !finishing else { return }
        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal]
        camera.session.run(config, options: [.resetTracking, .removeExistingAnchors])
        let link = CADisplayLink(target: self, selector: #selector(animate(_:)))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    private func configure(_ button: UIButton, _ title: String) {
        var style = UIButton.Configuration.filled()
        style.title = title
        style.baseBackgroundColor = UIColor(red: 0.99, green: 0.91, blue: 0.76, alpha: 1)
        style.baseForegroundColor = UIColor(red: 0.31, green: 0.22, blue: 0.18, alpha: 1)
        style.cornerStyle = .capsule
        style.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 18, bottom: 12, trailing: 18)
        button.configuration = style
        button.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(button)
    }

    @objc private func goBack() { finish() }
    @objc private func interrupted() { finish() }

    func finish(_ result: Int32 = 1) {
        guard !finishing else { return }
        finishing = true
        displayLink?.invalidate()
        displayLink = nil
        camera.session.pause()
        NotificationCenter.default.removeObserver(self)
        dismiss(animated: false) { self.onClose?(result) }
    }

    func session(_ session: ARSession, didFailWithError error: Error) {
        DispatchQueue.main.async { self.finish(2) }
    }

    func sessionWasInterrupted(_ session: ARSession) {
        DispatchQueue.main.async { self.finish() }
    }

    func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
        let ready: Bool
        if case .normal = camera.trackingState { ready = true } else { ready = false }
        DispatchQueue.main.async { self.tracking = ready }
    }

    @objc private func reposition() {
        playground?.removeFromParent()
        playground = nil
        pets.removeAll()
        reset.isHidden = true
    }

    private func surface(_ point: CGPoint) -> ARRaycastResult? {
        guard tracking else { return nil }
        return camera.raycast(from: point, allowing: .existingPlaneGeometry, alignment: .horizontal).first
    }

    @objc private func tap(_ gesture: UITapGestureRecognizer) {
        let point = gesture.location(in: camera)
        if playground != nil {
            var hit = camera.entity(at: point)
            while let entity = hit {
                if let pet = pets.first(where: { $0.root === entity }) {
                    pet.greet(until: elapsed + 1.4)
                    return
                }
                hit = entity.parent
            }
            return
        }
        guard let placement = surface(point) else { return }
        let anchor = AnchorEntity(world: placement.worldTransform)
        let placedPets = models.compactMap { TableHamster(index: $0.index, template: $0.entity) }
        guard placedPets.count == models.count else {
            finish(3)
            return
        }
        for pet in placedPets { anchor.addChild(pet.root) }
        pets = placedPets
        camera.scene.addAnchor(anchor)
        playground = anchor
        reticle.isEnabled = false
        reset.isHidden = false
    }

    @objc private func animate(_ link: CADisplayLink) {
        let delta = previousFrame > 0 ? min(0.1, link.timestamp - previousFrame) : 0
        previousFrame = link.timestamp
        elapsed += delta
        if playground != nil {
            hint.text = tracking ? "点点小仓鼠，和它打个招呼" : "相机在找回桌面，请慢慢移动"
            if tracking { pets.forEach { $0.animate(elapsed, Float(delta)) } }
            return
        }
        let center = CGPoint(x: camera.bounds.midX, y: camera.bounds.midY)
        if let result = surface(center) {
            reticle.transform = Transform(matrix: result.worldTransform)
            reticle.isEnabled = true
            hint.text = "点桌面，让仓鼠出来玩"
        } else {
            reticle.isEnabled = false
            hint.text = "慢慢移动相机，寻找桌面"
        }
    }
}

@MainActor
private final class TableHamster {
    let root = Entity()
    private let head: Entity
    private let index: Int
    private let feet: [Entity]
    private let headRest: Transform
    private let footRest: [SIMD3<Float>]
    private var greeting = 0.0

    private enum ModelError: Error {
        case missingAsset, missingParts
    }

    static func load(index: Int) throws -> Entity {
        let name = index == 0 ? "HamsterGray" : "HamsterWhite"
        guard let url = Bundle.main.url(forResource: name, withExtension: "usdz") else {
            throw ModelError.missingAsset
        }
        let model = try Entity.load(contentsOf: url)
        guard model.findEntity(named: "Body") != nil, model.findEntity(named: "Head") != nil,
              (0..<4).allSatisfy({ model.findEntity(named: "Foot\($0)") != nil }) else {
            throw ModelError.missingParts
        }
        return model
    }

    init?(index: Int, template: Entity) {
        let model = template.clone(recursive: true)
        let feet = (0..<4).compactMap { model.findEntity(named: "Foot\($0)") }
        guard let head = model.findEntity(named: "Head"), feet.count == 4 else { return nil }
        self.index = index
        self.head = head
        self.feet = feet
        headRest = head.transform
        footRest = feet.map(\.position)
        root.position.x = index == 0 ? -0.09 : 0.09
        root.addChild(model)
        // 用整只仓鼠的包围盒响应点按，省去毛束和胡须的逐面碰撞。
        let bounds = model.visualBounds(relativeTo: root)
        let hitbox = ShapeResource.generateBox(size: bounds.extents)
            .offsetBy(translation: bounds.center)
        root.components.set(CollisionComponent(shapes: [hitbox]))
    }

    func greet(until: Double) { greeting = until }

    func animate(_ elapsed: Double, _ delta: Float) {
        let t = Float(elapsed) + Float(index) * 2.4
        let responding = elapsed < greeting
        let walking = !responding && sin(t * 0.9) > -0.45
        if walking {
            let offset: Float = index == 0 ? -0.10 : 0.10
            let goal = SIMD3<Float>(offset + sin(t * 0.82) * 0.078, 0, cos(t * 0.71) * 0.088)
            let movement = goal - root.position
            if simd_length_squared(movement) > 0.000001 {
                root.orientation = simd_quatf(angle: atan2(movement.x, movement.z), axis: [0, 1, 0])
                root.position += movement * min(1, delta * 3)
            }
        }
        // 导出资源的根节点已按米缩放，头和脚仍在原始模型坐标中。
        head.position.y = headRest.translation.y + (responding ? 0.050 : sin(t * 5) * 0.012)
        head.orientation = headRest.rotation * simd_quatf(angle: responding ? -0.30 : sin(t * 5) * 0.02, axis: [1, 0, 0])
        for (offset, foot) in feet.enumerated() {
            let step = walking ? max(0, sin(t * 18 + ([1, 2].contains(offset) ? .pi : 0))) * 0.024 : 0
            foot.position.y = footRest[offset].y + step
        }
    }
}

import ARKit
import AVFoundation
import RealityKit
import UIKit
import simd

private let bridge = HamsterARBridge()

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

    func open(_ mask: Int32) {
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

    private func present(_ mask: Int32) {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive || $0.activationState == .foregroundInactive }
        let window = scene?.windows.first(where: \.isKeyWindow)
            ?? UIApplication.shared.windows.first(where: \.isKeyWindow)
        guard let host = window?.rootViewController,
              host.presentedViewController == nil else {
            publish(2)
            return
        }
        let table = TableController(mask: mask)
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
    private let mask: Int32
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

    init(mask: Int32) {
        self.mask = mask
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
        for index in 0..<2 where mask & (Int32(1) << index) != 0 {
            let pet = TableHamster(index)
            anchor.addChild(pet.root)
            pets.append(pet)
        }
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
    private let head = Entity()
    private let index: Int
    private var greeting = 0.0
    private var feet: [ModelEntity] = []
    private let pink = UIColor(red: 0.86, green: 0.60, blue: 0.59, alpha: 1)

    init(_ index: Int) {
        self.index = index
        let fur = index == 0
            ? UIColor(red: 0.62, green: 0.56, blue: 0.58, alpha: 1)
            : UIColor(red: 1, green: 0.94, blue: 0.88, alpha: 1)
        let cream = UIColor(red: 1, green: 0.93, blue: 0.83, alpha: 1)
        root.position.x = index == 0 ? -0.09 : 0.09
        root.addChild(sphere(fur, [0, 0.037, -0.012], [0.038, 0.034, 0.044]))
        root.addChild(sphere(cream, [0, 0.029, 0.012], [0.032, 0.023, 0.034]))
        root.addChild(sphere(fur, [0, 0.021, -0.056], [0.012, 0.009, 0.01]))
        head.position = [0, 0.05, 0.024]
        root.addChild(head)
        head.addChild(sphere(fur, [0, 0, 0], [0.033, 0.028, 0.030]))
        for side: Float in [-1, 1] {
            head.addChild(sphere(fur, [side * 0.023, 0.023, 0], [0.012, 0.014, 0.007]))
            head.addChild(sphere(pink, [side * 0.023, 0.023, 0.006], [0.008, 0.009, 0.003]))
            head.addChild(sphere(.black, [side * 0.016, 0.005, 0.025], [0.004, 0.005, 0.004]))
            head.addChild(sphere(.white, [side * 0.016 - 0.001, 0.006, 0.028], [0.0015, 0.0015, 0.0015]))
            head.addChild(sphere(cream, [side * 0.010, -0.012, 0.025], [0.015, 0.010, 0.011]))
            for z: Float in [-0.034, 0.025] {
                let foot = sphere(pink, [side * 0.022, 0.006, z], [0.01, 0.006, 0.014])
                root.addChild(foot)
                feet.append(foot)
            }
        }
        head.addChild(sphere(pink, [0, -0.007, 0.036], [0.006, 0.004, 0.003]))
        root.generateCollisionShapes(recursive: true)
    }

    private func sphere(_ color: UIColor, _ position: SIMD3<Float>, _ radii: SIMD3<Float>) -> ModelEntity {
        let entity = ModelEntity(mesh: .generateSphere(radius: 1),
            materials: [SimpleMaterial(color: color, isMetallic: false)])
        entity.position = position
        entity.scale = radii
        return entity
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
        head.position.y = responding ? 0.059 : 0.050 + sin(t * (walking ? 12 : 5)) * 0.002
        head.orientation = simd_quatf(angle: responding ? -0.31 : sin(t * 5) * 0.09, axis: [1, 0, 0])
        for (offset, foot) in feet.enumerated() {
            foot.position.y = 0.006 + (walking ? max(0, sin(t * 18 + Float(offset) * .pi)) * 0.005 : 0)
        }
    }
}

//
//  GameView.swift
//  DinoRun Watch App
//
//  Created by Mike Price on 21.09.2024.
//

import SwiftUI
import Combine
import SpriteKit

/// Физические маски
struct PhysicsTypes {
    static let none: UInt32 = 1 << 0
    static let dinosaur: UInt32 = 1 << 1
    static let ground: UInt32 = 1 << 2
    static let cactus: UInt32 = 1 << 3
}

/// Имя нод
struct NodeName {
    static let ground: String = "ground"
    static let dino: String = "dino"
    static let cactus: String = "cactus"
}

/// Спрайты окружения
struct StaticSprite {
    static let ground = "ground"
    static let cactus = "cactus"
}

/// Спрайты динозавра
struct DinoSprite {
    static let idle = "dino-stationary"
    static let run1 = "dino-run-0"
    static let run2 = "dino-run-1"
    static let die = "dino-lose"
}

/// Состояния игры
enum GameState {
    case idle
    case running
    case gameOver
}

struct GameView: View {
    let duration: TimeInterval = 20
    let cactusSpawnDuration: TimeInterval = 4
    let size: CGSize = WKInterfaceDevice.current().screenBounds.size
    let scene: GameScene
    
    @AppStorage("bestScore") var bestScore: Int = 0
    @State var score: Int = 0 {
        didSet {
            if score > bestScore {
                bestScore = score
            }
            
            scene[NodeName.ground].forEach { $0.speed = 1 + scoreRate }
            scene[NodeName.cactus].forEach { $0.speed = 1 + scoreRate }
        }
    }
    
    @State var timer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()
    
    @State var dino: SKSpriteNode?
    @State var isJumping: Bool = false
    @State var state: GameState = .idle {
        willSet {
            if case .running = newValue, case .gameOver = state {
                reload()
            }
        }
        didSet {
            switch state {
            case .idle:
                scene.isPaused = true
                
            case .running:
                scene.isPaused = false
                dino?.run(.repeatForever(.sequence([
                    .setTexture(SKTexture(imageNamed: DinoSprite.run1)),
                    .wait(forDuration: 0.1),
                    .setTexture(SKTexture(imageNamed: DinoSprite.run2)),
                    .wait(forDuration: 0.1)
                ])))
                feedback(.start)
                
            case .gameOver:
                scene.isPaused = true
                dino?.removeAllActions()
                dino?.texture = SKTexture(imageNamed: DinoSprite.die)
                feedback(.failure)
            }
        }
    }
    
    var scoreRate: Double { Double(score) / 1000 }
    
    init() {
        scene = GameScene(size: size)
        scene.scaleMode = .fill
        scene.backgroundColor = UIColor(red: 231/255, green: 232/255, blue: 231/255, alpha: 1)
        scene.physicsWorld.gravity = .init(dx: 0, dy: -4.9)
        scene.physicsWorld.contactDelegate = scene
    }
    
    var body: some View {
        SpriteView(scene: scene)
            .overlay(alignment: .topLeading) {
                VStack {
                    Text(String(format: "%08d", score))
                        .foregroundStyle(Color.white)
                    
                    Text(String(format: "%08d", bestScore))
                        .foregroundStyle(Color.yellow)
                }
                .font(.system(size: 16, design: .monospaced))
                .padding(16)
            }
            .overlay {
                switch state {
                case .idle, .gameOver:
                    Image(systemName: "hand.point.up.left.fill")
                        .foregroundStyle(Color.white)
                        .font(.system(size: 100))
                        .shadow(radius: 1)
                    
                case .running:
                    EmptyView()
                }
            }
            .ignoresSafeArea(.all)
            .task {
                reload()
                
                Task {
                    try? await Task.sleep(for: .seconds(0.1))
                    state = .idle
                }
            }
            .onReceive(scene.dinoDidContact) { name in
                switch name {
                case NodeName.ground: isJumping = false
                case NodeName.cactus: state = .gameOver
                default: break
                }
            }
            .onReceive(timer) { _ in
                guard case .running = state else { return }
                score += 1
            }
            .onTapGesture {
                switch state {
                case .idle: state = .running
                case .running: jump()
                case .gameOver: state = .running
                }
            }
    }
    
    func reload() {
        score = 0
        
        scene.removeAllChildren()
        scene.removeAllActions()
        
        spawnGround()
        spawnDinosaur()
        
        /// спавн кактусов
        scene.run(.repeatForever(.sequence([
            .run {
                if Bool.random(0.8) {
                    if Bool.random(scoreRate) {
                        spawnCactus()
                    } else {
                        spawnCactus()
                        spawnCactus(xOffset: 30)
                        if Bool.random(scoreRate / 10) {
                            spawnCactus(xOffset: 60)
                        }
                    }
                }
            },
            .wait(forDuration: cactusSpawnDuration)
        ])))
    }
    
    func spawnGround() {
        let texture = SKTexture(imageNamed: StaticSprite.ground)
        let ground = SKSpriteNode(texture: texture)
        ground.name = NodeName.ground
        ground.size = texture.size()
        ground.position = .init(x: ground.size.width / 2, y: 20)
        ground.physicsBody = .init(rectangleOf: ground.size.applying(.init(scaleX: 1, y: 0.3)))
        ground.physicsBody?.categoryBitMask = PhysicsTypes.ground
        ground.physicsBody?.contactTestBitMask = PhysicsTypes.dinosaur
        ground.physicsBody?.collisionBitMask = PhysicsTypes.dinosaur
        ground.physicsBody?.isDynamic = false
        ground.physicsBody?.affectedByGravity = false
        ground.physicsBody?.allowsRotation = false
        ground.physicsBody?.friction = 1
        ground.run(.repeatForever(.sequence([
            .move(to: ground.position, duration: 0),
            .moveTo(x: -ground.size.width / 2 + size.width, duration: duration)
        ])))
        scene.addChild(ground)
    }
    
    func spawnDinosaur() {
        let texture = SKTexture(imageNamed: DinoSprite.idle)
        let dinosaur = SKSpriteNode(texture: texture)
        dinosaur.name = NodeName.dino
        dinosaur.size = texture.size().applying(.init(scaleX: 0.5, y: 0.5))
        dinosaur.position = .init(x: 50, y: 50)
        dinosaur.physicsBody = .init(
            rectangleOf: dinosaur.size.applying(.init(scaleX: 0.5, y: 1)),
            center: CGPoint(x: 0, y: 0)
        )
        dinosaur.physicsBody?.categoryBitMask = PhysicsTypes.dinosaur
        dinosaur.physicsBody?.contactTestBitMask = PhysicsTypes.ground | PhysicsTypes.cactus
        dinosaur.physicsBody?.collisionBitMask = PhysicsTypes.ground | PhysicsTypes.cactus
        dinosaur.physicsBody?.isDynamic = true
        dinosaur.physicsBody?.mass = 1
        dinosaur.physicsBody?.density = 10
        scene.addChild(dinosaur)
        dino = dinosaur
    }
    
    func spawnCactus(xOffset: CGFloat = 0) {
        let texture = SKTexture(imageNamed: StaticSprite.cactus)
        let cactus = SKSpriteNode(texture: texture)
        cactus.name = NodeName.cactus
        cactus.size = texture.size().applying(.init(scaleX: 0.5, y: 0.5))
        cactus.position = .init(x: size.width + xOffset, y: 35)
        cactus.physicsBody = .init(rectangleOf: cactus.size)
        cactus.physicsBody?.categoryBitMask = PhysicsTypes.cactus
        cactus.physicsBody?.contactTestBitMask = PhysicsTypes.dinosaur
        cactus.physicsBody?.collisionBitMask = PhysicsTypes.dinosaur
        cactus.physicsBody?.isDynamic = false
        cactus.physicsBody?.affectedByGravity = false
        cactus.physicsBody?.allowsRotation = false
        cactus.physicsBody?.friction = 1
        cactus.run(.sequence([
            .moveTo(x: -size.width + xOffset, duration: duration * 0.19),
            .removeFromParent()
        ]))
        scene.addChild(cactus)
    }
    
    func jump() {
        guard !isJumping else { return }
        isJumping = true
        dino?.physicsBody?.applyImpulse(CGVector(dx: 0, dy: 200))
        feedback(.click)
    }
    
    func feedback(_ type: WKHapticType) {
        WKInterfaceDevice.current().play(type)
    }
}

// MARK: - Game scene

final class GameScene: SKScene, SKPhysicsContactDelegate {
    private var _dinoDidContact = PassthroughSubject<String, Never>()
    var dinoDidContact: AnyPublisher<String, Never> { _dinoDidContact.eraseToAnyPublisher() }
    
    func didBegin(_ contact: SKPhysicsContact) {
        guard
            let nodeA = contact.bodyA.node,
            let nodeB = contact.bodyB.node
        else { return }
        
        let dino = nodeA.name == NodeName.dino ? nodeA : nodeB
        let other = dino == nodeA ? nodeB : nodeA
        
        guard let name = other.name else { return }
        
        _dinoDidContact.send(name)
    }
}

// MARK: - Extensions

extension Bool {
    /// Вернуть булево с определенной вероятностью
    /// - Parameter probability: Вероятность, где 0 - всегда `false`, а 1 - всегда `true`
    /// - Returns: Булевый результат
    static func random(_ probability: Double) -> Bool {
        Double.random(in: 0...1) < probability
    }
}

// MARK: - Preview

#Preview {
    GameView()
}

//
//  GameScene.swift
//  motion_capture_test
//
//  Created by 飛鳥馬空 on 2026/04/24.
//

import SpriteKit
import GameplayKit

class GameScene: SKScene {

    private var handIndicator: SKShapeNode!
    private var scoreLabel: SKLabelNode!
    private var statusLabel: SKLabelNode!
    private var score = 0

    private var glassPanels: [SKShapeNode] = []
    private var spawnAccumulator: TimeInterval = 0
    private var lastUpdateTime: TimeInterval = 0
    private let maxGlass = 6

    override func didMove(to view: SKView) {
        backgroundColor = SKColor(white: 0.08, alpha: 1.0)

        // The .sks template ships with a "Hello, World!" label — remove it.
        childNode(withName: "//helloLabel")?.removeFromParent()

        setupHUD()
        setupHandIndicator()
        spawnInitialGlass(count: 3)
    }

    private func setupHUD() {
        let score = SKLabelNode(fontNamed: "Helvetica-Bold")
        score.fontSize = 36
        score.fontColor = .white
        score.horizontalAlignmentMode = .left
        score.verticalAlignmentMode = .top
        score.position = CGPoint(x: -size.width / 2 + 24, y: size.height / 2 - 24)
        score.text = "SCORE: 0"
        score.zPosition = 1000
        addChild(score)
        self.scoreLabel = score

        let status = SKLabelNode(fontNamed: "Helvetica")
        status.fontSize = 18
        status.fontColor = SKColor(white: 1.0, alpha: 0.6)
        status.horizontalAlignmentMode = .right
        status.verticalAlignmentMode = .top
        status.position = CGPoint(x: size.width / 2 - 24, y: size.height / 2 - 24)
        status.text = "Waiting for camera…"
        status.zPosition = 1000
        addChild(status)
        self.statusLabel = status
    }

    private func setupHandIndicator() {
        let outer = SKShapeNode(circleOfRadius: 28)
        outer.strokeColor = .cyan
        outer.fillColor = SKColor.cyan.withAlphaComponent(0.15)
        outer.lineWidth = 3
        outer.zPosition = 900
        outer.isHidden = true

        let inner = SKShapeNode(circleOfRadius: 4)
        inner.fillColor = .cyan
        inner.strokeColor = .clear
        outer.addChild(inner)

        addChild(outer)
        self.handIndicator = outer
    }

    // MARK: - Glass lifecycle

    private func spawnInitialGlass(count: Int) {
        for _ in 0..<count { spawnGlass() }
    }

    private func spawnGlass() {
        guard glassPanels.count < maxGlass else { return }

        let w = CGFloat.random(in: 120...220)
        let h = CGFloat.random(in: 140...240)
        let panel = SKShapeNode(rectOf: CGSize(width: w, height: h), cornerRadius: 6)
        panel.strokeColor = SKColor(calibratedRed: 0.75, green: 0.92, blue: 1.0, alpha: 0.9)
        panel.fillColor = SKColor(calibratedRed: 0.55, green: 0.85, blue: 1.0, alpha: 0.25)
        panel.lineWidth = 2
        panel.zPosition = 10
        panel.name = "glass"
        panel.userData = NSMutableDictionary(dictionary: ["hp": 3, "w": w, "h": h])

        // Shine highlight for a glassy feel.
        let shine = SKShapeNode(rectOf: CGSize(width: w * 0.25, height: h * 0.8), cornerRadius: 4)
        shine.fillColor = SKColor(white: 1.0, alpha: 0.15)
        shine.strokeColor = .clear
        shine.position = CGPoint(x: -w * 0.25, y: 0)
        shine.zPosition = 1
        panel.addChild(shine)

        panel.position = randomPanelPosition(size: CGSize(width: w, height: h))
        panel.setScale(0.01)
        panel.run(.scale(to: 1, duration: 0.25))
        addChild(panel)
        glassPanels.append(panel)
    }

    private func randomPanelPosition(size panelSize: CGSize) -> CGPoint {
        let halfW = size.width / 2 - panelSize.width / 2 - 20
        let halfH = size.height / 2 - panelSize.height / 2 - 120
        return CGPoint(x: CGFloat.random(in: -halfW...halfW),
                       y: CGFloat.random(in: -halfH...halfH))
    }

    // MARK: - Punch handling

    private func handlePunch(at scenePoint: CGPoint) {
        guard let panel = topmostGlass(at: scenePoint) else { return }

        guard let data = panel.userData,
              let hp = data["hp"] as? Int else { return }

        let newHP = hp - 1
        if newHP <= 0 {
            shatter(panel: panel, at: scenePoint)
            glassPanels.removeAll { $0 == panel }
            score += 1
            scoreLabel.text = "SCORE: \(score)"
        } else {
            data["hp"] = newHP
            addCracks(to: panel, at: scenePoint, intensity: 3 - newHP)
            panel.run(.sequence([
                .scale(to: 1.05, duration: 0.05),
                .scale(to: 1.0, duration: 0.08)
            ]))
        }
    }

    private func topmostGlass(at scenePoint: CGPoint) -> SKShapeNode? {
        // Iterate in reverse so panels on top are preferred.
        for panel in glassPanels.reversed() {
            guard let data = panel.userData,
                  let w = data["w"] as? CGFloat,
                  let h = data["h"] as? CGFloat else { continue }
            let dx = scenePoint.x - panel.position.x
            let dy = scenePoint.y - panel.position.y
            if abs(dx) <= w / 2 && abs(dy) <= h / 2 {
                return panel
            }
        }
        return nil
    }

    private func addCracks(to panel: SKShapeNode, at scenePoint: CGPoint, intensity: Int) {
        let local = CGPoint(x: scenePoint.x - panel.position.x,
                            y: scenePoint.y - panel.position.y)
        let lineCount = 3 + intensity * 2
        for _ in 0..<lineCount {
            let path = CGMutablePath()
            path.move(to: local)
            let angle = CGFloat.random(in: 0..<(2 * .pi))
            let length = CGFloat.random(in: 20...70)
            let end = CGPoint(x: local.x + cos(angle) * length,
                              y: local.y + sin(angle) * length)
            path.addLine(to: end)
            let crack = SKShapeNode(path: path)
            crack.strokeColor = SKColor(white: 1.0, alpha: 0.85)
            crack.lineWidth = CGFloat.random(in: 1...2.2)
            crack.zPosition = 2
            panel.addChild(crack)
        }
    }

    private func shatter(panel: SKShapeNode, at scenePoint: CGPoint) {
        guard let data = panel.userData,
              let w = data["w"] as? CGFloat,
              let h = data["h"] as? CGFloat else {
            panel.removeFromParent()
            return
        }

        let shardCount = 24
        for _ in 0..<shardCount {
            let size = CGFloat.random(in: 6...18)
            let shard = SKShapeNode(rectOf: CGSize(width: size, height: size * CGFloat.random(in: 0.6...1.4)))
            shard.fillColor = SKColor(calibratedRed: 0.75, green: 0.92, blue: 1.0, alpha: 0.9)
            shard.strokeColor = SKColor(white: 1.0, alpha: 0.9)
            shard.lineWidth = 1
            shard.zPosition = panel.zPosition + 1
            shard.position = CGPoint(x: panel.position.x + CGFloat.random(in: -w/2...w/2),
                                     y: panel.position.y + CGFloat.random(in: -h/2...h/2))
            addChild(shard)

            let angle = CGFloat.random(in: 0..<(2 * .pi))
            let distance = CGFloat.random(in: 120...320)
            let dx = cos(angle) * distance
            let dy = sin(angle) * distance - 80
            let duration = TimeInterval.random(in: 0.5...0.9)
            let fly = SKAction.moveBy(x: dx, y: dy, duration: duration)
            fly.timingMode = .easeOut
            let spin = SKAction.rotate(byAngle: CGFloat.random(in: -6...6), duration: duration)
            let fade = SKAction.fadeOut(withDuration: duration)
            shard.run(.sequence([.group([fly, spin, fade]), .removeFromParent()]))
        }

        // Flash at impact point.
        let flash = SKShapeNode(circleOfRadius: 60)
        flash.fillColor = SKColor(white: 1.0, alpha: 0.6)
        flash.strokeColor = .clear
        flash.position = scenePoint
        flash.zPosition = 950
        flash.setScale(0.2)
        addChild(flash)
        flash.run(.sequence([
            .group([.scale(to: 1.4, duration: 0.25), .fadeOut(withDuration: 0.25)]),
            .removeFromParent()
        ]))

        panel.removeFromParent()
    }

    // MARK: - Update loop

    override func update(_ currentTime: TimeInterval) {
        let dt = lastUpdateTime == 0 ? 0 : currentTime - lastUpdateTime
        lastUpdateTime = currentTime

        spawnAccumulator += dt
        if spawnAccumulator > 1.2 {
            spawnAccumulator = 0
            spawnGlass()
        }
    }
}

// MARK: - HandTrackerDelegate

extension GameScene: HandTrackerDelegate {

    func handTrackerDidUpdate(position: CGPoint?, speed: CGFloat, didPunch: Bool) {
        guard let normalized = position else {
            handIndicator.isHidden = true
            return
        }

        statusLabel.text = String(format: "Tracking  speed %.1f", Double(speed))
        handIndicator.isHidden = false

        let anchor = anchorPoint
        let scenePoint = CGPoint(
            x: (normalized.x - anchor.x) * size.width,
            y: (normalized.y - anchor.y) * size.height
        )
        handIndicator.position = scenePoint

        // Tint the indicator red on punch for visual feedback.
        if didPunch {
            handIndicator.strokeColor = .red
            handIndicator.run(.sequence([
                .scale(to: 1.6, duration: 0.05),
                .scale(to: 1.0, duration: 0.15)
            ]))
            handlePunch(at: scenePoint)
            handIndicator.run(.wait(forDuration: 0.25)) { [weak self] in
                self?.handIndicator.strokeColor = .cyan
            }
        }
    }

    func handTrackerDidFail(reason: String) {
        statusLabel.text = reason
        statusLabel.fontColor = .red
    }
}

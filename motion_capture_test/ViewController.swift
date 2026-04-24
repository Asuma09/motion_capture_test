//
//  ViewController.swift
//  motion_capture_test
//
//  Created by 飛鳥馬空 on 2026/04/24.
//

import Cocoa
import SpriteKit
import GameplayKit

class ViewController: NSViewController {

    @IBOutlet var skView: SKView!

    private let handTracker = HandTracker()

    override func viewDidLoad() {
        super.viewDidLoad()

        guard let view = skView, let scene = SKScene(fileNamed: "GameScene") as? GameScene else {
            return
        }

        scene.scaleMode = .aspectFill
        handTracker.delegate = scene
        view.presentScene(scene)

        view.ignoresSiblingOrder = true
        view.showsFPS = true
        view.showsNodeCount = true

        handTracker.start()
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
        handTracker.stop()
    }
}

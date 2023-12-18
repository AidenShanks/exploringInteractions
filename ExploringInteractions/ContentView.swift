//
//  ContentView.swift
//  ExploringInteractions
//
//  Created by Aiden Shanks on 12/9/23.
//

import SwiftUI
import RealityKit
import Speech
import CoreMotion

struct ContentView : View {
    @StateObject var speechRecognizer = SpeechRecognizer()
    @StateObject var viewModel = ARViewModel()

    var body: some View {
        ZStack {
            ARViewContainer(speechRecognizer: speechRecognizer, viewModel: viewModel)
                .edgesIgnoringSafeArea(.all)
            
            VStack {
                // Toggle button for speech recognition
                Button(action: {
                    if speechRecognizer.isListening {
                        speechRecognizer.stopSpeechRecognition()
                    } else {
                        speechRecognizer.startSpeechRecognition { command in
                            viewModel.handleSpeechCommand(command)
                        }
                    }
                }) {
                    Image(systemName: speechRecognizer.isListening ? "mic.slash.fill" : "mic.fill")
                        .font(.title)
                        .padding()
                        .background(speechRecognizer.isListening ? Color.red.opacity(0.7) : Color.green.opacity(0.7))
                        .clipShape(Circle())
                }
                
                Spacer()
                
                Spacer()
                HStack {
                    Button(action: {
                        viewModel.changeCubeSize(increase: false)
                    }) {
                        Image(systemName: "minus")
                            .font(.title)
                            .padding()
                            .background(Color.white.opacity(0.7))
                            .clipShape(Circle())
                    }
                    Button(action: {
                        viewModel.changeCubeSize(increase: true)
                    }) {
                        Image(systemName: "plus")
                            .font(.title)
                            .padding()
                            .background(Color.white.opacity(0.7))
                            .clipShape(Circle())
                    }
                }
                .padding()
            }
        }
    }
}

class ARViewModel: ObservableObject {
    var model: ModelEntity?
    
    private let motionManager = CMMotionManager()

    func changeCubeSize(increase: Bool) {
        let scaleChange: Float = increase ? 0.1 : -0.1
        if let model = model {
            model.scale += SIMD3<Float>(scaleChange, scaleChange, scaleChange)
        }
    }
    
    func handleSpeechCommand(_ command: String) {
        switch command {
        case "increase":
            changeCubeSize(increase: true)
        case "decrease":
            changeCubeSize(increase: false)
        default:
            break
        }
    }
    
    func startMotionUpdates(model: ModelEntity) {
        print("Starting motion updates") // Debugging print statement
        let rotationRateThreshold: Double = 0.5 // rotation rate threshold to consider as a movement
        
        if motionManager.isGyroAvailable {
            motionManager.gyroUpdateInterval = 0.1
            motionManager.startGyroUpdates(to: .main) { (data, error) in
                if let error = error {
                    print("Error starting gyroscope updates: \(error)")
                }
                
                guard let rotationRate = data?.rotationRate else {
                    print("No rotation rate data received")
                    return
                }
                
                print("Rotation rate data: \(rotationRate)") // Debugging print statement
                
                DispatchQueue.main.async {
                    if rotationRate.y > rotationRateThreshold {
                        // Increase cube size
                        let newScale = min(model.scale + SIMD3<Float>(0.1, 0.1, 0.1), SIMD3<Float>(1.0, 1.0, 1.0))
                        model.scale = newScale
                        print("Rotated right, new scale: \(newScale)") // Debugging print statement
                    } else if rotationRate.y < -rotationRateThreshold {
                        // Decrease cube size
                        let newScale = max(model.scale - SIMD3<Float>(0.1, 0.1, 0.1), SIMD3<Float>(0.1, 0.1, 0.1))
                        model.scale = newScale
                        print("Rotated left, new scale: \(newScale)") // Debugging print statement
                    } else {
                        print("Rotation rate below threshold")
                    }
                }
            }
        } else {
            print("Gyroscope not available")
        }
    }
}

struct ARViewContainer: UIViewRepresentable {
    @ObservedObject var speechRecognizer: SpeechRecognizer
    @ObservedObject var viewModel: ARViewModel
    // Motion manager for tracking user movement
    private let motionManager = CMMotionManager()
    
    func makeUIView(context: Context) -> ARView {
        
        let arView = ARView(frame: .zero)

        // Create a cube model
        let mesh = MeshResource.generateBox(size: 0.1, cornerRadius: 0.005)
        let material = SimpleMaterial(color: .gray, roughness: 0.15, isMetallic: true)
        let model = ModelEntity(mesh: mesh, materials: [material])
        
        model.generateCollisionShapes(recursive: true)
        
        arView.installGestures(for: model)

        // Create horizontal plane anchor for the content
        let anchor = AnchorEntity(.plane(.horizontal, classification: .any, minimumBounds: SIMD2<Float>(0.2, 0.2)))
        anchor.children.append(model)

        // Add the horizontal plane anchor to the scene
        arView.scene.anchors.append(anchor)
        
        viewModel.model = model
        
        // Start speech recognition
        speechRecognizer.startSpeechRecognition { command in
            DispatchQueue.main.async {
                switch command {
                case "increase":
                    // Increase the size of the model
                    model.scale.x += 0.5
                    model.scale.y += 0.5
                    model.scale.z += 0.5
                case "decrease":
                    // Decrease the size of the model
                    model.scale.x -= 0.5
                    model.scale.y -= 0.5
                    model.scale.z -= 0.5
                default: break
                }
            }
        }
        
        viewModel.startMotionUpdates(model: model)
        
        return arView
        
    }
    
    func updateUIView(_ uiView: ARView, context: Context) {}
    
    
}

class SpeechRecognizer: NSObject, ObservableObject {
    private let speechRecognizer = SFSpeechRecognizer()
    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    override init() {
        super.init()
        self.requestAuthorization()
    }
    
    @Published var isListening = false

    func startSpeechRecognition(completion: @escaping (String) -> Void) {
        do {
            try startListening(completion: completion)
        } catch {
            print("There was a problem starting speech recognition: \(error.localizedDescription)")
        }
        self.isListening = true
    }

    private func startListening(completion: @escaping (String) -> Void) throws {
        // Cancel the previous task if it's running
        if let recognitionTask = recognitionTask {
            recognitionTask.cancel()
            self.recognitionTask = nil
        }

        // Setup audio engine and speech recognizer
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        let inputNode = audioEngine.inputNode
        
        // Remove existing tap if any
        inputNode.removeTap(onBus: 0)

        // Create and configure the speech recognition request
        let recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        self.recognitionRequest = recognitionRequest
        recognitionRequest.shouldReportPartialResults = true

        // Start recognition
        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { result, error in
            if let result = result {
                let recognizedText = result.bestTranscription.formattedString.lowercased()
                if recognizedText.contains("increase") || recognizedText.contains("decrease") {
                    completion(recognizedText)
                    print("VOICE RECOGNIZED")
                    self.resetRecognitionTask(completion: completion)
                }
            } else if let error = error {
                print("Error in recognition task: \(error)")
            }
        }

        // Configure the audio session for the app
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            recognitionRequest.append(buffer)
        }

        // Start audio engine
        audioEngine.prepare()
        try audioEngine.start()
    }
    
    func stopSpeechRecognition() {
        if audioEngine.isRunning {
            audioEngine.stop()
            recognitionRequest?.endAudio()
            recognitionTask?.cancel()
        }
        self.isListening = false
    }
    
    private func resetRecognitionTask(completion: @escaping (String) -> Void) {
        recognitionTask?.cancel()
        recognitionTask = nil

        do {
            try startListening(completion: completion)
        } catch {
            print("Error restarting speech recognition: \(error)")
        }
    }

    private func requestAuthorization() {
        SFSpeechRecognizer.requestAuthorization { authStatus in
            // Handle authorization status
            switch authStatus {
            case .authorized:
                print("Speech recognition authorized")
            case .denied, .restricted, .notDetermined:
                print("Speech recognition not authorized")
            @unknown default:
                print("Unknown authorization status")
            }
        }
    }

    deinit {
        // Stop the audio engine and end the recognition request
        audioEngine.stop()
        recognitionRequest?.endAudio()
    }
}


#Preview {
    ContentView()
}

import UIKit
import AVFoundation
import Photos
import CoreLocation

protocol VideoRecordingDelegate: AnyObject {
    func videoRecordingDidFinish(with url: URL, place: Place?)
    func videoRecordingDidCancel()
}

class VideoRecordingViewController: UIViewController {
    
    // MARK: - Properties
    weak var delegate: VideoRecordingDelegate?
    private var captureSession: AVCaptureSession?
    private var videoOutput: AVCaptureMovieFileOutput?
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var currentCameraPosition: AVCaptureDevice.Position = .back
    private var isRecording = false
    private var recordingTimer: Timer?
    private var recordingSeconds = 0
    private let maxRecordingSeconds = 15
    private var selectedPlace: Place?
    private var selectedPlaceName: String?
    private var selectedPlaceId: String?
    private var outputURL: URL?
    
    // MARK: - UI Elements
    private let previewView: UIView = {
        let view = UIView()
        view.backgroundColor = .black
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private let closeButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "xmark"), for: .normal)
        button.tintColor = .white
        button.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        button.layer.cornerRadius = 20
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    private let flipCameraButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "camera.rotate"), for: .normal)
        button.tintColor = .white
        button.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        button.layer.cornerRadius = 20
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    private let flashButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "bolt.slash"), for: .normal)
        button.tintColor = .white
        button.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        button.layer.cornerRadius = 20
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    private let recordButton: UIButton = {
        let button = UIButton(type: .custom)
        button.backgroundColor = .systemRed
        button.layer.cornerRadius = 35
        button.layer.borderWidth = 4
        button.layer.borderColor = UIColor.white.cgColor
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    private let timerLabel: UILabel = {
        let label = UILabel()
        label.text = "0:00"
        label.font = .monospacedDigitSystemFont(ofSize: 18, weight: .medium)
        label.textColor = .white
        label.textAlignment = .center
        label.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        label.layer.cornerRadius = 8
        label.clipsToBounds = true
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let progressView: UIProgressView = {
        let progress = UIProgressView(progressViewStyle: .default)
        progress.progressTintColor = .systemRed
        progress.trackTintColor = UIColor.white.withAlphaComponent(0.3)
        progress.translatesAutoresizingMaskIntoConstraints = false
        return progress
    }()
    
    // Place selection removed - now happens after video capture
    private let placeSelectionButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("📍 Place will be added next", for: .normal)
        button.isHidden = true  // Hidden since selection happens after
        button.titleLabel?.font = .systemFont(ofSize: 16, weight: .medium)
        button.setTitleColor(.white, for: .normal)
        button.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        button.layer.cornerRadius = 20
        button.contentEdgeInsets = UIEdgeInsets(top: 10, left: 16, bottom: 10, right: 16)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    private let uploadButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Upload from Library", for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 14, weight: .medium)
        button.setTitleColor(.white, for: .normal)
        button.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        button.layer.cornerRadius = 16
        button.contentEdgeInsets = UIEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    private let instructionLabel: UILabel = {
        let label = UILabel()
        label.text = "Hold to record up to 15 seconds"
        label.font = .systemFont(ofSize: 14)
        label.textColor = .white
        label.textAlignment = .center
        label.alpha = 0.8
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        checkCameraPermissions()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        startCaptureSession()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopCaptureSession()
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    override var prefersStatusBarHidden: Bool {
        return true
    }
    
    // MARK: - Setup
    private func setupUI() {
        view.backgroundColor = .black
        
        // Add subviews
        view.addSubview(previewView)
        view.addSubview(progressView)
        view.addSubview(closeButton)
        view.addSubview(flipCameraButton)
        view.addSubview(flashButton)
        view.addSubview(timerLabel)
        view.addSubview(placeSelectionButton)
        view.addSubview(recordButton)
        view.addSubview(instructionLabel)
        view.addSubview(uploadButton)
        
        // Setup constraints
        NSLayoutConstraint.activate([
            previewView.topAnchor.constraint(equalTo: view.topAnchor),
            previewView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            previewView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            previewView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            
            progressView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            progressView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            progressView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            progressView.heightAnchor.constraint(equalToConstant: 4),
            
            closeButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            closeButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            closeButton.widthAnchor.constraint(equalToConstant: 40),
            closeButton.heightAnchor.constraint(equalToConstant: 40),
            
            timerLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            timerLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            timerLabel.widthAnchor.constraint(equalToConstant: 80),
            timerLabel.heightAnchor.constraint(equalToConstant: 32),
            
            flipCameraButton.topAnchor.constraint(equalTo: closeButton.topAnchor),
            flipCameraButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            flipCameraButton.widthAnchor.constraint(equalToConstant: 40),
            flipCameraButton.heightAnchor.constraint(equalToConstant: 40),
            
            flashButton.topAnchor.constraint(equalTo: flipCameraButton.bottomAnchor, constant: 16),
            flashButton.trailingAnchor.constraint(equalTo: flipCameraButton.trailingAnchor),
            flashButton.widthAnchor.constraint(equalToConstant: 40),
            flashButton.heightAnchor.constraint(equalToConstant: 40),
            
            placeSelectionButton.bottomAnchor.constraint(equalTo: recordButton.topAnchor, constant: -24),
            placeSelectionButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            placeSelectionButton.heightAnchor.constraint(equalToConstant: 40),
            
            recordButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -40),
            recordButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            recordButton.widthAnchor.constraint(equalToConstant: 70),
            recordButton.heightAnchor.constraint(equalToConstant: 70),
            
            instructionLabel.topAnchor.constraint(equalTo: recordButton.bottomAnchor, constant: 16),
            instructionLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            
            uploadButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            uploadButton.centerYAnchor.constraint(equalTo: recordButton.centerYAnchor),
            uploadButton.heightAnchor.constraint(equalToConstant: 32)
        ])
        
        // Add button actions
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        flipCameraButton.addTarget(self, action: #selector(flipCameraTapped), for: .touchUpInside)
        flashButton.addTarget(self, action: #selector(flashTapped), for: .touchUpInside)
        // Place selection removed - happens after video capture
        // placeSelectionButton.addTarget(self, action: #selector(selectPlaceTapped), for: .touchUpInside)
        uploadButton.addTarget(self, action: #selector(uploadFromLibraryTapped), for: .touchUpInside)
        
        // Setup record button gestures
        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(recordButtonPressed(_:)))
        longPress.minimumPressDuration = 0.0
        recordButton.addGestureRecognizer(longPress)
    }
    
    // MARK: - Camera Setup
    private func checkCameraPermissions() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            setupCamera()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                if granted {
                    DispatchQueue.main.async {
                        self?.setupCamera()
                    }
                } else {
                    DispatchQueue.main.async {
                        self?.showPermissionDenied()
                    }
                }
            }
        case .denied, .restricted:
            showPermissionDenied()
        @unknown default:
            break
        }
        
        // Also request microphone permission
        AVCaptureDevice.requestAccess(for: .audio) { _ in }
    }
    
    private func setupCamera() {
        captureSession = AVCaptureSession()
        // Use HD preset for consistent quality
        captureSession?.sessionPreset = .hd1920x1080
        
        // Setup video input
        guard let videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: currentCameraPosition),
              let videoInput = try? AVCaptureDeviceInput(device: videoDevice),
              let captureSession = captureSession,
              captureSession.canAddInput(videoInput) else { return }
        
        captureSession.addInput(videoInput)
        
        // Setup audio input
        if let audioDevice = AVCaptureDevice.default(for: .audio),
           let audioInput = try? AVCaptureDeviceInput(device: audioDevice),
           captureSession.canAddInput(audioInput) {
            captureSession.addInput(audioInput)
        }
        
        // Setup video output
        videoOutput = AVCaptureMovieFileOutput()
        videoOutput?.maxRecordedDuration = CMTime(seconds: Double(maxRecordingSeconds), preferredTimescale: 1)
        
        if let videoOutput = videoOutput, captureSession.canAddOutput(videoOutput) {
            captureSession.addOutput(videoOutput)
            
            // Configure the connection for proper orientation
            if let connection = videoOutput.connection(with: .video) {
                // Enable video stabilization for better quality
                if connection.isVideoStabilizationSupported {
                    connection.preferredVideoStabilizationMode = .auto
                }
                
                // Set initial orientation
                updateVideoOrientation()
            }
        }
        
        // Setup preview layer
        previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        previewLayer?.videoGravity = .resizeAspectFill
        previewLayer?.frame = previewView.bounds
        
        if let previewLayer = previewLayer {
            previewView.layer.addSublayer(previewLayer)
        }
        
        // Observe device orientation changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(deviceOrientationDidChange),
            name: UIDevice.orientationDidChangeNotification,
            object: nil
        )
    }
    
    private func startCaptureSession() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.captureSession?.startRunning()
        }
    }
    
    private func stopCaptureSession() {
        captureSession?.stopRunning()
    }
    
    // MARK: - Recording
    @objc private func recordButtonPressed(_ gesture: UILongPressGestureRecognizer) {
        switch gesture.state {
        case .began:
            startRecording()
        case .ended, .cancelled, .failed:
            stopRecording()
        default:
            break
        }
    }
    
    private func startRecording() {
        guard !isRecording else { return }
        
        // Check quota before recording
        checkQuotaAndRecord()
    }
    
    private func checkQuotaAndRecord() {
        // For now, proceed with recording - quota check happens on upload
        // This could be enhanced to check quota before recording
        proceedWithRecording()
    }
    
    private func proceedWithRecording() {
        // Create output URL
        let fileName = "reel_\(Date().timeIntervalSince1970).mp4"
        let tempDir = NSTemporaryDirectory()
        outputURL = URL(fileURLWithPath: tempDir).appendingPathComponent(fileName)
        
        guard let outputURL = outputURL else { return }
        
        // Update video orientation before recording
        updateVideoOrientation()
        
        // Start recording
        videoOutput?.startRecording(to: outputURL, recordingDelegate: self)
        
        isRecording = true
        recordingSeconds = 0
        
        // Update UI
        UIView.animate(withDuration: 0.2) {
            self.recordButton.transform = CGAffineTransform(scaleX: 0.8, y: 0.8)
            self.recordButton.backgroundColor = .white
        }
        
        instructionLabel.text = "Recording..."
        
        // Start timer
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateRecordingTimer()
        }
        
        // Haptic feedback
        let impact = UIImpactFeedbackGenerator(style: .medium)
        impact.impactOccurred()
    }
    
    private func stopRecording() {
        guard isRecording else { return }
        
        videoOutput?.stopRecording()
        isRecording = false
        
        // Stop timer
        recordingTimer?.invalidate()
        recordingTimer = nil
        
        // Update UI
        UIView.animate(withDuration: 0.2) {
            self.recordButton.transform = .identity
            self.recordButton.backgroundColor = .systemRed
        }
        
        instructionLabel.text = "Hold to record up to 15 seconds"
    }
    
    private func updateRecordingTimer() {
        recordingSeconds += 1
        
        let minutes = recordingSeconds / 60
        let seconds = recordingSeconds % 60
        timerLabel.text = String(format: "%d:%02d", minutes, seconds)
        
        let progress = Float(recordingSeconds) / Float(maxRecordingSeconds)
        progressView.setProgress(progress, animated: true)
        
        if recordingSeconds >= maxRecordingSeconds {
            stopRecording()
        }
    }
    
    // MARK: - Actions
    @objc private func closeTapped() {
        delegate?.videoRecordingDidCancel()
        dismiss(animated: true)
    }
    
    @objc private func deviceOrientationDidChange() {
        updateVideoOrientation()
    }
    
    private func updateVideoOrientation() {
        guard let connection = videoOutput?.connection(with: .video) else { return }
        
        // Get the current device orientation
        let deviceOrientation = UIDevice.current.orientation
        
        // Convert device orientation to video orientation
        let videoOrientation: AVCaptureVideoOrientation
        
        switch deviceOrientation {
        case .portrait:
            videoOrientation = .portrait
        case .portraitUpsideDown:
            videoOrientation = .portraitUpsideDown
        case .landscapeLeft:
            videoOrientation = .landscapeRight // Note: these are reversed
        case .landscapeRight:
            videoOrientation = .landscapeLeft  // Note: these are reversed
        default:
            videoOrientation = .portrait // Default to portrait
        }
        
        // Set the orientation if supported
        if connection.isVideoOrientationSupported {
            connection.videoOrientation = videoOrientation
        }
        
        // Also update preview layer orientation
        previewLayer?.connection?.videoOrientation = videoOrientation
    }
    
    @objc private func flipCameraTapped() {
        currentCameraPosition = currentCameraPosition == .back ? .front : .back
        
        // Recreate capture session with new camera
        captureSession?.stopRunning()
        captureSession?.inputs.forEach { captureSession?.removeInput($0) }
        setupCamera()
        startCaptureSession()
    }
    
    @objc private func flashTapped() {
        guard let device = AVCaptureDevice.default(for: .video) else { return }
        
        if device.hasTorch {
            do {
                try device.lockForConfiguration()
                
                if device.torchMode == .on {
                    device.torchMode = .off
                    flashButton.setImage(UIImage(systemName: "bolt.slash"), for: .normal)
                } else {
                    device.torchMode = .on
                    flashButton.setImage(UIImage(systemName: "bolt.fill"), for: .normal)
                }
                
                device.unlockForConfiguration()
            } catch {
                print("Flash error: \(error)")
            }
        }
    }
    
    @objc private func selectPlaceTapped() {
        let placeSearchVC = PlaceSearchViewController()
        placeSearchVC.delegate = self
        let navController = UINavigationController(rootViewController: placeSearchVC)
        present(navController, animated: true)
    }
    
    @objc private func uploadFromLibraryTapped() {
        let picker = UIImagePickerController()
        picker.delegate = self
        picker.sourceType = .photoLibrary
        picker.mediaTypes = ["public.movie"]
        picker.videoMaximumDuration = 15
        picker.videoQuality = .typeHigh
        present(picker, animated: true)
    }
    
    private func showPermissionDenied() {
        let alert = UIAlertController(
            title: "Camera Access Required",
            message: "Please enable camera access in Settings to record videos.",
            preferredStyle: .alert
        )
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { [weak self] _ in
            self?.delegate?.videoRecordingDidCancel()
            self?.dismiss(animated: true)
        })
        
        alert.addAction(UIAlertAction(title: "Settings", style: .default) { _ in
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        })
        
        present(alert, animated: true)
    }
    
    private func showAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = previewView.bounds
    }
}

// MARK: - AVCaptureFileOutputRecordingDelegate
extension VideoRecordingViewController: AVCaptureFileOutputRecordingDelegate {
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        if let error = error {
            print("Recording error: \(error)")
            showAlert(title: "Recording Failed", message: error.localizedDescription)
        } else {
            // Recording successful
            // Pass nil for place - selection happens after video processing
            delegate?.videoRecordingDidFinish(with: outputFileURL, place: nil)
            dismiss(animated: true)
        }
    }
}

// MARK: - UIImagePickerControllerDelegate
extension VideoRecordingViewController: UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
        picker.dismiss(animated: true)
        
        guard let videoURL = info[.mediaURL] as? URL else { return }
        
        // Pass nil for place - selection happens after video processing
        delegate?.videoRecordingDidFinish(with: videoURL, place: nil)
        dismiss(animated: true)
    }
    
    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true)
    }
}

// MARK: - PlaceSearchDelegate
extension VideoRecordingViewController: PlaceSearchDelegate {
    func didSelectExistingPlace(_ place: Place) {
        // Use the existing place
        selectedPlaceName = place.name
        selectedPlaceId = place.id
        selectedPlace = place
        
        // Update the button to show the selected place
        placeSelectionButton.setTitle("📍 \(place.name)", for: .normal)
    }
    
    func didSelectPlace(name: String, address: String, coordinate: CLLocationCoordinate2D, phone: String?, website: String?, category: String?, description: String?) {
        // For video recording, we just need to track the place name and generate an ID
        // The full place object will be created on the backend when uploading
        selectedPlaceName = name
        selectedPlaceId = UUID().uuidString
        
        // Update the button to show the selected place
        placeSelectionButton.setTitle("📍 \(name)", for: .normal)
        
        // Create a minimal Place object for video upload
        // Most fields will be filled by the backend
        let location = GeoLocation(
            type: "Point",
            coordinates: [coordinate.longitude, coordinate.latitude]
        )
        
        let placeCategory: PlaceCategory
        if let category = category {
            switch category.lowercased() {
            case "restaurant": placeCategory = .restaurant
            case "cafe": placeCategory = .cafe
            case "bar": placeCategory = .bar
            case "hotel": placeCategory = .hotel
            case "retail": placeCategory = .retail
            case "service": placeCategory = .service
            case "attraction": placeCategory = .attraction
            default: placeCategory = .other
            }
        } else {
            placeCategory = .other
        }
        
        selectedPlace = Place(
            id: selectedPlaceId!,
            name: name,
            description: description,
            address: address,
            location: location,
            website: website,
            phone: phone,
            googlePlaceId: nil,
            photos: nil,
            videos: nil,
            category: placeCategory,
            customCategoryId: nil,
            subcategory: nil,
            rating: nil,
            userRatingsTotal: nil,
            notes: nil,
            privateNotes: nil,
            publicNotes: nil,
            tags: nil,
            reviews: nil,
            openingHours: nil,
            priceLevel: nil,
            likes: nil,
            likesCount: nil,
            commentsCount: nil,
            circleId: "", // Will be set by backend
            addedBy: AuthService.shared.getUserId() ?? "",
            addedByUser: nil,
            privacy: .public,
            createdAt: Date(),
            updatedAt: Date(),
            isNew: nil
        )
    }
}
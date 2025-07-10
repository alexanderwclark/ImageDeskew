//
//  TestCoreMLModel.swift
//  ImageDeskew
//
//  Created by Alexander W Clark on 7/2/25.
//

import UIKit
import CoreML
import Vision

func testCoreMLModel() {
    print("Successfully initialized coreMLModel \n")
    // 1. Load your Core ML model (replace with your model class name)
    guard let model = try? VNCoreMLModel(for: DeepLabV3().model) else {
        print("Failed to load model!")
        return
    }
    
    // 2. Load a sample image (replace with your image name or pick one from the bundle)
    guard let uiImage = UIImage(named: "test_photo.jpeg") else {
        print("Failed to load test image!")
        return
    }
    guard let cgImage = uiImage.cgImage else {
        print("Failed to convert UIImage to CGImage!")
        return
    }
    
    // 3. Set up Vision request
    let request = VNCoreMLRequest(model: model) { request, error in
        if let results = request.results as? [VNClassificationObservation] {
            print("Top results:")
            for result in results.prefix(5) {
                print("- \(result.identifier): \(result.confidence)")
            }
        } else if let features = request.results as? [VNCoreMLFeatureValueObservation],
                  let array = features.first?.featureValue.multiArrayValue {
            print("Feature vector:")
            print(array)
        } else {
            print("No recognizable results!")
        }
    }
    
    // 4. Run the request
    let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
    do {
        try handler.perform([request])
    } catch {
        print("Failed to perform Core ML request: \(error)")
    }
}

// Call this function somewhere in your app (e.g., viewDidLoad, button action, etc.)
//testCoreMLModel()

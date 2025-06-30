# ImageDeskew
Image correction app

## Building with Swift Package Manager

> **Note**: This project relies on SwiftUI, PhotosUI, Vision and other Apple
> frameworks. Building and running therefore requires **macOS** with Xcode.
> Attempting a Linux build will fail because these frameworks are unavailable.

1. Clone the repository and open the project directory:
   ```bash
   git clone <repo-url>
   cd ImageDeskew
   ```
2. Build the app using SwiftPM:
   ```bash
   swift build
   ```
3. Run unit tests:
   ```bash
   swift test
   ```
4. To run the app from the command line use:
   ```bash
   swift run ImageDeskew
   ```
   or open `Package.swift` in Xcode for an IDE workflow.

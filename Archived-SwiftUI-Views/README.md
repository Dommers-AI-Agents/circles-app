# Archived SwiftUI Views

This folder contains the SwiftUI implementation of the Circles app that was archived on 6/21/2025.

These views are not currently being used by the app, which now uses UIKit ViewControllers exclusively.

## Why Archived?

- The app currently uses UIKit implementation (Controllers)
- Maintaining both UIKit and SwiftUI versions was creating confusion and extra work
- These files are preserved here for potential future use or reference

## Contents

- **Authentication/**: Login, Registration views
- **Circles/**: Circle management views
- **Discover/**: Discovery view
- **Network/**: Network and connections views
- **Places/**: Place management views
- **Profile/**: User profile views
- **Other UI Components**: Various SwiftUI components and helpers

## To Restore

If you want to switch back to SwiftUI in the future:
1. Move these files back to the Views folder
2. Update SceneDelegate.swift to use SwiftUI views instead of UIKit ViewControllers
3. Remove or archive the UIKit Controllers
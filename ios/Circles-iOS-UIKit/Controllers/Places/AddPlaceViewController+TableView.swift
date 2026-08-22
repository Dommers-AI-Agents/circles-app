import UIKit
import MapKit
import CoreLocation
import PhotosUI

// Table view data source/delegate and category picker for AddPlaceViewController. Extracted from the main controller (Wave 4).

// MARK: - UITableViewDataSource & Delegate

extension AddPlaceViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if tableView == circleDropdownTableView {
            return userCircles.count
        } else if tableView == categoryDropdownTableView {
            return categoryDropdownItems.count
        } else {
            // Add 1 for place type suggestion if applicable
            return showPlaceTypeSuggestion ? searchResults.count + 1 : searchResults.count
        }
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if tableView == circleDropdownTableView {
            let cell = tableView.dequeueReusableCell(withIdentifier: "CircleCell") ?? UITableViewCell(style: .default, reuseIdentifier: "CircleCell")
            
            // Set cell background for dark mode support
            cell.backgroundColor = .secondarySystemBackground
            
            let circle = userCircles[indexPath.row]
            cell.textLabel?.text = circle.name
            cell.textLabel?.font = UIFont.systemFont(ofSize: 16)
            cell.textLabel?.textColor = .label
            
            // Add checkmark for selected circle
            if circle.id == selectedCircleId {
                cell.accessoryType = .checkmark
            } else {
                cell.accessoryType = .none
            }
            
            return cell
            
        } else if tableView == categoryDropdownTableView {
            let cell = tableView.dequeueReusableCell(withIdentifier: "CategoryCell") ?? UITableViewCell(style: .default, reuseIdentifier: "CategoryCell")
            
            // Set cell background for dark mode support
            cell.backgroundColor = .secondarySystemBackground
            let item = categoryDropdownItems[indexPath.row]
            
            // Format display text
            if item.category == .other && item.subcategory == "More..." {
                // Special formatting for "More..." option
                cell.textLabel?.text = "More..."
                cell.textLabel?.font = UIFont.systemFont(ofSize: 16, weight: .medium)
                cell.textLabel?.textColor = .systemBlue
            } else if let subcategory = item.subcategory {
                cell.textLabel?.text = "    \(subcategory)"  // Indent subcategories
                cell.textLabel?.font = UIFont.systemFont(ofSize: 15)
                cell.textLabel?.textColor = .secondaryLabel  // Better for dark mode
            } else {
                cell.textLabel?.text = item.category.displayName
                cell.textLabel?.font = UIFont.systemFont(ofSize: 16, weight: .medium)
                cell.textLabel?.textColor = .label  // Adapts to dark/light mode
            }
            
            // Add checkmark for selected item
            let isSelected = (item.subcategory == nil && item.category == selectedCategory && selectedSubcategory == nil) ||
                           (item.subcategory != nil && item.category == selectedCategory && item.subcategory == selectedSubcategory)
            
            if isSelected {
                cell.accessoryType = .checkmark
                cell.tintColor = .systemBlue
            } else {
                cell.accessoryType = .none
            }
            
            // Add icon only for main categories
            if item.category == .other && item.subcategory == "More..." {
                // Special icon for "More..." option
                let config = UIImage.SymbolConfiguration(pointSize: 20, weight: .medium)
                cell.imageView?.image = UIImage(systemName: "ellipsis.circle", withConfiguration: config)
                cell.imageView?.tintColor = .systemBlue
            } else if item.subcategory == nil {
                let config = UIImage.SymbolConfiguration(pointSize: 20, weight: .medium)
                cell.imageView?.image = UIImage(systemName: item.category.systemIconName, withConfiguration: config)
                cell.imageView?.tintColor = .systemBlue
            } else {
                cell.imageView?.image = nil
            }
            
            return cell
        } else {
            var cell = tableView.dequeueReusableCell(withIdentifier: "SearchCell")
            if cell == nil {
                cell = UITableViewCell(style: .subtitle, reuseIdentifier: "SearchCell")
            }
            
            // Handle place type suggestion row
            if showPlaceTypeSuggestion && indexPath.row == 0 {
                // Configure as place type suggestion
                cell?.textLabel?.text = "\"\(placeTypeSuggestionQuery)\" nearby"
                cell?.textLabel?.font = UIFont.systemFont(ofSize: 16, weight: .medium)
                cell?.textLabel?.textColor = .systemBlue
                cell?.textLabel?.numberOfLines = 1
                
                cell?.detailTextLabel?.text = "Search for this type of place"
                cell?.detailTextLabel?.font = UIFont.systemFont(ofSize: 14)
                cell?.detailTextLabel?.textColor = .systemGray
                
                // Add search icon
                let config = UIImage.SymbolConfiguration(pointSize: 20, weight: .medium)
                cell?.imageView?.image = UIImage(systemName: "magnifyingglass.circle.fill", withConfiguration: config)
                cell?.imageView?.tintColor = .systemBlue
            } else {
                // Regular search result
                let resultIndex = showPlaceTypeSuggestion ? indexPath.row - 1 : indexPath.row
                let result = searchResults[resultIndex]
                
                // Configure cell for better display
                cell?.textLabel?.text = result.title
                cell?.textLabel?.font = UIFont.systemFont(ofSize: 16, weight: .medium)
                cell?.textLabel?.numberOfLines = 2
                cell?.textLabel?.textColor = .label
                
                // Show full address with city, state, country
                cell?.detailTextLabel?.text = result.subtitle
                cell?.detailTextLabel?.font = UIFont.systemFont(ofSize: 14)
                cell?.detailTextLabel?.textColor = .systemGray
                cell?.detailTextLabel?.numberOfLines = 2
                
                // Add location icon for regular results
                let config = UIImage.SymbolConfiguration(pointSize: 16, weight: .regular)
                cell?.imageView?.image = UIImage(systemName: "mappin.circle", withConfiguration: config)
                cell?.imageView?.tintColor = .systemGray
            }
            
            return cell!
        }
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        
        if tableView == circleDropdownTableView {
            let circle = userCircles[indexPath.row]
            selectedCircle = circle
            selectedCircleId = circle.id
            circleButton.setTitle(circle.name, for: .normal)
            
            // Hide dropdown
            isCircleDropdownVisible = false
            updateCircleDropdown()
            
        } else if tableView == categoryDropdownTableView {
            let item = categoryDropdownItems[indexPath.row]
            
            // Check if "More..." was selected
            if item.category == .other && item.subcategory == "More..." {
                // Hide dropdown first
                categoryButtonTapped()
                
                // Present the category picker
                let categoryPicker = CategoryPickerViewController(forPlaceCategory: true)
                categoryPicker.legacyDelegate = self
                let navController = UINavigationController(rootViewController: categoryPicker)
                present(navController, animated: true)
            } else {
                // Normal category selection
                if item.category == .other && item.subcategory == nil {
                    // User selected "Other" from dropdown - show category picker for custom input
                    categoryButtonTapped() // Hide dropdown first
                    
                    let categoryPicker = CategoryPickerViewController(forPlaceCategory: true)
                    categoryPicker.legacyDelegate = self
                    let navController = UINavigationController(rootViewController: categoryPicker)
                    present(navController, animated: true)
                } else {
                    // Regular category/subcategory selection
                    selectedCategory = item.category
                    selectedSubcategory = item.subcategory
                    
                    // Update button title
                    if let subcategory = item.subcategory {
                        categoryButton.setTitle("\(item.category.displayName) - \(subcategory)", for: .normal)
                    } else {
                        categoryButton.setTitle(item.category.displayName, for: .normal)
                    }
                    
                    // Hide dropdown
                    categoryButtonTapped()
                    
                    tableView.reloadData()
                }
            }
        } else {
            // Handle place type suggestion
            if showPlaceTypeSuggestion && indexPath.row == 0 {
                // Perform a search for this place type nearby
                performPlaceTypeSearch(placeTypeSuggestionQuery)
            } else {
                // Regular search result selection
                let resultIndex = showPlaceTypeSuggestion ? indexPath.row - 1 : indexPath.row
                selectSearchResult(searchResults[resultIndex])
            }
        }
    }
}

// MARK: - LegacyCategoryPickerDelegate

extension AddPlaceViewController {
    func categoryPicker(_ picker: CategoryPickerViewController, didSelectCategory category: PlaceCategory, subcategory: String?, customCategory: String?) {
        selectedCategory = category
        
        // Handle custom category for "Other"
        if category == .other && customCategory != nil {
            selectedSubcategory = customCategory
        } else {
            selectedSubcategory = subcategory
        }
        
        // Update button title
        updateCategoryButtonTitle()
    }
    
    func updateCategoryButtonTitle() {
        if let subcategory = selectedSubcategory {
            categoryButton.setTitle("\(selectedCategory.displayName) - \(subcategory)", for: .normal)
        } else {
            categoryButton.setTitle(selectedCategory.displayName, for: .normal)
        }
    }
    
    func clearPreviousAnnotations() {
        // Remove any existing temporary annotations (like "Selected Location")
        let annotationsToRemove = mapView.annotations.filter { annotation in
            if let placeAnnotation = annotation as? PlaceSearchAnnotation {
                return placeAnnotation.isTemporary || placeAnnotation.title == "Selected Location"
            }
            return false
        }
        mapView.removeAnnotations(annotationsToRemove)
    }
    
    func addSelectedLocationPin(at coordinate: CLLocationCoordinate2D,
                                title: String = "Selected Location",
                                subtitle: String = "Place will be added here",
                                category: PlaceCategory? = nil) {
        // Remove any existing "Selected Location" pins
        clearPreviousAnnotations()
        
        // Add new pin for selected location
        let annotation = PlaceSearchAnnotation()
        annotation.coordinate = coordinate
        annotation.title = title
        annotation.subtitle = subtitle
        annotation.category = category
        annotation.isTemporary = true
        mapView.addAnnotation(annotation)
        annotations.append(annotation)
        
        // Center map on the selected location
        let region = MKCoordinateRegion(
            center: coordinate,
            latitudinalMeters: 500,
            longitudinalMeters: 500
        )
        mapView.setRegion(region, animated: true)
    }
}

// MARK: - PHPickerViewControllerDelegate

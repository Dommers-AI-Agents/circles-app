# FEATURE_PLANS.md - Future Feature Plans for Circles App

This document contains planned features and improvements that have been discussed but not yet implemented. Each plan includes rationale, implementation details, and considerations.

## Table of Contents
1. [Swap Messages and Create Circle Button Locations](#swap-messages-and-create-circle-button-locations)

---

## Swap Messages and Create Circle Button Locations

**Status**: Planned  
**Date Added**: January 2025  
**Priority**: Medium  

### Overview
Move the "Create Circle" functionality (currently a + button in the top right) to the center of the tab bar, and move the Messages functionality to the top navigation bar. This emphasizes the app's core purpose of creating circles.

### Current State
- **Messages**: Center tab (index 2) in the tab bar
- **Create Circle (+)**: Right bar button item in CirclesHomeViewController navigation bar

### Proposed Changes

#### 1. **Modify CirclesTabBarController.swift**
- Remove Messages from the tab bar entirely
- Add a placeholder/dummy view controller at index 2 (center) that will trigger the create circle action
- Update the tab order to: My Circles, My Network, [Create Circle +], Discover, Profile
- Implement special handling for the center tab to present CreateCircleViewController modally instead of switching tabs
- Update badge management to remove Messages badge from tab bar
- Adjust keyboard shortcuts for Mac version

#### 2. **Create Custom Center Tab Button**
- Style the center tab with a prominent plus.circle icon
- Make it stand out visually (potentially with a different color or size)
- Ensure it doesn't show as "selected" like other tabs

#### 3. **Update CirclesHomeViewController.swift**
- Remove the + button from the right bar button items
- Add a Messages button (message icon) to the right bar button items
- Implement message button tap handler to present ConversationsListViewController

#### 4. **Handle Messages Badge**
- Move the unread messages badge from the tab bar to the new Messages button in the navigation bar
- Update notification observers to update the navigation bar button badge

#### 5. **Update Navigation Flows**
- Update push notification handling for messages to use the new navigation pattern
- Ensure deep linking to messages still works
- Update any other references to tab index 2 throughout the codebase

#### 6. **Maintain Functionality**
- Ensure CreateCircleViewController delegate callbacks still work
- Preserve all existing Messages functionality
- Maintain SSE connections and real-time updates for messages

### Benefits
1. **Better UX**: Places the primary action (creating circles) in the most prominent position
2. **Consistency**: Aligns with the app's core purpose
3. **Discoverability**: Makes circle creation more obvious to new users
4. **Clean Design**: Reduces clutter in the navigation bar

### Implementation Checklist
- [ ] Update CirclesTabBarController to restructure tabs
- [ ] Add Messages button to CirclesHomeViewController
- [ ] Implement center button behavior for Create Circle
- [ ] Update badge management
- [ ] Test all navigation flows
- [ ] Update documentation

### Technical Considerations
- Need to handle the center tab differently - it should present a modal instead of switching tabs
- Badge updates will need to be redirected from tab bar to navigation bar
- Push notification navigation will need updating
- Keyboard shortcuts for Mac version need adjustment

---

## Template for New Feature Plans

**Status**: [Planned/In Progress/On Hold]  
**Date Added**: [Date]  
**Priority**: [High/Medium/Low]  

### Overview
[Brief description of the feature]

### Current State
[How things work now]

### Proposed Changes
[Detailed implementation plan]

### Benefits
[Why this feature is valuable]

### Implementation Checklist
- [ ] Task 1
- [ ] Task 2
- [ ] Task 3

### Technical Considerations
[Any technical challenges or considerations]
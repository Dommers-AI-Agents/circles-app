import Foundation
import UIKit

// MARK: - Help Topic Model
struct HelpTopic {
    let id: String
    let title: String
    let subtitle: String?
    let content: String
    let category: HelpCategory
    let relatedTopics: [String]? // IDs of related topics
    let videoTimestamp: TimeInterval? // For linking to specific video sections
    // External destination (e.g. a hosted video tutorial) — the topic screen
    // shows a prominent button that opens it
    var externalURL: String? = nil
    var externalURLTitle: String? = nil
    
    enum HelpCategory: String, CaseIterable {
        case gettingStarted = "Getting Started"
        case circles = "Circles"
        case places = "Places"
        case social = "Social Features"
        case moments = "Moments"
        case quickActions = "Quick Actions"
        case maps = "Maps & Discovery"
        case privacy = "Privacy & Settings"
        case aiAssistants = "AI Assistants"
        case storeOwners = "For Store Owners"
        case favCoins = "FavCoins"
        case troubleshooting = "Troubleshooting"

        var icon: String {
            switch self {
            case .gettingStarted: return "star.fill"
            case .circles: return "circle.grid.2x2.fill"
            case .places: return "mappin.circle.fill"
            case .social: return "person.2.fill"
            case .moments: return "video.fill"
            case .quickActions: return "bolt.fill"
            case .maps: return "map.fill"
            case .privacy: return "lock.fill"
            case .aiAssistants: return "sparkles"
            case .storeOwners: return "storefront.fill"
            case .favCoins: return "dollarsign.circle.fill"
            case .troubleshooting: return "wrench.and.screwdriver.fill"
            }
        }
        
        var color: UIColor {
            switch self {
            case .gettingStarted: return .systemYellow
            case .circles: return Constants.Colors.primary
            case .places: return .systemGreen
            case .social: return .systemBlue
            case .moments: return .systemPurple
            case .quickActions: return .systemOrange
            case .maps: return .systemTeal
            case .privacy: return .systemGray
            case .aiAssistants: return .systemIndigo
            case .storeOwners: return .systemOrange
            case .favCoins: return .systemGreen
            case .troubleshooting: return .systemRed
            }
        }
    }
}

// MARK: - Help Content Provider
class HelpContentProvider {
    static let shared = HelpContentProvider()
    
    private init() {}
    
    // MARK: - All Help Topics
    var allTopics: [HelpTopic] {
        return gettingStartedTopics + circlesTopics + placesTopics + socialTopics +
               momentsTopics + quickActionsTopics + mapsTopics + privacyTopics +
               aiAssistantsTopics + storeOwnersTopics + favCoinsTopics + troubleshootingTopics
    }
    
    // MARK: - Getting Started Topics
    var gettingStartedTopics: [HelpTopic] {
        return [
            HelpTopic(
                id: "app-overview",
                title: "Welcome to Circles",
                subtitle: "Your personal recommendation platform",
                content: """
                Circles is a social platform for sharing and discovering favorite places with your network.
                
                **Key Concepts:**
                • **Circles** - Curated collections of your favorite places
                • **Places** - Restaurants, shops, services, and locations you love
                • **Network** - Friends and connections you share with
                • **Moments** - Photos and videos from places you visit
                
                **Getting Started:**
                1. Create your first circle (e.g., "Best Coffee Shops")
                2. Add your favorite places to circles
                3. Connect with friends to see their recommendations
                4. Share moments from places you visit
                """,
                category: .gettingStarted,
                relatedTopics: ["create-circle", "add-place", "connect-users"],
                videoTimestamp: 0
            ),
            HelpTopic(
                id: "navigation-basics",
                title: "Navigating the App",
                subtitle: "Understanding the main sections",
                content: """
                The app has five main sections accessible from the tab bar:
                
                **Home** 🏠
                • Activity feed from your network
                • Quick access to create circles and add places
                • Moments from people you follow
                
                **Network** 👥
                • Find and connect with other users
                • View connection requests
                • Manage your connections
                
                **Messages** 💬
                • Chat with connections
                • Send place suggestions
                • Share circles privately
                
                **Notifications** 🔔
                • Activity on your content
                • Connection requests
                • New followers
                
                **Profile** 👤
                • Your circles and places
                • Settings and preferences
                • Privacy controls
                """,
                category: .gettingStarted,
                relatedTopics: nil,
                videoTimestamp: 30
            )
        ]
    }
    
    // MARK: - Circles Topics
    var circlesTopics: [HelpTopic] {
        return [
            HelpTopic(
                id: "create-circle",
                title: "Creating a Circle",
                subtitle: "Start your first collection",
                content: """
                Circles are collections of places organized by theme or purpose.
                
                **To create a circle:**
                1. Tap the **+** button on the Home screen
                2. Select "Create Circle"
                3. Choose a name (e.g., "Date Night Spots")
                4. Select a category (Food, Travel, Shopping, etc.)
                5. Set privacy (Public, My Network, or Private)
                6. Add an optional description
                7. Tap "Create"
                
                **Tips:**
                • Use descriptive names others can understand
                • Group similar places together
                • You can create unlimited circles
                • Circles can be edited or deleted later
                """,
                category: .circles,
                relatedTopics: ["circle-privacy", "add-place"],
                videoTimestamp: 60
            ),
            HelpTopic(
                id: "circle-privacy",
                title: "Circle Privacy Settings",
                subtitle: "Control who sees your circles",
                content: """
                Each circle has its own privacy setting:
                
                **Public** 🌐
                • Anyone can view this circle
                • Appears in search results
                • Great for sharing broadly
                
                **My Network** 👥
                • Only your connections can view
                • Perfect for trusted recommendations
                • Most common setting
                
                **Private** 🔒
                • Only you can see this circle
                • Good for personal lists
                • Can be shared individually later
                
                **To change privacy:**
                1. Open the circle
                2. Tap Edit (pencil icon)
                3. Select new privacy level
                4. Save changes
                """,
                category: .circles,
                relatedTopics: ["create-circle", "share-circle"],
                videoTimestamp: 120
            ),
            HelpTopic(
                id: "group-circles",
                title: "Grouping Circles",
                subtitle: "Organize circles into folders",
                content: """
                Group related circles together for better organization.
                
                **To create a group:**
                1. Go to your Profile
                2. Press and hold a circle
                3. Drag it over another circle
                4. Hold for 0.5 seconds until it highlights
                5. Release to create a group
                
                **Managing groups:**
                • Tap a group to see all circles inside
                • Drag circles in or out of groups
                • Rename groups by tapping Edit
                • Groups inherit the most restrictive privacy setting
                
                **Quick reorder vs grouping:**
                • Quick drag = reorder circles
                • Hold over another circle = create/add to group
                """,
                category: .circles,
                relatedTopics: ["create-circle", "organize-content"],
                videoTimestamp: 180
            )
        ]
    }
    
    // MARK: - Places Topics
    var placesTopics: [HelpTopic] {
        return [
            HelpTopic(
                id: "add-place",
                title: "Adding Places",
                subtitle: "Build your recommendations",
                content: """
                There are multiple ways to add places to your circles:
                
                **From Home Screen:**
                1. Tap the **+** button
                2. Select "Add Place"
                3. The map zooms to your location - tap a place to select it
                4. Or use the search bar to find it by name
                5. Choose which circle(s) to add it to
                6. Add optional notes
                
                **From Inside a Circle:**
                1. Open a circle
                2. Tap "Add Place" button
                3. Search or select from map
                4. Place is added directly to that circle
                
                **From the Map:**
                1. Tap to open full-screen map
                2. Browse or search locations
                3. Tap a place marker
                4. Select "Add to Circle"
                
                **Pro tip:** Add notes to explain why you love each place!
                """,
                category: .places,
                relatedTopics: ["search-places", "place-notes", "map-discovery"],
                videoTimestamp: 240
            ),
            HelpTopic(
                id: "search-places",
                title: "Searching for Places",
                subtitle: "Find specific locations",
                content: """
                Find places quickly using search:
                
                **Search Methods:**
                • **By name** - Type the business name
                • **By category** - Search "coffee" or "pizza"
                • **By location** - Include neighborhood or city
                • **Near me** - Find places close to your location
                
                **Search Tips:**
                • Be specific for better results
                • Use filters to narrow results
                • Check the address to ensure correct location
                • Look for photos to verify the place
                
                **Can't find a place?**
                • Check spelling
                • Try alternate names
                • Search by address
                • Make sure location services are enabled
                """,
                category: .places,
                relatedTopics: ["add-place", "map-discovery"],
                videoTimestamp: 300
            ),
            HelpTopic(
                id: "badges-milestones",
                title: "Place Badges & Milestones",
                subtitle: "Earn badges as you save places",
                content: """
                Every place you save counts toward your explorer badge! Your current badge appears next to your name on your profile, where all your connections can see it.

                **The Badges:**
                • **Explorer** — 5 places saved
                • **Adventurer** — 10 places saved
                • **Pathfinder** — 20 places saved
                • **Trailblazer** — 50 places saved
                • **Globetrotter** — 100 places saved
                • **Voyager** — 200 places saved
                • **Legend** — 500 places saved
                • **Cartographer** — 1,000 places saved

                **How it works:**
                • Any place you add to any of your circles counts
                • You'll get a congratulations screen the moment you reach a new tier
                • Your badge upgrades automatically as your count grows
                • Badges are visible to anyone who can view your profile

                **Tips for leveling up:**
                • Save places as you discover them — favorites, hidden gems, places to try
                • Check in when you're out; check-ins can save new places too
                • Import your saved places from other apps in Settings
                """,
                category: .places,
                relatedTopics: ["add-place", "search-places"],
                videoTimestamp: nil
            ),
            HelpTopic(
                id: "place-notes",
                title: "Adding Notes to Places",
                subtitle: "Share why you love it",
                content: """
                Add personal notes to make your recommendations more valuable:
                
                **To add a note:**
                1. Select a place in any circle
                2. Tap "Add Note" or the note icon
                3. Write your recommendation
                4. Save
                
                **What to include:**
                • What to order/try
                • Best time to visit
                • Parking tips
                • Price range
                • Special occasions it's good for
                • Insider tips
                
                **Note visibility:**
                • Notes follow circle privacy settings
                • Public circles = public notes
                • Edit or delete notes anytime
                """,
                category: .places,
                relatedTopics: ["add-place", "share-recommendations"],
                videoTimestamp: 360
            )
        ]
    }
    
    // MARK: - Social Topics
    var socialTopics: [HelpTopic] {
        return [
            HelpTopic(
                id: "connect-users",
                title: "Connecting with Others",
                subtitle: "Build your network",
                content: """
                Connect with friends to share and discover places:
                
                **To connect:**
                1. Go to Network tab
                2. Search for users by name
                3. Tap "Connect" on their profile
                4. Wait for them to accept
                
                **Connection vs Following:**
                • **Connections** - Mutual relationship, see each other's network-only content
                • **Following** - One-way, see their public content only
                
                **Managing connections:**
                • View all connections in Network tab
                • Remove connections from their profile
                • Block users if needed
                
                **Privacy note:** Only share with people you trust!
                """,
                category: .social,
                relatedTopics: ["follow-users", "share-circle"],
                videoTimestamp: 420
            ),
            HelpTopic(
                id: "follow-users",
                title: "Following Users",
                subtitle: "Discover public content",
                content: """
                Follow users to see their public circles and moments:
                
                **To follow someone:**
                1. Visit their profile
                2. Tap "Follow" button
                3. Their public content appears in your feed
                
                **What you'll see:**
                • Public circles they create
                • Moments they share publicly
                • Places they add to public circles
                
                **Managing follows:**
                • Unfollow from their profile
                • Mute users temporarily
                • Your following list is visible on your profile
                
                **Note:** Following is different from connecting - it's one-way and only shows public content.
                """,
                category: .social,
                relatedTopics: ["connect-users", "activity-feed"],
                videoTimestamp: 480
            )
        ]
    }
    
    // MARK: - Moments Topics
    var momentsTopics: [HelpTopic] {
        return [
            HelpTopic(
                id: "create-moment",
                title: "Creating Moments",
                subtitle: "Share your experiences",
                content: """
                Share photos and videos from places you visit:
                
                **To create a moment:**
                1. Tap the **+** button on Home screen
                2. Select "Share a Moment"
                3. Choose type:
                   • **Record** - Take a video (15 sec max)
                   • **Photo** - Take or select a photo
                   • **Link** - Share social media video
                4. Select the associated place
                5. Add optional caption
                6. Post
                
                **Moment tips:**
                • Show the atmosphere or your experience
                • Tag the correct place for discovery
                • Moments inherit place privacy settings
                • Delete your moments anytime
                """,
                category: .moments,
                relatedTopics: ["moments-feed", "share-video"],
                videoTimestamp: 540
            ),
            HelpTopic(
                id: "moments-feed",
                title: "Viewing Moments",
                subtitle: "Discover through video",
                content: """
                See moments from your network:
                
                **Home Moments Tab:**
                • Swipe to Moments section
                • Scroll through recent moments
                • Tap to view full screen
                • Double-tap to like
                
                **On profiles:**
                • View all user's moments
                • Filtered by privacy settings
                • Organized by date
                
                **Interactions:**
                • Like moments
                • Comment on moments
                • Share moments
                • Save places from moments
                """,
                category: .moments,
                relatedTopics: ["create-moment", "discover-places"],
                videoTimestamp: 600
            )
        ]
    }
    
    // MARK: - Quick Actions Topics
    var quickActionsTopics: [HelpTopic] {
        return [
            HelpTopic(
                id: "quick-buttons",
                title: "Quick Action Buttons",
                subtitle: "Fast access to favorite places",
                content: """
                Use quick buttons for instant access to specific circles:
                
                **Home Button** 🏠
                • Your places near home
                • Neighborhood favorites
                • Local services
                
                **Quick Button** ⚡
                • Frequently accessed places
                • Daily go-to spots
                • Quick lunch options
                
                **Work Button** 💼
                • Places near work
                • Business lunch spots
                • After-work venues
                
                **Setting up:**
                1. Go to Settings
                2. Select Quick Actions
                3. Choose which circles to link
                4. Buttons appear on home screen
                
                **Tip:** Customize these for your daily routine!
                """,
                category: .quickActions,
                relatedTopics: ["create-circle", "organize-content"],
                videoTimestamp: 660
            )
        ]
    }
    
    // MARK: - Maps Topics
    var mapsTopics: [HelpTopic] {
        return [
            HelpTopic(
                id: "map-discovery",
                title: "Using the Map",
                subtitle: "Visual place discovery",
                content: """
                Discover places visually on the map:
                
                **Full-screen map:**
                1. Tap map icon on any screen
                2. Pinch to zoom in/out
                3. Drag to move around
                4. Tap markers to see places
                
                **Map features:**
                • **Your places** - Blue markers
                • **Network places** - Green markers
                • **New places** - Gray markers
                • **Clusters** - Numbers show multiple places
                
                **Adding from map:**
                1. Tap any location
                2. Select "Add to Circle"
                3. Choose circles
                4. Confirm
                
                **Filter options:**
                • By category
                • By circle
                • By user
                • By distance
                """,
                category: .maps,
                relatedTopics: ["add-place", "discover-places"],
                videoTimestamp: 720
            ),
            HelpTopic(
                id: "discover-places",
                title: "Discovering Network Places",
                subtitle: "Find recommendations from connections",
                content: """
                See what your network recommends:
                
                **Discovery methods:**
                • **Map view** - See all network places geographically
                • **Activity feed** - Recent additions from connections
                • **User profiles** - Browse their public circles
                • **Search** - Filter by user or category
                
                **Save places you like:**
                1. Tap the place
                2. Select "Add to My Circles"
                3. Choose your circles
                4. Add your own notes
                
                **Discovery tips:**
                • Check who recommended it
                • Read their notes
                • Look at photos
                • Consider the source's taste
                """,
                category: .maps,
                relatedTopics: ["map-discovery", "connect-users"],
                videoTimestamp: 780
            )
        ]
    }
    
    // MARK: - Privacy Topics
    var privacyTopics: [HelpTopic] {
        return [
            HelpTopic(
                id: "privacy-controls",
                title: "Privacy Controls",
                subtitle: "Manage your information",
                content: """
                Control your privacy throughout the app:
                
                **Profile Privacy:**
                • Set default circle privacy
                • Control who can message you
                • Manage blocked users
                
                **Content Privacy:**
                • Each circle has individual settings
                • Moments inherit place privacy
                • Notes follow circle privacy
                
                **Visibility Settings:**
                • Hide from search
                • Approve followers
                • Private profile option
                
                **Data Control:**
                • Export your data
                • Delete account
                • Clear history
                
                Remember: You control what you share!
                """,
                category: .privacy,
                relatedTopics: ["circle-privacy", "account-settings"],
                videoTimestamp: 840
            )
        ]
    }
    
    // MARK: - AI Assistants Topics
    var aiAssistantsTopics: [HelpTopic] {
        return [
            HelpTopic(
                id: "connect-ai-assistants",
                title: "Connect ChatGPT & Claude",
                subtitle: "Ask AI about your favorite places",
                content: """
                Connect your Circles account to the ChatGPT or Claude app on your phone and ask about your saved places in plain language — powered by the FavCircles connector.

                Setup is a one-time step in your phone's web browser. After that, the connection works right inside the Claude or ChatGPT app.

                **What you can do once connected:**
                • "What restaurants do my friends recommend near me?"
                • "Which places do Sarah and I both like?"
                • "Add this café to my Coffee circle"
                • "Plan a Saturday using places my friends love"

                **Connect Claude:**
                1. In Safari, go to claude.ai and sign in
                   (connectors can only be added on the website — they sync to the Claude app automatically)
                2. Tap **Settings → Connectors**
                3. Tap **Add custom connector**
                4. Enter this URL:
                   https://mcp.favcircles.com/mcp
                5. Tap **Connect**, then sign in with your Circles account
                6. Open the Claude app and start a new chat — Claude can now see your circles when you ask

                **Connect ChatGPT:**
                1. In Safari, go to chatgpt.com and sign in
                   (like Claude, setup happens on the website — then it works in the ChatGPT app)
                2. Tap **Settings → Connectors**
                   (if there's no option to add one, first enable **Developer mode** under Connectors → Advanced)
                3. Add a connector with the same URL:
                   https://mcp.favcircles.com/mcp
                4. Tap **Connect**, then sign in with your Circles account
                5. Open the ChatGPT app and ask away — it will use your circles for recommendations

                **Good to know:**
                • Custom connectors require a paid plan — Claude Pro (or higher) or ChatGPT Plus (or higher)
                • Sign in with the same email & password, Google, or Facebook login you use in this app (Sign in with Apple isn't supported on the connect page yet)

                **Privacy:**
                • The assistant sees your circles and your network's shared places — the same things you can see in the app, never more
                • Adding or deleting anything always requires your confirmation in the chat
                • Disconnect anytime from the assistant's settings to revoke access
                """,
                category: .aiAssistants,
                relatedTopics: ["circle-privacy", "connect-users"],
                videoTimestamp: nil
            )
        ]
    }

    // MARK: - Troubleshooting Topics
    var troubleshootingTopics: [HelpTopic] {
        return [
            HelpTopic(
                id: "common-issues",
                title: "Common Issues",
                subtitle: "Quick fixes",
                content: """
                Solutions to common problems:
                
                **Can't find a place:**
                • Check spelling
                • Try searching by address
                • Ensure location services are on
                
                **Images not loading:**
                • Check internet connection
                • Pull to refresh
                • Restart the app
                
                **Can't connect with someone:**
                • They may have blocked you
                • Check if their profile is private
                • Try searching by exact username
                
                **Notifications not working:**
                • Check Settings > Notifications
                • Ensure app permissions are enabled
                • Check Do Not Disturb settings
                
                **App crashes:**
                • Update to latest version
                • Restart your device
                • Reinstall if needed
                
                Still having issues? Contact support!
                """,
                category: .troubleshooting,
                relatedTopics: nil,
                videoTimestamp: 900
            )
        ]
    }
    
    // MARK: - Search

    // MARK: - For Store Owners

    var storeOwnersTopics: [HelpTopic] {
        return [
            HelpTopic(
                id: "store-video-tutorial",
                title: "▶ Watch the store owner tutorial",
                subtitle: "Start here — the whole program in a few minutes",
                content: """
                The fastest way to learn the store owner program: a short narrated video tour, from claiming your business to running your loyalty program.

                **What it covers:**
                1. Welcome to FavCircles for stores
                2. Claiming your business
                3. What happens after approval
                4. The free tier — your dashboard and window QR
                5. FavCircles Business — unlocking the full toolkit
                6. The loyalty program and register card
                7. Offers your customers redeem with points
                8. Announcements that reach your followers

                Tap the button above to watch — it opens in your browser.
                """,
                category: .storeOwners,
                relatedTopics: ["store-rewards-program", "store-getting-started"],
                videoTimestamp: nil,
                externalURL: "https://favcircles.com/store-owner-tutorial.html",
                externalURLTitle: "▶ Watch the tutorial"
            ),
            HelpTopic(
                id: "store-rewards-program",
                title: "How the rewards program works",
                subtitle: "Store points, offers, and what they cost you",
                content: """
                FavCircles gives your store its own loyalty program — store points your customers earn with you and spend on the offers you choose to run.

                **The loop:**
                1. A customer scans the FavCircles sticker in your window and saves your place (+50 points)
                2. After a purchase, they scan the register card at your counter — you set how many points that pays
                3. Points add up across visits — and they stay with your store: points earned with you can only be spent on your offers, never at a competitor
                4. They redeem points on an offer you posted — "Free coffee — 100 points"
                5. The app shows them a 5-minute voucher; they show it at the counter, you hand over the reward

                **Who pays for what:**
                • You fund your own offers — an offer is your discount, honored at your counter
                • FavCircles never charges you per point or per redemption
                • You control the economics: your earn rate, your offers, your prices

                **Watching it work:**
                • The Stats & Insights dashboard tracks saves, followers, visits, QR scans, and redemptions
                • Announcements you post reach your followers' feeds and the Specials tab

                **What about FavCoins?**
                Customers also earn FavCoins — a separate crypto coin — for using FavCircles generally. You don't fund, grant, or redeem FavCoins. Your loyalty currency is store points.
                """,
                category: .storeOwners,
                relatedTopics: ["store-video-tutorial", "store-getting-started", "store-loyalty-codes", "favcoin-vs-store-points"],
                videoTimestamp: nil
            ),
            HelpTopic(
                id: "store-getting-started",
                title: "Claiming and managing your store",
                subtitle: "From claim to control panel",
                content: """
                **Claiming your store:**
                1. Find your place in FavCircles (search or map)
                2. On its page, tap Claim this business and add your contact info
                3. FavCircles verifies you're the owner and approves the claim
                4. You'll get a notification — your store now appears under My Venues

                **Where everything lives:**
                • On your profile, tap the storefront icon → My Venues
                • Each store opens its own control panel: dashboard, business info, QR codes, offers, announcements, earn rate, loyalty codes

                **Free for every store:**
                • Stats dashboard headline (saves, followers, visits, scans)
                • Business contact info and your public place page
                • The scan-to-save window QR

                **With FavCircles Business (subscription):**
                • Offers customers redeem with points
                • Announcements to your followers and the Specials tab
                • Your own points-per-purchase earn rate
                • The register QR card and single-use loyalty codes
                • Full monthly stats history

                One Business subscription covers your physical store and your online store together.
                """,
                category: .storeOwners,
                relatedTopics: ["store-rewards-program", "store-online-storefront"],
                videoTimestamp: nil
            ),
            HelpTopic(
                id: "store-loyalty-codes",
                title: "Loyalty codes, orders, and event booths",
                subtitle: "Reward customers you never see at a register",
                content: """
                Single-use loyalty codes let customers earn your store points from a shipped order or a conference booth — anywhere there's no register to scan.

                **Minting codes:**
                1. My Venues → your store → Loyalty codes
                2. Tap + and choose how many codes and how many points each is worth
                3. Share the list straight to your printer or spreadsheet

                **Where to use them:**
                • Pack one card into every shipped order — "Scan to earn 50 points"
                • Hand them out at events, shows, and conferences
                • Each code works exactly once, and you can set an expiry

                **Event booths:**
                • Your register QR card travels — print it and keep it at your booth
                • A scan after a purchase pays your points, same as at a counter

                **What you get back:**
                • Every redemption shows in your dashboard stats
                • Customers who redeem become followers you can reach with announcements
                """,
                category: .storeOwners,
                relatedTopics: ["store-rewards-program", "store-online-storefront"],
                videoTimestamp: nil
            ),
            HelpTopic(
                id: "store-online-storefront",
                title: "Online stores and your brand storefront",
                subtitle: "For businesses without a front door",
                content: """
                Sell online? Your business can live on FavCircles without a physical location.

                **Your brand storefront:**
                • A card on your profile with your business name, story, website, and catalog link
                • Set it up from My Venues → the storefront button
                • Pick a "Find us at" circle — your schedule of events and conference stops — and it shows right on the card

                **Your online store:**
                • Create it from My Venues → the globe button
                • It gets everything a physical store gets: offers, announcements, loyalty codes, a register QR for your booth, and a dashboard
                • It never appears on the map — customers find you through the Specials tab, your profile, and follows

                **Circles are your content:**
                • Create circles your customers actually want — "Places We Ride", "Conference Schedule"
                • Every circle you share gives people a reason to follow your brand
                • Your account shows a STORE badge across the app
                """,
                category: .storeOwners,
                relatedTopics: ["store-getting-started", "store-loyalty-codes"],
                videoTimestamp: nil
            )
        ]
    }

    // MARK: - FavCoins

    var favCoinsTopics: [HelpTopic] {
        return [
            HelpTopic(
                id: "favcoin-what-is",
                title: "What is FavCoin?",
                subtitle: "The crypto coin you earn for building FavCircles",
                content: """
                FavCoin is a real cryptocurrency on the 🌵 Cactus blockchain. You earn FavCoins by building FavCircles — adding places, creating circles, connecting with friends — and they collect in your Piggy Bank.

                **The essentials:**
                • FavCoins are yours: once claimed, they sit in a 🌵 wallet only you control
                • Their value is whatever people choose to give them — FavCircles doesn't set a price
                • You don't spend FavCoins in the app — they're for holding, sending, or trading outside it
                • Shop discounts are a different thing entirely: those are store points

                **Where to see yours:**
                1. Tap the $ button, then the Piggy Bank tab
                2. Your total shows coins in the piggy, coins clearing, and coins already on the 🌵 blockchain
                3. "How to earn" lists what every action pays right now
                """,
                category: .favCoins,
                relatedTopics: ["favcoin-earning", "favcoin-claiming", "favcoin-vs-store-points"],
                videoTimestamp: nil
            ),
            HelpTopic(
                id: "favcoin-earning",
                title: "Earning FavCoins",
                subtitle: "What pays, and the rules that keep it fair",
                content: """
                You earn FavCoins for the things that make FavCircles better — and small change for everyday engagement.

                **Bigger earns (the piggy bank drop):**
                • Adding places, creating circles, making connections
                • Posting Moments, checking in, referring friends

                **Small change (the dancing leprechaun):**
                • Liking places and moments, reacting to activity, following people
                • These pay fractions of a coin — being generous with hearts is welcome, but it can't out-earn creating things

                **The rules that keep it fair:**
                • First-time-only: re-liking, unfollow/refollow, or re-adding the same place never pays twice
                • Daily limits apply to every action
                • New coins wait up to a day in "clearing" while the action sticks — if it's undone, the coins quietly vanish
                • Your own content pays you nothing when you like it yourself

                For live values, open the Piggy Bank and check "How to earn" — the amounts come straight from the server and can change.
                """,
                category: .favCoins,
                relatedTopics: ["favcoin-what-is", "favcoin-claiming"],
                videoTimestamp: nil
            ),
            HelpTopic(
                id: "favcoin-claiming",
                title: "Claiming coins to your 🌵 wallet",
                subtitle: "Move your FavCoins onto the 🌵 blockchain",
                content: """
                Claiming moves your confirmed FavCoins out of FavCircles and into a 🌵 Cactus wallet only you control. After that, they're on the 🌵 blockchain — FavCircles can't move or take them.

                **Getting a wallet:**
                • FavCircles can create one for you in a tap — the secret phrase is generated on your phone and stored in your iCloud Keychain, never on our servers
                • Or link a 🌵 Cactus wallet you already have (a cac address)

                **Claiming:**
                1. Piggy Bank → Claim
                2. Your entire confirmed balance moves in one claim
                3. The transfer lands on-chain in under a minute — tap the activity row for on-chain proof

                **Good to know:**
                • Your first claim works at any amount; after that a small minimum applies
                • Coins still "clearing" can't be claimed yet — they join the next claim
                • Once on-chain, coins are transferable like any 🌵 Cactus asset
                """,
                category: .favCoins,
                relatedTopics: ["favcoin-what-is", "favcoin-earning"],
                videoTimestamp: nil
            ),
            HelpTopic(
                id: "favcoin-vs-store-points",
                title: "FavCoins vs Store Points",
                subtitle: "Two currencies, two very different jobs",
                content: """
                FavCircles has two currencies, and they never mix. Here's the difference in one breath: store points are shop loyalty you spend on offers; FavCoin is crypto you earn and keep.

                **Store points:**
                • Come from shops — the stores fund every reward
                • Earned by showing up: sticker scans, register scans after a purchase, order-card codes
                • True loyalty: points stay with the shop where you earned them — each store runs its own program
                • Spent in the app on that shop's offers, via a voucher at the counter
                • Live on the Store Points tab of the $ screen

                **FavCoins:**
                • Come from FavCircles — earned by building the app's world
                • Earned by contributing: places, circles, moments, connections, and small change for engagement
                • Never spent in the app — claimed to your own crypto wallet on the 🌵 Cactus blockchain
                • Live on the Piggy Bank tab of the $ screen

                **Why both?**
                Shops know how to say thanks for a purchase — that's points. FavCircles wants to say thanks for building the community — that's coins. Keeping them separate means shops control their own costs, and your coins stay genuinely yours.
                """,
                category: .favCoins,
                relatedTopics: ["favcoin-what-is", "store-rewards-program"],
                videoTimestamp: nil
            )
        ]
    }

    func search(query: String) -> [HelpTopic] {
        let lowercasedQuery = query.lowercased()
        return allTopics.filter { topic in
            topic.title.lowercased().contains(lowercasedQuery) ||
            topic.content.lowercased().contains(lowercasedQuery) ||
            (topic.subtitle?.lowercased().contains(lowercasedQuery) ?? false)
        }
    }
    
    func topics(for category: HelpTopic.HelpCategory) -> [HelpTopic] {
        return allTopics.filter { $0.category == category }
    }
    
    func topic(withId id: String) -> HelpTopic? {
        return allTopics.first { $0.id == id }
    }
}
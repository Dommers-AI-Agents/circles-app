import Testing
@testable import Circles_iOS

/// The window sticker's save offer names the list it goes in (2026-11-16).
struct StickerSaveCopyTests {
    @Test func theOfferNamesTheList() {
        #expect(StickerSaveCopy.offer(storeName: "Sal's", listName: "Favorite Local Spots")
                == "Build your map! Save Sal's to your map — it goes in your Favorite Local Spots list, and you can move it any time.")
        #expect(StickerSaveCopy.offer(storeName: "Sal's", listName: "Favorite Local Spots", bonus: 50)
                == "Build your map! Save Sal's to your map and earn 50 more points here — it goes in your Favorite Local Spots list, and you can move it any time.")
        // No circles at all: the picker will ask, and "circle" is still paired with "list"
        #expect(StickerSaveCopy.offer(storeName: "Sal's", listName: nil) == "Build your map! Save Sal's to one of your circles (your lists of places).")
    }

    @Test func afterTheSave() {
        #expect(StickerSaveCopy.saved(listName: "Favorite Local Spots") == "Saved to Favorite Local Spots.")
        #expect(StickerSaveCopy.saved(listName: nil) == "Place saved to your circle!")
        #expect(StickerSaveCopy.moveButton == "Move to another list")
        #expect(StickerSaveCopy.pickerTitle(storeName: "Sal's") == "Pick a circle (a list) for Sal's")
    }
}

import UIKit

protocol TappableLabelDelegate: AnyObject {
    func tappableLabel(_ label: TappableLabel, didTapPlaceWithId placeId: String)
}

class TappableLabel: UILabel {
    
    weak var delegate: TappableLabelDelegate?
    private var placeMentions: [PlaceMention] = []
    private var placeRanges: [NSRange] = []
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }
    
    private func setup() {
        isUserInteractionEnabled = true
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        addGestureRecognizer(tapGesture)
    }
    
    func configure(text: String, placeMentions: [PlaceMention]) {
        self.placeMentions = placeMentions
        self.placeRanges = []
        
        let attributedString = NSMutableAttributedString(string: text)
        
        // Apply default attributes
        let defaultAttributes: [NSAttributedString.Key: Any] = [
            .font: font ?? UIFont.systemFont(ofSize: 15),
            .foregroundColor: textColor ?? UIColor.label
        ]
        attributedString.addAttributes(defaultAttributes, range: NSRange(location: 0, length: text.count))
        
        // Apply place mention attributes
        for mention in placeMentions {
            let range = NSRange(location: mention.startIndex, length: mention.endIndex - mention.startIndex)
            placeRanges.append(range)
            
            let placeAttributes: [NSAttributedString.Key: Any] = [
                .foregroundColor: Constants.Colors.primary,
                .underlineStyle: NSUnderlineStyle.single.rawValue,
                .underlineColor: Constants.Colors.primary
            ]
            attributedString.addAttributes(placeAttributes, range: range)
        }
        
        self.attributedText = attributedString
    }
    
    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        let location = gesture.location(in: self)
        
        // Create text container
        let textContainer = NSTextContainer(size: bounds.size)
        textContainer.lineFragmentPadding = 0
        textContainer.maximumNumberOfLines = numberOfLines
        textContainer.lineBreakMode = lineBreakMode
        
        // Create layout manager
        let layoutManager = NSLayoutManager()
        layoutManager.addTextContainer(textContainer)
        
        // Create text storage
        let textStorage = NSTextStorage(attributedString: attributedText ?? NSAttributedString())
        textStorage.addLayoutManager(layoutManager)
        
        // Find the character index at tap location
        let characterIndex = layoutManager.characterIndex(
            for: location,
            in: textContainer,
            fractionOfDistanceBetweenInsertionPoints: nil
        )
        
        // Check if tap is on a place mention
        for (index, range) in placeRanges.enumerated() {
            if NSLocationInRange(characterIndex, range) {
                let mention = placeMentions[index]
                delegate?.tappableLabel(self, didTapPlaceWithId: mention.placeId)
                return
            }
        }
    }
}
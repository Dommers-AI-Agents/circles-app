import Foundation
import Testing
import UIKit
@testable import Circles_iOS

/// The shared person row: what it shows and that reuse clears it.
@MainActor
struct UserRowCellTests {
    private func user(_ id: String, _ name: String) throws -> User {
        try JSONDecoder().decode(User.self, from: Data(#"{"_id": "\#(id)", "displayName": "\#(name)"}"#.utf8))
    }

    @Test func showsNameSubtitleAndInitials() throws {
        let cell = UserRowCell(style: .default, reuseIdentifier: UserRowCell.reuseIdentifier)
        cell.configure(with: try user("u1", "Brit Sgroi"), subtitle: "Circles user")

        #expect(cell.nameLabel.text == "Brit Sgroi")
        #expect(cell.subtitleLabel.text == "Circles user")
        #expect(cell.subtitleLabel.isHidden == false)
        #expect(cell.avatarView.image != nil)
        #expect(cell.avatarView.userId == "u1")
    }

    @Test func noSubtitleHidesTheLine() throws {
        let cell = UserRowCell(style: .default, reuseIdentifier: nil)
        cell.configure(with: try user("u2", "Sal"), subtitle: nil)
        #expect(cell.subtitleLabel.isHidden)
    }

    @Test func reuseDropsTheTrailingButton() throws {
        let cell = UserRowCell(style: .default, reuseIdentifier: nil)
        cell.configure(with: try user("u3", "Kai"), subtitle: "Follows you")
        cell.setTrailingButton(UIButton.smallActionButton(title: "Follow")) {}
        #expect(cell.trailingButton?.superview === cell.contentView)

        cell.prepareForReuse()

        #expect(cell.trailingButton == nil)
        #expect(cell.nameLabel.text == nil)
        #expect(cell.avatarView.userId == nil)
    }

    @Test func emptyStateShowsItsButtonOnlyWithAnAction() {
        let plain = EmptyStateView(systemImage: "heart", title: "No likes yet")
        #expect(plain.actionButton == nil)

        var tapped = false
        let withButton = EmptyStateView(title: "No places", message: "Add one", buttonTitle: "Add a Place") { tapped = true }
        withButton.actionButton?.sendActions(for: .touchUpInside)
        #expect(withButton.actionButton?.title(for: .normal) == "Add a Place")
        #expect(tapped)
    }
}

// backend/config/salesKit.js
//
// The admin dashboard's Sales kit tab (Wes, 2026-11-06: one place only he can
// get to for every store-selling asset). The list is served behind the
// dashboard token (GET /api/admin/dashboard/sales-kit), never from the public
// page script. Files live on favcircles.com in an unlinked folder, so adding
// one = upload it there over SFTP + add a line here + deploy.
// Only current material: nothing that breaks the sell-sheet copy rules (no
// points cap, no printed defaults, one $49.99 plan after 3 free months).

const KIT = 'https://favcircles.com/kit-8fd2638e871f';

const SALES_KIT = [
  {
    title: 'Conversation',
    items: [
      {
        title: 'Store owner discovery questions',
        sub: '35 pain-point questions, grouped, each with where FavCircles fits. Your Google Doc, so you can edit it.',
        url: 'https://docs.google.com/document/d/1nVhfqFEmQUpp1qWLxh2UN0cg8qAjLJ9ggdBQG85Yzfc/edit',
        action: 'Open the doc'
      },
      {
        title: 'Window sticker demo guide',
        sub: 'The pitch, the two-minute demo, what is free and what is not, and answers to the usual questions.',
        url: `${KIT}/window-sticker-demo-guide.pdf`,
        thumb: `${KIT}/window-sticker-demo-guide.png`,
        action: 'Open PDF'
      }
    ]
  },
  {
    title: 'Leave-behinds',
    items: [
      {
        title: 'Store sell sheet',
        sub: 'Two-sided US Letter. Print double-sided (long edge), actual size, background graphics on.',
        url: 'https://favcircles.com/FavCircles-Founding-Store-Sell-Sheet.pdf',
        thumb: 'https://favcircles.com/img/sell-sheet-thumb.png',
        action: 'Open PDF to print'
      },
      {
        title: 'Business cards',
        sub: 'Print file for the printer (yours and the brand ambassador card).',
        url: `${KIT}/business-cards.pdf`,
        thumb: `${KIT}/business-cards.png`,
        action: 'Open PDF'
      }
    ]
  },
  {
    title: 'In the store',
    items: [
      {
        title: 'Window and register stickers for a store',
        sub: "Each store's own codes print from the app: open the store's page, tap ••• → Store Admin, then a code → Share → Print a sign or tent.",
      },
      {
        title: 'Table tent',
        sub: 'Home-print US Letter on card stock (65–110 lb). Cut, score, fold, tape.',
        url: `${KIT}/table-tent.pdf`,
        thumb: `${KIT}/table-tent.png`,
        action: 'Open PDF to print'
      },
      {
        title: 'Coaster stickers',
        sub: 'Avery 94102 sheets. Print at actual size; try one on plain paper first.',
        url: `${KIT}/coasters.pdf`,
        thumb: `${KIT}/coasters.jpg`,
        action: 'Open PDF to print'
      }
    ]
  },
  {
    title: 'Videos',
    items: [
      {
        title: 'Store owner tutorial',
        sub: 'How a store runs FavCircles from the phone. Good to send after a visit.',
        url: 'https://favcircles.com/store-owner-tutorial.html',
        thumb: 'https://favcircles.com/videos/store-owner-tutorial-poster.jpg',
        action: 'Watch'
      }
    ]
  }
];

module.exports = { SALES_KIT };

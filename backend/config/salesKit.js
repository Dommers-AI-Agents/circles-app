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
        title: 'Making a new store\'s kit',
        sub: 'One page, start to finish: 3D print the Totem, write its NFC tag, make the QR label, assemble, print the signs, final check.',
        url: `${KIT}/store-setup-checklist.pdf`,
        thumb: `${KIT}/store-setup-checklist.png`,
        action: 'Open PDF to print'
      },
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
        title: 'Totem QR labels (Join FavCircles)',
        sub: 'Generic round 1.5 in labels (favcircles.com/s/JOINUS) for demo Totems. A store\'s own labels print from the app, one per store, starting at any label: Settings → Sticker Venues → QR button → Totem QR labels for several stores. Avery 8293 or Presta 94506, print at Actual size; try one on plain paper first. The base\'s NFC tag is written from Store Admin → NFC stickers → + → Points, named Totem.',
        url: `${KIT}/totem-qr-labels.pdf`,
        thumb: `${KIT}/totem-qr-labels.png`,
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
    title: 'AI assistants',
    items: [
      {
        title: 'FavCircles in Claude: walkthrough',
        sub: 'Connect Claude, then try it as a new customer (testingAI) and as a store owner (testingAI Store): sign up, save places, map links, claim and set up a store. Test logins: ~/.config/favcircles-test-accounts.txt on your Mac.',
        url: `${KIT}/ai-assistant-walkthrough.html`,
        action: 'Open walkthrough'
      },
      {
        title: 'What store owners see',
        sub: 'The "set up your store by chatting with Claude" section on the Store Owners page, and the full Claude connect guide.',
        url: 'https://favcircles.com/store-owners.html#ai',
        action: 'Open page'
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

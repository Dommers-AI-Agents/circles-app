#!/usr/bin/env python3
"""Builds posts.json: one Instagram post per widget (from the website's
widgets.json, so the copy matches favcircles.com/widgets.html) plus a few
posts about FavCircles itself. Every caption ends with the email ask:
captions can't hold links, so it points at the link in bio (favcircles.com/ig)."""
import json, os

HERE = os.path.dirname(os.path.abspath(__file__))
SITE = json.load(open(os.path.join(HERE, '../../website/widgets/widgets.json')))

ACCENT = {'billsplit': '#2C9C93', 'calories': '#FF8500', 'drink': '#D53F8C', 'events': '#7B2FF7', 'fridgemail': '#D97706',
          'habits': '#38A169', 'heartbeat': '#F43F5E', 'howareyou': '#E0567F', 'motivation': '#E53E3E', 'newcontacts': '#2B6CB0',
          'nextbar': '#9F7AEA', 'packages': '#B7791F', 'parking': '#DD6B20', 'postcard': '#E53E3E', 'quotes': '#7C6BD6',
          'run': '#DD6B20', 'sleep': '#6B46C1', 'sleepsounds': '#5B6CFF', 'stocks': '#6001D2', 'water': '#4299E1',
          'weather': '#2B8CD9', 'whattoeat': '#DD6B20', 'workouts': '#3182CE', 'meds': '#319795'}
TAGS = {'Family & friends': '#family #staytogether #grandparents #groupchat',
        'Going out': '#nightout #foodie #whattoeat #friends',
        'Health & fitness': '#fitness #healthyhabits #workout #wellness',
        'Every day': '#productivity #dailyroutine #lifehacks'}
EMAIL_ASK = "📬 Want to hear when new widgets drop? Pop your email in at the link in bio — one short email now and then, never spam."
BASE_TAGS = '#favcircles #iphoneapps #appoftheday'

total = sum(len(g['widgets']) for g in SITE['groups'])
posts = []

# FavCircles itself first, then widgets in the order the website lists them
# Real app screenshots for the phone in each card (shots/<name>.jpg, from
# Marketing/widget-clips/raw and app-store-2026-09/source/raw-iphone). A post
# without one isn't ready: seed-queue.js loads it paused.
SHOTS = {'app-friends-map': 'home-zoomed', 'app-widgets-intro': 'widgets', 'app-place': 'place', 'app-rewards': 'storepoints',
         'app-privacy': 'privacy', 'app-profile': 'profile',
         'widget-events': 'events', 'widget-howareyou': 'howareyou', 'widget-postcard': 'postcard', 'widget-fridgemail': 'fridgemail',
         'widget-nextbar': 'nextbar', 'widget-whattoeat': 'whattoeat', 'widget-drink': 'drink', 'widget-workouts': 'workouts',
         'widget-heartbeat': 'heartbeat', 'widget-sleepsounds': 'sleepsounds', 'widget-habits': 'habits'}

APP_POSTS = [
    dict(id='app-friends-map', emoji='📍', accent='#0E2A47', kicker='Your people',
         headline="Your friends' favorite places, on one map",
         caption="Reviews from strangers vs. a spot your friend swears by. We built FavCircles for the second one 📍\n\nSave your favorite places into circles, share them with the people you choose, and see where your friends actually go."),
    dict(id='app-widgets-intro', emoji='✨', accent='#5A4BD1', kicker='Widgets',
         headline=f'{total} mini-apps, one app',
         caption=f"FavCircles comes with {total} built-in widgets — little apps for the stuff you do every day. Turn on the ones you like; skip the rest. Follow along to meet them one by one 👉"),
    dict(id='app-place', emoji='🍻', accent='#B83280', kicker='Places',
         headline='Every place, and who you know that loves it',
         caption="Every place in FavCircles shows the people you know who saved it, their photos, and one tap to check in, get directions, call or book. Fewer strangers' reviews, more friends' picks."),
    dict(id='app-rewards', emoji='🌵', accent='#2F855A', kicker='Rewards',
         headline='Rewards at the local spots you love',
         caption="Earn points at local shops and cafés that use FavCircles, and redeem them for free stuff. Supporting your favorite small businesses should pay you back 🌵"),
    dict(id='app-privacy', emoji='🔒', accent='#2D3748', kicker='Privacy',
         headline='You choose who sees what',
         caption="Check-ins, photos, saved places: for each one you decide whether everyone, your connections, or just your Inner Circle sees it. Private by default, shared on your terms 🔒"),
    dict(id='app-profile', emoji='🗺️', accent='#2B6CB0', kicker='Your profile',
         headline='All your favorite places in one profile',
         caption="Your circles, the places in them, your moments and your check-ins, all on one profile. A map of you, shared with the people you choose."),
]
for p in APP_POSTS:
    p['caption'] += f"\n\n{EMAIL_ASK}\n\n{BASE_TAGS} #friends #travel"
    posts.append(p)

for group in SITE['groups']:
    for w in group['widgets']:
        caption = (f"{w['emoji']} {w['name']}: {w['tagline']}\n\n"
                   + "\n".join(f"• {f}" for f in w['features'][:3])
                   + f"\n\nIt's one of {total} widgets inside FavCircles. Free to download on the App Store."
                   + f"\n\n{EMAIL_ASK}\n\n{BASE_TAGS} {TAGS.get(group['title'], '')}")
        posts.append(dict(id=f"widget-{w['id']}", widget=w['id'], emoji=w['emoji'], accent=ACCENT.get(w['id'], '#2B6CB0'),
                          kicker=w['name'], headline=w['tagline'], caption=caption.strip()))

# Shorter headlines where the website tagline runs to three lines
HEADLINES = {'widget-events': 'Party photos only your group sees', 'widget-nextbar': 'Your next bar, from where your friends go'}
# Screenshots too empty to look good yet: these wait for a better capture
WEAK = {'widget-howareyou', 'widget-fridgemail', 'widget-habits', 'widget-heartbeat'}

for p in posts:
    p['shot'] = SHOTS.get(p['id'])
    p['ready'] = bool(p['shot']) and p['id'] not in WEAK
    h = HEADLINES.get(p['id'], p['headline']).rstrip('.')
    p['headline'] = h.replace('-', '\u2011')  # never break a hyphenated word across lines

json.dump({'generated_from': 'website/widgets/widgets.json', 'posts': posts}, open(os.path.join(HERE, 'posts.json'), 'w'), indent=2, ensure_ascii=False)
print(len(posts), 'posts,', sum(1 for p in posts if p['ready']), 'ready to post;', 'longest caption', max(len(p['caption']) for p in posts), 'chars (Instagram allows 2200)')

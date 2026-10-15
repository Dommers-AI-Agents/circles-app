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
APP_POSTS = [
    dict(id='app-friends-map', emoji='📍', accent='#0E2A47', kicker='FavCircles',
         headline="Your friends' favorite places, on one map",
         features=['Save places into circles', 'See where the people you trust actually go', 'Private by default, shared on your terms'],
         caption="Reviews from strangers vs. a spot your friend swears by. We built FavCircles for the second one 📍\n\nSave your favorite places into circles, share them with the people you choose, and see where your friends actually go."),
    dict(id='app-widgets-intro', emoji='✨', accent='#5A4BD1', kicker='FavCircles',
         headline=f'{total} mini-apps, one app',
         features=['Water, workouts, runs and habits', 'Bill split, postcards and party photos', 'Weather, stocks, parking and more'],
         caption=f"FavCircles comes with {total} built-in widgets — little apps for the stuff you do every day. Turn on the ones you like; skip the rest. Swipe through our posts to meet them one by one 👉"),
    dict(id='app-party-bus', emoji='🚌', accent='#7B2FF7', kicker='Events',
         headline='Photos only your group sees',
         features=['One link and everyone is in', 'Photos and videos stay with the group', 'The places you went, saved for later'],
         caption="Party bus, bachelorette, family trip: start an Event in FavCircles and everyone joins with one link. Photos and videos stay with the group — not on everyone's public feed."),
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
                          kicker=group['title'], headline=w['name'], tagline=w['tagline'],
                          features=w['features'][:3], caption=caption.strip()))

json.dump({'generated_from': 'website/widgets/widgets.json', 'posts': posts}, open(os.path.join(HERE, 'posts.json'), 'w'), indent=2, ensure_ascii=False)
print(len(posts), 'posts;', 'longest caption', max(len(p['caption']) for p in posts), 'chars (Instagram allows 2200)')

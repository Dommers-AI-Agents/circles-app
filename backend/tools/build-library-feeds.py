#!/usr/bin/env python3
"""Builds config/libraryFeeds.generated.json: library systems for the Local
tab's "Happening nearby".

usage: python3 backend/tools/build-library-feeds.py backend/config/libraryFeeds.generated.json
       ... --only=skpl,www.bossierlibrary.org   (add or refresh just these; the rest of the file is kept)

- BiblioCommons systems (BC list): branches, map points and time zone come
  from the platform's own /locations list.
- LibCal systems (LC list): an event's `campus` names its branch; each is
  located once with OpenStreetMap near the library's city (1 request/s).
  Branches that can't be placed are left out (their events don't show).
- Communico systems (CM list) and LibraryMarket systems (LM list): the next
  two weeks of events name the branches; each is located the same way.
Add a system to a list and re-run; hand-made rows in eventFeeds.js win.
"""
import json, urllib.request, urllib.parse, time, math, re, sys
UA="Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1.15 Safari/605.1.15"
def getj(url, headers=None):
    req=urllib.request.Request(url, headers=headers or {"User-Agent":UA})
    return json.load(urllib.request.urlopen(req, timeout=25))
def miles(a,b):
    R=3958.8; p=math.radians
    dl=p(b[0]-a[0]); dn=p(b[1]-a[1]); x=math.sin(dl/2)**2+math.cos(p(a[0]))*math.cos(p(b[0]))*math.sin(dn/2)**2
    return 2*R*math.asin(math.sqrt(x))
def nominatim(q):
    url="https://nominatim.openstreetmap.org/search?"+urllib.parse.urlencode({"q":q,"format":"json","limit":1,"countrycodes":"us,ca"})
    try: r=getj(url,{"User-Agent":"FavCircles/1.0 (wesley@favcircles.com)"})
    except Exception: r=[]
    time.sleep(1.1)
    return (float(r[0]['lat']), float(r[0]['lon'])) if r else None
def shape(points):
    lat=sum(p[0] for p in points)/len(points); lng=sum(p[1] for p in points)/len(points)
    radius=max(miles((lat,lng),p) for p in points)+10
    return {"lat":round(lat,4),"lng":round(lng,4)}, int(min(max(radius,15),70))

ONLY=None
for arg in sys.argv[2:]:
    if arg.startswith('--only='): ONLY=set(arg.split('=',1)[1].split(','))
want=lambda key: ONLY is None or key in ONLY
# Branches OpenStreetMap can't find (or finds wrong) by name: their street address
ADDRESS={
    # LA County Library
    "A C Bilbrew Library":"150 E El Segundo Blvd, Los Angeles, CA",
    "Bell Express Library":"4411 E Gage Ave, Bell, CA",
    "East Los Angeles Library":"4837 E 3rd St, Los Angeles, CA",
    "George Nye, Jr. Library":"6600 Del Amo Blvd, Lakewood, CA",
    "View Park Bebe Moore Campbell Library":"3854 W 54th St, Los Angeles, CA",
    # Bossier Parish (addresses from bossierlibrary.org, 2026-11-23)
    "Central Library Complex":"7204 Hutchison Dr, Bossier City, LA",
    "Aulds Library Branch":"3950 Wayne Ave, Bossier City, LA",
    "Benton Library Branch":"115 Courthouse Dr, Benton, LA",
    "East 80 Library Branch":"1050 Bellevue Rd, Haughton, LA",
    "Haughton Library Branch":"116 W McKinley Ave, Haughton, LA",
    "Plain Dealing Library Branch":"208 E Mary Lee Ave, Plain Dealing, LA",
    "Tooke Library Branch":"451 Fairview Point Rd, Elm Grove, LA",
}
def place_branches(names, city, home, suffix=" Library"):
    """[(event's branch name, (lat,lng))] for the names OpenStreetMap can find near `home`."""
    out=[]
    for camp in names:
        if re.search(r'(?i)virtual|online|offsite|off-site|zoom|bookmobile|community engagement', camp): continue
        m=re.search(r'\(([^)]*\d[^)]*)\)', camp)   # "(300 N. Roxboro St)"
        base=re.sub(r'\s*\(.*?\)','',camp).strip()
        named=base if re.search(r'(?i)library', base) else f"{base}{suffix}"
        queries=[ADDRESS[camp]] if camp in ADDRESS else ([f"{m.group(1)}, {city}"] if m else [])+[f"{named}, {city}", f"{base}, {city}"]
        hit=None
        for q in dict.fromkeys(queries):
            hit=nominatim(q)
            if hit and home and miles(home,hit)<45: break
            hit=None
        if hit: out.append((camp, base, hit))
        print('   ',repr(camp),'->',hit)
    return out
feeds=[]
# BiblioCommons: everything from the platform's own branch list
BC=["chipublib","sdcl","sjpl","sccl","kcls","bpl","pima","oaklandlibrary","fulcolibrary","omaha","hclib","cincinnatilibrary",
    "slpl","jocolibrary","tacoma","tpl","vpl","epl","halifax","arapahoelibraries","aurora","rclreads","sppl","grpl","kdl","dayton"]
for lid in BC:
    if not want(lid): continue
    try:
        lib=getj(f"https://gateway.bibliocommons.com/v2/libraries/{lid}")
        name=list(lib['entities']['libraries'].values())[0]['longName']
        locs={}
        page=1
        while True:
            d=getj(f"https://gateway.bibliocommons.com/v2/libraries/{lid}/locations?limit=100&page={page}")
            locs.update(d['entities'].get('locations',{}))
            if page>=d['locations']['pagination']['pages']: break
            page+=1
        pts=[]; tz=None
        for l in locs.values():
            c=(l.get('mapLocation') or {}).get('centrePoint') or {}
            if isinstance(c.get('lat'),(int,float)) and isinstance(c.get('lng'),(int,float)) and c['lat']!=0:
                pts.append((c['lat'],c['lng'])); tz=tz or (l.get('mapLocation') or {}).get('timeZone')
        # drop far outliers (bookmobile depots, mis-geocoded rows)
        if len(pts)>3:
            mlat=sorted(p[0] for p in pts)[len(pts)//2]; mlng=sorted(p[1] for p in pts)[len(pts)//2]
            pts=[p for p in pts if miles((mlat,mlng),p)<80]
        if not pts or not tz: print('skip',lid,'no points/tz'); continue
        center,radius=shape(pts)
        feeds.append({"type":"bibliocommons","libraryId":lid,"name":name,"center":center,"radiusMiles":radius,"timeZone":tz})
        print('BC',lid,name,len(pts),'branches',center,radius,tz)
    except Exception as e:
        print('BC fail',lid,e)

# LibCal: branch = event 'campus'; located once with OpenStreetMap near the library's city
LC=[("houstonlibrary","Houston Public Library","Houston, TX","America/Chicago"),
    ("denverlibrary","Denver Public Library","Denver, CO","America/Denver"),
    ("cpl","Cleveland Public Library","Cleveland, OH","America/New_York"),
    ("npl","Newark Public Library","Newark, NJ","America/New_York"),
    ("durhamcountylibrary","Durham County Library","Durham, NC","America/New_York"),
    ("fresnolibrary","Fresno County Public Library","Fresno, CA","America/Los_Angeles"),
    ("arlingtonva","Arlington Public Library","Arlington, VA","America/New_York"),
    ("bccls","Bergen County libraries (BCCLS)","Bergen County, NJ","America/New_York"),
    ("hclibrary","Hunterdon County Library","Flemington, NJ","America/New_York"),
    ("charlottecountyfl","Charlotte County Library System","Port Charlotte, FL","America/New_York"),
    ("skpl","South Kingstown Public Library","South Kingstown, RI","America/New_York")]
for host,name,city,tz in LC:
    if not want(host): continue
    try:
        campuses={}
        for page in (1,2,3):
            d=getj(f"https://{host}.libcal.com/ajax/calendar/list?c=-1&date=0000-00-00&perpage=100&page={page}&audience=&cats=&camps=&inc=0",{"User-Agent":UA,"X-Requested-With":"XMLHttpRequest"})
            for r in d.get('results',[]):
                k=(r.get('campus') or '').strip()
                if k: campuses[k]=campuses.get(k,0)+1
            if len(d.get('results',[]))<100: break
        home=nominatim(city)
        branches=[{"name":base,"match":[base],"lat":round(hit[0],5),"lng":round(hit[1],5)} for camp,base,hit in place_branches(campuses, city, home)]
        if not branches: print('skip',host); continue
        center,radius=shape([(b['lat'],b['lng']) for b in branches])
        feeds.append({"type":"libcal","host":f"{host}.libcal.com","calendarId":-1,"name":name,"center":center,"radiusMiles":radius,"timeZone":tz,"branches":branches})
        print('LC',host,len(branches),'of',len(campuses),'branches placed')
    except Exception as e:
        print('LC fail',host,e)

# Communico: an event's `location` is the branch's own name
CM=[("visit.lacountylibrary.org","https://static.libnet.info/images/events/lacountylibrary/","LA County Library","Los Angeles County, CA","America/Los_Angeles")]
today=time.strftime('%Y-%m-%d')
for host,image_base,name,city,tz in CM:
    if not want(host): continue
    try:
        req=json.dumps({"private":False,"date":today,"days":21,"locations":[],"ages":[],"types":[]})
        rows=getj(f"https://{host}/eeventcaldata?"+urllib.parse.urlencode({"event_type":0,"req":req}))
        names=sorted({(r.get('location') or '').strip() for r in rows if r.get('event_type')=='INPERSON' and r.get('venue_type')!='external'}-{''})
        home=nominatim(city)
        placed=place_branches(names, city, home)
        branches=[{"name":camp,"match":[camp],"lat":round(hit[0],5),"lng":round(hit[1],5)} for camp,base,hit in placed]
        if not branches: print('skip',host); continue
        center,radius=shape([(b['lat'],b['lng']) for b in branches])
        feeds.append({"type":"communico","host":host,"imageBase":image_base,"name":name,"center":center,"radiusMiles":radius,"timeZone":tz,"branches":branches})
        print('CM',host,len(branches),'of',len(names),'branches placed')
    except Exception as e:
        print('CM fail',host,e)

# LibraryMarket: an event's `branch` names its branch
LM=[("www.bossierlibrary.org","Bossier Parish Libraries","Bossier Parish, LA","America/Chicago")]
for host,name,city,tz in LM:
    if not want(host): continue
    try:
        end=time.strftime('%Y-%m-%d', time.localtime(time.time()+21*86400))
        rows=getj(f"https://{host}/events/feed/json?start={today}&end={end}")
        names=sorted({v for r in rows if isinstance(r.get('branch'),dict) and len(r['branch'])==1 for v in r['branch'].values()})
        home=nominatim(city)
        placed=place_branches(names, city, home)
        short=lambda base: re.sub(r'(?i)\s+library branch$','',base)   # "Aulds Library Branch" → "Aulds"
        branches=[{"name":short(base),"match":[camp],"lat":round(hit[0],5),"lng":round(hit[1],5)} for camp,base,hit in placed]
        if not branches: print('skip',host); continue
        center,radius=shape([(b['lat'],b['lng']) for b in branches])
        feeds.append({"type":"librarymarket","host":host,"name":name,"center":center,"radiusMiles":radius,"timeZone":tz,"branches":branches})
        print('LM',host,len(branches),'of',len(names),'branches placed')
    except Exception as e:
        print('LM fail',host,e)

if ONLY is not None:
    # Keep everything else in the file; the named systems are added or replaced
    key=lambda f: f.get('libraryId') or f.get('host')
    fresh={key(f) for f in feeds}
    feeds=[f for f in json.load(open(sys.argv[1])) if key(f) not in fresh]+feeds
json.dump(feeds,open(sys.argv[1],'w'),indent=1)
print(len(feeds),'feeds')

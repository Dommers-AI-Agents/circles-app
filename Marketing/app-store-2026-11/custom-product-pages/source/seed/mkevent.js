const admin=require("/Users/wesleysgroi/circles-app/backend/node_modules/firebase-admin");admin.initializeApp({credential:admin.credential.cert(require("/Users/wesleysgroi/circles-app/backend/config/firebase-service-account.json"))});
const T=require('fs').readFileSync(process.argv[2],'utf8').trim();
(async()=>{
  const r=await fetch('https://api.favcircles.com/api/widgets/events',{method:'POST',headers:{Authorization:`Bearer ${T}`,'Content-Type':'application/json'},body:JSON.stringify({
    name:"Maya's 8th Birthday", emoji:'🎂', startsAt:'2026-11-14T19:00:00.000Z', endsAt:'2026-11-14T21:30:00.000Z', timezone:'America/New_York',
    location:{name:'Freedom Park, Shelter 3', address:'1900 East Blvd, Charlotte, NC 28203', lat:35.1913, lng:-80.8433},
    details:'Pizza, cake and a bounce house. Wear sneakers! Siblings welcome.'})});
  const j=await r.json(); if(!r.ok){console.log(j);process.exit(1)}
  const id=j.event.id; const db=admin.firestore();
  await db.collection('events').doc(id).update({reminderAt: admin.firestore.FieldValue.delete()});
  const now=new Date().toISOString();
  const guests=[['Sarah Chen','going',2,2,'Can’t wait! Bringing the twins 🎈'],['The Okafors','going',2,1,''],['Priya Patel','going',1,1,'Lily is so excited'],['Mike & Dana','maybe',2,2,'Soccer game till 2, will try!'],['Grandma Rose','going',2,0,'We’ll bring the ice cream'],['Jess Alvarez','no',0,0,'Out of town, happy birthday Maya!'],['Tom Becker','pending',0,0,'']];
  for(const [name,rsvp,a,k,note] of guests){
    const tag=name.toLowerCase().replace(/[^a-z]/g,'');
    await db.collection('eventGuests').add({eventId:id,email:`${tag}@example.invalid`,name,token:require('crypto').randomBytes(16).toString('hex'),rsvp,adults:a,kids:k,note,invitedBy:j.event.hostId||'1z4ZzMBfJDay1ihv1BsEBR67uw93',invitedAt:now,createdAt:now,optedOut:true,respondedAt:rsvp==='pending'?null:now,updatedAt:now});
  }
  console.log('event',id);process.exit(0);
})();

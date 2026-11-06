// Holiday favorites circle on the hidden demo account (widget-demo@), for the In-App Event images
const admin=require("/Users/wesleysgroi/circles-app/backend/node_modules/firebase-admin");admin.initializeApp({credential:admin.credential.cert(require("/Users/wesleysgroi/circles-app/backend/config/firebase-service-account.json"))});
const db=admin.firestore(); const T=require('fs').readFileSync(process.argv[2],'utf8').trim();
const B='https://api.favcircles.com/api'; const H={Authorization:`Bearer ${T}`,'Content-Type':'application/json'};
const picks=[
 ['HO8Gxd4UQIMZnw1abtY8','The tree lighting, then a walk around Uptown'],
 ['uB86AgyHOtjBAAaGbmmY','Hot cocoa and a salted caramel brownie'],
 ['Qx1w1mhSa7o5edymblTc','Drive through the Christmas lights'],
 ['MVDXHUUemTOJrPKnemYw','Rainy-day plan with the kids'],
 ['QYYkwJvAvhX3k1JcmW9g','Gifts for everyone on the list'],
 ['jGIq1otGQ3J3XCDIowwA','Coffee before the McAdenville lights'],
 ['O3IimapYLMgWff9EL0Am','Wreaths and holiday baking things'],
 ['PRrevxWV45a9fOQjtHXZ','Holiday flavors are back'],
 ['OaV0JZfhxV41TOfdULrW','Peppermint mocha'],
];
(async()=>{
  const c=await fetch(B+'/circles',{method:'POST',headers:H,body:JSON.stringify({name:'Holiday favorites',description:'My go-to spots for the season',privacy:process.argv[3]})});
  const cj=await c.json(); if(!c.ok){console.log(cj);process.exit(1)}
  const circleId=(cj.circle||cj.data||cj).id; console.log('circle',circleId);
  for(const [gid,note] of picks){
    const g=(await db.collection('globalPlaces').doc(gid).get()).data();
    const loc=g.location||{}; const lat=loc.latitude??loc._latitude??loc.lat??loc.coordinates?.[1]; const lng=loc.longitude??loc._longitude??loc.lng??loc.coordinates?.[0];
    const body={circleId,globalPlaceId:gid,googlePlaceId:g.googlePlaceId||undefined,name:g.name,address:g.address,category:g.category,location:{type:'Point',coordinates:[lng,lat]},publicNotes:note,force:true};
    const r=await fetch(B+'/places',{method:'POST',headers:H,body:JSON.stringify(body)});
    const j=await r.json(); console.log(r.status,g.name,r.ok?(j.place||j.data||{}).id:JSON.stringify(j).slice(0,200));
  }
  process.exit(0);
})();

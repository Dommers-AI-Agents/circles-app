const admin=require("/Users/wesleysgroi/circles-app/backend/node_modules/firebase-admin");admin.initializeApp({credential:admin.credential.cert(require("/Users/wesleysgroi/circles-app/backend/config/firebase-service-account.json")),storageBucket:'circles-app-83b67.firebasestorage.app'});
const crypto=require('crypto');
(async()=>{const token=crypto.randomUUID();const name=`circles/${crypto.randomUUID()}.jpg`;
await admin.storage().bucket().upload(process.argv[2],{destination:name,metadata:{contentType:'image/jpeg',metadata:{firebaseStorageDownloadTokens:token}}});
console.log(`https://firebasestorage.googleapis.com/v0/b/circles-app-83b67.firebasestorage.app/o/${encodeURIComponent(name)}?alt=media&token=${token}`);process.exit(0)})();

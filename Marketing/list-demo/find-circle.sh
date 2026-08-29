#!/bin/bash
# find-circle.sh — prints the id of the circle the demo just imported (newest
# non-deleted circle of Wes's carrying the demo list's sourceListUrl), or nothing.
cd "$(dirname "$0")/../../backend"
node -e '
require("dotenv").config();
const { initializeFirebase, getFirestore } = require("./config/firebase");
initializeFirebase();
getFirestore().collection("circles").where("owner","==","111819744557116370195").get().then(q => {
  const hits = q.docs.filter(c => !c.data().deletedAt && /rXJr3AmshQAtHA3pW_AsNN8HYb4JyA/.test(c.data().sourceListUrl || ""));
  if (hits.length) console.log(hits[hits.length-1].id);
  process.exit(0);
});' 2>/dev/null | grep -v Firebase

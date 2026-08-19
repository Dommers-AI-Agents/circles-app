// Passkey (WebAuthn) signup + login.
//
// Passkey accounts follow the SOCIAL account pattern: Firestore-doc-only,
// no Firebase Auth record, linkedProviders.passkey marks the method. The
// register path preserves the anti-takeover invariant: an existing email can
// never gain a passkey through these endpoints (409 ACCOUNT_EXISTS — adding
// a passkey to an existing account will be an authenticated Settings flow).
//
// Encoding truth: iOS native ceremonies report clientDataJSON.origin as
// https://<RP_ID> — never the API host. One RP_ID constant drives the iOS
// entitlement string, the provider's relyingPartyIdentifier, and both
// expected values here. RP_ID is PERMANENT once users hold credentials.

const {
  generateRegistrationOptions, verifyRegistrationResponse,
  generateAuthenticationOptions, verifyAuthenticationResponse
} = require('@simplewebauthn/server');
const { isoBase64URL, isoUint8Array } = require('@simplewebauthn/server/helpers');
const admin = require('firebase-admin');
const { getFirestore } = require('../config/firebase');
const { COLLECTIONS, createUser, serializeDoc } = require('../models/FirestoreModels');
const { mintSessionToken, getTokenExpiresInSeconds } = require('./firebaseAuthController');
const { normalizeUserId } = require('../services/idService');

const db = getFirestore();

const RP_ID = process.env.WEBAUTHN_RP_ID || 'favcircles.com';
const RP_NAME = 'FavCircles';
const EXPECTED_ORIGIN = `https://${RP_ID}`;
const CHALLENGE_TTL_MS = 5 * 60 * 1000;

// ---------------------------------------------------------------- challenges

async function storeChallenge(challenge, fields) {
  await db.collection(COLLECTIONS.WEBAUTHN_CHALLENGES).doc(challenge).create({
    ...fields,
    used: false,
    usedAt: null,
    createdAt: admin.firestore.Timestamp.now(),
    expiresAt: admin.firestore.Timestamp.fromMillis(Date.now() + CHALLENGE_TTL_MS)
  });
}

/// Single-use consumption, transactional — safe across Cloud Run instances.
/// Returns the challenge doc data or null (missing/used/expired/wrong type).
async function consumeChallenge(challenge, expectedType) {
  if (!challenge || typeof challenge !== 'string') return null;
  const ref = db.collection(COLLECTIONS.WEBAUTHN_CHALLENGES).doc(challenge);
  try {
    return await db.runTransaction(async (tx) => {
      const doc = await tx.get(ref);
      if (!doc.exists) return null;
      const data = doc.data();
      if (data.used || data.type !== expectedType) return null;
      if (data.expiresAt.toMillis() < Date.now()) return null;
      tx.update(ref, { used: true, usedAt: admin.firestore.Timestamp.now() });
      return data;
    });
  } catch (error) {
    console.error('⚠️ Challenge consume failed:', error.message);
    return null;
  }
}

function challengeFromClientData(credential) {
  try {
    const clientData = JSON.parse(isoBase64URL.toUTF8String(credential.response.clientDataJSON));
    return clientData.challenge || null;
  } catch (e) {
    return null;
  }
}

// ------------------------------------------------------------------ handlers

// @desc  Does an account exist for this email (and does it have a passkey)?
// @route POST /api/auth/email-check   (public, authLimiter)
exports.emailCheck = async (req, res) => {
  try {
    const email = String(req.body.email || '').toLowerCase().trim();
    const snap = await db.collection(COLLECTIONS.USERS)
      .where('email', '==', email).limit(1).get();
    const exists = !snap.empty;
    const hasPasskey = exists && !!(snap.docs[0].data().linkedProviders || {}).passkey;
    res.json({ success: true, exists, hasPasskey });
  } catch (error) {
    console.error('email-check failed:', error);
    res.status(500).json({ success: false, message: 'Something went wrong. Please try again.' });
  }
};

// @desc  Registration ceremony options for a NEW account
// @route POST /api/auth/passkey/register-options
exports.passkeyRegisterOptions = async (req, res) => {
  try {
    const email = String(req.body.email || '').toLowerCase().trim();

    if (email.includes('@privaterelay.appleid.com')) {
      return res.status(400).json({
        success: false,
        message: 'Private relay emails are not allowed. Please use your real email address.',
        code: 'PRIVATE_RELAY_NOT_ALLOWED'
      });
    }

    // Anti-takeover: existing email never mints a registration challenge
    const existing = await db.collection(COLLECTIONS.USERS)
      .where('email', '==', email).limit(1).get();
    if (!existing.empty) {
      return res.status(409).json({
        success: false,
        message: 'An account with this email already exists. Please sign in instead.',
        code: 'ACCOUNT_EXISTS',
        email
      });
    }

    // Pre-allocate the Firestore user id — it becomes the WebAuthn userHandle
    const uid = db.collection(COLLECTIONS.USERS).doc().id;

    const options = await generateRegistrationOptions({
      rpName: RP_NAME,
      rpID: RP_ID,
      userName: email,
      userID: isoUint8Array.fromUTF8String(uid),
      attestationType: 'none',
      authenticatorSelection: {
        authenticatorAttachment: 'platform',
        residentKey: 'required',
        requireResidentKey: true,
        userVerification: 'required'
      },
      supportedAlgorithmIDs: [-7, -257], // ES256 (iOS) + RS256
      timeout: 300000
    });

    await storeChallenge(options.challenge, { type: 'registration', email, uid });

    res.json({ success: true, options });
  } catch (error) {
    console.error('passkey register-options failed:', error);
    res.status(500).json({ success: false, message: 'Could not start passkey setup. Please try again.' });
  }
};

// @desc  Verify attestation, create the account, mint a session
// @route POST /api/auth/passkey/register-verify
exports.passkeyRegisterVerify = async (req, res) => {
  try {
    const email = String(req.body.email || '').toLowerCase().trim();
    const credential = req.body.credential;
    const deviceName = String(req.body.deviceName || 'iPhone').slice(0, 64);

    const challenge = challengeFromClientData(credential);
    const challengeDoc = challenge ? await consumeChallenge(challenge, 'registration') : null;
    if (!challengeDoc || challengeDoc.email !== email) {
      return res.status(400).json({
        success: false,
        message: 'This sign-up attempt expired. Please try again.',
        code: 'CHALLENGE_INVALID'
      });
    }

    const { verified, registrationInfo } = await verifyRegistrationResponse({
      response: credential,
      expectedChallenge: challenge,
      expectedOrigin: EXPECTED_ORIGIN,
      expectedRPID: RP_ID,
      requireUserVerification: true
    });
    if (!verified || !registrationInfo) {
      return res.status(400).json({
        success: false,
        message: 'Passkey verification failed. Please try again.',
        code: 'VERIFICATION_FAILED'
      });
    }

    const cred = registrationInfo.credential; // { id, publicKey(Uint8Array), counter, transports? }
    const uid = challengeDoc.uid;
    const now = new Date().toISOString();

    // Create user + credential atomically, re-checking the email inside the
    // transaction (409 on a signup race — same invariant as register)
    try {
      await db.runTransaction(async (tx) => {
        const raceCheck = await tx.get(
          db.collection(COLLECTIONS.USERS).where('email', '==', email).limit(1));
        if (!raceCheck.empty) {
          const err = new Error('An account with this email already exists. Please sign in instead.');
          err.accountExists = true;
          throw err;
        }
        const userData = createUser({
          uid,
          email,
          displayName: email.split('@')[0],
          profilePicture: null,
          linkedProviders: { passkey: cred.id }
        });
        tx.set(db.collection(COLLECTIONS.USERS).doc(uid), userData);
        tx.create(db.collection(COLLECTIONS.WEBAUTHN_CREDENTIALS).doc(cred.id), {
          userId: uid,
          email,
          publicKey: isoBase64URL.fromBuffer(cred.publicKey),
          counter: cred.counter || 0,
          transports: cred.transports || ['internal'],
          deviceName,
          createdAt: now,
          lastUsedAt: null
        });
      });
    } catch (txError) {
      if (txError.accountExists) {
        return res.status(409).json({
          success: false,
          message: txError.message,
          code: 'ACCOUNT_EXISTS',
          email
        });
      }
      throw txError;
    }

    // Onboarding (default circles, welcome requests, follows) — same as
    // register: awaited so the first home screen isn't empty
    let circlesCount = 0;
    let placesCount = 0;
    try {
      const OnboardingService = require('../services/onboardingService');
      await OnboardingService.completeUserOnboarding(uid, null);
      const circlesSnapshot = await db.collection(COLLECTIONS.CIRCLES)
        .where('owner', '==', uid).get();
      circlesCount = circlesSnapshot.size;
      circlesSnapshot.forEach((doc) => { placesCount += doc.data().placesCount || 0; });
    } catch (onboardingError) {
      console.error('⚠️ Passkey onboarding failed (signup continues):', onboardingError.message);
    }

    // Welcome email — fire-and-forget
    require('../services/emailService').sendWelcomeEmail(email, email.split('@')[0])
      .catch((e) => console.error('Welcome email failed:', e.message));

    const userDoc = await db.collection(COLLECTIONS.USERS).doc(uid).get();
    const user = serializeDoc(userDoc);
    const normalizedId = normalizeUserId(uid);
    const token = mintSessionToken(normalizedId, email);

    res.status(201).json({
      success: true,
      token,
      refreshToken: token,
      expiresIn: getTokenExpiresInSeconds(),
      isNewUser: true, // drives the first-session carousel chain on iOS
      user: {
        _id: normalizedId,
        email: user.email,
        displayName: user.displayName,
        firstName: user.firstName || null,
        lastName: user.lastName || null,
        phoneNumber: user.phoneNumber || null,
        profilePicture: user.profilePicture || null,
        bio: user.bio || null,
        location: user.location || null,
        friends: user.friends || [],
        friendRequests: user.friendRequests || [],
        followersCount: user.followersCount || 0,
        followingCount: user.followingCount || 0,
        circlesCount,
        placesCount,
        createdAt: user.createdAt
      }
    });
  } catch (error) {
    console.error('passkey register-verify failed:', error);
    res.status(500).json({ success: false, message: 'Could not finish sign-up. Please try again.' });
  }
};

// @desc  Authentication ceremony options (discoverable when no email)
// @route POST /api/auth/passkey/login-options
exports.passkeyLoginOptions = async (req, res) => {
  try {
    const email = req.body && req.body.email
      ? String(req.body.email).toLowerCase().trim() : null;

    let allowCredentials;
    if (email) {
      const creds = await db.collection(COLLECTIONS.WEBAUTHN_CREDENTIALS)
        .where('email', '==', email).get();
      if (!creds.empty) {
        allowCredentials = creds.docs.map((d) => ({ id: d.id, type: 'public-key' }));
      }
      // Unknown email or no passkeys: fall through with no allowCredentials —
      // valid options either way, no account enumeration
    }

    const options = await generateAuthenticationOptions({
      rpID: RP_ID,
      userVerification: 'required',
      timeout: 300000,
      ...(allowCredentials ? { allowCredentials } : {})
    });

    await storeChallenge(options.challenge, { type: 'authentication', email, uid: null });

    res.json({ success: true, options });
  } catch (error) {
    console.error('passkey login-options failed:', error);
    res.status(500).json({ success: false, message: 'Could not start sign-in. Please try again.' });
  }
};

// @desc  Verify assertion, mint a session
// @route POST /api/auth/passkey/login-verify
exports.passkeyLoginVerify = async (req, res) => {
  try {
    const credential = req.body.credential;

    const challenge = challengeFromClientData(credential);
    const challengeDoc = challenge ? await consumeChallenge(challenge, 'authentication') : null;
    if (!challengeDoc) {
      return res.status(400).json({
        success: false,
        message: 'This sign-in attempt expired. Please try again.',
        code: 'CHALLENGE_INVALID'
      });
    }

    const credDoc = await db.collection(COLLECTIONS.WEBAUTHN_CREDENTIALS)
      .doc(credential.id).get();
    if (!credDoc.exists) {
      return res.status(401).json({
        success: false,
        message: 'Passkey not recognized. Try another sign-in method.',
        code: 'UNKNOWN_CREDENTIAL'
      });
    }
    const stored = credDoc.data();

    // The assertion's userHandle must match the credential's owner
    const userHandle = credential.response.userHandle
      ? isoBase64URL.toUTF8String(credential.response.userHandle) : null;
    if (userHandle && userHandle !== stored.userId) {
      return res.status(401).json({
        success: false,
        message: 'Passkey not recognized. Try another sign-in method.',
        code: 'UNKNOWN_CREDENTIAL'
      });
    }

    const { verified, authenticationInfo } = await verifyAuthenticationResponse({
      response: credential,
      expectedChallenge: challenge,
      expectedOrigin: EXPECTED_ORIGIN,
      expectedRPID: RP_ID,
      credential: {
        id: credDoc.id,
        publicKey: isoBase64URL.toBuffer(stored.publicKey),
        counter: stored.counter || 0, // iOS platform authenticator stays 0 — valid
        transports: stored.transports
      },
      requireUserVerification: true
    });
    if (!verified) {
      return res.status(401).json({
        success: false,
        message: 'Passkey verification failed. Try another sign-in method.',
        code: 'VERIFICATION_FAILED'
      });
    }

    const now = new Date().toISOString();
    await credDoc.ref.update({ counter: authenticationInfo.newCounter, lastUsedAt: now });

    const userDoc = await db.collection(COLLECTIONS.USERS).doc(stored.userId).get();
    if (!userDoc.exists) {
      return res.status(401).json({
        success: false,
        message: 'Account not found for this passkey.',
        code: 'UNKNOWN_CREDENTIAL'
      });
    }
    const user = serializeDoc(userDoc);
    await userDoc.ref.update({ lastLogin: now, updatedAt: now }).catch(() => {});

    const normalizedId = normalizeUserId(stored.userId);
    const token = mintSessionToken(normalizedId, user.email);

    res.json({
      success: true,
      token,
      refreshToken: token,
      expiresIn: getTokenExpiresInSeconds(),
      isNewUser: false,
      user: {
        _id: normalizedId,
        email: user.email || '',
        displayName: user.displayName || 'User',
        firstName: user.firstName || null,
        lastName: user.lastName || null,
        phoneNumber: user.phoneNumber || null,
        profilePicture: user.profilePicture || null,
        bio: user.bio || null,
        location: user.location || null,
        friends: user.friends || [],
        friendRequests: user.friendRequests || [],
        followersCount: user.followersCount || 0,
        followingCount: user.followingCount || 0,
        createdAt: user.createdAt
      }
    });
  } catch (error) {
    console.error('passkey login-verify failed:', error);
    res.status(500).json({ success: false, message: 'Could not sign in. Please try again.' });
  }
};

// @desc  Registration options to ADD a passkey to the CURRENT signed-in account
// @route POST /api/auth/passkey/add-options   (protected)
//
// Unlike register-options this does NOT require the email to be new — the user
// is already authenticated (req.user.uid). It's how an existing account (social
// login, email/password, etc.) enrolls Face ID / passcode sign-in.
exports.passkeyAddOptions = async (req, res) => {
  try {
    const uid = req.user.uid;
    const userDoc = await db.collection(COLLECTIONS.USERS).doc(uid).get();
    if (!userDoc.exists) {
      return res.status(404).json({ success: false, message: 'Account not found.' });
    }
    const email = String(userDoc.data().email || '').toLowerCase().trim();

    // Exclude any credentials this account already holds so the platform
    // doesn't create a duplicate on the same device.
    const existingCreds = await db.collection(COLLECTIONS.WEBAUTHN_CREDENTIALS)
      .where('userId', '==', uid).get();
    const excludeCredentials = existingCreds.docs.map((d) => ({ id: d.id, type: 'public-key' }));

    const options = await generateRegistrationOptions({
      rpName: RP_NAME,
      rpID: RP_ID,
      userName: email || `user-${uid.slice(0, 6)}`,
      userID: isoUint8Array.fromUTF8String(uid), // WebAuthn userHandle = existing uid
      attestationType: 'none',
      authenticatorSelection: {
        authenticatorAttachment: 'platform',
        residentKey: 'required',
        requireResidentKey: true,
        userVerification: 'required'
      },
      supportedAlgorithmIDs: [-7, -257],
      timeout: 300000,
      ...(excludeCredentials.length ? { excludeCredentials } : {})
    });

    await storeChallenge(options.challenge, { type: 'add', uid, email });

    res.json({ success: true, options });
  } catch (error) {
    console.error('passkey add-options failed:', error);
    res.status(500).json({ success: false, message: 'Could not start passkey setup. Please try again.' });
  }
};

// @desc  Verify attestation and attach the new passkey to the current account
// @route POST /api/auth/passkey/add-verify   (protected)
exports.passkeyAddVerify = async (req, res) => {
  try {
    const uid = req.user.uid;
    const credential = req.body.credential;
    const deviceName = String(req.body.deviceName || 'iPhone').slice(0, 64);

    const challenge = challengeFromClientData(credential);
    const challengeDoc = challenge ? await consumeChallenge(challenge, 'add') : null;
    if (!challengeDoc || challengeDoc.uid !== uid) {
      return res.status(400).json({
        success: false,
        message: 'This passkey setup expired. Please try again.',
        code: 'CHALLENGE_INVALID'
      });
    }

    const { verified, registrationInfo } = await verifyRegistrationResponse({
      response: credential,
      expectedChallenge: challenge,
      expectedOrigin: EXPECTED_ORIGIN,
      expectedRPID: RP_ID,
      requireUserVerification: true
    });
    if (!verified || !registrationInfo) {
      return res.status(400).json({
        success: false,
        message: 'Passkey verification failed. Please try again.',
        code: 'VERIFICATION_FAILED'
      });
    }

    const cred = registrationInfo.credential;
    const now = new Date().toISOString();
    const email = String(challengeDoc.email || '').toLowerCase().trim();

    // Store the credential and mark the account as passkey-enabled. create()
    // makes a replayed attestation a no-op rather than a duplicate.
    await db.collection(COLLECTIONS.WEBAUTHN_CREDENTIALS).doc(cred.id).create({
      userId: uid,
      email,
      publicKey: isoBase64URL.fromBuffer(cred.publicKey),
      counter: cred.counter || 0,
      transports: cred.transports || ['internal'],
      deviceName,
      createdAt: now,
      lastUsedAt: null
    });
    await db.collection(COLLECTIONS.USERS).doc(uid).update({
      'linkedProviders.passkey': cred.id,
      updatedAt: now
    });

    res.json({ success: true, message: 'Passkey added' });
  } catch (error) {
    if (error.code === 6 || /already exists/i.test(error.message || '')) {
      // Same credential re-posted — treat as success (idempotent)
      return res.json({ success: true, message: 'Passkey already added' });
    }
    console.error('passkey add-verify failed:', error);
    res.status(500).json({ success: false, message: 'Could not add passkey. Please try again.' });
  }
};
